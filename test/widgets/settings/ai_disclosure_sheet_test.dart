import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/features/settings/widgets/ai_disclosure_sheet.dart';
import 'package:noti_notes_app/theme/app_theme.dart';
import 'package:noti_notes_app/theme/app_typography.dart';
import 'package:noti_notes_app/theme/tokens.dart';

NotiText _stubText(WritingFont font, Brightness brightness) {
  const blank = TextStyle();
  return NotiText(
    writingFont: font,
    brightness: brightness,
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

ThemeData _theme() => AppTheme.bone(text: _stubText(WritingFont.inter, Brightness.light));

Widget _harness({required void Function(bool? confirmed) onResult}) {
  return MaterialApp(
    theme: _theme(),
    home: Builder(
      builder: (context) {
        return Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                final result = await AiDisclosureSheet.show(context);
                onResult(result);
              },
              child: const Text('Open sheet'),
            ),
          ),
        );
      },
    ),
  );
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('Open sheet'));
  await tester.pumpAndSettle();
}

void main() {
  group('AiDisclosureSheet', () {
    testWidgets('renders verbatim disclosure copy', (tester) async {
      await tester.pumpWidget(_harness(onResult: (_) {}));
      await _openSheet(tester);

      expect(find.text('Enable AI assist?'), findsOneWidget);
      expect(
        find.textContaining(
          'small language model that runs entirely on this device',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('one-time, one-way connection'),
        findsOneWidget,
      );
      expect(find.textContaining('around 640 MB'), findsOneWidget);
    });

    testWidgets('renders Cancel and Download buttons', (tester) async {
      await tester.pumpWidget(_harness(onResult: (_) {}));
      await _openSheet(tester);

      expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Download'), findsOneWidget);
    });

    testWidgets('Cancel pops with false', (tester) async {
      bool? captured;
      await tester.pumpWidget(_harness(onResult: (r) => captured = r));
      await _openSheet(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(captured, isFalse);
    });

    testWidgets('Download pops with true', (tester) async {
      bool? captured;
      await tester.pumpWidget(_harness(onResult: (r) => captured = r));
      await _openSheet(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Download'));
      await tester.pumpAndSettle();

      expect(captured, isTrue);
    });
  });
}
