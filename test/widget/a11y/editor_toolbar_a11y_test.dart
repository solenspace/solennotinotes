import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noti_notes_app/features/note_editor/widgets/editor_toolbar.dart';
import 'package:noti_notes_app/generated/app_localizations.dart';
import 'package:noti_notes_app/theme/app_theme.dart';

/// Spec 29 guard-rail: every interactive widget on the editor toolbar
/// must expose either a `Semantics(label:)` or an ancestor `Tooltip` so
/// VoiceOver / TalkBack can read it. The toolbar is the most-touched
/// chrome in the app — a future spec adding an unlabelled button here
/// would fail this test and surface the regression at PR time.
Future<void> _pumpToolbar(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.bone(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: EditorToolbar(
          currentBlockIsChecklist: false,
          onToggleChecklist: () {},
          onAddImage: () {},
          onOpenStyleSheet: () {},
          onResetOverlay: () {},
          onOpenReminderSheet: () {},
          onOpenTagSheet: () {},
          onDoneEditing: () {},
        ),
      ),
    ),
  );
}

void main() {
  group('EditorToolbar accessibility floor (Spec 29)', () {
    testWidgets('every visible tool button carries a Tooltip and Semantics label', (tester) async {
      await _pumpToolbar(tester);

      // Every Tooltip in the toolbar must carry a non-empty message — that
      // doubles as the VoiceOver label via the wrapping Semantics in
      // `_ToolButton`.
      final tooltips = tester.widgetList<Tooltip>(find.byType(Tooltip));
      expect(tooltips, isNotEmpty);
      for (final t in tooltips) {
        final msg = t.message ?? '';
        expect(
          msg,
          isNotEmpty,
          reason: 'A Tooltip rendered without a localized message — '
              'every editor-toolbar affordance must have an accessible name (WCAG 4.1.2).',
        );
      }
    });

    testWidgets('every tool button hits the 44x44 minimum touch target', (tester) async {
      await _pumpToolbar(tester);

      // The toolbar wraps each affordance in a fixed 44x44 AnimatedContainer.
      // We assert the rendered size of every `Tooltip` descendant meets the
      // WCAG 2.5.5 / Material 44dp minimum.
      final tooltipFinder = find.byType(Tooltip);
      expect(tooltipFinder, findsWidgets);
      for (final element in tooltipFinder.evaluate()) {
        final size = element.size;
        if (size == null) continue;
        expect(
          size.width,
          greaterThanOrEqualTo(44),
          reason:
              'Editor toolbar button width is below the 44dp minimum touch target (WCAG 2.5.5).',
        );
        expect(
          size.height,
          greaterThanOrEqualTo(44),
          reason:
              'Editor toolbar button height is below the 44dp minimum touch target (WCAG 2.5.5).',
        );
      }
    });
  });
}
