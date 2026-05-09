import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:noti_notes_app/models/noti_identity.dart';
import 'package:noti_notes_app/repositories/settings/hive_settings_repository.dart';
import 'package:noti_notes_app/repositories/settings/settings.dart';
import 'package:noti_notes_app/theme/app_typography.dart';
import 'package:noti_notes_app/theme/curated_palettes.dart';

import '../noti_identity/fake_noti_identity_repository.dart';

void main() {
  late Directory tempDir;
  late Box<dynamic> box;
  late HiveSettingsRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_settings_repo_test_');
    Hive.init(tempDir.path);
    box = await Hive.openBox<dynamic>('settings_v2');
    repo = HiveSettingsRepository.withBox(box: box);
  });

  tearDown(() async {
    await box.close();
    await Hive.deleteBoxFromDisk('settings_v2');
    await tempDir.delete(recursive: true);
  });

  group('HiveSettingsRepository', () {
    test('getCurrent returns Settings.defaults when box is empty', () async {
      final settings = await repo.getCurrent();
      expect(settings, Settings.defaults);
    });

    test('save then getCurrent round-trips themeMode and writingFont', () async {
      const updated = Settings(
        themeMode: ThemeMode.dark,
        writingFont: WritingFont.lora,
      );
      await repo.save(updated);

      final restored = await repo.getCurrent();
      expect(restored, updated);
    });

    test('watch yields current snapshot then save events', () async {
      final emissions = <Settings>[];
      final sub = repo.watch().listen(emissions.add);

      await Future<void>.delayed(Duration.zero);
      expect(emissions, [Settings.defaults]);

      await repo.save(Settings.defaults.copyWith(themeMode: ThemeMode.dark));
      await Future<void>.delayed(Duration.zero);
      expect(emissions.length, 2);
      expect(emissions.last.themeMode, ThemeMode.dark);

      await sub.cancel();
    });

    test('out-of-range persisted indices fall back to defaults', () async {
      await box.put('themeMode', 999);
      await box.put('writingFont', -1);

      final settings = await repo.getCurrent();
      expect(settings.themeMode, ThemeMode.system);
      expect(settings.writingFont, WritingFont.inter);
    });
  });

  group('appThemeColor migration', () {
    test('moves the legacy color into signaturePalette[2] and clears the key', () async {
      // Persist a legacy index — 3 = sunset.
      await box.put('appThemeColor', 3);

      // Identity has a starter palette, so the user is on a default accent.
      final identityRepo = FakeNotiIdentityRepository();
      final starter = NotiIdentityDefaults.starterPalettes.first;
      final identity = NotiIdentity(
        id: 'id',
        displayName: '',
        bornDate: DateTime(2026, 5, 4),
        signaturePalette: List.of(starter),
      );
      identityRepo.emit(identity);

      await repo.init(identityRepository: identityRepo);

      expect(
        box.containsKey('appThemeColor'),
        isFalse,
        reason: 'legacy key should be deleted after one-shot migration',
      );
      expect(identityRepo.savedIdentities, hasLength(1));
      expect(
        identityRepo.savedIdentities.single.signaturePalette[2],
        LegacyAppThemeColors.values[3],
      );
    });

    test('does NOT overwrite a custom (non-starter) accent', () async {
      await box.put('appThemeColor', 1);

      const customAccent = Color(0xFF112233);
      final identityRepo = FakeNotiIdentityRepository();
      final identity = NotiIdentity(
        id: 'id',
        displayName: '',
        bornDate: DateTime(2026, 5, 4),
        signaturePalette: [
          NotiIdentityDefaults.starterPalettes.first[0],
          NotiIdentityDefaults.starterPalettes.first[1],
          customAccent,
          NotiIdentityDefaults.starterPalettes.first[3],
        ],
      );
      identityRepo.emit(identity);

      await repo.init(identityRepository: identityRepo);

      expect(
        box.containsKey('appThemeColor'),
        isFalse,
        reason: 'legacy key is still cleared even when accent is preserved',
      );
      expect(
        identityRepo.savedIdentities,
        isEmpty,
        reason: 'a customized accent must not be overwritten',
      );
    });

    test('skips migration silently when identityRepository is null', () async {
      await box.put('appThemeColor', 2);

      await repo.init();

      // Without an identity repo, migration does nothing — including not
      // deleting the legacy key. A future warm boot with the identity wired
      // in completes the migration.
      expect(box.containsKey('appThemeColor'), isTrue);
    });
  });

  group('device-capability cache (Spec 17)', () {
    test('every getter returns null when the box is empty', () async {
      expect(await repo.getAiTier(), isNull);
      expect(await repo.getRamBytes(), isNull);
      expect(await repo.getOsMajorVersion(), isNull);
      expect(await repo.getArchIsArm64(), isNull);
      expect(await repo.getHasMetal(), isNull);
      expect(await repo.getHasNeuralEngine(), isNull);
      expect(await repo.getLastProbedOsVersion(), isNull);
    });

    test('round-trips every key through set/get', () async {
      await repo.setAiTier('full');
      await repo.setRamBytes(8 * 1024 * 1024 * 1024);
      await repo.setOsMajorVersion(17);
      await repo.setArchIsArm64(true);
      await repo.setHasMetal(true);
      await repo.setHasNeuralEngine(true);
      await repo.setLastProbedOsVersion('Darwin 23.4.0');

      expect(await repo.getAiTier(), 'full');
      expect(await repo.getRamBytes(), 8 * 1024 * 1024 * 1024);
      expect(await repo.getOsMajorVersion(), 17);
      expect(await repo.getArchIsArm64(), isTrue);
      expect(await repo.getHasMetal(), isTrue);
      expect(await repo.getHasNeuralEngine(), isTrue);
      expect(await repo.getLastProbedOsVersion(), 'Darwin 23.4.0');
    });

    test('passing null clears every key from the box', () async {
      await repo.setAiTier('compact');
      await repo.setRamBytes(4 * 1024 * 1024 * 1024);
      await repo.setOsMajorVersion(33);
      await repo.setArchIsArm64(true);
      await repo.setHasMetal(false);
      await repo.setHasNeuralEngine(false);
      await repo.setLastProbedOsVersion('Linux 5.10 API 33');

      await repo.setAiTier(null);
      await repo.setRamBytes(null);
      await repo.setOsMajorVersion(null);
      await repo.setArchIsArm64(null);
      await repo.setHasMetal(null);
      await repo.setHasNeuralEngine(null);
      await repo.setLastProbedOsVersion(null);

      expect(box.containsKey('aiTier'), isFalse);
      expect(box.containsKey('ramBytes'), isFalse);
      expect(box.containsKey('osMajorVersion'), isFalse);
      expect(box.containsKey('archIsArm64'), isFalse);
      expect(box.containsKey('hasMetal'), isFalse);
      expect(box.containsKey('hasNeuralEngine'), isFalse);
      expect(box.containsKey('lastProbedOsVersion'), isFalse);
    });

    test('roundtrips falsey values without confusing them with absence', () async {
      // The cache distinguishes "never probed" (null) from "probed and got
      // a falsey value" (0 / false). Important for the iOS-only flags which
      // are legitimately false on Android.
      await repo.setRamBytes(0);
      await repo.setArchIsArm64(false);
      await repo.setHasMetal(false);
      await repo.setHasNeuralEngine(false);

      expect(await repo.getRamBytes(), 0);
      expect(await repo.getArchIsArm64(), isFalse);
      expect(await repo.getHasMetal(), isFalse);
      expect(await repo.getHasNeuralEngine(), isFalse);
    });
  });
}
