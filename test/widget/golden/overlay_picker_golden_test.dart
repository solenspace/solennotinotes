import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noti_notes_app/features/note_editor/bloc/note_editor_bloc.dart';
import 'package:noti_notes_app/features/note_editor/widgets/overlay_accent_picker.dart';
import 'package:noti_notes_app/features/note_editor/widgets/overlay_palette_grid.dart';
import 'package:noti_notes_app/features/note_editor/widgets/overlay_pattern_grid.dart';
import 'package:noti_notes_app/theme/app_theme.dart';

import '_fixtures/fixture_notes.dart';
import '_helpers/golden_text.dart';
import '_helpers/pump_scene.dart';
import '_helpers/seeded_editor_bloc.dart';

/// Three goldens, one per tab. All base-themed (the picker sheet itself
/// renders against the editor's overlay-themed surface in production, but
/// the tab bodies' visual identity comes from the picker tiles, not the
/// surrounding sheet chrome — and the spec § A pins these to base only).
void main() {
  group('Overlay picker goldens', () {
    testWidgets('overlay_picker — palette', (tester) async {
      await _pumpTab(tester, _Tab.palette);
      await expectLater(
        find.byType(OverlayPaletteGrid),
        matchesGoldenFile('../../goldens/overlay_picker/palette.png'),
      );
    });

    testWidgets('overlay_picker — pattern', (tester) async {
      await _pumpTab(tester, _Tab.pattern);
      await expectLater(
        find.byType(OverlayPatternGrid),
        matchesGoldenFile('../../goldens/overlay_picker/pattern.png'),
      );
    });

    testWidgets('overlay_picker — accent', (tester) async {
      await _pumpTab(tester, _Tab.accent);
      await expectLater(
        find.byType(OverlayAccentPicker),
        matchesGoldenFile('../../goldens/overlay_picker/accent.png'),
      );
    });
  });
}

enum _Tab { palette, pattern, accent }

Future<void> _pumpTab(WidgetTester tester, _Tab tab) async {
  final env = seededEditorEnv(fixtureNoteA());
  addTearDown(env.bloc.close);
  addTearDown(env.notes.dispose);

  final scroll = ScrollController();
  addTearDown(scroll.dispose);

  await pumpScene(
    tester,
    theme: AppTheme.bone(text: goldenText()),
    child: BlocProvider<NoteEditorBloc>.value(
      value: env.bloc,
      child: Scaffold(
        body: SafeArea(
          child: switch (tab) {
            _Tab.palette => OverlayPaletteGrid(scrollController: scroll),
            _Tab.pattern => OverlayPatternGrid(scrollController: scroll),
            _Tab.accent => OverlayAccentPicker(scrollController: scroll),
          },
        ),
      ),
    ),
  );
  // Let the seeded bloc's EditorOpened handler complete.
  await tester.pump();
}
