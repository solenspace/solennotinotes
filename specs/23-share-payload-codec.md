# 23 — share-payload-codec

## Goal

Define the **wire format** for a shared note: a self-contained `.noti` archive that bundles the note's JSON manifest, every embedded asset (audio + images), the sender's `NotiIdentity` metadata block, and an Ed25519 signature over the manifest+assets so receivers can verify provenance. Encoding produces `List<int>` ready for `PeerService.send(...)` (Spec 22). Decoding takes the received bytes and returns either a verified `IncomingShare` (manifest + extracted assets on disk) or a typed error. The codec lives at `lib/services/share/share_codec.dart`. **Format version is 1**, encoded explicitly so a future v2 doesn't break devices on v1.

## Dependencies

- [22-p2p-transport-service](22-p2p-transport-service.md) — provides `KeypairService.sign`/`verify`.
- [09-noti-identity](09-noti-identity.md), [11-noti-theme-overlay](11-noti-theme-overlay.md) — `NotiIdentity` and `NotiThemeOverlay` are what travels with the note.
- [04-repository-layer](04-repository-layer.md) — file I/O patterns.

## Agents & skills

**Pre-coding skills:**
- `flutter-implement-json-serialization` — manifest schema codec.
- `dart-add-unit-test` — round-trip + tampered-bytes + version-mismatch + size-cap tests.

**After-coding agents:**
- `code-reviewer` — manifest canonicalization for signing is easy to get wrong; review byte order + asset enumeration order.
- `flutter-expert` — confirm the streaming-extract path doesn't read the whole archive into memory.

## Design Decisions

### Format: ZIP archive with manifest + assets

```
note.noti (ZIP)
├── manifest.json          ← note metadata + overlay + sender identity
├── signature.bin          ← Ed25519 signature over (manifest.json + asset bytes in deterministic order)
└── assets/
    ├── images/<asset_uuid>.jpg
    ├── audio/<asset_uuid>.m4a
    └── transcripts/<audio_uuid>.txt   (optional, if note has whisper transcripts)
```

ZIP because:
- Universal — every platform decodes it.
- Streamable — receiver can extract incrementally.
- Compresses text (manifest), passes through already-compressed media (jpg, m4a).
- Pure-Dart implementation via `archive` package (no native deps; offline-clean).

### `manifest.json` schema (v1)

```json
{
  "format_version": 1,
  "share_id": "<uuid>",
  "created_at": "2026-05-04T18:30:00Z",
  "sender": {
    "id": "<NotiIdentity.id>",
    "display_name": "<NotiIdentity.displayName>",
    "public_key": "<base64 Ed25519 public key>",
    "signature_palette": [<argb_int>, ...],
    "signature_pattern_key": "<NotiPatternKey.name or null>",
    "signature_accent": "<grapheme or null>",
    "signature_tagline": "<string ≤ 60>"
  },
  "note": {
    "id": "<Note.id>",
    "title": "<string>",
    "blocks": [...],            ← exact same shape as Note.blocks
    "tags": [...],
    "date_created": "<ISO 8601>",
    "reminder": "<ISO 8601 or null>",
    "is_pinned": <bool>,
    "overlay": {                ← derived from Note.toOverlay() at send time
      "surface": <argb_int>,
      "surface_variant": <argb_int>,
      "accent": <argb_int>,
      "on_accent": <argb_int>,
      "on_surface": <argb_int or null>,
      "pattern_key": "<NotiPatternKey.name or null>"
    }
  },
  "assets": [
    {
      "id": "<asset_uuid>",
      "kind": "image" | "audio" | "transcript",
      "path_in_archive": "assets/images/<id>.jpg",
      "size_bytes": <int>,
      "sha256": "<hex>"
    }
  ]
}
```

### Signature

Ed25519 over the canonical bytes:

