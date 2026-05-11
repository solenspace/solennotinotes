import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noti_notes_app/features/home/widgets/note_card.dart';
import 'package:noti_notes_app/generated/app_localizations.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/theme/app_theme.dart';

/// Spec 29 guard-rail: the note card in the home grid must expose a
/// composed semantic label (title + preview + state) so screen-reader
/// users can identify each tile, and the long-press multi-select gesture
/// must reach screen-reader users through a non-gesture path.

Note _seedNote({
  String id = 'n1',
  String title = 'Groceries',
  bool pinned = false,
}) {
  return Note(
    <String>{'errands'},
    null,
    null,
    const <Map<String, dynamic>>[],
    null,
    null,
    id: id,
    title: title,
    content: '',
    dateCreated: DateTime(2026, 5, 1),
    colorBackground: const Color(0xFFEDE6D6),
    fontColor: const Color(0xFF1C1B1A),
    hasGradient: false,
    isPinned: pinned,
    blocks: [
      {'type': 'text', 'id': 't1', 'text': 'milk, bread, eggs'},
    ],
  );
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.bone(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('Home note card accessibility floor (Spec 29)', () {
    testWidgets('NoteCard exposes a composed Semantics label with the title and preview',
        (tester) async {
      await _pump(
        tester,
        NoteCard(note: _seedNote(), onTap: () {}, onLongPress: () {}),
      );

      final semanticsList = tester.widgetList<Semantics>(find.byType(Semantics));
      final cardLabel = semanticsList.firstWhere(
        (s) => (s.properties.label ?? '').contains('Groceries'),
        orElse: () => throw TestFailure(
          'NoteCard must wrap its body in a Semantics(label:) containing the title (WCAG 4.1.2).',
        ),
      );
      final label = cardLabel.properties.label ?? '';
      expect(label, contains('Groceries'));
      expect(label.toLowerCase(), contains('milk'));
      expect(
        cardLabel.properties.button,
        isTrue,
        reason: 'The card must announce itself as a button so a11y users '
            'know it is activatable.',
      );
    });

    testWidgets('NoteCard tap and long-press callbacks both reach the user', (tester) async {
      var tapped = 0;
      var longPressed = 0;
      await _pump(
        tester,
        NoteCard(
          note: _seedNote(),
          onTap: () => tapped++,
          onLongPress: () => longPressed++,
        ),
      );

      await tester.tap(find.byType(NoteCard));
      await tester.pumpAndSettle();
      expect(tapped, 1);

      await tester.longPress(find.byType(NoteCard));
      await tester.pumpAndSettle();
      expect(
        longPressed,
        1,
        reason: 'Long-press must remain dispatchable so the multi-select '
            'gesture is reachable in addition to the menu-sheet alternative.',
      );
    });

    testWidgets('Pinned notes announce the pinned state to screen readers', (tester) async {
      await _pump(
        tester,
        NoteCard(note: _seedNote(pinned: true), onTap: () {}, onLongPress: () {}),
      );

      final semanticsList = tester.widgetList<Semantics>(find.byType(Semantics));
      final hasPinnedLabel = semanticsList.any(
        (s) => (s.properties.label ?? '').toLowerCase().contains('pinned'),
      );
      expect(
        hasPinnedLabel,
        isTrue,
        reason: 'Pin state is color-coded and an icon — Semantics(label: pinned) '
            'is what makes the state reachable to non-sighted users (WCAG 1.4.1).',
      );
    });
  });
}
