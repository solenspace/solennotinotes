import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/generated/app_localizations.dart';

/// Fixed iPhone-13-Pro reference viewport used for every golden (Spec 27
/// "Device frame"). Width × height in logical pixels.
const Size kGoldenViewport = Size(390, 844);

/// Pumps [child] into a `MaterialApp` with [theme], the standard l10n
/// delegates, and a fixed 390×844 surface. The DPI is forced to 1.0 so the
/// golden PNG's pixel dimensions equal the logical size — cross-host
/// stability and predictable file size both follow.
Future<void> pumpScene(
  WidgetTester tester, {
  required ThemeData theme,
  required Widget child,
}) async {
  await tester.binding.setSurfaceSize(kGoldenViewport);
  tester.view.physicalSize = kGoldenViewport;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: theme,
      home: child,
    ),
  );
  // Asset images (pattern backdrops, signatures) resolve through async
  // futures held by the binding. `tester.runAsync` releases the fake clock
  // so those futures complete before we capture the golden; `pumpAndSettle`
  // would hang on indefinite animations like `CircularProgressIndicator`.
  await tester.runAsync(() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  });
  await tester.pump();
}
