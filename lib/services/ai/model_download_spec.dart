import 'package:equatable/equatable.dart';

/// Identity of a single on-device model file fetched through
/// [ModelDownloader] (the one authorised network surface — see
/// `architecture.md` invariant 1 and `scripts/.offline-allowlist`).
///
/// Each subsystem that owns a model exposes one or more `static const`
/// instances of this class:
///
///   * `LlmModelConstants.spec` — the LLM GGUF (Spec 19, decision #32).
///   * `WhisperModelConstants.tinyEn` / `.baseEn` — the Whisper variants
///     selected per [AiTier] (Spec 21, decision #7).
///
/// The downloader resolves files to
/// `<app_support>/<subdirectory>/<filename>` and verifies SHA-256 against
/// [sha256] before atomically renaming the partial sidecar onto the
/// canonical name. The version field is bumped in lock-step with
/// `filename` / `url` / `sha256` so a stale download from a previous
/// schema is not treated as ready (cf. `LlmModelConstants.version`).
///
/// Equality is by-value so tests can assert "the right spec was passed".
class ModelDownloadSpec extends Equatable {
  const ModelDownloadSpec({
    required this.subdirectory,
    required this.filename,
    required this.url,
    required this.sha256,
    required this.totalBytes,
    required this.version,
  });

  /// Application-support sub-folder (e.g. `'llm'` or `'whisper'`). Lets
  /// two model families coexist without filename collisions when one
  /// ships multiple variants.
  final String subdirectory;

  /// On-disk filename (no path components).
  final String filename;

  /// Canonical, immutable mirror. Must be HTTPS; the user audits the
  /// single outbound URL as part of trusting this app to remain offline.
  final String url;

  /// Lower-case hex SHA-256 of the canonical bytes. Verified during
  /// download (single-pass) and on every cold-start probe.
  final String sha256;

  /// Exact byte count of the canonical file. Used to pre-size progress
  /// bars when the HTTP response omits `Content-Length` (rare but
  /// possible on `Range` resumes).
  final int totalBytes;

  /// Schema version of these constants. Bumped when any of [filename] /
  /// [url] / [sha256] change in lock-step.
  final String version;

  @override
  List<Object?> get props => [subdirectory, filename, url, sha256, totalBytes, version];
}