1. Serialize `manifest.json` with sorted keys, no whitespace.
2. Concat: manifest bytes || asset bytes (in the order assets appear in the manifest's `assets` array).
3. Sign via `KeypairService.sign(...)`.

Receiver re-derives the same canonical bytes from the extracted archive and calls `KeypairService.verify(...)` against the sender's `public_key` from the manifest.

### Size cap enforcement

Encoder rejects payloads > 50 MB total (matches invariant 11). Caller catches `PayloadTooLarge` and shows the user "Note is too big to share — try removing audio or large images".

### Asset deduplication

Within a single note, the same asset_uuid never repeats. If a future spec lets a note reference the same audio in multiple blocks, the encoder still packs the file once; the manifest's `assets` array de-duplicates by uuid.

### What doesn't travel

- The original Hive raw record format. The receiver reconstructs `Note` from the manifest's `note` object. This is forward-compatible with Spec 04b's adapter migration.
- The user's private key. (Obvious, but worth stating.)
- Transcripts marked "draft" — only finalized transcripts (accepted by the user) ship.
- The user's tag list as a whole — only tags actually attached to this note.

### Decode-side errors (typed)

```dart
sealed class DecodeResult { const DecodeResult(); }
class DecodeOk extends DecodeResult { final IncomingShare share; ... }
class DecodeUnsupportedVersion extends DecodeResult { ... }
class DecodeSignatureInvalid extends DecodeResult { ... }
class DecodeSizeExceeded extends DecodeResult { ... }
class DecodeMalformed extends DecodeResult { final String reason; ... }
```

UI uses these to render specific failure messages.

## Implementation

### A. Files

```
lib/services/share/
├── share_codec.dart           ← encode/decode
├── share_models.dart          ← OutgoingShare, IncomingShare, DecodeResult
└── share_constants.dart       ← FORMAT_VERSION, MAX_PAYLOAD_BYTES

test/services/share/
├── share_codec_test.dart
└── fixtures/                  ← golden .noti files for tests
```

### B. `pubspec.yaml`

```yaml
dependencies:
  archive: ^4.0.1
```

### C. Encoder API

```dart
class ShareEncoder {
  ShareEncoder({required KeypairService keypair, required NotesRepository notes});

  Future<List<int>> encode({
    required Note note,
    required NotiIdentity sender,
  });
}
```

Resolves asset file paths via `NotesRepository.resolveAssetFile(...)` (a small extension to the existing repo), reads each asset's bytes, computes SHA-256, builds manifest, signs, ZIPs. If total > `MAX_PAYLOAD_BYTES` throws `PayloadTooLarge`.

### D. Decoder API

```dart
class ShareDecoder {
  ShareDecoder({required KeypairService keypair});

  Future<DecodeResult> decode(List<int> bytes);
}
```

Streams the ZIP entries, extracts the manifest first, validates `format_version`, verifies signature, extracts assets to `<app_documents>/inbox/<share_id>/...` (NOT into the user's notes dir until the share is accepted in Spec 25), returns `DecodeOk(share)`.

### E. `IncomingShare`

Holds the parsed manifest fields + the path prefix where assets were extracted. The inbox repository (Spec 25) wraps it for storage.

### F. Backwards compat — version handling

The encoder always writes `format_version: 1`. The decoder accepts only `1`. Versioned upgrades:

- v1 → v2 will introduce some optional manifest fields. The decoder's strategy: if the version is known, decode; otherwise return `DecodeUnsupportedVersion` with the version reported in the error.

## Success Criteria

- [ ] Files in Section A exist.
- [ ] `share_codec_test.dart` covers:
  - Round trip — encode → decode → equal manifest, equal asset bytes, signature verifies.
  - Tampered signature → `DecodeSignatureInvalid`.
  - Tampered manifest → `DecodeSignatureInvalid`.
  - Size exceeded → `PayloadTooLarge` on encode; `DecodeSizeExceeded` if a malicious sender ignores the cap.
  - Unsupported version (manually edited fixture) → `DecodeUnsupportedVersion`.
  - Empty manifest fields → `DecodeMalformed`.
- [ ] Golden `.noti` fixtures committed under `test/services/share/fixtures/` for regression testing.
- [ ] `flutter analyze` / format / test clean.
- [ ] No file under `lib/` outside `lib/services/share/` imports `package:archive`.
- [ ] Offline gate clean.
- [ ] No invariant changed.

## References

- [22-p2p-transport-service](22-p2p-transport-service.md), [09-noti-identity](09-noti-identity.md), [11-noti-theme-overlay](11-noti-theme-overlay.md)
- Plugin: <https://pub.dev/packages/archive>
- `cryptography` Ed25519 — used via `KeypairService` from Spec 22
- Skill: [`flutter-implement-json-serialization`](../.agents/skills/flutter-implement-json-serialization/SKILL.md)
- Agent: `code-reviewer` — manifest canonicalization for signing is easy to get wrong; review byte order
- Follow-up: [24-share-nearby-flow](24-share-nearby-flow.md) wires encode → send; [25-received-inbox](25-received-inbox.md) wires decode → inbox.
