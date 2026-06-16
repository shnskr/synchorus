import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_dimens.dart';
import 'app_typography.dart';

/// Synchorus 앱 테마 (다크 전용).
///
/// 디자인 시스템(`Synchorus Design System`)의 토큰을 Material 3 ThemeData로
/// 조립. Material 위젯들이 ColorScheme·TextTheme를 상속하므로 화면 코드를
/// 거의 안 건드려도 색·폰트가 전역 적용됨.
abstract final class AppTheme {
  static ColorScheme get _scheme {
    final base = ColorScheme.fromSeed(
      seedColor: AppColors.violet200,
      brightness: Brightness.dark,
    );
    return base.copyWith(
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      primaryContainer: AppColors.primaryContainer,
      onPrimaryContainer: AppColors.violet50,
      secondary: AppColors.violet300,
      onSecondary: AppColors.onPrimary,
      secondaryContainer: AppColors.violet800,
      onSecondaryContainer: AppColors.violet100,
      tertiary: AppColors.accent,
      onTertiary: AppColors.onAccent,
      tertiaryContainer: AppColors.onAccent,
      onTertiaryContainer: AppColors.rose200,
      error: AppColors.danger,
      onError: AppColors.ink950,
      // surface = 앱 캔버스(ink950), 컨테이너 단계로 elevation 표현
      surface: AppColors.bg,
      onSurface: AppColors.textHi,
      onSurfaceVariant: AppColors.textMid,
      surfaceContainerLowest: AppColors.ink900,
      surfaceContainerLow: AppColors.ink850,
      surfaceContainer: AppColors.surfaceCard,
      surfaceContainerHigh: AppColors.surfaceRaised,
      surfaceContainerHighest: AppColors.ink700,
      outline: AppColors.borderStrong,
      outlineVariant: AppColors.border,
    );
  }

  static ThemeData get dark {
    final scheme = _scheme;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      fontFamily: AppTypography.sans,
      textTheme: AppTypography.textTheme,
      splashFactory: InkRipple.splashFactory,

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.textHi,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: AppTypography.sans,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.textHi,
        ),
      ),

      cardTheme: CardThemeData(
        color: AppColors.surfaceCard,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.cardBorder,
          side: AppBorders.hairline,
        ),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.surface,
        showDragHandle: true,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.sheetTop),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),

      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.trackActive,
        inactiveTrackColor: AppColors.track,
        thumbColor: AppColors.primary,
        overlayColor: AppColors.primarySoft,
        trackHeight: 4,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          minimumSize: const Size(0, AppSpacing.controlH),
          textStyle: AppTypography.textTheme.labelLarge,
          shape: const StadiumBorder(),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.surfaceRaised,
          foregroundColor: AppColors.textHi,
          elevation: 0,
          minimumSize: const Size(0, AppSpacing.controlH),
          textStyle: AppTypography.textTheme.labelLarge,
          shape: const StadiumBorder(),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: AppBorders.strong,
          minimumSize: const Size(0, AppSpacing.controlH),
          textStyle: AppTypography.textTheme.labelLarge,
          shape: const StadiumBorder(),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: AppTypography.textTheme.labelLarge,
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceRaised,
        selectedColor: AppColors.primarySoft,
        side: AppBorders.hairline,
        labelStyle: AppTypography.textTheme.labelMedium,
        shape: const StadiumBorder(),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceCard,
        hintStyle: const TextStyle(color: AppColors.textLow),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          borderSide: AppBorders.hairline,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          borderSide: AppBorders.hairline,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        titleTextStyle: AppTypography.textTheme.titleLarge,
        contentTextStyle: AppTypography.textTheme.bodyMedium,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceRaised,
        contentTextStyle: const TextStyle(color: AppColors.textHi),
        actionTextColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.onPrimary
              : AppColors.ink300,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.surfaceRaised,
        ),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),

      iconTheme: const IconThemeData(color: AppColors.textHi),
    );
  }
}
