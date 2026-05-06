import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import 'package:noti_notes_app/theme/app_typography.dart';

enum ThemeStatus { initial, ready }

/// State emitted by [ThemeCubit]. `MaterialApp` reads
/// `state.themeMode` plus the two derived themes to render. The
/// `writingFont` field is exposed verbatim so the settings screen can
/// render its picker without re-reading the repository.
class ThemeState extends Equatable {
  const ThemeState({
    required this.status,
    required this.themeMode,
    required this.writingFont,
    required this.boneTheme,
    required this.darkTheme,
  });

  final ThemeStatus status;
  final ThemeMode themeMode;
  final WritingFont writingFont;
  final ThemeData boneTheme;
  final ThemeData darkTheme;

  /// Initial state before the cubit's `start()` resolves. The themes here
  /// are placeholder values keyed off the bone defaults so an early
  /// `MaterialApp` build still has something to paint.
  factory ThemeState.initial({
    required ThemeData boneTheme,
    required ThemeData darkTheme,
  }) {
    return ThemeState(
      status: ThemeStatus.initial,
      themeMode: ThemeMode.system,
      writingFont: WritingFont.inter,
      boneTheme: boneTheme,
      darkTheme: darkTheme,
    );
  }

  ThemeState copyWith({
    ThemeStatus? status,
    ThemeMode? themeMode,
    WritingFont? writingFont,
    ThemeData? boneTheme,
    ThemeData? darkTheme,
  }) {
    return ThemeState(
      status: status ?? this.status,
      themeMode: themeMode ?? this.themeMode,
      writingFont: writingFont ?? this.writingFont,
      boneTheme: boneTheme ?? this.boneTheme,
      darkTheme: darkTheme ?? this.darkTheme,
    );
  }

  @override
  List<Object?> get props => [status, themeMode, writingFont, boneTheme, darkTheme];
}
