// ignore_for_file: forbidden_import
// Allowed by scripts/.offline-allowlist for Spec 19 (model download). This
// is the only file under lib/ permitted to import dart:io.HttpClient — see
// architecture.md invariant 1 and the allowlist comment for the audit
// trail. Adding a second consumer requires a written rationale and a new
// architecture-decision entry; do not silently extend.

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'llm_model_constants.dart';

/// One-shot, resumable, integrity-checked downloader for the GGUF model
/// file Spec 19 freezes in [LlmModelConstants]. Lifecycle:
///
///   1. Caller (typically `LlmReadinessCubit`) checks
///      [isAlreadyDownloaded] on app start. If true, the runtime can load
///      the file directly — no UI involvement.
///   2. Otherwise the user opts in via the disclosure sheet, [download] is
///      subscribed, and progress events drive the UI.
///   3. The sink writes to `<app_support>/llm/<filename>.partial`. On
///      success the partial is atomically renamed to its final name; on
///      failure / cancel the partial stays on disk so the next attempt's
///      `Range` request can resume from where this one stopped.
///   4. SHA-256 is computed in a single pass: every byte written to disk
///      is also fed through the digest, so verification at the end is a
///      memory-only string compare. This avoids the second 700 MB read
///      the spec text sketched (verify-equivalent, half the disk I/O).
///
/// Cancellation: closing the [download] subscription terminates the
/// `await for` loop, the `finally` block closes the sink + HttpClient, and
/// the partial file is left on disk. The caller is expected to invoke
/// [deletePartial] when the user explicitly cancels (vs. a transient
/// network drop the user wants to resume from).
class LlmModelDownloader {
  const LlmModelDownloader();

  Future<File> resolveTargetFile() async {
    final supportDir = await getApplicationSupportDirectory();
    final llmDir = Directory(p.join(supportDir.path, 'llm'));
    if (!llmDir.existsSync()) llmDir.createSync(recursive: true);
    return File(p.join(llmDir.path, LlmModelConstants.filename));
  }

  Future<File> _resolvePartialFile() async {
    final target = await resolveTargetFile();
    return File('${target.path}.partial');
  }

  /// Returns true when the canonical model file is on disk *and* its
  /// SHA-256 matches [LlmModelConstants.sha256]. A mismatching file is
  /// silently treated as not-downloaded so the next start triggers a
  /// re-fetch (the file is the source of truth, not a flag in settings).
  Future<bool> isAlreadyDownloaded() async {
    final target = await resolveTargetFile();
    if (!target.existsSync()) return false;
    return _verifyFileDigest(target);
  }

  /// Streams the download lifecycle. Resumable across app launches via the
  /// `.partial` sidecar file: a fresh subscription with bytes already on
  /// disk issues an HTTP `Range: bytes=N-` request and appends from there.
  /// Servers that honor the range respond `206 Partial Content`; the rare
  /// server that ignores Range and replies `200 OK` triggers a full
  /// restart (partial is truncated; digest reset).
  Stream<DownloadProgress> download() async* {
    final target = await resolveTargetFile();
    final partial = await _resolvePartialFile();

    final client = HttpClient();
    IOSink? sink;

    try {
      final initialPartialBytes = partial.existsSync() ? partial.lengthSync() : 0;

      final request = await client.getUrl(Uri.parse(LlmModelConstants.url));
      if (initialPartialBytes > 0) {
        request.headers.add(
          HttpHeaders.rangeHeader,
          'bytes=$initialPartialBytes-',
        );
      }
      final response = await request.close();

      final isPartialContent = response.statusCode == HttpStatus.partialContent;
      final isOk = response.statusCode == HttpStatus.ok;
      if (!isPartialContent && !isOk) {
        throw HttpException(
          'Unexpected HTTP status while downloading model: '
          '${response.statusCode}',
          uri: Uri.parse(LlmModelConstants.url),
        );
      }

      // We resume only when we asked for a Range AND the server honoured
      // it. A `200 OK` response on a Range request means the server
      // ignored the header and is sending the full body; we discard the
      // partial and start over, which keeps the digest aligned with the
      // bytes the server is actually sending.
      final resuming = isPartialContent && initialPartialBytes > 0;
      if (!resuming && partial.existsSync()) {
        await partial.delete();
      }
      final startByte = resuming ? initialPartialBytes : 0;

      // Single-pass SHA-256: feed every byte we write to disk through the
      // digest. On resume, replay the bytes already on disk so the final
      // hash covers (partial_bytes || new_bytes) == full file.
      final accumulator = _DigestSink();
      final digestSink = crypto.sha256.startChunkedConversion(accumulator);
      if (resuming) {
        await for (final chunk in partial.openRead()) {
          digestSink.add(chunk);
        }
      }

      sink = partial.openWrite(
        mode: resuming ? FileMode.writeOnlyAppend : FileMode.writeOnly,
      );

      final declaredLength = response.contentLength;
      final total = declaredLength > 0 ? startByte + declaredLength : LlmModelConstants.totalBytes;
      var written = startByte;

      await for (final chunk in response) {
        sink.add(chunk);
        digestSink.add(chunk);
        written += chunk.length;
        yield DownloadProgress.downloading(written, total);
      }

      await sink.close();
      sink = null;
      digestSink.close();

      yield const DownloadProgress.verifying();
      final actualHex = accumulator.digest.toString();
      if (actualHex != LlmModelConstants.sha256) {
        // Corrupt download — remove the partial so the next attempt
        // restarts cleanly rather than resuming on a poisoned prefix.
        if (partial.existsSync()) await partial.delete();
        yield const DownloadProgress.failed('Hash mismatch');
        return;
      }

      if (target.existsSync()) await target.delete();
      await partial.rename(target.path);
      yield const DownloadProgress.ready();
    } finally {
      await sink?.close();
      client.close();
    }
  }

