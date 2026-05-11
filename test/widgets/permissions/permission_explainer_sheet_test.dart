import 'package:flutter/material.dart';
import 'package:noti_notes_app/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/services/permissions/permission_result.dart';
import 'package:noti_notes_app/services/permissions/permissions_service.dart';
import 'package:noti_notes_app/theme/app_theme.dart';
import 'package:noti_notes_app/theme/app_typography.dart';
import 'package:noti_notes_app/theme/tokens.dart';
import 'package:noti_notes_app/widgets/permissions/permission_explainer_sheet.dart';

import '../../services/permissions/fake_permissions_service.dart';

/// Builds a `NotiText` with empty styles so widget tests don't go through
/// GoogleFonts (which would touch the asset bundle / network). Mirrors the
/// `_stubTextBuilder` pattern in `test/features/settings/cubit/theme_cubit_test.dart`.
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

ThemeData _theme() => AppTheme.bone(
      text: _stubText(WritingFont.inter, Brightness.light),
    );

Widget _harness({
  required PermissionResult result,
  required PermissionsService service,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: _theme(),
    home: Builder(
      builder: (context) {
        return Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => PermissionExplainerSheet.show(
                context,
                title: 'Microphone needed',
                body: 'Notinotes needs microphone access to record audio notes.',
                result: result,
                service: service,
              ),
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
  group('PermissionExplainerSheet', () {
    testWidgets('granted: shows OK and no settings button', (tester) async {
      final fake = FakePermissionsService();
      await tester.pumpWidget(_harness(result: PermissionResult.granted, service: fake));
      await _openSheet(tester);

      expect(find.text('OK'), findsOneWidget);
      expect(find.text('Open settings'), findsNothing);
      expect(find.text('Not now'), findsNothing);
    });

    testWidgets('denied: shows OK and no settings button', (tester) async {
      final fake = FakePermissionsService();
      await tester.pumpWidget(_harness(result: PermissionResult.denied, service: fake));
      await _openSheet(tester);

      expect(find.text('OK'), findsOneWidget);
      expect(find.text('Open settings'), findsNothing);
    });

    testWidgets('limited: shows OK (treated as granted)', (tester) async {
      final fake = FakePermissionsService();
      await tester.pumpWidget(_harness(result: PermissionResult.limited, service: fake));
      await _openSheet(tester);

      expect(find.text('OK'), findsOneWidget);
      expect(find.text('Open settings'), findsNothing);
    });

    testWidgets('permanentlyDenied: shows Not now + Open settings', (tester) async {
      final fake = FakePermissionsService();
      await tester.pumpWidget(
        _harness(result: PermissionResult.permanentlyDenied, service: fake),
      );
      await _openSheet(tester);

      expect(find.text('Not now'), findsOneWidget);
      expect(find.text('Open settings'), findsOneWidget);
      expect(find.text('OK'), findsNothing);
    });

    testWidgets('restricted: shows Not now + Open settings', (tester) async {
      // The OS will not let a parental-controls user actually flip the toggle,
      // but the button still surfaces because `result.isFinalDenial == true`.
      final fake = FakePermissionsService();
      await tester.pumpWidget(_harness(result: PermissionResult.restricted, service: fake));
      await _openSheet(tester);

      expect(find.text('Not now'), findsOneWidget);
      expect(find.text('Open settings'), findsOneWidget);
    });

    testWidgets('tapping Open settings invokes service.openSettings()', (tester) async {
      final fake = FakePermissionsService();
      await tester.pumpWidget(
        _harness(result: PermissionResult.permanentlyDenied, service: fake),
      );
      await _openSheet(tester);

      expect(fake.settingsOpened, isFalse);
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();

      expect(fake.settingsOpened, isTrue);
    });

    testWidgets('tapping Open settings dismisses the sheet', (tester) async {
      final fake = FakePermissionsService();
      await tester.pumpWidget(
        _harness(result: PermissionResult.permanentlyDenied, service: fake),
      );
      await _openSheet(tester);

      expect(find.text('Open settings'), findsOneWidget);
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();

      expect(find.text('Open settings'), findsNothing);
    });
  });
}
