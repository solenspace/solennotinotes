import 'package:flutter/material.dart';
import 'package:noti_notes_app/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/features/inbox/widgets/share_preview_panel.dart';
import 'package:noti_notes_app/models/received_share.dart';
import 'package:noti_notes_app/services/share/share_models.dart';
import 'package:noti_notes_app/theme/app_theme.dart';
import 'package:noti_notes_app/theme/app_typography.dart';
import 'package:noti_notes_app/theme/noti_theme_overlay.dart';
import 'package:noti_notes_app/theme/tokens/typography_tokens.dart';

NotiText _stubText() {
  const blank = TextStyle();
  return const NotiText(
    writingFont: WritingFont.inter,
    brightness: Brightness.light,
    displayLg: blank,
    displayMd: blank,
    displaySm: blank,
    headlineMd: blank,
    titleLg: blank,
    titleMd: blank,
    titleSm: blank,
    bodyLg: blank,
    bodyMd: blank,
    bodySm: blank,
    labelLg: blank,
    labelMd: blank,
    labelSm: blank,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required ReceivedShare share,
  required VoidCallback onAccept,
  required VoidCallback onDiscard,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.bone(text: _stubText()),
      home: SharePreviewPanel(
        share: share,
        onAccept: onAccept,
        onDiscard: onDiscard,
      ),
    ),
  );
}

void main() {
  group('SharePreviewPanel', () {
    testWidgets('renders title, sender chip, and text body', (tester) async {
      await _pump(
        tester,
        share: _share(
          title: 'Dinner ideas',
          blocks: const [
            {'type': 'text', 'id': 'b1', 'text': 'Hello there'},
          ],
        ),
        onAccept: () {},
        onDiscard: () {},
      );
      expect(find.text('Dinner ideas'), findsOneWidget);
      expect(find.text('Hello there'), findsOneWidget);
      expect(find.textContaining('from Alex'), findsOneWidget);
    });

    testWidgets('Accept and Discard buttons invoke callbacks', (tester) async {
      var accepted = 0;
      var discarded = 0;
      await _pump(
        tester,
        share: _share(title: 't'),
        onAccept: () => accepted++,
        onDiscard: () => discarded++,
      );

      await tester.tap(find.text('Discard'));
      await tester.pump();
      await tester.tap(find.text('Accept'));
      await tester.pump();

      expect(accepted, 1);
      expect(discarded, 1);
    });

    testWidgets('renders checklist blocks with check icons', (tester) async {
      await _pump(
        tester,
        share: _share(
          title: 'Groceries',
          blocks: const [
            {'type': 'checklist', 'id': 'c1', 'text': 'Milk', 'checked': true},
            {'type': 'checklist', 'id': 'c2', 'text': 'Eggs', 'checked': false},
          ],
        ),
        onAccept: () {},
        onDiscard: () {},
      );
      expect(find.byIcon(Icons.check_box_rounded), findsOneWidget);
      expect(find.byIcon(Icons.check_box_outline_blank_rounded), findsOneWidget);
    });
  });
}

ReceivedShare _share({
  required String title,
  List<Map<String, dynamic>> blocks = const <Map<String, dynamic>>[],
}) {
  return ReceivedShare(
    shareId: 's',
    receivedAt: DateTime.utc(2026, 5, 9, 12),
    sender: const IncomingSender(
      id: 'alex',
      displayName: 'Alex',
      publicKey: <int>[1, 2, 3],
      signaturePalette: <int>[0xFF112233, 0xFF445566, 0xFF778899, 0xFFAABBCC],
      signaturePatternKey: null,
      signatureAccent: '✦',
      signatureTagline: '',
    ),
    note: IncomingNote(
      id: 'n',
      title: title,
      blocks: blocks,
      tags: const <String>[],
      dateCreated: DateTime.utc(2026, 5, 9, 11),
      reminder: null,
      isPinned: false,
      overlay: const NotiThemeOverlay(
        surface: Color(0xFFEDE6D6),
        surfaceVariant: Color(0xFFE3DBC8),
        accent: Color(0xFF4A8A7F),
        onAccent: Color(0xFFEDE6D6),
      ),
    ),
    assets: const <IncomingAsset>[],
    inboxRoot: '/tmp/s',
  );
}
