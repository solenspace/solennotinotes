import 'package:noti_notes_app/theme/noti_theme_overlay.dart';

/// Asset categories carried inside a `.noti` archive. `transcript` is
/// reserved for finalized Whisper output once Spec 21's transcript store
/// lands; the encoder emits none today and the decoder accepts the kind
/// silently for forward compatibility.
enum ShareAssetKind { image, audio, transcript }

extension ShareAssetKindWire on ShareAssetKind {
  String get wireName => switch (this) {
        ShareAssetKind.image => 'image',
        ShareAssetKind.audio => 'audio',
        ShareAssetKind.transcript => 'transcript',
      };

  static ShareAssetKind? fromWire(String? value) => switch (value) {
        'image' => ShareAssetKind.image,
        'audio' => ShareAssetKind.audio,
        'transcript' => ShareAssetKind.transcript,
        _ => null,
      };
}

/// Output of [ShareEncoder.encode]. The bytes are ready to hand to
/// [PeerService.send]; [shareId] is the manifest's stable id, useful for
/// transfer attribution.
class OutgoingShare {
  const OutgoingShare({required this.bytes, required this.shareId});
  final List<int> bytes;
  final String shareId;
}

/// Sender block lifted out of a verified manifest. The 32-byte [publicKey]
/// stays in raw form; callers that persist it should base64-encode at the
/// storage boundary to match [NotiIdentity]'s on-disk shape.
class IncomingSender {
  const IncomingSender({
    required this.id,
    required this.displayName,
    required this.publicKey,
    required this.signaturePalette,
    required this.signaturePatternKey,
    required this.signatureAccent,
    required this.signatureTagline,
  });

  final String id;
  final String displayName;
  final List<int> publicKey;
  final List<int> signaturePalette;
  final String? signaturePatternKey;
  final String? signatureAccent;
  final String signatureTagline;
}

/// Note block lifted out of a verified manifest. [blocks] is the same
/// shape the editor consumes (a list of `{type, id, ...}` maps); the inbox
/// repository (Spec 25) is responsible for rewriting embedded asset paths
/// from archive-relative to extracted-on-disk before reconstructing a
/// [Note] domain object.
class IncomingNote {
  const IncomingNote({
    required this.id,
    required this.title,
    required this.blocks,
    required this.tags,
    required this.dateCreated,
    required this.reminder,
    required this.isPinned,
    required this.overlay,
  });

  final String id;
  final String title;
  final List<Map<String, dynamic>> blocks;
  final List<String> tags;
  final DateTime dateCreated;
  final DateTime? reminder;
  final bool isPinned;
  final NotiThemeOverlay overlay;
}

class IncomingAsset {
  const IncomingAsset({
    required this.id,
    required this.kind,
    required this.pathInArchive,
    required this.sizeBytes,
    required this.sha256,
  });

  final String id;
  final ShareAssetKind kind;
  final String pathInArchive;
  final int sizeBytes;
  final String sha256;
}

/// Verified, extracted result of [ShareDecoder.decode]. Asset bytes have
/// been written under [inboxRoot]; [pathInArchive] entries on each asset
/// are also valid relative paths against [inboxRoot].
class IncomingShare {
  const IncomingShare({
    required this.shareId,
    required this.createdAt,
    required this.sender,
    required this.note,
    required this.assets,
    required this.inboxRoot,
  });

  final String shareId;
  final DateTime createdAt;
  final IncomingSender sender;
  final IncomingNote note;
  final List<IncomingAsset> assets;
  final String inboxRoot;
}

/// Outcome of a decode call. Sealed so consumers must `switch` exhaustively
/// and render a specific UI for every failure mode.
sealed class DecodeResult {
  const DecodeResult();
}

class DecodeOk extends DecodeResult {
  const DecodeOk(this.share);
  final IncomingShare share;
}

class DecodeUnsupportedVersion extends DecodeResult {
  const DecodeUnsupportedVersion(this.version);
  final int version;
}

class DecodeSignatureInvalid extends DecodeResult {
  const DecodeSignatureInvalid();
}

class DecodeSizeExceeded extends DecodeResult {
  const DecodeSizeExceeded({required this.actual, required this.cap});
  final int actual;
  final int cap;
}

class DecodeMalformed extends DecodeResult {
  const DecodeMalformed(this.reason);
  final String reason;
}

/// Thrown by [ShareEncoder.encode] when the cumulative asset + manifest
/// size exceeds [shareMaxPayloadBytes]. UI catches this to surface a
/// "remove audio or large images" hint.
class PayloadTooLarge implements Exception {
  const PayloadTooLarge({required this.actual, required this.cap});
  final int actual;
  final int cap;

  @override
  String toString() => 'PayloadTooLarge(actual: $actual, cap: $cap)';
}
