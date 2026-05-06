import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:noti_notes_app/features/settings/cubit/theme_state.dart';
import 'package:noti_notes_app/models/noti_identity.dart';
import 'package:noti_notes_app/repositories/noti_identity/noti_identity_repository.dart';
import 'package:noti_notes_app/repositories/settings/settings.dart';
import 'package:noti_notes_app/repositories/settings/settings_repository.dart';
import 'package:noti_notes_app/theme/app_theme.dart';
import 'package:noti_notes_app/theme/app_typography.dart';
import 'package:noti_notes_app/theme/tokens.dart';

/// Builds a `NotiText` role bundle for the chosen writing font + brightness.
/// Defaults to `NotiText.forFont` (which routes through GoogleFonts in
/// production); tests inject a non-network builder so the asset-bundle
/// dependency stays out of unit-test scope.
typedef NotiTextBuilder = NotiText Function(WritingFont font, Brightness brightness);

/// Owns the active `ThemeData` derivation. Subscribes to
/// [SettingsRepository.watch] (themeMode + writingFont) and
/// [NotiIdentityRepository.watch] (signaturePalette[2] = seed accent), and
/// emits a fresh [ThemeState] whenever either upstream changes.
///
/// Mutators ([setThemeMode], [setWritingFont]) write through to
/// `SettingsRepository.save`; the resulting watch emission triggers the
/// derive-and-emit path, so there's exactly one place that builds themes.
class ThemeCubit extends Cubit<ThemeState> {
  ThemeCubit({
    required this.settingsRepository,
    required this.identityRepository,
    @visibleForTesting NotiTextBuilder? textBuilder,
  })  : _textBuilder = textBuilder ?? NotiText.forFont,
        super(
          ThemeState.initial(
            boneTheme: AppTheme.bone(
              text: (textBuilder ?? NotiText.forFont)(
                WritingFont.inter,
                Brightness.light,
              ),
            ),
            darkTheme: AppTheme.dark(
              text: (textBuilder ?? NotiText.forFont)(
                WritingFont.inter,
                Brightness.dark,
              ),
            ),
          ),
        );

  final SettingsRepository settingsRepository;
  final NotiIdentityRepository identityRepository;
  final NotiTextBuilder _textBuilder;

  StreamSubscription<Settings>? _settingsSub;
  StreamSubscription<NotiIdentity>? _identitySub;

  Settings _settings = Settings.defaults;
  NotiIdentity? _identity;

  /// Loads initial state from both repositories, emits the first ready
  /// `ThemeState`, then begins watching for downstream updates. Idempotent
  /// — calling it twice is harmless (subscriptions are replaced).
  Future<void> start() async {
    await _settingsSub?.cancel();
    await _identitySub?.cancel();
    _settings = await settingsRepository.getCurrent();
    _identity = await identityRepository.getCurrent();
    _emitDerivedTheme();
    _settingsSub = settingsRepository.watch().listen((settings) {
      _settings = settings;
      _emitDerivedTheme();
    });
    _identitySub = identityRepository.watch().listen((identity) {
      _identity = identity;
      _emitDerivedTheme();
    });
  }

  Future<void> setThemeMode(ThemeMode mode) {
    return settingsRepository.save(_settings.copyWith(themeMode: mode));
  }

  Future<void> setWritingFont(WritingFont font) {
    return settingsRepository.save(_settings.copyWith(writingFont: font));
  }

  void _emitDerivedTheme() {
    final identity = _identity;
    if (identity == null) return;
    final accent = identity.signaturePalette.length > 2
        ? identity.signaturePalette[2]
        : NotiColors.bone.accent;
    final boneText = _textBuilder(_settings.writingFont, Brightness.light);
    final darkText = _textBuilder(_settings.writingFont, Brightness.dark);
    emit(
      state.copyWith(
        status: ThemeStatus.ready,
        themeMode: _settings.themeMode,
        writingFont: _settings.writingFont,
        boneTheme: AppTheme.bone(seedAccent: accent, text: boneText),
        darkTheme: AppTheme.dark(seedAccent: accent, text: darkText),
      ),
    );
  }

  @override
  Future<void> close() async {
    await _settingsSub?.cancel();
    await _identitySub?.cancel();
    return super.close();
  }
}
