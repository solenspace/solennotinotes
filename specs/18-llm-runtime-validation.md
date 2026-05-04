# 18 — llm-runtime-validation

## Goal

**Validate the on-device LLM runtime** before committing the rest of Phase 5 to it. Open question 6 in [progress-tracker.md](../context/progress-tracker.md) flagged that `fllama` (the planned llama.cpp Flutter binding) is at v0.0.1 from ~17 months ago with an unverified uploader. This spec runs an empirical check against the actual hardware tiers Spec 17 defined: download a small GGUF model in a debug build, load it via the candidate package, run a 5-token generation, measure latency + memory, decide go/no-go. The decision then locks the package choice for Specs 19–21.

This spec ships **only as a debug-only probe path** — no UI, no production code, no model files in the release. The output is a written decision record committed to `progress-tracker.md` plus a stub `LlmRuntime` interface that the chosen package implements in Spec 19.

## Dependencies

- [17-device-capability-service](17-device-capability-service.md) — runs the validation only on `AiTier.full` / `AiTier.compact` devices.

## Agents & skills

**Pre-coding skills:**
- `flutter-apply-architecture-best-practices` — abstract-runtime interface design that survives package swaps.

**After-coding agents:**
- `flutter-expert` — review the harness; ensure the benchmark numbers are reproducible (warm vs cold loads, GC pauses subtracted, peak-memory probe is real).
- `code-reviewer` — verify the decision record in `progress-tracker.md` is concrete (numbers + device names) before any downstream spec proceeds.

## Design Decisions

### Candidates

In order of preference (per validation findings; `fllama` is dropped — v0.0.1 from ~17mo ago, unverified uploader, effectively abandoned):

1. **`llama_cpp_dart`** ([pub.dev](https://pub.dev/packages/llama_cpp_dart)) — the canonical Dart binding to llama.cpp. Updated March 2026; three abstraction levels; active maintenance. **Lead candidate.**
2. **`flutter_llama`** ([pub.dev](https://pub.dev/packages/flutter_llama)) — simpler, platform-specific (iOS / Android / macOS) wrapper. Alternate if `llama_cpp_dart` has integration problems.
3. **MLC LLM** with custom FFI bridge ([blog](https://www.callstack.com/blog/want-to-run-llms-on-your-device-meet-mlc)) — best mobile performance (Metal on iOS, OpenCL on Android). More setup. Tested on a flagship device only; if benchmarks dramatically beat the Dart bindings, consider as the production runtime.
4. **Custom FFI** against a vendored llama.cpp shared library — slowest path; full control; last resort if all of the above fail to build cleanly.

### Validation criteria

A candidate "passes" if all of the following hold on a test device of matching tier:

- [ ] Builds cleanly on iOS + Android with current Flutter SDK (3.24+).
- [ ] Loads a 1B-parameter Q4 GGUF (target: TinyLlama-1.1B-Q4_K_M, ~700 MB) in < 30s.
- [ ] Runs a 50-token generation in < 30s on `AiTier.full`, < 60s on `AiTier.compact`.
- [ ] Peak memory delta < 1.5× model size during generation.
- [ ] No crashes on 5 sequential generations with the same model loaded.
- [ ] Streaming token callback fires per token (essential for Spec 20 UX).
- [ ] No transitive network imports — verified by re-running the offline gate after add.

### Decision encoding

Result lands in `progress-tracker.md` as architecture decision 24 (or 25 depending on numbering). Format:

```markdown
24. **LLM runtime: <package> @ <version>**. Validated 2026-MM-DD on <test devices>.
    - Load latency: ...
    - 50-token gen: ...
    - Peak memory delta: ...
    - Reasoning for choice over alternatives: ...
```

### Stub `LlmRuntime` interface

Whichever package wins, the rest of Phase 5 codes against a thin abstraction at `lib/services/ai/llm_runtime.dart`. Spec 19's concrete implementation wraps the chosen package.

## Implementation

### A. Files

```
lib/services/ai/
└── llm_runtime.dart          ← abstract; concrete impl lands in Spec 19

tools/llm-validation/
├── README.md                 ← run instructions for the validation harness
├── pubspec.yaml              ← throwaway Dart project pinning each candidate
└── bin/probe.dart            ← runs load + gen + memory benchmarks
```

`tools/llm-validation/` is **not** part of the Flutter app build. It's a standalone Dart project we use to A/B candidates without polluting the main `pubspec.yaml`.

### B. `LlmRuntime` interface

```dart
abstract class LlmRuntime {
  Future<bool> load({required String modelPath});
  Stream<String> generate({
    required String prompt,
    int maxTokens = 256,
    double temperature = 0.7,
  });
  Future<void> unload();
  bool get isLoaded;
}
```

### C. Validation procedure

The implementer runs `tools/llm-validation/bin/probe.dart` against each candidate package. Each run records to a fresh `tools/llm-validation/results/<package>-<device>.json` file. The implementer tabulates the results, picks the winner, and writes the decision record into `progress-tracker.md`.

### D. Fallback path

If **none** of the four candidates pass:

- Spec 19 (model download) and Spec 20 (AI assist UI) are deferred to v2.
- Spec 21 (Whisper transcription) is deferred to v2 (it depends on the same runtime).
- AI affordances stay hidden by `AiTier.unsupported` everywhere; the offline-only product still ships with capture, theming, P2P, and STT/TTS.

This is documented as **architecture decision 24-fallback** in progress-tracker.md.

## Success Criteria

- [ ] `tools/llm-validation/` exists with the harness, runnable via `cd tools/llm-validation && dart run bin/probe.dart`.
- [ ] At least one candidate package passes all six validation criteria on at least one `AiTier.full` device and one `AiTier.compact` device.
- [ ] The decision is recorded in `progress-tracker.md` with concrete numbers.
- [ ] `lib/services/ai/llm_runtime.dart` exists with the abstract interface.
- [ ] **No production code change in this spec** — the harness is a sibling project; the main app's `pubspec.yaml` is untouched.
- [ ] `flutter analyze` / `flutter test` clean (the harness has its own pubspec; main app unaffected).

## References

- [progress-tracker.md](../context/progress-tracker.md) open question 6
- Plugin: <https://pub.dev/packages/fllama>
- Plugin: <https://pub.dev/packages/llama_cpp_dart>
- Skill: [`flutter-apply-architecture-best-practices`](../.agents/skills/flutter-apply-architecture-best-practices/SKILL.md)
- Follow-up: Spec 19 implements the chosen runtime concretely.
