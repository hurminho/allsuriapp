import 'package:flutter/material.dart';

import '../widgets/business/business_tokens.dart';

/// 올수리 앱 공통 디자인 토큰 (네이비·블루 B2B).
class BusinessTheme {
  static const Color navy = BusinessTokens.navy;
  static const Color blue = BusinessTokens.blue;
  static const Color lightBlue = BusinessTokens.blueLight;
  static const Color background = BusinessTokens.canvas;
  static const Color textPrimary = BusinessTokens.text;
  static const Color success = BusinessTokens.success;
  static const Color warning = BusinessTokens.warning;
  static const Color danger = BusinessTokens.danger;
  static const Color surface = BusinessTokens.surface;
  static const Color border = BusinessTokens.border;
  static const Color textMuted = BusinessTokens.mutedText;

  static const double radius = 14;
  static const double radiusSm = 12;
  static const double space = 8;

  static BoxDecoration cardDecoration({Color? color}) {
    return BoxDecoration(
      color: color ?? surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border),
    );
  }

  static ThemeData theme(ThemeData base) {
    final scheme = ColorScheme.fromSeed(
      seedColor: blue,
      primary: blue,
      onPrimary: Colors.white,
      secondary: navy,
      surface: surface,
      error: danger,
      brightness: Brightness.light,
    );
    final textTheme = base.textTheme
        .apply(
          fontFamily: 'NotoSansKR',
          bodyColor: textPrimary,
          displayColor: textPrimary,
        )
        .copyWith(
          headlineSmall: const TextStyle(
            fontFamily: 'NotoSansKR',
            color: textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
          titleLarge: const TextStyle(
            fontFamily: 'NotoSansKR',
            color: textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
          titleMedium: const TextStyle(
            fontFamily: 'NotoSansKR',
            color: textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
          bodyLarge: const TextStyle(
            fontFamily: 'NotoSansKR',
            color: textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w400,
            height: 1.55,
          ),
          bodyMedium: const TextStyle(
            fontFamily: 'NotoSansKR',
            color: textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w400,
            height: 1.5,
          ),
          labelLarge: const TextStyle(
            fontFamily: 'NotoSansKR',
            fontSize: 14,
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
        );

    return base.copyWith(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: Colors.white),
        actionsIconTheme: IconThemeData(color: Colors.white),
      ),
      dividerColor: border,
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: border),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        selectedColor: blue,
        backgroundColor: surface,
        side: const BorderSide(color: border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: blue,
          foregroundColor: Colors.white,
          minimumSize: const Size(44, 48),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: blue,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(44, 48),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: navy,
          minimumSize: const Size(44, 48),
          textStyle: textTheme.labelLarge,
          side: const BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: blue,
          minimumSize: const Size(44, 44),
          textStyle: textTheme.labelLarge,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: blue,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightBlue.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: blue, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      dividerTheme:
          const DividerThemeData(color: border, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        iconColor: navy,
        textColor: textPrimary,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: blue),
      textTheme: textTheme,
    );
  }

  static String formatWon(num amount) {
    final n = amount.round();
    final s = n.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
    return '$s원';
  }

  static String relativeTime(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return '방금';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
  }

  static String regionFromAddress(String address) {
    final parts = address.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '지역 미확인';
    if (parts.length == 1) return parts.first;
    return '${parts[0]} ${parts[1]}';
  }

  static bool isVisitSoon(DateTime visitDate) {
    final hours = visitDate.difference(DateTime.now()).inHours;
    return hours >= 0 && hours <= 48;
  }

  static bool isNewLead(DateTime createdAt) {
    return DateTime.now().difference(createdAt).inHours < 24;
  }
}
