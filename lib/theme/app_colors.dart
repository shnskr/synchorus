import 'package:flutter/material.dart';

/// Synchorus 디자인 시스템 컬러 토큰.
///
/// 출처: "Synchorus Design System"/tokens/colors.css — 앱의 Material-You
/// deepPurple dark 스킴을 역설계해 정리한 팔레트. **다크 전용.**
/// 라벤더(primary) + 로즈(accent) on violet-tinted near-black.
///
/// 알파가 들어간 토큰은 `const` 유지를 위해 0xAARRGGBB 로 미리 계산함
/// (base #ECE6F5 = (236,230,245)).
abstract final class AppColors {
  // ---- Brand core · violet --------------------------------
  static const violet50 = Color(0xFFF2ECFF);
  static const violet100 = Color(0xFFE4D8FF);
  static const violet200 = Color(0xFFCBB4FF); // signature lavender — primary
  static const violet300 = Color(0xFFB79CFF);
  static const violet400 = Color(0xFFA689F2);
  static const violet500 = Color(0xFF8A6BE0);
  static const violet600 = Color(0xFF6F50C4);
  static const violet700 = Color(0xFF4F378B); // primary container
  static const violet800 = Color(0xFF311F5C);
  static const violet900 = Color(0xFF211141);

  // ---- rose -----------------------------------------------
  static const rose200 = Color(0xFFF2B8CE); // signature rose — accent / slots
  static const rose300 = Color(0xFFE89BB9);
  static const rose400 = Color(0xFFD97FA2);

  // ---- ink · violet-tinted near-blacks --------------------
  static const ink950 = Color(0xFF100E15); // app background
  static const ink900 = Color(0xFF15121C);
  static const ink850 = Color(0xFF1A1722); // base surface
  static const ink800 = Color(0xFF221E2D); // card surface
  static const ink750 = Color(0xFF2A2538); // elevated surface
  static const ink700 = Color(0xFF342E45);
  static const ink600 = Color(0xFF463F59);
  static const ink500 = Color(0xFF5E5672);
  static const ink300 = Color(0xFF938AA8);
  static const ink100 = Color(0xFFD9D3E6);
  static const paper = Color(0xFFFBFAFE);

  // ---- semantic base --------------------------------------
  static const mint300 = Color(0xFF6FE0B8); // success / in-sync
  static const amber300 = Color(0xFFF2C879); // warning / connecting
  static const coral400 = Color(
    0xFFF2615D,
  ); // danger / exit (= Colors.red[400])

  // ---- semantic aliases — 컴포넌트는 이 이름을 참조 ----------
  // Backgrounds & surfaces
  static const bg = ink950;
  static const surface = ink850;
  static const surfaceCard = ink800;
  static const surfaceRaised = ink750;
  static const surfaceOverlay = Color(
    0xB814121C,
  ); // rgba(20,18,28,0.72) — 시트 scrim

  // Primary (lavender)
  static const primary = violet200;
  static const primaryStrong = violet300;
  static const primaryContainer = violet700;
  static const onPrimary = Color(0xFF2A1A4D);
  static const primarySoft = Color(
    0x24CBB4FF,
  ); // rgba(203,180,255,0.14) — tint/hover

  // Accent (rose)
  static const accent = rose200;
  static const accentStrong = rose300;
  static const accentSoft = Color(0x24F2B8CE); // rgba(242,184,206,0.14)

  // Text
  static const textHi = Color(0xFFECE6F5);
  static const textMid = Color(0xB8ECE6F5); // 0.72
  static const textLow = Color(0x73ECE6F5); // 0.45
  static const textFaint = Color(0x47ECE6F5); // 0.28
  static const onAccent = Color(0xFF43162A);

  // Lines & dividers
  static const border = Color(0x1AECE6F5); // 0.10
  static const borderStrong = Color(0x2EECE6F5); // 0.18
  static const divider = Color(0x12ECE6F5); // 0.07

  // Status
  static const success = mint300;
  static const warning = amber300;
  static const danger = coral400;

  // Control track (sliders)
  static const track = Color(0x29ECE6F5); // 0.16
  static const trackActive = primary;
}
