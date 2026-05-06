import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:noti_notes_app/theme/app_typography.dart';
import 'package:noti_notes_app/theme/tokens.dart';

/// Builds `ThemeData` for the bone (canonical) and dark (opt-in) modes.
/// Both factories assemble a `ColorScheme.fromSeed` baseline and surgically
/// override surface/onSurface/primary/onPrimary/error so the framework
/// widgets read the bone palette while every NotiNotes-specific value
/// flows through the `ThemeExtension` layer registered on
/// `ThemeData.extensions`.
class AppTheme {
  AppTheme._();

  static ThemeData bone({Color? seedAccent, NotiText? text}) {
    final colors = NotiColors.bone.copyWith(
      accent: seedAccent ?? NotiColors.bone.accent,
      focus: seedAccent ?? NotiColors.bone.focus,
    );
    final scheme = ColorScheme.fromSeed(
      seedColor: colors.accent,
      brightness: Brightness.light,
    ).copyWith(
      surface: colors.surface,
      onSurface: colors.onSurface,
      primary: colors.accent,
      onPrimary: colors.onAccent,
      error: colors.error,
      outline: colors.divider,
    );
    return _build(
      scheme: scheme,
      colors: colors,
      text: text ?? NotiText.forFont(WritingFont.inter, Brightness.light),
      elevation: NotiElevation.bone,
    );
  }

  static ThemeData dark({Color? seedAccent, NotiText? text}) {
    final colors = NotiColors.dark.copyWith(
      accent: seedAccent ?? NotiColors.dark.accent,
      focus: seedAccent ?? NotiColors.dark.focus,
    );
    final scheme = ColorScheme.fromSeed(
      seedColor: colors.accent,
      brightness: Brightness.dark,
    ).copyWith(
      surface: colors.surface,
      onSurface: colors.onSurface,
      primary: colors.accent,
      onPrimary: colors.onAccent,
      error: colors.error,
      outline: colors.divider,
    );
    return _build(
      scheme: scheme,
      colors: colors,
      text: text ?? NotiText.forFont(WritingFont.inter, Brightness.dark),
      elevation: NotiElevation.dark,
    );
  }

  static ThemeData _build({
    required ColorScheme scheme,
    required NotiColors colors,
    required NotiText text,
    required NotiElevation elevation,
  }) {
    final shape = NotiShape.standardSet;
    final textTheme = text.toTextTheme();
    final isDark = scheme.brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.surface,
      fontFamily: text.bodyLg.fontFamily,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: shape.smRadius),
          side: BorderSide(color: scheme.outline, width: 1.0),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: shape.smRadius),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: shape.smRadius,
          side: BorderSide(color: scheme.outline, width: 1.0),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: shape.smRadius,
          side: BorderSide(color: scheme.outline, width: 1.0),
        ),
      ),
      cardTheme: CardThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: shape.smRadius,
          side: BorderSide(color: scheme.outline, width: 1.0),
        ),
        elevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: shape.smRadius,
          side: BorderSide(color: scheme.outline, width: 1.0),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLg,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: colors.surface,
                systemNavigationBarIconBrightness: Brightness.light,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: colors.surface,
                systemNavigationBarIconBrightness: Brightness.dark,
              ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: colors.onSurfaceMuted.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(shape.sm)),
          side: BorderSide(
            color: colors.divider.withValues(alpha: 0.5),
            width: 1.0,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: shape.smRadius,
          side: BorderSide(color: colors.accent, width: 1.0),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.onSurface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: shape.smRadius),
          textStyle: text.labelLg.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: colors.onAccent,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: shape.smRadius,
            side: BorderSide(color: colors.onSurface, width: 1.0),
          ),
          textStyle: text.labelLg.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceVariant,
        selectedColor: colors.accent,
        labelStyle: text.labelMd,
        secondaryLabelStyle: text.labelMd.copyWith(color: colors.onAccent),
        side: BorderSide(
          color: colors.divider.withValues(alpha: 0.5),
          width: 1.0,
        ),
        shape: RoundedRectangleBorder(borderRadius: shape.smRadius),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceElevated,
        hintStyle: text.bodyMd.copyWith(
          color: colors.onSurfaceMuted.withValues(alpha: 0.6),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: shape.mdRadius,
          borderSide: BorderSide(color: colors.divider, width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: shape.mdRadius,
          borderSide: BorderSide(
            color: colors.divider.withValues(alpha: 0.5),
            width: 1.0,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: shape.mdRadius,
          borderSide: BorderSide(color: colors.accent, width: 1.5),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.divider.withValues(alpha: 0.4),
        thickness: 1,
        space: 1,
      ),
      extensions: [
        colors,
        text,
        NotiMotion.standardSet,
        NotiShape.standardSet,
        elevation,
        NotiSpacing.standardSet,
        NotiPatternBackdrop.none,
        NotiSignature.empty,
      ],
    );
  }
}
