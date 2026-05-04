# 03 — project-structure-migration

## Goal

Migrate the imported `lib/` from the legacy `{api, helpers, providers, models, screens, theme, widgets}/` layout to a **collocated feature layout** under `lib/features/<feature>/{bloc, repository, widgets, screen.dart}` with a small set of cross-cutting roots (`app/`, `services/`, `models/`, `theme/`, `helpers/`, `widgets/` for shared widgets only). All movements are file-level — no logic changes, no behavior changes. Imports are updated so the app builds, runs, and `flutter analyze` is clean. After this spec, every future feature spec writes into a single `lib/features/<feature>/` tree instead of four sibling trees.

## Dependencies

- [01-lint-and-format-hardening](01-lint-and-format-hardening.md) — `flutter analyze` is the verification gate, so it must pass first.
- [02-offline-invariant-ci-gate](02-offline-invariant-ci-gate.md) — pre-commit hook is in place; large file moves go through it.

## Agents & skills

**Pre-coding skills:**
- `flutter-apply-architecture-best-practices` — refresh feature-folder organization and import direction conventions.

**After-coding agents:**
- `flutter-expert` — audit the moves; surface any subtle import-path bug the analyzer missed (cyclic imports, dead code).
- `code-reviewer` — confirm `git diff --stat` shows ONLY renames + import-line edits; no method body or class signature changed.

## Design Decisions

- **Collocated `lib/features/<feature>/` over parallel hierarchies.** A feature ships as one folder containing its `bloc/`, `repository/`, `widgets/`, and `screen.dart`. Refactoring or deleting a whole feature touches one tree. Cross-feature greps are still cheap because file naming is regular (`*_bloc.dart`, `*_repository.dart`, etc.).
- **Cross-cutting code stays at `lib/` root.** `services/` (native plugin wrappers), `models/` (shared domain types), `theme/`, `helpers/`, and `widgets/` (shared widgets only) live alongside `features/`. A widget moves *out* of a feature into shared `lib/widgets/` only when a second feature genuinely needs it.
- **Big-bang move.** Every file with an obvious destination moves in this spec; one diff contains all renames + import updates. The two specs that follow (BLoC migration, repository layer) then operate on the final paths from day one.
- **No logic changes.** Method bodies, class signatures, and behavior are untouched. Only the location and import paths change. Naming-only fixes (typos) are allowed; semantic renames (e.g., `User` → `NotiIdentity`) are deferred to the spec that owns the rename.
- **Provider-based files retain their current names** (`lib/providers/*.dart`) and move under their consuming feature's folder, but the migration to `flutter_bloc` is **not** in this spec — it's Spec 05+. The provider files become a temporary `legacy/` subfolder per feature so the codebase still compiles.
- **`lib/widgets/sheets/*` is split per consuming feature.** `note_style_sheet.dart`, `reminder_sheet.dart`, `tag_sheet.dart` move under `features/note_editor/widgets/`. `long_press_menu_sheet.dart` moves under `features/home/widgets/`. `sheet_scaffold.dart` is genuinely shared, so it lands at `lib/widgets/sheets/sheet_scaffold.dart`.
- **Update `architecture.md` and `code-standards.md` in the same commit.** The "System boundaries" section in `architecture.md` and the "File organization" section in `code-standards.md` both describe parallel hierarchies; this spec rewrites those sections to describe the collocated layout. **The 12 invariants are NOT changed.**
- **One typo fix.** `lib/helpers/aligment.dart` → `lib/helpers/alignment.dart`. All references updated.
- **No `index.dart` / barrel files.** Imports stay concrete (`package:noti_notes_app/features/home/screen.dart`), per [`context/code-standards.md`](../context/code-standards.md).

## Implementation

### A. New `lib/` layout (target tree)

