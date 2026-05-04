# 08 — notes-legacy-removal

## Goal

Delete `lib/features/home/legacy/notes_provider.dart` (the original ~492-line `Notes` ChangeNotifier) and its `ChangeNotifierProvider` registration in `lib/main.dart`. Verify zero remaining consumers (every method was migrated to `NotesListBloc` in Spec 05 or `NoteEditorBloc` in Spec 06; both spec families annotated their migrations with `@Deprecated('migrated to ...; remove in Spec 08')`). After this spec, the only legacy ChangeNotifier left in the codebase is `lib/theme/theme_provider.dart`, retired by the theme overhaul spec.

**This spec does NOT remove `package:provider` from `pubspec.yaml`** — `theme_provider.dart` still uses it. Package removal happens when the last consumer migrates (theme spec).

## Dependencies

- [05-bloc-introduction-home](05-bloc-introduction-home.md) and [06-bloc-migration-editor](06-bloc-migration-editor.md) — every method on the legacy `Notes` provider was migrated by these two specs and annotated `@Deprecated`.
- [07-bloc-migration-search-and-user](07-bloc-migration-search-and-user.md) — `Search` and `UserData` legacies already deleted; this spec parallels that pattern for `Notes`.

## Agents & skills

**Pre-coding skills:**
- `dart-fix-static-analysis-errors` — surfaces every undefined-name reference once the legacy file is deleted; mechanical fix loop.

**After-coding agents:**
- `code-reviewer` — confirm no behavior changed for any non-target file; this spec must be diff = pure deletion + main.dart simplification.

## Design Decisions

- **Hard delete, no deprecation window.** The `@Deprecated` markers from Specs 05 and 06 served as a sunset countdown. By the time Spec 08 runs, every call site has been migrated; deletion is mechanical.
- **`flutter analyze` is the gate.** If any reference to `Notes` (the class) survives in `lib/`, the analyzer will fail with "undefined name". Don't try to be clever — let the analyzer enumerate the leftovers.
- **No new tests.** The BLoC tests added in Specs 05–06 already cover all the behavior the deleted methods used to provide.
- **`package:provider` package stays in `pubspec.yaml`** until `theme_provider.dart` migrates. Add a TODO comment next to the import in `theme_provider.dart` referencing the future theme spec.

## Implementation

### A. Delete the legacy file

```bash
git rm lib/features/home/legacy/notes_provider.dart
rmdir lib/features/home/legacy
```

### B. Update `lib/main.dart`

Remove:
- The `import` of `notes_provider.dart`.
- The `ChangeNotifierProvider(create: (ctx) => Notes(...)..loadNotesFromDataBase())` block.
- If `MultiProvider` now wraps only the theme provider, simplify to a single `ChangeNotifierProvider`.

The provider tree shape after the removal:

```dart
runApp(
  MultiRepositoryProvider(
    providers: [
      RepositoryProvider<NotesRepository>.value(value: notesRepository),
      RepositoryProvider<UserRepository>.value(value: userRepository),
    ],
    child: ChangeNotifierProvider(
      // TODO(spec-09 or spec-10): migrate ThemeProvider to a ThemeBloc/Cubit
      // and remove the `provider` package + this wrapper.
      create: (_) => ThemeProvider(),
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (ctx) => NotesListBloc(repository: ctx.read<NotesRepository>())
              ..add(const NotesListSubscribed()),
          ),
          BlocProvider(create: (_) => SearchCubit()),
          BlocProvider(
            create: (ctx) => UserCubit(repository: ctx.read<UserRepository>())..load(),
          ),
        ],
        child: const NotiApp(),
      ),
    ),
  ),
);
```

### C. Run `flutter analyze`; fix any survivor reference

Expected: zero references to `Notes` (the class), `ToolingNote` (the legacy enum), or `notesToDelete` outside the deleted file. If any survive, they were missed migrations from Specs 05–06 — refactor them in this spec rather than restoring the legacy file.

### D. Verify with grep

```bash
grep -RnE "package:noti_notes_app/features/home/legacy/" lib/ test/
grep -RnE "\\bclass Notes\\b" lib/
grep -RnE "ToolingNote" lib/
```

All three should produce zero output.

### E. Update [`context/progress-tracker.md`](../context/progress-tracker.md)

- Mark Spec 08 complete in **Completed**.
- Add to **Architecture decisions**:
  ```markdown
  16. **Legacy `Notes` ChangeNotifier deleted.** The home + editor BLoCs are now the sole sources of truth for notes mutations. `package:provider` package remains in pubspec until `theme_provider.dart` migrates.
  ```
- Move open question 10 ("`NotificationsService` should be instance-ified") higher in the queue if it's still pending.

### F. Spec roadmap update note

If the theme spec has not yet been numbered, the next spec (theme-tokens) is the one that finally removes `package:provider`. Add a note to the next spec's "Dependencies" section confirming this.

## Success Criteria

- [ ] `lib/features/home/legacy/notes_provider.dart` does not exist; `lib/features/home/legacy/` directory does not exist.
- [ ] `flutter analyze` exits 0.
- [ ] `bash scripts/check-offline.sh` exits 0.
- [ ] `dart format --set-exit-if-changed -l 100 lib/ test/` exits 0.
- [ ] `flutter test` exits 0 — no test changes needed; pre-existing BLoC tests carry coverage.
- [ ] `flutter run` boots iOS simulator and Android emulator. Manual smoke equivalent to Specs 05/06: home renders, edit/select/delete works, editor mutations persist.
- [ ] `grep -RnE "\\bclass Notes\\b" lib/` and `grep -RnE "ToolingNote" lib/` both produce zero output.
- [ ] `pubspec.yaml` is **unchanged** (provider stays).
- [ ] `lib/main.dart` no longer imports `notes_provider.dart` and no longer wraps the tree in a `MultiProvider` for legacy notes state.
- [ ] [`context/progress-tracker.md`](../context/progress-tracker.md) records Spec 08 completion + decision 16.

## References

- [05-bloc-introduction-home](05-bloc-introduction-home.md), [06-bloc-migration-editor](06-bloc-migration-editor.md)
- [`context/architecture.md`](../context/architecture.md) — invariants 5, 6
- Agent: `code-reviewer` — invoke pre-commit; this spec must NOT alter behavior, only delete dead code
- Follow-up: theme overhaul spec (numbered when drafted) finalizes `package:provider` removal
