import 'package:flutter/widgets.dart';

import 'app_colors.dart';

/// 코너 radii — Material-3 derived, 살짝 더 부드럽게. (effects.css)
abstract final class AppRadii {
  static const xs = 6.0;
  static const sm = 10.0; // inputs
  static const md = 14.0; // cards
  static const lg = 20.0;
  static const xl = 28.0; // bottom sheet
  static const pill = 999.0; // buttons / chips

  static const cardBorder = BorderRadius.all(Radius.circular(md));
  static const sheetTop = BorderRadius.vertical(top: Radius.circular(xl));
}

/// 4px 그리드 간격. 앱은 8/12/16 리듬(Material) 위주. (spacing.css)
abstract final class AppSpacing {
  static const x1 = 2.0;
  static const x2 = 4.0;
  static const x3 = 8.0;
  static const x4 = 12.0;
  static const x5 = 16.0; // 기본 화면 패딩
  static const x6 = 20.0;
  static const x7 = 24.0;
  static const x8 = 32.0;
  static const x9 = 40.0;
  static const x10 = 48.0;
  static const x12 = 64.0;

  static const screenPad = 16.0;
  static const touchMin = 44.0;
  static const controlH = 48.0;
}

/// 차분한, 음악적인 모션. 바운스 없음. (effects.css)
abstract final class AppMotion {
  static const easeOut = Cubic(0.22, 1.0, 0.36, 1.0);
  static const easeInOut = Cubic(0.65, 0.0, 0.35, 1.0);
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 320);

  /// press = 살짝 줄어듦 (재생 버튼·칩).
  static const pressScale = 0.97;
}

/// 다크 UI 그림자(은은) + 라벤더 글로우(강조 — 재생 버튼·방 코드에만).
/// (effects.css `--shadow-*`, `--glow-primary/accent`)
abstract final class AppShadows {
  static const sm = [
    BoxShadow(color: Color(0x59000000), blurRadius: 2, offset: Offset(0, 1)),
  ];
  static const md = [
    BoxShadow(color: Color(0x66000000), blurRadius: 16, offset: Offset(0, 4)),
  ];
  static const lg = [
    BoxShadow(color: Color(0x80000000), blurRadius: 40, offset: Offset(0, 12)),
  ];
  static const sheet = [
    BoxShadow(color: Color(0x8C000000), blurRadius: 40, offset: Offset(0, -8)),
  ];

  /// 라벤더 글로우: 0 0 0 1px rgba(203,180,255,0.30) + 0 6px 24px rgba(138,107,224,0.30)
  static const glowPrimary = [
    BoxShadow(color: Color(0x4DCBB4FF), spreadRadius: 1),
    BoxShadow(color: Color(0x4D8A6BE0), blurRadius: 24, offset: Offset(0, 6)),
  ];

  /// 로즈 글로우: 0 0 0 1px rgba(242,184,206,0.30) + 0 6px 24px rgba(217,127,162,0.25)
  static const glowAccent = [
    BoxShadow(color: Color(0x4DF2B8CE), spreadRadius: 1),
    BoxShadow(color: Color(0x40D97FA2), blurRadius: 24, offset: Offset(0, 6)),
  ];

  /// 재생 버튼 라벤더 bloom — 하드 링 없이 부드러운 후광만 (아이콘 뒤 halo).
  static const glowSoft = [
    BoxShadow(color: Color(0x668A6BE0), blurRadius: 28),
    BoxShadow(color: Color(0x33CBB4FF), blurRadius: 12),
  ];
}

/// 하단 시트 scrim / glass 오버레이 blur. (effects.css `--blur-overlay`)
const double kBlurOverlay = 18.0;

/// 보더 헬퍼.
abstract final class AppBorders {
  static const hairline = BorderSide(color: AppColors.border, width: 1);
  static const strong = BorderSide(color: AppColors.borderStrong, width: 1);
}