```
lib/
├── main.dart                                    ← entry; bootstraps Hive, providers, routes
├── app/                                         ← (created empty; populated in Spec 04+)
│   └── .gitkeep
├── features/
│   ├── home/
│   │   ├── screen.dart                          ← was lib/screens/home_screen.dart
│   │   ├── widgets/
│   │   │   ├── empty_state.dart                 ← was lib/widgets/home/empty_state.dart
│   │   │   ├── expandable_fab.dart              ← was lib/widgets/home/expandable_fab.dart
│   │   │   ├── filter_chips_row.dart            ← was lib/widgets/home/filter_chips_row.dart
│   │   │   ├── home_app_bar.dart                ← was lib/widgets/home/home_app_bar.dart
│   │   │   ├── note_card.dart                   ← was lib/widgets/home/note_card.dart
│   │   │   ├── section_header.dart              ← was lib/widgets/home/section_header.dart
│   │   │   └── long_press_menu_sheet.dart       ← was lib/widgets/sheets/long_press_menu_sheet.dart
│   │   └── legacy/
│   │       └── notes_provider.dart              ← was lib/providers/notes.dart
│   ├── note_editor/
│   │   ├── screen.dart                          ← was lib/screens/note_editor_screen.dart
│   │   └── widgets/
│   │       ├── checklist_block.dart             ← was lib/widgets/editor/checklist_block.dart
│   │       ├── editor_block.dart                ← was lib/widgets/editor/editor_block.dart
│   │       ├── editor_toolbar.dart              ← was lib/widgets/editor/editor_toolbar.dart
│   │       ├── image_block.dart                 ← was lib/widgets/editor/image_block.dart
│   │       ├── note_app_bar.dart                ← was lib/widgets/editor/note_app_bar.dart
│   │       ├── text_block.dart                  ← was lib/widgets/editor/text_block.dart
│   │       ├── note_style_sheet.dart            ← was lib/widgets/sheets/note_style_sheet.dart
│   │       ├── reminder_sheet.dart              ← was lib/widgets/sheets/reminder_sheet.dart
│   │       └── tag_sheet.dart                   ← was lib/widgets/sheets/tag_sheet.dart
│   ├── note_drop/
│   │   └── screen.dart                          ← was lib/screens/note_drop_screen.dart
│   ├── search/
│   │   └── legacy/
│   │       └── search_provider.dart             ← was lib/providers/search.dart
│   ├── settings/
│   │   └── screen.dart                          ← was lib/screens/settings_screen.dart
│   └── user_info/
│       ├── screen.dart                          ← was lib/screens/user_info_screen.dart
│       └── legacy/
│           └── user_data_provider.dart          ← was lib/providers/user_data.dart
├── services/
│   ├── notifications/
│   │   └── notifications_service.dart           ← was lib/api/notifications_api.dart
│   └── image/
│       └── image_picker_service.dart            ← was lib/helpers/photo_picker.dart
├── models/
│   ├── note.dart                                ← was lib/models/note.dart (unchanged)
│   └── user.dart                                ← was lib/models/user.dart (renamed semantically in Spec 09)
├── theme/
│   ├── app_theme.dart                           ← was lib/theme/app_theme.dart
│   ├── app_tokens.dart                          ← was lib/theme/app_tokens.dart
│   ├── app_typography.dart                      ← was lib/theme/app_typography.dart
│   ├── notes_color_palette.dart                 ← was lib/theme/notes_color_palette.dart
│   └── theme_provider.dart                      ← was lib/theme/theme_provider.dart
│                                                  (stays a Provider; migrated in Spec 05+)
├── helpers/
│   ├── alignment.dart                           ← was lib/helpers/aligment.dart (typo fix)
│   ├── color_picker.dart                        ← was lib/helpers/color_picker.dart
│   └── database_helper.dart                     ← was lib/helpers/database_helper.dart
│                                                  (lifted into lib/repositories/ in Spec 04)
├── widgets/                                     ← shared, cross-feature widgets only
│   └── sheets/
│       └── sheet_scaffold.dart                  ← was lib/widgets/sheets/sheet_scaffold.dart
└── assets/                                      ← UNTOUCHED (asset paths in pubspec.yaml unchanged)
    ├── fonts/...
    ├── icons/...
    └── images/...
```

> Note: `lib/repositories/` is **not** created in this spec. Spec 04 is the first to introduce a repository, and that spec creates the folder.

### B. Move sequence (deterministic)

Use `git mv` for every move so history is preserved. Process in this order so intermediate commits compile (each section below is one logical move; commit between sections is fine but a single commit at the end is also acceptable):

1. **Create empty roots:**
   ```bash
   mkdir -p lib/app lib/features lib/services lib/widgets/sheets
   touch lib/app/.gitkeep
   ```

