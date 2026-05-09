import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import 'package:noti_notes_app/theme/app_typography.dart';

/// Immutable persisted user-chrome settings. Loaded by the `ThemeCubit` on
/// boot, written through `SettingsRepository.save`. The legacy
/// `appThemeColor` field is intentionally absent — the accent now lives on
/// `NotiIdentity.signaturePalette[2]` and is migrated once on first read
/// after Spec 10 by `HiveSettingsRepository`.
class Settings extends Equatable {
  const Settings({required this.themeMode, required this.writingFont});

  final ThemeMode themeMode;
  final WritingFont writingFont;

  static const Settings defaults = Settings(
    themeMode: ThemeMode.system,
    writingFont: WritingFont.inter,
  );

  Settings copyWith({ThemeMode? themeMode, WritingFont? writingFont}) {
    return Settings(
      themeMode: themeMode ?? this.themeMode,
      writingFont: writingFont ?? this.writingFont,
    );
  }

  @override
  List<Object?> get props => [themeMode, writingFont];
}
