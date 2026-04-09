import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_tokens.dart';
import 'app_typography.dart';
import 'theme_provider.dart';

/// Highly customized modern theme for NotiNotes.
/// Replaces standard Material design with a more distinct, authentic look featuring
/// flat elevations, crisp borders, and refined shapes for a unique personality.
class AppTheme {
  AppTheme._();

  static ThemeData light(WritingFont writingFont, AppThemeColor appColor) {
    final scheme = ColorScheme.fromSeed(
      seedColor: appColor.color,
      brightness: Brightness.light,
    ).copyWith(
      surface: const Color(0xFFFAFAFA),
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFF5F5F5),
      surfaceContainer: const Color(0xFFEFEFEF),
      surfaceContainerHigh: const Color(0xFFE8E8E8),
      surfaceContainerHighest: const Color(0xFFE0E0E0),
      outline: const Color(0xFFD4D4D4),
    );
    return _build(scheme, writingFont, Brightness.light);
  }

  static ThemeData dark(WritingFont writingFont, AppThemeColor appColor) {
    final scheme = ColorScheme.fromSeed(
      seedColor: appColor.color,
      brightness: Brightness.dark,
    ).copyWith(
      surface: const Color(0xFF141414),
      surfaceContainerLowest: const Color(0xFF0E0E0E),
      surfaceContainerLow: const Color(0xFF181818),
      surfaceContainer: const Color(0xFF1F1F1F),
      surfaceContainerHigh: const Color(0xFF262626),
      surfaceContainerHighest: const Color(0xFF2E2E2E),
      outline: const Color(0xFF333333),
    );
    return _build(scheme, writingFont, Brightness.dark);
  }

  static ThemeData _build(
    ColorScheme scheme,
    WritingFont writingFont,
    Brightness brightness,
  ) {
    final textTheme = AppTypography.buildTextTheme(
      brightness: brightness,
      writingFont: writingFont,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      fontFamily: GoogleFonts.getFont(writingFont.googleFontName).fontFamily,
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm), // Neobrutalism small radius
          ),
          side: BorderSide(color: scheme.outline, width: 1.0),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          side: BorderSide(color: scheme.outline, width: 1.0),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          side: BorderSide(color: scheme.outline, width: 1.0),
        ),
      ),
      cardTheme: CardThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          side: BorderSide(color: scheme.outline, width: 1.0),
        ),
        elevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          side: BorderSide(color: scheme.outline, width: 1.0),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: scheme.surface,
                systemNavigationBarIconBrightness: Brightness.light,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: scheme.surface,
                systemNavigationBarIconBrightness: Brightness.dark,
              ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0, // Flat design
        showDragHandle: true,
        dragHandleColor: scheme.onSurfaceVariant.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.sm), // Changed from 32 to use AppRadius token
          ),
          side: BorderSide(
            color: scheme.outline.withValues(alpha: 0.5),
            width: 1.0, // Reduced from 1.5
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
          borderRadius: const BorderRadius.all(Radius.circular(AppRadius.sm)), // Changed from 20
          side: BorderSide(
            color: scheme.primary,
            width: 1.0, // Reduced from 1.5
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm), // Changed from 12
          ),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm), // Changed from 16
            side: BorderSide(color: scheme.onSurface, width: 1.0), // Reduced from 1.5
          ),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        selectedColor: scheme.primary,
        labelStyle: textTheme.labelMedium,
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onPrimary,
        ),
        side: BorderSide(
          color: scheme.outline.withValues(alpha: 0.5),
          width: 1.0, // Thinned
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm), // Changed from 12
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md), // Changed from 16
          borderSide: BorderSide(color: scheme.outline, width: 1.0), // Reduced from 1.5
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md), // Changed from 16
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.5), width: 1.0), // Reduced from 1.5
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md), // Changed from 16
          borderSide: BorderSide(color: scheme.primary, width: 1.5), // Reduced from 2.0
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.4),
        thickness: 1,
        space: 1,
      ),
    );
  }
}