2. **Move screens to feature folders:**
   ```bash
   mkdir -p lib/features/home lib/features/note_editor lib/features/note_drop \
            lib/features/settings lib/features/user_info lib/features/search
   git mv lib/screens/home_screen.dart        lib/features/home/screen.dart
   git mv lib/screens/note_editor_screen.dart lib/features/note_editor/screen.dart
   git mv lib/screens/note_drop_screen.dart   lib/features/note_drop/screen.dart
   git mv lib/screens/settings_screen.dart    lib/features/settings/screen.dart
   git mv lib/screens/user_info_screen.dart   lib/features/user_info/screen.dart
   rmdir lib/screens
   ```

3. **Move feature widgets:**
   ```bash
   mkdir -p lib/features/home/widgets lib/features/note_editor/widgets
   git mv lib/widgets/home/*.dart   lib/features/home/widgets/
   git mv lib/widgets/editor/*.dart lib/features/note_editor/widgets/
   ```

4. **Split sheets:**
   ```bash
   git mv lib/widgets/sheets/long_press_menu_sheet.dart \
          lib/features/home/widgets/long_press_menu_sheet.dart
   git mv lib/widgets/sheets/note_style_sheet.dart \
          lib/features/note_editor/widgets/note_style_sheet.dart
   git mv lib/widgets/sheets/reminder_sheet.dart \
          lib/features/note_editor/widgets/reminder_sheet.dart
   git mv lib/widgets/sheets/tag_sheet.dart \
          lib/features/note_editor/widgets/tag_sheet.dart
   git mv lib/widgets/sheets/sheet_scaffold.dart \
          lib/widgets/sheets/sheet_scaffold.dart   # already at target; no-op if path matches
   rmdir lib/widgets/home lib/widgets/editor
   # lib/widgets/sheets/ now contains only sheet_scaffold.dart
   ```

5. **Move providers to legacy/ subfolders:**
   ```bash
   mkdir -p lib/features/home/legacy lib/features/search/legacy lib/features/user_info/legacy
   git mv lib/providers/notes.dart     lib/features/home/legacy/notes_provider.dart
   git mv lib/providers/search.dart    lib/features/search/legacy/search_provider.dart
   git mv lib/providers/user_data.dart lib/features/user_info/legacy/user_data_provider.dart
   rmdir lib/providers
   ```

6. **Move api/ + helpers/ to services/ and helpers/:**
   ```bash
   mkdir -p lib/services/notifications lib/services/image
   git mv lib/api/notifications_api.dart  lib/services/notifications/notifications_service.dart
   rmdir lib/api
   git mv lib/helpers/photo_picker.dart   lib/services/image/image_picker_service.dart
   git mv lib/helpers/aligment.dart       lib/helpers/alignment.dart
   ```

7. **No-op moves for staying-put files** — `lib/main.dart`, `lib/models/*`, `lib/theme/*`, `lib/helpers/{color_picker,database_helper}.dart` stay where they are.

### C. Update imports

After file moves, every Dart file that imports a moved file needs its import line updated. Two cases:

1. **Absolute imports** (`package:noti_notes_app/...`): mechanical find-and-replace.
2. **Relative imports** (`../`, `./`): may be invalid after moves; convert to absolute as you fix them.

Recommended workflow:

```bash
# Run flutter analyze; it reports every broken import.
flutter analyze 2>&1 | grep -E "Target of URI doesn't exist" | sort -u
```

For each reported import:
- Find the file's new location.
- Replace the import path in the consuming file with the new absolute path.
- After all are fixed, run `dart fix --apply` to catch any auto-fixable cleanup.
- Run `flutter analyze` again until clean.

### D. Update `lib/main.dart`

`lib/main.dart` imports the screens, theme provider, and Hive bootstrapping. Update its imports to the new paths. Confirm:

- `MaterialApp` `home:` and `routes:` reference the new screen paths.
- Provider tree (still using `package:provider`) imports the legacy provider classes from their new `features/<feature>/legacy/` paths.
- No behavioral logic in `main.dart` changes.

### E. Class renames inside files (filename ↔ class)

When `home_screen.dart` becomes `screen.dart`, the **class name stays `HomeScreen`** — only the file name changes. Same for the other screens (`NoteEditorScreen`, etc.). This avoids logic-level renames in this spec. The class-name → file-name alignment can happen later if desired.

The typo fix `aligment.dart` → `alignment.dart`: rename the file, but the class/function names inside don't change unless they were also misspelled.

