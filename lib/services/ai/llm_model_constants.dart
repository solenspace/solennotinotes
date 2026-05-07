/// Frozen identity of the on-device LLM model file shipped with v1 of the
/// AI assist flow (Spec 19). The values are locked by architecture decision
/// #32 in `context/progress-tracker.md` and the harness README at
/// `tools/llm-validation/README.md` — three places that must agree because
/// they are how we audit "the file the downloader fetched is the file the
/// runtime loads is the file Spec 18 validated against."
///
/// These are deliberately top-level constants, not configuration. The whole
/// point of the offline invariant (architecture.md #1) is that the user can
/// audit *exactly one* outbound URL the app will hit; making this swappable
/// at runtime would defeat the audit.
class LlmModelConstants {
  /// Schema version of these constants. Bumped when `filename` / `url` /
  /// `sha256` change in lock-step (e.g. switching to a different quant or
  /// model). The downloader records this alongside the on-disk file so a
  /// stale download from a previous schema is not treated as ready.
  static const String version = '0.1.0';

  /// The chosen GGUF: TinyLlama-1.1B-Chat v1.0 quantized to Q4_K_M. Named in
  /// Spec 18 § "Validation criteria" as the test target; reused as the
  /// production model so the validation numbers stay meaningful.
  static const String filename = 'tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf';

  /// Canonical mirror controlled by TheBloke on Hugging Face. The same URL
  /// is documented in the harness README so the binary downloaded for
  /// validation and the binary fetched in production are bit-identical.
  /// Updating this requires a new SHA-256 and a new architecture-decision
  /// entry — the URL is pinned, not configured.
  static const String url =
      'https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf';

  /// SHA-256 of the GGUF, sourced from the file's git-LFS pointer at
  /// `huggingface.co/.../raw/main/<filename>`. Verified after every
  /// download; any mismatch deletes the partial file and surfaces a
  /// `failed` state to the user.
  static const String sha256 = '9fecc3b3cd76bba89d504f29b616eedf7da85b96540e490ca5824d3f7d2776a0';

  /// Exact byte size of the GGUF (also from the LFS pointer). Used to
  /// pre-size progress bars when the HTTP response omits `Content-Length`
  /// (rare but possible on `Range` resumes).
  static const int totalBytes = 668788096;

  const LlmModelConstants._();
}
