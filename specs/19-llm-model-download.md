# 19 — llm-model-download

## Goal

Implement the **first-run download flow** for the on-device LLM model file (GGUF). Per the user's decision in earlier alignment, the model download is the **only authorized network call** in Notinotes' runtime — it is explicit, visible, opt-in, and one-time per device. After download, the model lives in app-support storage and the app makes no further network calls during AI usage. The download path (HTTP client + URL) is added to `scripts/.offline-allowlist` with a justification line referencing this spec, so the offline-imports gate exempts it specifically.

The flow: user taps "Enable AI assist" → sees model size, hash, and a "download once, kept on this device, never sent anywhere" disclosure → confirms → progress bar with cancel → file written to `<app_support>/llm/<model_filename>` → SHA-256 verified → ready signal flips on. Subsequent launches skip the flow because the file is present.

## Dependencies

- [17-device-capability-service](17-device-capability-service.md) — only offered when `aiTier.canRunLlm`.
- [18-llm-runtime-validation](18-llm-runtime-validation.md) — defines the chosen runtime + its model file requirements.
- [02-offline-invariant-ci-gate](02-offline-invariant-ci-gate.md) — extends the offline-allowlist for the single allowed network surface.

## Agents & skills

**Pre-coding skills:**
- `dart-flutter-patterns` — cubit + cancellable stream pattern for the download flow.
- `flutter-implement-json-serialization` — for any download-state persistence (last-attempt, last-failure).

**After-coding agents:**
- `code-reviewer` — this is the one place we relax invariant 1; the diff must read straight. Verify the allowlist entry is the ONLY exemption.
- `flutter-expert` — confirm the cancel path properly closes the `HttpClient` and deletes the partial file; resumable Range requests work across app backgrounding.

## Design Decisions

### One file, one URL, one allowlist entry

- The model file is a known GGUF — exact name + version + SHA-256 frozen at the spec's Implementation Section A.
- Download URL is a CDN-backed mirror controlled by the project (Hugging Face for v1; can switch to self-hosted in a polish spec).
- Only `lib/services/ai/llm_model_downloader.dart` is allowed to import `dart:io.HttpClient`. The custom_lint forbidden-import rule reads the offline-allowlist file paths and exempts this specific file. Every other path remains banned.
- **No `package:http`, `package:dio`, or other HTTP package.** We use the bare `dart:io.HttpClient` so the surface area is small and audit-trivial.

### Disclosure copy

Plain language, no marketing fluff:

> **Enable AI assist?**
>
> The AI features summarize, rewrite, and suggest titles using a small language model that runs entirely on this device.
>
> Notinotes will download the model file once (~700 MB). The download is a one-time, one-way connection. Nothing else leaves your device — not now, not later. You can cancel any time.
>
> [ Cancel ]    [ Download ]

### Resumable, cancellable

- Uses HTTP `Range` requests so a dropped connection resumes from the last byte.
- Progress reported as `bytesReceived / contentLength`.
- User cancels → in-flight chunk closes → partial file deleted → state returns to "AI disabled".

### Verification

Post-download, the file's SHA-256 is computed (via `package:crypto`, already a transitive dep via Flutter) and compared against the constant in code. Mismatch → file deleted, error surfaced, user invited to retry.

### Storage location

`<app_support>/llm/<model_filename>` (NOT `<app_documents>` — model isn't user content; it's a runtime asset). The path is computed via `path_provider.getApplicationSupportDirectory()`.

### State machine

