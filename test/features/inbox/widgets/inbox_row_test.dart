import 'package:flutter/material.dart';
import 'package:noti_notes_app/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/features/inbox/widgets/inbox_row.dart';
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

Future<void> _pumpRow(WidgetTester tester, ReceivedShare share, {VoidCallback? onTap}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.bone(text: _stubText()),
      home: Scaffold(body: InboxRow(share: share, onTap: onTap ?? () {})),
    ),
  );
}

void main() {
  group('InboxRow', () {
    testWidgets('renders sender display name and title', (tester) async {
      await _pumpRow(tester, _share(title: 'Dinner ideas'));
      expect(find.textContaining('Alex'), findsOneWidget);
      expect(find.textContaining('Dinner ideas'), findsOneWidget);
    });

    testWidgets('falls back to first text block when title is empty', (tester) async {
      await _pumpRow(
        tester,
        _share(
          title: '',
          blocks: const [
            {'type': 'text', 'id': 'b1', 'text': 'A note body for preview'},
          ],
        ),
      );
      expect(find.textContaining('A note body for preview'), findsOneWidget);
    });

    testWidgets('uses Untitled note when nothing readable exists', (tester) async {
      await _pumpRow(tester, _share(title: ''));
      expect(find.textContaining('Untitled note'), findsOneWidget);
    });

    testWidgets('tapping invokes onTap', (tester) async {
      var tapped = 0;
      await _pumpRow(tester, _share(title: 'Hi'), onTap: () => tapped++);
      await tester.tap(find.byType(InboxRow));
      expect(tapped, 1);
    });

    testWidgets('exposes a semantic label naming the sender', (tester) async {
      await _pumpRow(tester, _share(title: 'Dinner'));
      final semantics = tester.getSemantics(find.byType(InboxRow));
      expect(semantics.label, contains('From Alex'));
      expect(semantics.label, contains('Dinner'));
    });
  });
}

ReceivedShare _share({
  required String title,
  List<Map<String, dynamic>> blocks = const <Map<String, dynamic>>[],
}) {
  return ReceivedShare(
    shareId: 's',
    receivedAt: DateTime.now().subtract(const Duration(minutes: 2)),
    sender: const IncomingSender(
      id: 'alex',
      displayName: 'Alex',
      publicKey: <int>[1, 2, 3],
      signaturePalette: <int>[0xFF112233, 0xFF445566, 0xFF778899, 0xFFAABBCC],
      signaturePatternKey: null,
      signatureAccent: '✦',
      signatureTagline: 'note from alex',
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
