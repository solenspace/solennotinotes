# 01 — lint-and-format-hardening

## Goal

Tighten the Dart static-analysis baseline by extending `analysis_options.yaml` with seven hand-picked rules on top of `flutter_lints`, set `dart format` to a 100-column line length, and apply `dart fix --apply` so the existing codebase passes the new lints. After this spec, `flutter analyze` is clean, `dart format --set-exit-if-changed lib/ test/ -l 100` is clean, and the verification commands documented in [`context/code-standards.md`](../context/code-standards.md) and [`CLAUDE.md`](../CLAUDE.md) are runnable as-is.

## Dependencies

None — first spec.

## Agents & skills

**Pre-coding skills** (load before writing code):
- `dart-run-static-analysis` — refresh the analyze-then-fix loop conventions.
- `dart-fix-static-analysis-errors` — workflow for resolving the warnings the new lints surface.

**After-coding agents** (dispatch when implementation lands):
- `code-reviewer` — confirm `dart fix --apply` did not silently change behavior; verify the lint-debt list in `progress-tracker.md` matches what the analyzer reports.

## Design Decisions

- **Hand-picked lint additions over community presets.** The seven rules listed in [`context/code-standards.md`](../context/code-standards.md) ("Dart and analyzer" section) are explicit, justified, and require no third-party dev dependency. We deliberately skip `very_good_analysis` to keep the dependency graph minimal — the offline invariant rewards fewer transitive packages.
- **Line length 100.** Compromise between Dart's default 80 (tight inside nested widget trees) and 120 (risks horizontal scroll). Matches `very_good_analysis` and the Flutter community default. Configured both in `analysis_options.yaml` (for `dart_style`) and as the `-l 100` flag on every format command.
- **`dart fix --apply` is run as part of this spec; manual cleanups are deferred.** Any rule with an automated fix (const constructors, const literals, single quotes, trailing commas, return types) gets corrected now. Rules without auto-fixes (`avoid_print`, `unawaited_futures`) may surface remaining warnings — those go on a TODO list in [`context/progress-tracker.md`](../context/progress-tracker.md) and are addressed in the spec that next touches the offending file.
- **No CI yet.** A forbidden-imports + lint CI gate lands in Spec 02. This spec only sets the local baseline.
- **No new dev dependencies.** `flutter_lints` is already in `pubspec.yaml`; the seven additions are core lint rules that ship with the analyzer.
- **Protected files stay protected.** Generated files and native project files are excluded from analysis via the `analyzer.exclude` list.

## Implementation

### A. Replace `analysis_options.yaml`

Path: `analysis_options.yaml` (root)

```yaml
# Static-analysis configuration for Notinotes.
# See context/code-standards.md "Dart and analyzer" for rationale.

include: package:flutter_lints/flutter.yaml

analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
  errors:
    # Promote a few warnings to errors so CI fails on them.
    avoid_print: error
    unawaited_futures: error
    always_declare_return_types: error
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"
    - "**/*.mocks.dart"
    - "build/**"
    - "ios/Pods/**"
    - "android/**/build/**"

linter:
  rules:
    # Const correctness — cheaper rebuilds, smaller bundles.
    prefer_const_constructors: true
    prefer_const_literals_to_create_immutables: true

    # Hygiene
    avoid_print: true
    unawaited_futures: true
    always_declare_return_types: true

    # Style consistency
    prefer_single_quotes: true
    require_trailing_commas: true

# Configure dart format line length.
formatter:
  page_width: 100
```

> Notes:
> - `analyzer.language.strict-*` flags tighten implicit-cast and dynamic-typing escape hatches without requiring `--strict-mode` in CI.
> - `formatter.page_width: 100` is read by `dart format` (Dart 3.7+) so contributors don't need to remember the `-l 100` flag — but every documented command still passes `-l 100` for explicitness and older Dart versions.
> - Generated and native build artifacts are excluded so adapter regen and pod installs don't trip the analyzer.

### B. Apply auto-fixes to existing code

```bash
flutter pub get
dart fix --apply
dart format -l 100 lib/ test/
flutter analyze
```

If `flutter analyze` still reports issues after the auto-fix pass:

1. **Auto-fixable issues (still red):** repeat `dart fix --apply` once; some fixes cascade. If still red, the issue category goes to the TODO list (Step D).
2. **Manual issues (no auto-fix):** record file paths + lint name + count in [`context/progress-tracker.md`](../context/progress-tracker.md) under a new "Lint debt" subsection. Resolve in the spec that next touches the offending file.
3. **False positives in legacy code:** as a last resort, add `// ignore: <lint>` with a one-line reason. Use sparingly; CI grep tracks count over time.

### C. Document verification commands

[`context/code-standards.md`](../context/code-standards.md) already lists `dart format --set-exit-if-changed lib/ test/`. Update that line and the matching one in [`context/ai-workflow-rules.md`](../context/ai-workflow-rules.md) to:

```bash
dart format --set-exit-if-changed -l 100 lib/ test/
```

Update [`CLAUDE.md`](../CLAUDE.md) "Verification before declaring a unit done" to use the same command.

### D. Append a "Lint debt" subsection to `progress-tracker.md`

After Spec 01 runs, list every remaining lint warning that wasn't auto-fixable, grouped by rule and file. Format:

```markdown
## Lint debt (post Spec 01)

- `unawaited_futures` (5 hits)
  - lib/screens/notes/notes_screen.dart:42, :78
  - lib/screens/note_editor/note_editor_screen.dart:103, :211, :289
- `avoid_print` (2 hits)
  - lib/api/sample_notes.dart:14, :22
```

Each entry is closed by the future spec that refactors that file. The list shrinks; it never grows from this point.

## Success Criteria

- [ ] `analysis_options.yaml` matches Section A verbatim; nothing else under `linter:` or `analyzer:` is changed by hand.
- [ ] `flutter pub get` succeeds without modifications to `pubspec.yaml` or `pubspec.lock` (no new packages).
- [ ] `dart fix --apply` ran and any auto-fixed files are part of this spec's commit.
- [ ] `dart format --set-exit-if-changed -l 100 lib/ test/` exits 0.
- [ ] `flutter analyze` exits 0 — or, if non-zero, every remaining warning is itemized under "Lint debt" in `progress-tracker.md` with a file path and line number.
- [ ] [`CLAUDE.md`](../CLAUDE.md), [`context/code-standards.md`](../context/code-standards.md), and [`context/ai-workflow-rules.md`](../context/ai-workflow-rules.md) all reference the `-l 100` flag in their verification command lists.
- [ ] [`context/progress-tracker.md`](../context/progress-tracker.md) marks Spec 01 as completed in the **Completed** section and removes it from **In progress**.
- [ ] No invariant in [`context/architecture.md`](../context/architecture.md) is touched.
- [ ] No code under `lib/assets/`, native project folders, or generated `.g.dart` files is edited.

## References

- [`context/code-standards.md`](../context/code-standards.md) — "Dart and analyzer" section (the seven extra rules + line-length rationale)
- [`context/ai-workflow-rules.md`](../context/ai-workflow-rules.md) — "Verification commands" section
- [`context/progress-tracker.md`](../context/progress-tracker.md) — "Lint debt" entry to be added
- Skill: [`flutter-fix-static-analysis-errors`](../.agents/skills/dart-fix-static-analysis-errors/SKILL.md) (workflow for resolving warnings)
- Skill: [`dart-run-static-analysis`](../.agents/skills/dart-run-static-analysis/SKILL.md) (the analyze + dart-fix loop)
- Agent: `flutter-expert` (consult before editing if a lint surfaces a Flutter-specific antipattern)