### F. Update [`context/architecture.md`](../context/architecture.md) — System boundaries

Replace the "System boundaries" section's tree (around the `lib/blocs/<feature>/` … `lib/screens/<feature>/` block) with:

```
lib/
├── main.dart                  ← app entry; bootstraps Hive, providers, routing
├── app/                       ← MaterialApp, theme glue, route table, global providers
├── features/<feature>/        ← collocated feature unit
│   ├── bloc/                  ← BLoCs / Cubits for the feature; no widget imports
│   ├── repository/            ← Hive + filesystem + native-plugin wrappers for the feature
│   ├── widgets/               ← UI components used only by this feature
│   ├── screen.dart            ← single-screen feature (or screens/ if multiple)
│   └── legacy/                ← Provider-based code in transition; retired in Spec 05+
├── services/                  ← cross-cutting native wrappers (STT, TTS, P2P, AI, permissions, notifications, image)
├── models/                    ← immutable domain models shared across features
├── theme/                     ← base ThemeData + NotiTheme overlay system
├── helpers/                   ← stateless utilities (validators, formatters)
├── widgets/                   ← shared widgets used by 2+ features
└── assets/                    ← icons, fonts, pattern images (frozen)
```

The 12 invariants are unchanged; only the layout description is updated. The "Data flow examples" subsection's path references are updated to the new tree.

### G. Update [`context/code-standards.md`](../context/code-standards.md) — File organization

Replace the existing "File organization" tree with the same collocated layout shown in Section F. Keep the rule "Imports: relative within a feature folder, absolute (`package:noti_notes_app/...`) across features."

### H. Update [`context/progress-tracker.md`](../context/progress-tracker.md)

- Mark Spec 03 complete in **Completed**.
- Add to **Architecture decisions**:
  ```markdown
  11. **Collocated feature layout** at `lib/features/<feature>/`. Cross-cutting code at `lib/{services, models, theme, helpers, widgets}/`. Replaces parallel-hierarchy plan from bootstrap.
  ```
- Add to **Open questions** if any imports could not be cleanly migrated.

## Success Criteria

- [ ] Target tree (Section A) matches actual `lib/` exactly. `find lib -type d` reports the directories listed and no extras (besides `assets/`).
- [ ] Every `git mv` in Section B was used (history preserved). `git log --follow lib/features/home/screen.dart` shows the original commit.
- [ ] `flutter analyze` exits 0 (no broken imports).
- [ ] `flutter run` boots the app on iOS simulator and Android emulator with no functional regressions vs the imported codebase. Manual smoke: open home, create a note, edit, save, delete.
- [ ] `flutter test` exits 0 (existing tests still pass; new tests are not added in this spec).
- [ ] `dart format --set-exit-if-changed -l 100 lib/ test/` exits 0.
- [ ] `bash scripts/check-offline.sh` exits 0 (offline invariant unchanged).
- [ ] No file under `lib/assets/` was moved. `pubspec.yaml` asset list is unchanged.
- [ ] No method body, class signature, or behavior was modified. `git diff --stat` shows only renames + import-line edits.
- [ ] [`context/architecture.md`](../context/architecture.md) "System boundaries" matches Section F. **The 12 invariants are unchanged.**
- [ ] [`context/code-standards.md`](../context/code-standards.md) "File organization" matches Section G.
- [ ] [`context/progress-tracker.md`](../context/progress-tracker.md) reflects Spec 03 completion + architecture decision #11.
- [ ] No new dependencies in `pubspec.yaml`.
- [ ] No `index.dart` / barrel files introduced.

## References

- [`context/architecture.md`](../context/architecture.md) — System boundaries (rewritten by this spec)
- [`context/code-standards.md`](../context/code-standards.md) — File organization (rewritten by this spec)
- [`context/ai-workflow-rules.md`](../context/ai-workflow-rules.md) — "Update context file *before* finishing a unit that…changes a system boundary"
- Skill: [`flutter-apply-architecture-best-practices`](../.agents/skills/flutter-apply-architecture-best-practices/SKILL.md) — guidance on feature-folder organization
- Agent: `flutter-expert` — invoke after the moves to audit any subtle import-path bugs the analyzer missed
- Agent: `code-reviewer` — invoke before commit to catch import inconsistencies and any accidental logic changes