`LlmReadinessCubit`:
- `idle` (no model present, user hasn't opted in)
- `downloading` (in-flight, with `progressBytes`, `totalBytes`)
- `verifying` (download done, hash check in progress)
- `ready` (file present, hash valid)
- `failed(reason)` — network error / hash mismatch / disk full

### UI

Two surfaces:

1. **Disclosure modal** in settings → "AI assist" row. Shown when status is `idle`. Tapping "Download" transitions to the progress modal.
2. **Progress modal** — shows percentage, bytes downloaded, cancel button. Auto-dismisses on `ready` with a one-line confirmation snackbar.

The settings row label changes per state: "Enable AI assist (700 MB)" / "Downloading… 42%" / "Verifying…" / "AI assist enabled" / "Download failed — retry".

## Implementation

> **Implementer guard-rail.** This spec must NOT be merged with placeholder values. Spec 18 concludes with a written decision record (in `context/progress-tracker.md` decision 24) naming the chosen runtime and its preferred GGUF model. The `filename`, `url`, `sha256`, and `approximateBytes` constants below are filled in **only after Spec 18 lands** and the decision is recorded. Without those values, this spec is incomplete and Spec 20 + 21 are blocked.

### A. Constants — `lib/services/ai/llm_model_constants.dart`

```dart
class LlmModelConstants {
  static const String version = '0.1.0';

  /// The exact GGUF chosen during Spec 18 validation.
  /// (Implementer fills in after Spec 18 picks a winner; placeholder below.)
  static const String filename = 'noti-llm-q4-v1.gguf';
  static const String url =
      'https://huggingface.co/<TBD-during-Spec-18>/resolve/main/$filename';
  static const String sha256 =
      '<TBD-during-Spec-18-validation>';   // 64 hex chars
  static const int approximateBytes = 720 * 1024 * 1024;  // 720 MB

  const LlmModelConstants._();
}
```

### B. Downloader — `lib/services/ai/llm_model_downloader.dart`

```dart
// ignore_for_file: forbidden_import
// Allowed by scripts/.offline-allowlist for Spec 19 (model download).

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'llm_model_constants.dart';

class LlmModelDownloader {
  Future<File> resolveTargetFile() async {
    final dir = await getApplicationSupportDirectory();
    final llmDir = Directory(p.join(dir.path, 'llm'));
    if (!llmDir.existsSync()) llmDir.createSync(recursive: true);
    return File(p.join(llmDir.path, LlmModelConstants.filename));
  }

  Future<bool> isAlreadyDownloaded() async {
    final f = await resolveTargetFile();
    if (!f.existsSync()) return false;
    return await _verify(f);
  }

  Stream<DownloadProgress> download() async* {
    final target = await resolveTargetFile();
    final partial = File('${target.path}.partial');
    final startByte = partial.existsSync() ? partial.lengthSync() : 0;

    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(LlmModelConstants.url));
    if (startByte > 0) {
      request.headers.add('Range', 'bytes=$startByte-');
    }
    final response = await request.close();
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw HttpException('Unexpected status: ${response.statusCode}');
    }
    final total = startByte + (response.contentLength == -1 ? LlmModelConstants.approximateBytes : response.contentLength);
    final sink = partial.openWrite(mode: FileMode.writeOnlyAppend);
    var written = startByte;
    try {
      await for (final chunk in response) {
        sink.add(chunk);
        written += chunk.length;
        yield DownloadProgress.downloading(written, total);
      }
    } finally {
      await sink.close();
      client.close();
    }

    yield const DownloadProgress.verifying();
    if (!await _verifyFile(partial)) {
      await partial.delete();
      yield const DownloadProgress.failed('Hash mismatch');
      return;
    }
    if (target.existsSync()) await target.delete();
    await partial.rename(target.path);
    yield const DownloadProgress.ready();
  }

  Future<bool> _verify(File f) async {
    return _verifyFile(f);
  }

  Future<bool> _verifyFile(File f) async {
    final digest = await _sha256(f);
    return digest == LlmModelConstants.sha256;
  }

  Future<String> _sha256(File f) async {
    final stream = f.openRead();
    final out = AccumulatorSink<Digest>();
    final s = sha256.startChunkedConversion(out);
    await for (final chunk in stream) {
      s.add(chunk);
    }
    s.close();
    return out.events.single.toString();
  }

  Future<void> deletePartial() async {
    final target = await resolveTargetFile();
    final partial = File('${target.path}.partial');
    if (partial.existsSync()) await partial.delete();
  }

  Future<void> deleteAll() async {
    final target = await resolveTargetFile();
    if (target.existsSync()) await target.delete();
    await deletePartial();
  }
}

class DownloadProgress {
  const DownloadProgress.downloading(this.bytes, this.total)
      : phase = _Phase.downloading,
        reason = null;
  const DownloadProgress.verifying()
      : phase = _Phase.verifying,
        bytes = 0,
        total = 0,
        reason = null;
  const DownloadProgress.ready()
      : phase = _Phase.ready,
        bytes = 0,
        total = 0,
        reason = null;
  const DownloadProgress.failed(this.reason)
      : phase = _Phase.failed,
        bytes = 0,
        total = 0;

  final _Phase phase;
  final int bytes;
  final int total;
  final String? reason;

  bool get isDownloading => phase == _Phase.downloading;
  bool get isVerifying => phase == _Phase.verifying;
  bool get isReady => phase == _Phase.ready;
  bool get isFailed => phase == _Phase.failed;
  double get fraction => total == 0 ? 0 : bytes / total;
}

enum _Phase { downloading, verifying, ready, failed }
```

### C. `LlmReadinessCubit`

`lib/features/settings/cubit/llm_readiness_cubit.dart`. State holds phase + progress. Two actions: `start()` (begins download) and `cancel()` (closes the in-flight subscription and deletes the partial). Tested with a `FakeLlmModelDownloader` that emits scripted progress.

### D. UI

Two widgets in `lib/features/settings/widgets/`:

- `ai_disclosure_sheet.dart` — modal with the disclosure copy from Design Decisions.
- `llm_download_progress_modal.dart` — full-screen modal with progress bar, byte count, cancel button.

Both styled via `context.tokens.*`.

### E. Offline-allowlist + custom_lint extension

Append to `scripts/.offline-allowlist`:

```
# Spec 19: model download is the one authorized network surface.
# Never extend this allowlist without a written rationale.
lib/services/ai/llm_model_downloader.dart
```

The `forbidden_imports_lint` rule from Spec 02 reads this file (path-allowlist already supported per Spec 15 extension) and exempts the listed paths from the `dart:io.HttpClient` ban.

### F. `lib/main.dart`

```dart
RepositoryProvider<LlmModelDownloader>.value(value: LlmModelDownloader()),
```

`LlmReadinessCubit` is mounted under settings — not at app root — so its lifecycle matches the AI-settings screen.

### G. `SettingsRepository` augmentation

Optional: cache `lastDownloadAttempt` and `lastDownloadFailure` for telemetry (debug-only) and retry UX.

## Success Criteria

- [ ] Files in Sections A–C exist; settings shows AI row with correct state-driven label.
- [ ] `bash scripts/check-offline.sh` exits 0; `dart:io.HttpClient` use is allowed only inside the allowlisted path.
- [ ] **Manual smoke**:
  - Fresh install on `AiTier.full` device: settings → AI assist row says "Enable AI assist (~720 MB)" → tap → disclosure → Download → progress modal → completes → row says "AI assist enabled".
  - Mid-download → tap Cancel → partial file deleted → row reverts to "Enable AI assist".
  - Mid-download → toggle airplane mode → progress halts → reconnect → resume picks up via Range request.
  - Tampered hash (manually edit the file) → next launch's `isAlreadyDownloaded()` returns false → row offers re-download.
  - On `AiTier.unsupported`: row hidden entirely.
- [ ] `flutter test` covers cubit happy path, cancel mid-flight, hash mismatch path.
- [ ] Compile-time check: no other file under `lib/` imports `HttpClient` — verified by the offline gate.

## References

- [`context/architecture.md`](../context/architecture.md) — invariants 1 (no network — exception scoped here), 8 (cancellation), 10 (model in app-support, not bundled)
- [02-offline-invariant-ci-gate](02-offline-invariant-ci-gate.md), [17-device-capability-service](17-device-capability-service.md), [18-llm-runtime-validation](18-llm-runtime-validation.md)
- Skill: [`dart-flutter-patterns`](../.agents/skills/dart-flutter-patterns/SKILL.md)
- Agent: `code-reviewer` — invoke pre-commit; this is the one place we relax invariant 1 and the diff must read straight
- Follow-up: Spec 20 (AI assist UI) consumes the ready signal.
