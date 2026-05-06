import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/features/settings/cubit/theme_cubit.dart';
import 'package:noti_notes_app/features/settings/cubit/theme_state.dart';
import 'package:noti_notes_app/models/noti_identity.dart';
import 'package:noti_notes_app/theme/app_typography.dart';
import 'package:noti_notes_app/theme/tokens.dart';

import '../../../repositories/noti_identity/fake_noti_identity_repository.dart';
import '../../../repositories/settings/fake_settings_repository.dart';

/// Test text builder that produces an empty `NotiText` without going
/// through GoogleFonts. Production wiring uses `NotiText.forFont` which
/// fetches via the asset bundle / network; tests stay fully offline by
/// substituting this builder via the cubit's `textBuilder` parameter.
NotiText _stubTextBuilder(WritingFont font, Brightness brightness) {
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

NotiIdentity _identityWithAccent(Color accent) {
  final palette = List<Color>.of(NotiIdentityDefaults.starterPalettes.first);
  palette[2] = accent;
  return NotiIdentity(
    id: 'id',
    displayName: 'Test',
    bornDate: DateTime(2026, 5, 4),
    signaturePalette: palette,
  );
}

ThemeCubit _buildCubit(
  FakeSettingsRepository settings,
  FakeNotiIdentityRepository identity,
) {
  return ThemeCubit(
    settingsRepository: settings,
    identityRepository: identity,
    textBuilder: _stubTextBuilder,
  );
}

/// Listens to the cubit's stream and waits for [expectedAtLeast] emissions
/// or until [timeout]. Mirrors the hand-rolled drain helper used in
/// NotesListBloc tests; spec 07 + progress-tracker open question 13 keep
/// the project on raw `flutter_test` instead of `bloc_test` until
/// `custom_lint 0.8+` lands.
Future<List<ThemeState>> _drain(
  ThemeCubit cubit,
  Future<void> Function() act, {
  required int expectedAtLeast,
  Duration timeout = const Duration(seconds: 2),
}) async {
  final emissions = <ThemeState>[];
  final sub = cubit.stream.listen(emissions.add);
  await act();
  final stopAt = DateTime.now().add(timeout);
  while (emissions.length < expectedAtLeast && DateTime.now().isBefore(stopAt)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  await sub.cancel();
  return emissions;
}

void main() {
  late FakeSettingsRepository settingsRepo;
  late FakeNotiIdentityRepository identityRepo;

  setUp(() {
    settingsRepo = FakeSettingsRepository();
    identityRepo = FakeNotiIdentityRepository();
  });

  tearDown(() async {
    await settingsRepo.dispose();
    await identityRepo.dispose();
  });

  group('ThemeCubit', () {
    test('initial state is ThemeStatus.initial with default themes', () {
      final cubit = _buildCubit(settingsRepo, identityRepo);
      expect(cubit.state.status, ThemeStatus.initial);
      expect(cubit.state.themeMode, ThemeMode.system);
      cubit.close();
    });

    test('start() emits a ready ThemeState with seeded accent', () async {
      const accent = Color(0xFFAA0000);
      identityRepo.emit(_identityWithAccent(accent));

      final cubit = _buildCubit(settingsRepo, identityRepo);
      final emissions = await _drain(cubit, cubit.start, expectedAtLeast: 1);

      expect(emissions, isNotEmpty);
      final ready = emissions.last;
      expect(ready.status, ThemeStatus.ready);
      expect(ready.darkTheme.colorScheme.primary, accent);
      expect(ready.boneTheme.colorScheme.primary, accent);
      await cubit.close();
    });

    test('emits a new ThemeState when identity.watch() emits a new accent', () async {
      const initialAccent = Color(0xFF112233);
      const newAccent = Color(0xFF445566);
      identityRepo.emit(_identityWithAccent(initialAccent));

      final cubit = _buildCubit(settingsRepo, identityRepo);
      await cubit.start();
      expect(cubit.state.darkTheme.colorScheme.primary, initialAccent);

      final emissions = await _drain(
        cubit,
        () async => identityRepo.emit(_identityWithAccent(newAccent)),
        expectedAtLeast: 1,
      );

      expect(emissions, isNotEmpty);
      expect(emissions.last.darkTheme.colorScheme.primary, newAccent);
      await cubit.close();
    });

    test('setThemeMode persists through SettingsRepository.save', () async {
      identityRepo.emit(_identityWithAccent(const Color(0xFF112233)));
      final cubit = _buildCubit(settingsRepo, identityRepo);
      await cubit.start();

      await cubit.setThemeMode(ThemeMode.dark);

      expect(settingsRepo.savedSettings, hasLength(1));
      expect(settingsRepo.savedSettings.last.themeMode, ThemeMode.dark);
      await cubit.close();
    });

    test('setWritingFont persists through SettingsRepository.save', () async {
      identityRepo.emit(_identityWithAccent(const Color(0xFF112233)));
      final cubit = _buildCubit(settingsRepo, identityRepo);
      await cubit.start();

      await cubit.setWritingFont(WritingFont.jetBrainsMono);

      expect(settingsRepo.savedSettings, hasLength(1));
      expect(settingsRepo.savedSettings.last.writingFont, WritingFont.jetBrainsMono);
      await cubit.close();
    });

    test('close cancels both stream subscriptions', () async {
      identityRepo.emit(_identityWithAccent(const Color(0xFF112233)));
      final cubit = _buildCubit(settingsRepo, identityRepo);
      await cubit.start();
      // The repositories' `watch()` are async* generators that yield a
      // snapshot first and then forward the broadcast controller's stream.
      // We need to drain microtasks so the generator advances past the
      // snapshot to the `yield* _controller.stream` line — that's where the
      // controller's `hasListener` flips to `true`.
      await pumpEventQueue();
      expect(identityRepo.hasListener, isTrue);
      expect(settingsRepo.hasListener, isTrue);

      await cubit.close();
      await pumpEventQueue();
      expect(identityRepo.hasListener, isFalse);
      expect(settingsRepo.hasListener, isFalse);
    });
  });
}
