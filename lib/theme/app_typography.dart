import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Synchorus 타이포그래피. (typography.css)
///
/// 역할 분담: **글자 = Pretendard, 숫자 = DM Mono.**
/// - Pretendard: 모든 UI/본문/제목 (한글+영문). Variable 1파일로 w400~w800.
/// - DM Mono: 방 코드·타이머·IP·±반음·×속도 (tabular).
abstract final class AppTypography {
  static const sans = 'Pretendard';
  static const mono = 'DM Mono';

  /// px 스케일을 Material TextTheme 슬롯에 매핑. letterSpacing은 em→px 환산.
  /// (display/headline은 -0.02em tight, body는 1.5 line-height)
  static const textTheme = TextTheme(
    displayLarge: TextStyle(
      fontFamily: sans,
      fontSize: 44,
      fontWeight: FontWeight.w800,
      height: 1.12,
      letterSpacing: -0.88,
      color: AppColors.textHi,
    ),
    displayMedium: TextStyle(
      fontFamily: sans,
      fontSize: 36,
      fontWeight: FontWeight.w800,
      height: 1.12,
      letterSpacing: -0.72,
      color: AppColors.textHi,
    ),
    displaySmall: TextStyle(
      fontFamily: sans,
      fontSize: 30,
      fontWeight: FontWeight.w700,
      height: 1.2,
      letterSpacing: -0.6,
      color: AppColors.textHi,
    ),
    headlineLarge: TextStyle(
      fontFamily: sans,
      fontSize: 32,
      fontWeight: FontWeight.w700,
      height: 1.2,
      letterSpacing: -0.64,
      color: AppColors.textHi,
    ),
    headlineMedium: TextStyle(
      fontFamily: sans,
      fontSize: 28,
      fontWeight: FontWeight.w700,
      height: 1.2,
      letterSpacing: -0.56,
      color: AppColors.textHi,
    ),
    headlineSmall: TextStyle(
      fontFamily: sans,
      fontSize: 22,
      fontWeight: FontWeight.w700,
      height: 1.25,
      color: AppColors.textHi,
    ),
    titleLarge: TextStyle(
      fontFamily: sans,
      fontSize: 20,
      fontWeight: FontWeight.w600,
      height: 1.3,
      color: AppColors.textHi,
    ),
    titleMedium: TextStyle(
      fontFamily: sans,
      fontSize: 17,
      fontWeight: FontWeight.w600,
      height: 1.3,
      color: AppColors.textHi,
    ),
    titleSmall: TextStyle(
      fontFamily: sans,
      fontSize: 15,
      fontWeight: FontWeight.w600,
      height: 1.3,
      color: AppColors.textHi,
    ),
    bodyLarge: TextStyle(
      fontFamily: sans,
      fontSize: 17,
      fontWeight: FontWeight.w400,
      height: 1.5,
      color: AppColors.textHi,
    ),
    bodyMedium: TextStyle(
      fontFamily: sans,
      fontSize: 15,
      fontWeight: FontWeight.w400,
      height: 1.5,
      color: AppColors.textMid,
    ),
    bodySmall: TextStyle(
      fontFamily: sans,
      fontSize: 13,
      fontWeight: FontWeight.w400,
      height: 1.45,
      color: AppColors.textMid,
    ),
    labelLarge: TextStyle(
      fontFamily: sans,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.2,
      color: AppColors.textHi,
    ),
    labelMedium: TextStyle(
      fontFamily: sans,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: AppColors.textMid,
    ),
    labelSmall: TextStyle(
      fontFamily: sans,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: AppColors.textLow,
    ),
  );

  /// 숫자용 DM Mono — 방 코드, 타이머, IP, ±반음, ×속도. tabular figures.
  static TextStyle monoStyle({
    double fontSize = 15,
    FontWeight fontWeight = FontWeight.w400,
    Color color = AppColors.textHi,
    double? letterSpacing,
    double? height,
  }) {
    return TextStyle(
      fontFamily: mono,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  /// 큰 mono — 방 코드(hero numeric)용.
  static const roomCode = TextStyle(
    fontFamily: mono,
    fontSize: 44,
    fontWeight: FontWeight.w500,
    color: AppColors.primary,
    letterSpacing: 4,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// eyebrow 라벨 — TRANSPOSE / SPEED. 10px, 대문자, 0.14em tracking.
  static const eyebrow = TextStyle(
    fontFamily: sans,
    fontSize: 10,
    fontWeight: FontWeight.w600,
    height: 1.0,
    letterSpacing: 1.4, // 0.14em @ 10px
    color: AppColors.textLow,
  );
}
