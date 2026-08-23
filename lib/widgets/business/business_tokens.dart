import 'package:flutter/material.dart';

const businessNavy = Color(0xFF0B2545);
const businessBlue = Color(0xFF2E74B5);
const businessBlueLight = Color(0xFFE8EEF5);
const businessCanvas = Color(0xFFF7FAFC);
const businessText = Color(0xFF102A43);
const businessMutedText = Color(0xFF6B7D90);
const businessBorder = Color(0xFFDCE6F0);
const businessYellow = Color(0xFFF5C400);
const businessSuccess = Color(0xFF1F8A70);
const businessWarning = Color(0xFFE6A700);
const businessDanger = Color(0xFFC9403A);

/// 사업자 화면에서만 사용하는 레이아웃·타이포그래피 토큰.
abstract final class BusinessTokens {
  static const navy = businessNavy;
  static const blue = businessBlue;
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
