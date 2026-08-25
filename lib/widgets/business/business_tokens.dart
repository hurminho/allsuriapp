import 'package:flutter/material.dart';

// 웹(allsuricommerce.netlify.app)과 톤을 맞춘 값. 웹은 Tailwind 기본
// 팔레트를 쓰므로 blue-600/blue-800/yellow-400/gray-50 을 그대로 가져온다.
const businessNavy = Color(0xFF0B2545);
const businessBlue = Color(0xFF2563EB); // blue-600
const businessBlueDark = Color(0xFF1D4ED8); // blue-700
const businessHeroEnd = Color(0xFF1E40AF); // blue-800
const businessBlueLight = Color(0xFFEFF6FF); // blue-50
const businessCanvas = Color(0xFFF9FAFB); // gray-50
const businessText = Color(0xFF111827); // gray-900
const businessMutedText = Color(0xFF6B7280); // gray-500
const businessBorder = Color(0xFFE5E7EB); // gray-200
const businessYellow = Color(0xFFFACC15); // yellow-400
const businessSuccess = Color(0xFF1F8A70);
const businessWarning = Color(0xFFE6A700);
const businessDanger = Color(0xFFC9403A);

/// 사업자 화면에서만 사용하는 레이아웃·타이포그래피 토큰.
abstract final class BusinessTokens {
  static const navy = businessNavy;
  static const blue = businessBlue;
  static const blueDark = businessBlueDark;
  static const heroEnd = businessHeroEnd;
  static const blueLight = businessBlueLight;
  static const canvas = businessCanvas;
  static const text = businessText;
  static const mutedText = businessMutedText;
  static const border = businessBorder;
  static const yellow = businessYellow;
  static const success = businessSuccess;
  static const warning = businessWarning;
  static const danger = businessDanger;
  static const surface = Colors.white;

  static const double space4 = 4;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space24 = 24;
  static const double space32 = 32;
  static const double cardRadius = 16;
  static const double controlRadius = 12;
  static const double pagePadding = 16;

  static BoxDecoration card({
    Color color = surface,
    Color borderColor = border,
    double radius = cardRadius,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor),
    );
  }

  /// 웹 히어로 섹션과 같은 blue-600 → blue-800 그라데이션.
  static BoxDecoration hero({double radius = cardRadius}) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [blue, heroEnd],
      ),
    );
  }

  static const title = TextStyle(
    color: text,
    fontSize: 20,
    fontWeight: FontWeight.w800,
    height: 1.25,
  );

  static const sectionTitle = TextStyle(
    color: text,
    fontSize: 16,
    fontWeight: FontWeight.w800,
    height: 1.3,
  );

  static const body = TextStyle(
    color: text,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.45,
  );

  static const caption = TextStyle(
    color: mutedText,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.35,
  );
}
