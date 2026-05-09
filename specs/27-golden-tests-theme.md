# 27 — golden-tests-theme

## Goal

Add **golden tests** that lock the visual output of every theme variant — base dark + base light + each of the 12 curated palettes from `lib/theme/curated_palettes.dart` (Spec 11) + each of the 7 bundled patterns. A single regression-prone change (a token value, a shade tweak, a pattern alpha shift) becomes immediately visible in `flutter test --update-goldens` diffs. The spec ships the harness + ~60 golden PNGs covering the matrix.

## Dependencies

- [10-theme-tokens](10-theme-tokens.md), [11-noti-theme-overlay](11-noti-theme-overlay.md) — what we lock visually.
- [05-bloc-introduction-home](05-bloc-introduction-home.md), [06-bloc-migration-editor](06-bloc-migration-editor.md) — golden tests render real screens with bloc state.

## Agents & skills

**Pre-coding skills:**
- `flutter-add-widget-test` — golden harness conventions, viewport sizing.
- `flutter-add-widget-preview` — preview each scene before committing the golden.

**After-coding agents:**
- `ui-designer` — eyeball every golden after the first run; reject any unintended side-effects (token values out of range, off-by-one spacing).

## Design Decisions

- **Golden harness**: Flutter's built-in `matchesGoldenFile` + `flutter_test`. No third-party libraries.
- **Golden scope**: `Home` (3 notes), `NoteEditor` (text + image + audio), `OverlayPickerSheet` (each tab), `ShareNearbySheet` (discover + sending phases), `InboxScreen` (empty + 3 entries).
- **Variants**: each scene rendered in:
  - Base dark theme
  - Base light theme
  - Each of the 12 curated palettes (Charcoal, Slate, Moss, Plum, Ember, Tide, Sand, Paper, Frost, Olive, Coral, Onyx) — only on `NoteEditor` + `Home` since other surfaces stay base-themed.
  - Each of the 7 patterns at the body opacity tier — on `NoteEditor` only.
- **Output**: PNG goldens stored under `test/goldens/<scene>/<variant>.png`. Roughly 60 files at MVP.
- **Device frame**: a fixed 390×844 viewport (iPhone 13 Pro reference). Cross-device responsiveness is verified separately by widget tests.
- **Skia-based rendering**: `flutter test` uses Skia by default. Goldens generated on macOS commit ~5–10 KB each PNG.

## Implementation

### A. Test files

```
test/goldens/                                  ← PNG outputs (committed; checked by CI)
├── home/<variant>.png
├── editor/<variant>.png
├── overlay_picker/<tab>.png
├── share_sheet/<phase>.png
└── inbox/<state>.png

test/widget/golden/
├── home_golden_test.dart
├── editor_golden_test.dart
├── overlay_picker_golden_test.dart
├── share_sheet_golden_test.dart
└── inbox_golden_test.dart
```

### B. Test pattern

```dart
void main() {
  group('Editor goldens', () {
    for (final variant in [
      ('dark_base', AppTheme.dark()),
      ('light_base', AppTheme.light()),
      ...kCuratedPalettes.map((p) => (p.name, AppTheme.darkWithOverlay(p))),
    ]) {
      testWidgets('editor — ${variant.$1}', (tester) async {
        await tester.pumpWidget(MaterialApp(
          theme: variant.$2,
          home: BlocProvider.value(
            value: _seededEditorBloc(),
            child: const NoteEditorScreen(),
          ),
        ));
        await expectLater(
          find.byType(NoteEditorScreen),
          matchesGoldenFile('../../goldens/editor/${variant.$1}.png'),
        );
      });
    }
  });
}
```

### C. Seeded fixtures

Helper builders create deterministic notes (fixed timestamps, fixed UUIDs) for goldens:

```dart
Note _fixtureNote({String id = 'g-001', NotiThemeOverlay? overlay}) { ... }
NoteEditorBloc _seededEditorBloc() { ... }
NotesListBloc _seededHomeBloc() { ... }
```

### D. Workflow commands

- Update goldens: `flutter test --update-goldens test/widget/golden`.
- Verify: `flutter test test/widget/golden` (default — fails on diff).

### E. CI hint

A future CI spec runs only on macOS to avoid Skia rendering differences across platforms. Until CI lands, the policy is: regenerate goldens on macOS before commit; reject PRs that update goldens from non-macOS hosts.

## Success Criteria

- [ ] `test/goldens/` has the 60-ish PNGs covering the matrix in Section A.
- [ ] `flutter test test/widget/golden` exits 0 on a fresh checkout.
- [ ] Changing a token value in `lib/theme/tokens/` produces a visible diff in `flutter test --update-goldens`.
- [ ] Goldens are < 30 KB each (Skia compressed PNGs).
- [ ] No invariant changed.

## References

- [10](10-theme-tokens.md), [11](11-noti-theme-overlay.md), [27 itself]
- Skill: [`flutter-add-widget-test`](../.agents/skills/flutter-add-widget-test/SKILL.md)
- Agent: `ui-designer` — invoke after the first run; eyeball the goldens for unintended side-effects (token values out of range, etc.)
- Follow-up: cross-platform golden CI in a future infra spec.
