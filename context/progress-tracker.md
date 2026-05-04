# Notinotes — Progress Tracker

## Current phase

**Implementation.** Specs 01–03 landed (lint baseline + offline-invariant gate + collocated feature layout); Spec 04 active.

## Active spec

[Spec 04 — repository-layer](../specs/04-repository-layer.md)

## Completed

- Bootstrap (2026-05-04): codebase imported from `solenspace/solennotinotes`; 19 skills + 5 agents installed; six context files; CLAUDE.md + AGENTS.md.
- 30-spec roadmap drafted (2026-05-04): Specs 01–29 + 04b stub at `specs/`.
- Validation pass complete (2026-05-04): package versions, palette, cross-spec consistency, repo readiness verified. Findings captured in architecture decisions below.
- Tooling expansion (2026-05-04): 5 additional VoltAgent subagents installed (`architect-reviewer`, `security-auditor`, `performance-engineer`, `dependency-manager`, `refactoring-specialist`); CLI tools installed (FVM, lefthook, lcov, gh, mason_cli, coverage, very_good_cli); project-scoped [`.mcp.json`](../.mcp.json) registers Playwright MCP only — other MCP candidates (`dart`, `git`, `ios-sim`, `mobile`, `memory`, `seqthink`, `github`) were rejected as redundant with existing CLI tools / built-ins. See [`AGENTS.md`](../AGENTS.md) for the rationale and visual-verification workflow.
- Spec 01 — lint-and-format-hardening (2026-05-04): rewrote [`analysis_options.yaml`](../analysis_options.yaml) with 7 hand-picked lints + `strict-casts`/`strict-inference`/`strict-raw-types` + `formatter.page_width: 100`; ran `dart fix --apply` (20 fixes across 13 files) and `dart format -l 100 lib/ test/` (29 of 38 files reflowed); created `test/.gitkeep` so the documented `dart format ... test/` command no longer errors on a missing path; updated `dart format` lines in [`CLAUDE.md`](../CLAUDE.md), [`code-standards.md`](code-standards.md), and [`ai-workflow-rules.md`](ai-workflow-rules.md) to use `-l 100`. `flutter analyze` reports 61 remaining issues, all surfaced by the new strict-mode flags (none auto-fixable) — itemized below under "Lint debt" and resolved by whichever future spec next touches each file.
- Spec 02 — offline-invariant-ci-gate (2026-05-04): added two layered gates against architecture invariant 1. New files: [`scripts/.forbidden-imports.txt`](../scripts/.forbidden-imports.txt) (single source of truth, 24 banned package patterns), [`scripts/.offline-allowlist`](../scripts/.offline-allowlist) (empty header — Spec 19 adds the first entry), [`scripts/check-offline.sh`](../scripts/check-offline.sh) (executable bash grep over `lib/`+`test/`, ~50 ms), and the [`tools/forbidden_imports_lint/`](../tools/forbidden_imports_lint/) Dart package implementing the `forbidden_import` `custom_lint` rule (AST-precise). Wired the rule via `analyzer.plugins: [custom_lint]` and `custom_lint.rules: [forbidden_import]` in [`analysis_options.yaml`](../analysis_options.yaml); added `custom_lint` and the path-dep `forbidden_imports_lint` to `dev_dependencies` in [`pubspec.yaml`](../pubspec.yaml) (no runtime deps changed). **Adapted to Lefthook** (the spec's draft prescribed a hand-rolled `scripts/install-hooks.sh`, but the bootstrap commit had already wired Lefthook): added `check-offline` and `custom-lint` commands to the `pre-commit` block of [`lefthook.yml`](../lefthook.yml); removed the now-redundant `pre-push.forbidden-imports` flat-regex grep (superseded by the precise `scripts/.forbidden-imports.txt`-driven gate). Documented the gate flow in [`AGENTS.md`](../AGENTS.md). Three spec-text defects were corrected during implementation: (a) the bash script's `"${EXCLUDE_ARGS[@]}"` expansion errored under macOS bash 3.2's `set -u` when the array is empty — fixed via the `${EXCLUDE_ARGS[@]+...}` parameter expansion guard; (b) `LintCode` is exported by both `package:analyzer/error/error.dart` and `package:custom_lint_builder/custom_lint_builder.dart` — hide the analyzer's variant; (c) the spec's `File('scripts/.forbidden-imports.txt')` relative path always resolved to a non-existent file because `custom_lint` runs the plugin in a sandboxed isolate (`/private/var/folders/.../custom_lint_clientXXXX`) — the rule now walks up from the analyzed file's path to find the patterns file (cached after first read). Also: `flutter analyze` does **not** fire `custom_lint` v0.7 plugins from CLI; `dart run custom_lint` is the CLI gate, and `analyzer.plugins: [custom_lint]` powers only IDE surfacing. Full `flutter analyze` is intentionally **not** in pre-commit while the 61 strict-mode lint-debt items from Spec 01 are still open (resolved by Specs 04/04b/08). End-to-end verified: baseline `bash scripts/check-offline.sh` exits 0; `dart run custom_lint` reports zero issues on the current tree; injecting `import 'package:http/http.dart';` to `lib/main.dart` causes both gates to fire and `lefthook run pre-commit` to exit 1 (commit blocked).
- Spec 03 — project-structure-migration (2026-05-04): big-bang move of `lib/` from the parallel-hierarchy layout (`api/`, `helpers/`, `providers/`, `models/`, `screens/`, `theme/`, `widgets/`) to the collocated feature layout (`lib/features/<feature>/{legacy, widgets, screen.dart}`) plus cross-cutting roots (`app/`, `services/`, `models/`, `theme/`, `helpers/`, shared `widgets/`). 27 `git mv` operations preserve history (verified via `git log --follow`); no method body or class signature changed (verified via diff review — only renames + import-line edits). Provider-based files retained as `<feature>/legacy/<name>_provider.dart` until Specs 05+ retire them. Cross-cutting moves: `lib/api/notifications_api.dart` → `lib/services/notifications/notifications_service.dart`; `lib/helpers/photo_picker.dart` → `lib/services/image/image_picker_service.dart`. Sheet split per consuming feature: `long_press_menu_sheet.dart` → `features/home/widgets/`; `note_style_sheet.dart`, `reminder_sheet.dart`, `tag_sheet.dart` → `features/note_editor/widgets/`; `sheet_scaffold.dart` stays at `lib/widgets/sheets/` (genuinely shared). One typo fix: `lib/helpers/aligment.dart` → `lib/helpers/alignment.dart` (sole consumer `notes_provider.dart` updated). Cross-cutting and cross-feature imports converted to absolute (`package:noti_notes_app/...`); within-feature imports stay relative per code-standards. `lib/main.dart` body untouched, only its 14-line import block rewritten. `pubspec.yaml`, `analysis_options.yaml`, `lefthook.yml`, all assets, and the 12 architecture invariants unchanged. Updated [`context/architecture.md`](architecture.md) "System boundaries" and [`context/code-standards.md`](code-standards.md) "File organization" trees to describe the new layout. Verification: 0 `Target of URI doesn't exist` errors, `flutter analyze` issue count holds steady at 61 (the Spec 01 strict-mode lint debt baseline; no new errors introduced), `dart format -l 100 lib/ test/` reports 0 changes, `bash scripts/check-offline.sh` exits 0, `dart run custom_lint` reports 0 issues. The lint debt list below has its file paths rewritten to the new locations.

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
16. **Offline invariant enforced by two layered gates** wired through Lefthook (Spec 02): pre-commit runs `scripts/check-offline.sh` (fast grep) and `dart run custom_lint` (AST-precise, fires the `forbidden_import` rule from `tools/forbidden_imports_lint/`). Forbidden patterns sourced from [`scripts/.forbidden-imports.txt`](../scripts/.forbidden-imports.txt) (single source of truth). Spec 02's draft prescribed a hand-rolled `scripts/install-hooks.sh`; superseded by the existing Lefthook setup, which already owned `.git/hooks/pre-commit` from the bootstrap commit. The previous `lefthook.yml` `pre-push.forbidden-imports` flat-regex grep was removed (redundant with the precise pre-commit gate). Two spec-text defects were corrected during implementation: (a) `flutter analyze` does **not** fire `custom_lint` v0.7 plugins from CLI — only IDE surfacing comes via `analyzer.plugins: [custom_lint]`; the CLI gate is `dart run custom_lint`. (b) The plugin runs in a sandboxed isolate at `/private/var/folders/.../custom_lint_clientXXXX`, so the spec's `File('scripts/.forbidden-imports.txt')` relative path always resolved to a non-existent file. The rule now walks up from the analyzed file's path until it finds the patterns file (cached after first read).
17. **Collocated feature layout** at `lib/features/<feature>/` (Spec 03), with cross-cutting code at `lib/{services, models, theme, helpers, widgets}/`. Replaces the parallel-hierarchy plan (`blocs/`, `repositories/`, `screens/`, `widgets/<feature>/`) sketched in the bootstrap context docs. Provider-based files retained as `features/<feature>/legacy/<name>_provider.dart` until Specs 05+ migrate them to `flutter_bloc` and Spec 08 deletes the `legacy/` folders. No barrel files; cross-cutting and cross-feature imports use the absolute `package:noti_notes_app/...` form; intra-feature imports stay relative per [`code-standards.md`](code-standards.md). Spec 03's draft hardcoded "decision #11" but that integer was already taken by intervening decisions; recorded as #17. Both [`architecture.md`](architecture.md) and [`code-standards.md`](code-standards.md) had their layout trees rewritten in the same commit.

## Open questions

1. **LLM model file** (resolved-pending): Spec 18 benchmarks `llama_cpp_dart` against TinyLlama-1.1B-Q4 / Phi-3-mini / Qwen2.5-1.5B; final pick locks the URL + SHA-256 for Spec 19's allowlist.
2. **Hard truncation at 10 MB for audio** (Spec 13): no FFmpeg dep yet; current cap = client-side max-duration UI gate; revisit when needed.
3. **Format-version evolution** (Spec 23): single integer with hard breaks at v1; v2 adds optional fields with downgrade negotiation.
4. **Multi-select bulk overlay** (Spec 11 design notes): future spec.
5. **Light-mode pattern luminance tuning** (Spec 11): patterns currently tuned for dark surfaces; bone-mode pattern variants deferred to a polish spec.
6. **Android < 12 STT availability** (Spec 15): conservatively hidden; revisit in a polish spec.
7. **`flutter_nearby_connections` viability** (Spec 22): probe outcome determines whether the spec doubles in size to platform-channels work.
8. **`speech_to_text` true offline trace** (Spec 15): instrumented test must confirm zero `HttpClient` opens during dictation; sherpa_onnx becomes the fallback path if the trace fails.
9. **Pre-commit hook discoverability** (Spec 02 follow-up): does Lefthook's `lefthook install` need a guard step (warning at `flutter pub get` when `.git/hooks/pre-commit` is absent or non-Lefthook)? Defer until contributor count > 1.
10. **`scripts/check-offline.sh` allowlist semantics** (Spec 02 follow-up, must resolve before Spec 19): the script currently passes allowlist entries as `grep --exclude=$line`, but `grep --exclude` matches the **basename only**, not the full relative path. So an entry like `lib/services/llm_download_service.dart` would silently exempt every file named `llm_download_service.dart` regardless of directory. Latent today (allowlist is empty); must be fixed before Spec 19 (llm-model-download) adds the first entry. Suggested fix: post-filter the `HITS` text against absolute allowlist paths, or replace `grep --exclude` with `find … -not -path …` followed by `xargs grep`.

## User decisions

- Notinotes signature accent: **`#4A8A7F` (muted teal)** — replaces provisional `#E5B26B`.
- App display name: TBD (`pubspec.yaml` is `noti_notes_app`).
- Whether the noti display name is editable per-install or generated immutably: editable (Spec 09 implementation).

## Lint debt (post Spec 01)

61 issues remain after `dart fix --apply` + `dart format -l 100`, all surfaced by the new `strict-casts` / `strict-inference` / `strict-raw-types` analyzer flags (no auto-fix path). They cluster in the legacy `Provider` data layer (`lib/features/home/legacy/notes_provider.dart`, `lib/features/user_info/legacy/user_data_provider.dart`) and in raw Hive `box`/`openBox` calls — both areas are rewritten by Specs 04 / 04b / 08, which will close most of this list at once. Paths reflect the post-Spec-03 collocated layout; line numbers are stable across the move (Spec 03 only renamed files and updated import lines).

- `argument_type_not_assignable` (27 hits)
  - lib/features/home/legacy/notes_provider.dart:70, :74, :75, :76, :77, :78, :82, :83, :85, :86, :89, :90, :91, :92, :93, :94, :95, :96, :97, :98, :237, :244
  - lib/features/user_info/legacy/user_data_provider.dart:115, :117, :118, :120, :122
- `inference_failure_on_function_invocation` (10 hits)
  - lib/helpers/database_helper.dart:12, :24, :28, :32, :44
  - lib/theme/theme_provider.dart:36, :41, :57, :64, :71
- `invalid_assignment` (8 hits)
  - lib/features/home/legacy/notes_provider.dart:241, :250, :253, :259, :262, :265, :271
  - lib/features/user_info/legacy/user_data_provider.dart:84
- `inference_failure_on_instance_creation` (5 hits)
  - lib/main.dart:51, :63
  - lib/features/home/screen.dart:129, :135
  - lib/features/home/widgets/expandable_fab.dart:87
- `strict_raw_type` (3 hits)
  - lib/helpers/database_helper.dart:15
  - lib/features/home/legacy/notes_provider.dart:101
  - lib/features/user_info/legacy/user_data_provider.dart:110
- `unawaited_futures` (3 hits)
  - lib/features/home/legacy/notes_provider.dart:164, :167
  - lib/features/home/widgets/expandable_fab.dart:72
- `use_build_context_synchronously` (2 hits)
  - lib/features/note_editor/screen.dart:316, :317
- `inference_failure_on_function_return_type` (1 hit)
  - lib/services/notifications/notifications_service.dart:33
- `inference_failure_on_collection_literal` (1 hit)
  - lib/features/user_info/legacy/user_data_provider.dart:50
- `non_bool_negation_expression` (1 hit)
  - lib/features/home/legacy/notes_provider.dart:381
