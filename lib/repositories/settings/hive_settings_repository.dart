import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'package:noti_notes_app/repositories/noti_identity/noti_identity_repository.dart';
import 'package:noti_notes_app/repositories/settings/settings.dart';
import 'package:noti_notes_app/repositories/settings/settings_repository.dart';
import 'package:noti_notes_app/theme/app_typography.dart';
import 'package:noti_notes_app/theme/curated_palettes.dart';

/// Hive-backed implementation of [SettingsRepository]. Reuses the existing
/// `settings_v2` box that legacy `ThemeProvider` wrote to so persisted
/// `themeMode` / `writingFont` indices survive the migration. The legacy
/// `appThemeColor` index is read once during [init], converted to a
/// concrete `Color`, and folded into `NotiIdentity.signaturePalette[2]`
/// when the user is still on a default starter accent. After the one-shot
/// the legacy key is deleted.
class HiveSettingsRepository implements SettingsRepository {
  HiveSettingsRepository();

  @visibleForTesting
  HiveSettingsRepository.withBox({required Box<dynamic> box}) : _box = box;

  static const String _boxName = 'settings_v2';
  static const String _themeModeKey = 'themeMode';
  static const String _writingFontKey = 'writingFont';
  static const String _legacyAppColorKey = 'appThemeColor';
  static const String _sttOfflineCapableKey = 'sttOfflineCapable';

  Box<dynamic>? _box;
  StreamController<Settings>? _controller;

  @override
  Future<void> init({NotiIdentityRepository? identityRepository}) async {
    final existing = _box;
    if (existing == null || !existing.isOpen) {
      await Hive.initFlutter();
      _box = await Hive.openBox<dynamic>(_boxName);
    }
    _controller ??= StreamController<Settings>.broadcast();

    final box = _box!;
    if (identityRepository != null && box.containsKey(_legacyAppColorKey)) {
      await _migrateLegacyAppColor(box, identityRepository);
    }
  }

  Box<dynamic> get _openBox {
    final box = _box;
    if (box == null || !box.isOpen) {
      throw StateError('HiveSettingsRepository.init() was not called.');
    }
    return box;
  }

  StreamController<Settings> get _broadcaster {
    return _controller ??= StreamController<Settings>.broadcast();
  }

  @override
  Future<Settings> getCurrent() async {
    final box = _openBox;
    final modeIndex = box.get(_themeModeKey, defaultValue: ThemeMode.system.index) as int;
    final fontIndex = box.get(_writingFontKey, defaultValue: WritingFont.inter.index) as int;
    return Settings(
      themeMode: _safeEnumValue(ThemeMode.values, modeIndex, ThemeMode.system),
      writingFont: _safeEnumValue(WritingFont.values, fontIndex, WritingFont.inter),
    );
  }

  @override
  Stream<Settings> watch() async* {
    yield await getCurrent();
    yield* _broadcaster.stream;
  }

  @override
  Future<void> save(Settings settings) async {
    final box = _openBox;
    await box.put(_themeModeKey, settings.themeMode.index);
    await box.put(_writingFontKey, settings.writingFont.index);
    _broadcaster.add(settings);
  }

  @override
  Future<bool> getSttOfflineCapable() async {
    final box = _openBox;
    return box.get(_sttOfflineCapableKey, defaultValue: false) as bool;
  }

  @override
  Future<void> setSttOfflineCapable(bool value) async {
    final box = _openBox;
    await box.put(_sttOfflineCapableKey, value);
  }

  Future<void> _migrateLegacyAppColor(
    Box<dynamic> box,
    NotiIdentityRepository identityRepository,
  ) async {
    final raw = box.get(_legacyAppColorKey);
    if (raw is! int || raw < 0 || raw >= LegacyAppThemeColors.values.length) {
      await box.delete(_legacyAppColorKey);
      return;
    }
    final legacyColor = LegacyAppThemeColors.values[raw];
    final identity = await identityRepository.getCurrent();
    if (identity.signaturePalette.length > 2 && _isStarterAccent(identity.signaturePalette[2])) {
      final newPalette = List<Color>.of(identity.signaturePalette);
      newPalette[2] = legacyColor;
      final updated = identity.copyWith(signaturePalette: newPalette);
      await identityRepository.save(updated);
    }
    await box.delete(_legacyAppColorKey);
  }

  /// True when [accent] equals one of the four starter-palette accent
  /// slots (`palette[2]`). A user who picked a custom color should not
  /// have it overwritten by the legacy migration.
  bool _isStarterAccent(Color accent) {
    final argb = accent.toARGB32();
    for (final palette in NotiIdentityDefaults.starterPalettes) {
      if (palette.length > 2 && palette[2].toARGB32() == argb) return true;
    }
    return false;
  }

  T _safeEnumValue<T>(List<T> values, int index, T fallback) {
    if (index < 0 || index >= values.length) return fallback;
    return values[index];
  }
}
