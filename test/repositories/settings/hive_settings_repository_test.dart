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
}