  /// Deletes the partial file if present. Idempotent. Called by the cubit
  /// on user-initiated cancel (vs. transient errors where we want resume
  /// to pick the partial back up on the next attempt).
  Future<void> deletePartial() async {
    final partial = await _resolvePartialFile();
    if (partial.existsSync()) await partial.delete();
  }

  /// Removes both the canonical file and any partial sidecar. Wired up for
  /// future "Disable AI assist" affordances; not consumed by Spec 19's UI.
  Future<void> deleteAll() async {
    final target = await resolveTargetFile();
    if (target.existsSync()) await target.delete();
    await deletePartial();
  }

  bool _verifyFileDigest(File f) {
    final accumulator = _DigestSink();
    final digestSink = crypto.sha256.startChunkedConversion(accumulator);
    final raf = f.openSync();
    try {
      const chunkSize = 1 << 20; // 1 MiB
      while (true) {
        final bytes = raf.readSync(chunkSize);
        if (bytes.isEmpty) break;
        digestSink.add(bytes);
      }
    } finally {
      raf.closeSync();
    }
    digestSink.close();
    return accumulator.digest.toString() == LlmModelConstants.sha256;
  }
}

/// Single-event sink for the chunked SHA-256 conversion. The crypto
/// package's [crypto.Hash.startChunkedConversion] feeds a single [Digest]
/// to its output sink on close; we capture it here. Tiny replacement for
/// `package:convert`'s `AccumulatorSink<Digest>` so this file stays on a
/// single dep.
class _DigestSink implements Sink<crypto.Digest> {
  crypto.Digest? _value;

  @override
  void add(crypto.Digest data) {
    _value = data;
  }

  @override
  void close() {}

  crypto.Digest get digest {
    final v = _value;
    if (v == null) {
      throw StateError(
        'Digest not finalised — close the chunked conversion sink before '
        'reading.',
      );
    }
    return v;
  }
}

/// Phase + payload of a single emission from [LlmModelDownloader.download].
/// Sealed so the cubit's `switch` over phases is exhaustively type-checked.
sealed class DownloadProgress {
  const DownloadProgress();

  const factory DownloadProgress.downloading(int bytes, int total) = DownloadingProgress;
  const factory DownloadProgress.verifying() = VerifyingProgress;
  const factory DownloadProgress.ready() = ReadyProgress;
  const factory DownloadProgress.failed(String reason) = FailedProgress;
}

class DownloadingProgress extends DownloadProgress {
  const DownloadingProgress(this.bytes, this.total);
  final int bytes;
  final int total;
}

class VerifyingProgress extends DownloadProgress {
  const VerifyingProgress();
}

class ReadyProgress extends DownloadProgress {
  const ReadyProgress();
}

class FailedProgress extends DownloadProgress {
  const FailedProgress(this.reason);
  final String reason;
}
