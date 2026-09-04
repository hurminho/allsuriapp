import 'package:flutter/foundation.dart';

/// 앱 전역 로깅.
///
/// 두 가지를 보장합니다.
///  1. 릴리즈 빌드에서는 아무것도 출력하지 않습니다. `print`는 릴리즈에서도
///     그대로 실행되므로, 로그 호출을 이 유틸로 모아 한곳에서 차단합니다.
///  2. 출력 전에 개인정보를 가립니다. 전화번호·이메일·토큰·주소가 로그로
///     새어 나가면 릴리즈 심사와 개인정보 정책 양쪽에서 문제가 됩니다.
///
/// 크래시 리포터(Crashlytics·Sentry)를 붙일 때는 [onReport] 만 채우면 됩니다.
/// 외부 계정 연동은 별도 승인이 필요하므로 훅만 열어 둡니다.
abstract final class AppLog {
  /// 크래시 리포터 연결 지점. 기본은 null(아무 데도 보내지 않음).
  ///
  /// 예: `AppLog.onReport = (e, s, ctx) => FirebaseCrashlytics.instance
  ///        .recordError(e, s, reason: ctx);`
  static void Function(Object error, StackTrace? stack, String? context)?
      onReport;

  /// 테스트에서 로그 호출을 관찰할 때 씁니다.
  @visibleForTesting
  static void Function(String level, String message)? onLog;

  static void debug(String tag, String message) => _emit('D', tag, message);

  static void info(String tag, String message) => _emit('I', tag, message);

  static void warn(String tag, String message) => _emit('W', tag, message);

  /// 예외를 기록합니다. 릴리즈에서도 [onReport] 가 있으면 그쪽으로는 전달됩니다.
  static void error(
    String tag,
    Object error, {
    StackTrace? stack,
    String? message,
  }) {
    final masked = mask(message == null ? '$error' : '$message: $error');
    _emit('E', tag, masked);
    onReport?.call(error, stack, '$tag${message == null ? '' : ' · $message'}');
  }

  static void _emit(String level, String tag, String message) {
    final masked = mask(message);
    onLog?.call(level, '[$tag] $masked');
    if (kReleaseMode) return;
    debugPrint('$level [$tag] $masked');
  }

  // ---------------------------------------------------------------------------
  // 마스킹
  // ---------------------------------------------------------------------------

  static final _phone = RegExp(r'01[016789][-\s]?\d{3,4}[-\s]?\d{4}');
  static final _email = RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+');
  // JWT 및 Bearer 토큰
  static final _jwt = RegExp(r'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+\.?[A-Za-z0-9_-]*');
  static final _bearer = RegExp(r'(?<=Bearer )[A-Za-z0-9._-]{8,}');
  // OpenAI·서비스 키 형태
  static final _apiKey = RegExp(r'sk-[A-Za-z0-9_-]{16,}');
  // "서울특별시 강남구 역삼동 123-45" 처럼 시·도로 시작하는 상세 주소
  static final _address = RegExp(
    r'(서울|부산|대구|인천|광주|대전|울산|세종|경기|강원|충북|충남|전북|전남|경북|경남|제주)'
    r'[가-힣]*\s?[가-힣]+(시|군|구)\s[가-힣0-9\s-]{2,}',
  );

  /// 로그 문자열에서 개인정보·비밀값을 가립니다.
  ///
  /// 완전히 지우지 않고 일부만 남기는 이유는, 장애를 추적할 때 "같은 사용자인가"
  /// 정도는 구분할 수 있어야 하기 때문입니다.
  static String mask(String input) {
    if (input.isEmpty) return input;
    return input
        .replaceAll(_jwt, '<token>')
        .replaceAll(_bearer, '<token>')
        .replaceAll(_apiKey, '<apikey>')
        .replaceAllMapped(_phone, (m) {
          final digits = m[0]!.replaceAll(RegExp(r'\D'), '');
          return '${digits.substring(0, 3)}****${digits.substring(digits.length - 4)}';
        })
        .replaceAllMapped(_email, (m) {
          final value = m[0]!;
          final at = value.indexOf('@');
          final head = value.substring(0, at);
          final kept = head.length <= 2 ? head : head.substring(0, 2);
          return '$kept***${value.substring(at)}';
        })
        .replaceAllMapped(_address, (m) => '${m[1]}*** (주소 생략)');
  }

  /// UUID 등 식별자를 앞 8자만 남깁니다. 로그 상관관계 추적용입니다.
  static String shortId(Object? id) {
    final s = '${id ?? ''}';
    if (s.length <= 8) return s;
    return '${s.substring(0, 8)}…';
  }
}
