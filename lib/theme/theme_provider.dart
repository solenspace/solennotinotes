import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'app_typography.dart';

enum AppThemeColor {
  indigo(Color(0xFF4F46E5), 'Indigo'),
  emerald(Color(0xFF10B981), 'Emerald'),
  rose(Color(0xFFE11D48), 'Rose'),
  sunset(Color(0xFFF97316), 'Sunset'),
  midnight(Color(0xFF334155), 'Midnight');

  final Color color;
  final String displayName;
  const AppThemeColor(this.color, this.displayName);
}

/// Stores the user's chosen theme mode, writing font, and app color, persisted to a
/// dedicated Hive box (`settings_v2`).
class ThemeProvider with ChangeNotifier {
  static const String _boxName = 'settings_v2';
  static const String _themeModeKey = 'themeMode';
  static const String _writingFontKey = 'writingFont';
  static const String _appThemeColorKey = 'appThemeColor';

  ThemeMode _themeMode = ThemeMode.system;
  WritingFont _writingFont = WritingFont.inter;
  AppThemeColor _appColor = AppThemeColor.indigo;

  ThemeMode get themeMode => _themeMode;
  WritingFont get writingFont => _writingFont;
  AppThemeColor get appColor => _appColor;

  static Future<void> ensureBoxOpen() async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox(_boxName);
    }
  }

  void load() {
    final box = Hive.box(_boxName);
    final modeIndex = box.get(_themeModeKey, defaultValue: ThemeMode.system.index) as int;
    _themeMode = ThemeMode.values[modeIndex];

    final fontIndex = box.get(_writingFontKey, defaultValue: WritingFont.inter.index) as int;
    _writingFont = WritingFont.values[fontIndex];

    final colorIndex = box.get(_appThemeColorKey, defaultValue: AppThemeColor.indigo.index) as int;
    _appColor = AppThemeColor.values[colorIndex];

    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    await Hive.box(_boxName).put(_themeModeKey, mode.index);
    notifyListeners();
  }

  Future<void> setWritingFont(WritingFont font) async {
    if (_writingFont == font) return;
    _writingFont = font;
    await Hive.box(_boxName).put(_writingFontKey, font.index);
    notifyListeners();
  }

  Future<void> setAppColor(AppThemeColor color) async {
    if (_appColor == color) return;
    _appColor = color;
    await Hive.box(_boxName).put(_appThemeColorKey, color.index);
    notifyListeners();
  }
}
