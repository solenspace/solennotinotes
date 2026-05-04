# Notinotes — Progress Tracker

## Current phase

**Implementation.** Spec 01 landed (lint + format baseline); Spec 02 active.

## Active spec

[Spec 02 — offline-invariant-ci-gate](../specs/02-offline-invariant-ci-gate.md)

## Completed

- Bootstrap (2026-05-04): codebase imported from `solenspace/solennotinotes`; 19 skills + 5 agents installed; six context files; CLAUDE.md + AGENTS.md.
- 30-spec roadmap drafted (2026-05-04): Specs 01–29 + 04b stub at `specs/`.
- Validation pass complete (2026-05-04): package versions, palette, cross-spec consistency, repo readiness verified. Findings captured in architecture decisions below.
- Tooling expansion (2026-05-04): 5 additional VoltAgent subagents installed (`architect-reviewer`, `security-auditor`, `performance-engineer`, `dependency-manager`, `refactoring-specialist`); CLI tools installed (FVM, lefthook, lcov, gh, mason_cli, coverage, very_good_cli); project-scoped [`.mcp.json`](../.mcp.json) registers Playwright MCP only — other MCP candidates (`dart`, `git`, `ios-sim`, `mobile`, `memory`, `seqthink`, `github`) were rejected as redundant with existing CLI tools / built-ins. See [`AGENTS.md`](../AGENTS.md) for the rationale and visual-verification workflow.
- Spec 01 — lint-and-format-hardening (2026-05-04): rewrote [`analysis_options.yaml`](../analysis_options.yaml) with 7 hand-picked lints + `strict-casts`/`strict-inference`/`strict-raw-types` + `formatter.page_width: 100`; ran `dart fix --apply` (20 fixes across 13 files) and `dart format -l 100 lib/ test/` (29 of 38 files reflowed); created `test/.gitkeep` so the documented `dart format ... test/` command no longer errors on a missing path; updated `dart format` lines in [`CLAUDE.md`](../CLAUDE.md), [`code-standards.md`](code-standards.md), and [`ai-workflow-rules.md`](ai-workflow-rules.md) to use `-l 100`. `flutter analyze` reports 61 remaining issues, all surfaced by the new strict-mode flags (none auto-fixable) — itemized below under "Lint debt" and resolved by whichever future spec next touches each file.

## In progress

(empty)

## Architecture decisions (locked)

1. **Cloud-free, ever** — invariant 1 in [`architecture.md`](architecture.md). The single allowed network surface is the LLM/Whisper model download (Spec 19), allowlisted by file path.
2. **flutter_bloc over Provider.** Provider removed by Spec 08; package banned in Spec 10.
3. **Hive CE retained as KV store.** Typed adapters land in Spec 04b (deferred).
4. **P2P transport via `flutter_nearby_connections`** — the package is dormant (last update ~2 years). Spec 22 §A starts with a viability probe on iOS 17+ + Android 14+; if probe fails, the spec extends to write platform channels (`MultipeerConnectivity` + `Nearby Connections API`).
5. **STT via `speech_to_text`; TTS via `flutter_tts`** — both wrap native APIs with hard offline gate. Spec 15 adds an instrumented offline-trace test; if a device fails the trace, STT hides on that device. `sherpa_onnx` reserved as a future polish-spec fallback.
6. **On-device LLM via `llama_cpp_dart`** (replacing `fllama` per validation findings — `fllama` is at v0.0.1, ~17mo old, unverified). `flutter_llama` is the alternate; `MLC LLM` via custom FFI is the high-performance fallback. Final pick locks during Spec 18 benchmark.
7. **Whisper variant**: `whisper-base.en` for `AiTier.full`, `whisper-tiny.en` for `AiTier.compact` — confirmed by Spec 21 benchmark.
8. **Skills installed via `pnpm dlx skills`**; subagents from `VoltAgent/awesome-claude-code-subagents`. No invented skills, no invented agents.
9. **Specs drafted as a complete v1 roadmap; implementation is sequential.** Each spec has a `## Agents & skills` section that names the pre-coding skills and after-coding agents to invoke.
10. **Base theme: bone surface (`#EDE6D6`) + narrow-black ink (`#1C1B1A`)** — canonical default. Dark mode opt-in. 12 curated NotiThemeOverlay palettes (5 bone-first + 2 warm light + 5 dark) per Spec 11; per-note overlay fully replaces surface + accent + pattern + signature glyph. Default Notinotes accent: `#4A8A7F` (muted teal).
11. **Localization via `gen_l10n`** (built into Flutter SDK) per Spec 26 — replaces the earlier provisional `intl_utils` choice.
12. **`custom_lint` for the offline-imports rule** (Spec 02) — `analysis_server_plugin` is the modern alternative, considered future-direction when we accumulate ≥3 custom rules.
13. **Cross-spec auditor agents**: `architect-reviewer`, `security-auditor`, `performance-engineer`, `dependency-manager`, `refactoring-specialist` are dispatched at trigger specs (see [`AGENTS.md`](../AGENTS.md) "Custom agents") in addition to the per-spec named agents. Drift, invariant violations, and dependency creep get caught between specs.
14. **Visual verification via Playwright MCP**: Flutter web UI is verified by Claude driving Chromium directly (AX-tree snapshots + on-demand screenshots) instead of writing widget-test code. Goldens (Spec 27) cover canonical scenes; Playwright MCP covers ad-hoc verification of every other surface.
15. **CLI-first, MCP-second**: Bash invocation of `dart`, `flutter`, `git`, `gh`, `xcrun simctl`, `adb` is preferred over wrapper MCPs. Only Playwright MCP is registered in [`.mcp.json`](../.mcp.json) — it's the single capability with no CLI equivalent. Rejected MCPs (`dart`, `git`, `ios-sim`, `mobile`, `memory`, `seqthink`, `github`) and their CLI replacements are listed in [`AGENTS.md`](../AGENTS.md).

