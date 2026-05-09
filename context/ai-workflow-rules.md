# Notinotes — AI Workflow Rules

## Approach

Spec-driven incremental build. Numbered specs in `/specs/` define the build order and the unit contract (Goal, Design, Implementation, Success Criteria). One unit at a time. The agent reads the six context files and the active spec **before** writing any code.

Specs are **not pre-written**. They are drafted one at a time, in conversation with the user, just before the unit is built. The `specs/` folder is empty at bootstrap.

## Scoping rules

- Work on one unit at a time.
- Prefer small, verifiable increments.
- Don't combine unrelated boundaries in one step (e.g., a P2P change and a theme refactor).
- Don't mix UI + repository + new dependency in one pass unless the spec explicitly says "contract sync".

## When to split work

- BLoC + repository + new plugin in one pass → split into two specs.
- Adding a forbidden-imports CI gate at the same time as touching `pubspec.yaml` → split.
- A NotiTheme schema change that requires migrating saved Hive records → schema spec is its own unit.
- Anything touching native iOS / Android project files for plugin permissions → its own spec.

## Handling missing requirements

- **Never invent** behavior, types, or values not in context files or the active spec.
- Things that must NOT be invented:
  - Hive box names
  - BLoC event/state class names that imply behavior the spec hasn't defined
  - P2P payload schema fields
  - AI model identifiers (Gemma 2-2B vs Phi-3-mini vs Qwen2.5-1.5B — chosen per spec after benchmarks)
  - Permission strings (look up in plugin docs and the spec)
  - Share payload `format_version` values
  - NotiTheme palette / pattern enum values
- If ambiguous: resolve in the active context file or spec **before** implementing.
- If genuinely missing: log under "Open questions" in `progress-tracker.md` and pause.

## Protected files

Do not edit unless a spec explicitly calls for it:
- `lib/assets/*` — icons, fonts, images, patterns are finalized
- `pubspec.lock` — never hand-edit
- Generated `*.g.dart` files (Hive adapters, json_serializable output) — only via `build_runner`
- Native project files (`ios/Runner.xcodeproj/*`, `android/app/build.gradle.kts`, `Info.plist`, `AndroidManifest.xml`) — change only when a spec adds a permission or plugin
- Past specs once they're completed — do not retroactively edit
- The six context files are *append-only and timeless* — invariants and conventions are added, not rewritten

## Keeping context files in sync

Update the relevant context file **before** finishing a unit that:
- Introduces or changes an invariant
- Changes a system boundary
- Changes the storage model
- Introduces a new color / token / motion tier
- Adds or removes a forbidden import
- Changes a verification command

`progress-tracker.md` is the only file that documents per-phase state and updates frequently. Everything else is timeless.

## Before declaring a unit done

- Spec's success criteria are met.
- No invariant violated. Re-read the **Invariants** section of `architecture.md` before claiming completion.
- `flutter analyze` clean.
- `flutter test` green.
- `dart format --set-exit-if-changed -l 100 lib/ test/` clean.
- App boots in iOS simulator and Android emulator.
- For UI work: simulated airplane mode confirms no network call appears in logs (invariant 1 sanity).
- For AI work: device capability gate verified on a low-RAM emulator profile.
- For P2P work: two devices/simulators successfully exchange a payload end-to-end.
- `progress-tracker.md` updated in the same commit as the unit's last change.

## Verification commands

- `flutter analyze` — Dart static analysis
- `dart format --set-exit-if-changed -l 100 lib/ test/` — formatter
- `flutter test` — unit + widget tests
- `flutter test integration_test/` — integration tests (per integration spec)
- `flutter build apk --debug` — smoke build
- `flutter build ios --debug --no-codesign` — iOS smoke build
- `pnpm dlx skills list` — verify installed skills
- `grep -RnE "package:http|package:dio|HttpClient|firebase_|supabase_" lib/` — must exit non-zero (no matches)

## Communication

- Update `progress-tracker.md` in the same commit as the unit's last change.
- Surface architectural surprises as **open questions** in `progress-tracker.md`, not silent workarounds.
- No commentary inside source files. Commentary lives in context files + progress tracker.
- When asked to plan a new spec, propose Goal + Design Decisions + Success Criteria first; await user confirmation; *then* write the spec file.
