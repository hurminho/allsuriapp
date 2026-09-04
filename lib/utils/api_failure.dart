import 'dart:async';
import 'dart:io';

/// 네트워크·서버 오류를 사용자에게 보여줄 수 있는 형태로 분류합니다.
///
/// 지금까지는 `e.toString()` 을 그대로 스낵바에 띄워서
/// "SocketException: Failed host lookup ..." 같은 개발자 문구가 고객에게
/// 노출됐습니다. 이 분류를 거치면 항상 한국어 안내 문구가 나갑니다.
enum ApiFailureKind {
  /// 인터넷 연결 없음·DNS 실패
  offline,

  /// 응답이 제한 시간을 넘김
  timeout,

  /// 인증 만료(401·403)
  unauthorized,

  /// 요청이 잘못됨(400·404·409) — 대개 사용자 입력 문제
  badRequest,

  /// 서버 오류(5xx)
  server,

  /// 분류하지 못한 오류
  unknown,
}

class ApiFailure implements Exception {
  const ApiFailure(this.kind, this.message, {this.statusCode, this.debugDetail});

  final ApiFailureKind kind;

  /// 사용자에게 그대로 보여줘도 되는 한국어 문구.
  final String message;

  final int? statusCode;

  /// 로그·리포트 전용. UI 에 띄우지 마세요.
  final String? debugDetail;

  /// 같은 요청을 다시 시도해 볼 만한 오류인지.
  bool get isRetryable =>
      kind == ApiFailureKind.offline ||
      kind == ApiFailureKind.timeout ||
      kind == ApiFailureKind.server;

  @override
  String toString() => 'ApiFailure($kind, $statusCode): $message';

  // ---------------------------------------------------------------------------

  static const _offlineMessage = '인터넷 연결을 확인해 주세요.';
  static const _timeoutMessage = '서버 응답이 늦어지고 있습니다. 잠시 후 다시 시도해 주세요.';
  static const _serverMessage = '일시적인 서버 문제로 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.';
  static const _unauthorizedMessage = '로그인이 만료되었습니다. 다시 로그인해 주세요.';
  static const _unknownMessage = '요청을 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.';

  /// 예외 객체를 분류합니다.
  factory ApiFailure.from(Object error) {
    if (error is ApiFailure) return error;

    if (error is TimeoutException) {
      return ApiFailure(ApiFailureKind.timeout, _timeoutMessage,
          debugDetail: '$error');
    }
    if (error is SocketException || error is HttpException) {
      return ApiFailure(ApiFailureKind.offline, _offlineMessage,
          debugDetail: '$error');
    }

    final text = '$error';
    if (text.contains('SocketException') ||
        text.contains('Failed host lookup') ||
        text.contains('Network is unreachable') ||
        text.contains('ClientException')) {
      return ApiFailure(ApiFailureKind.offline, _offlineMessage,
          debugDetail: text);
    }
    if (text.contains('TimeoutException') || text.contains('timed out')) {
      return ApiFailure(ApiFailureKind.timeout, _timeoutMessage,
          debugDetail: text);
    }
    return ApiFailure(ApiFailureKind.unknown, _unknownMessage,
        debugDetail: text);
  }

  /// HTTP 상태 코드를 분류합니다. [serverMessage] 는 서버가 내려준 안내 문구로,
  /// 사용자에게 보여도 되는 짧은 한국어일 때만 채택합니다.
  factory ApiFailure.fromStatus(int statusCode, {String? serverMessage}) {
    final safe = _usableServerMessage(serverMessage);

    if (statusCode == 401 || statusCode == 403) {
      return ApiFailure(
          ApiFailureKind.unauthorized, safe ?? _unauthorizedMessage,
          statusCode: statusCode, debugDetail: serverMessage);
    }
    if (statusCode >= 500) {
      return ApiFailure(ApiFailureKind.server, safe ?? _serverMessage,
          statusCode: statusCode, debugDetail: serverMessage);
    }
    if (statusCode >= 400) {
      return ApiFailure(ApiFailureKind.badRequest, safe ?? _unknownMessage,
          statusCode: statusCode, debugDetail: serverMessage);
    }
    return ApiFailure(ApiFailureKind.unknown, safe ?? _unknownMessage,
        statusCode: statusCode, debugDetail: serverMessage);
  }

  /// 서버 문구를 사용자에게 보여줄 수 있는지 판단합니다.
  ///
  /// 스택 트레이스·예외 클래스명·SQL 오류가 섞여 오는 경우가 있어서,
  /// 한글이 포함된 짧은 문장만 통과시킵니다.
  static String? _usableServerMessage(String? raw) {
    final message = raw?.trim();
    if (message == null || message.isEmpty) return null;
    if (message.length > 120) return null;
    if (!RegExp(r'[가-힣]').hasMatch(message)) return null;
    const developerMarkers = [
      'Exception',
      'Error:',
      'null value',
      'invalid input syntax',
      'violates',
      'constraint',
      'stack',
      'PGRST',
      'at line',
    ];
    for (final marker in developerMarkers) {
      if (message.contains(marker)) return null;
    }
    return message;
  }
}