## Open questions

1. **LLM model file** (resolved-pending): Spec 18 benchmarks `llama_cpp_dart` against TinyLlama-1.1B-Q4 / Phi-3-mini / Qwen2.5-1.5B; final pick locks the URL + SHA-256 for Spec 19's allowlist.
2. **Hard truncation at 10 MB for audio** (Spec 13): no FFmpeg dep yet; current cap = client-side max-duration UI gate; revisit when needed.
3. **Format-version evolution** (Spec 23): single integer with hard breaks at v1; v2 adds optional fields with downgrade negotiation.
4. **Multi-select bulk overlay** (Spec 11 design notes): future spec.
5. **Light-mode pattern luminance tuning** (Spec 11): patterns currently tuned for dark surfaces; bone-mode pattern variants deferred to a polish spec.
6. **Android < 12 STT availability** (Spec 15): conservatively hidden; revisit in a polish spec.
7. **`flutter_nearby_connections` viability** (Spec 22): probe outcome determines whether the spec doubles in size to platform-channels work.
8. **`speech_to_text` true offline trace** (Spec 15): instrumented test must confirm zero `HttpClient` opens during dictation; sherpa_onnx becomes the fallback path if the trace fails.

## User decisions

- Notinotes signature accent: **`#4A8A7F` (muted teal)** — replaces provisional `#E5B26B`.
- App display name: TBD (`pubspec.yaml` is `noti_notes_app`).
- Whether the noti display name is editable per-install or generated immutably: editable (Spec 09 implementation).

## Lint debt (post Spec 01)

61 issues remain after `dart fix --apply` + `dart format -l 100`, all surfaced by the new `strict-casts` / `strict-inference` / `strict-raw-types` analyzer flags (no auto-fix path). They cluster in the legacy `Provider` data layer (`lib/providers/notes.dart`, `lib/providers/user_data.dart`) and in raw Hive `box`/`openBox` calls — both areas are rewritten by Specs 04 / 04b / 08, which will close most of this list at once.

- `argument_type_not_assignable` (27 hits)
  - lib/providers/notes.dart:71, :75, :76, :77, :78, :79, :83, :84, :86, :87, :90, :91, :92, :93, :94, :95, :96, :97, :98, :99, :238, :245
  - lib/providers/user_data.dart:115, :117, :118, :120, :122
- `inference_failure_on_function_invocation` (10 hits)
  - lib/helpers/database_helper.dart:12, :24, :28, :32, :44
  - lib/theme/theme_provider.dart:36, :41, :57, :64, :71
- `invalid_assignment` (8 hits)
  - lib/providers/notes.dart:242, :251, :254, :260, :263, :266, :272
  - lib/providers/user_data.dart:84
- `inference_failure_on_instance_creation` (5 hits)
  - lib/main.dart:54, :66
  - lib/screens/home_screen.dart:128, :134
  - lib/widgets/home/expandable_fab.dart:87
- `strict_raw_type` (3 hits)
  - lib/helpers/database_helper.dart:15
  - lib/providers/notes.dart:102
  - lib/providers/user_data.dart:110
- `unawaited_futures` (3 hits)
  - lib/providers/notes.dart:165, :168
  - lib/widgets/home/expandable_fab.dart:72
- `use_build_context_synchronously` (2 hits)
  - lib/screens/note_editor_screen.dart:315, :316
- `inference_failure_on_function_return_type` (1 hit)
  - lib/api/notifications_api.dart:33
- `inference_failure_on_collection_literal` (1 hit)
  - lib/providers/user_data.dart:50
- `non_bool_negation_expression` (1 hit)
  - lib/providers/notes.dart:382
