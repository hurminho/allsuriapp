import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:allsuriapp/utils/api_failure.dart';
import 'package:allsuriapp/utils/app_logger.dart';

class ApiService extends ChangeNotifier {
  // API 기본 URL (dart-define로 덮어쓰기 가능)
  static const String baseUrl = String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'https://api.allsuri.app/api',
      );

  /// 조회 요청 제한 시간. 넘기면 사용자에게 재시도 안내를 띄웁니다.
  static const Duration readTimeout = Duration(seconds: 15);

  /// 쓰기 요청 제한 시간. 입찰·견적 제출은 조회보다 여유를 둡니다.
  static const Duration writeTimeout = Duration(seconds: 25);

  /// 파일 업로드 제한 시간.
  static const Duration uploadTimeout = Duration(seconds: 60);

  ApiService() {
    AppLog.debug('ApiService', 'API_BASE_URL -> $baseUrl');
  }

  /// 테스트에서 실제 네트워크 대신 가짜 클라이언트를 끼울 때 씁니다.
  /// 운영 코드에서는 절대 설정하지 마세요.
  @visibleForTesting
  static http.Client? testClient;

  static http.Client get _client => testClient ?? _defaultClient;
  static final http.Client _defaultClient = http.Client();

  /// 요청을 실행하고 결과를 항상 같은 모양의 Map 으로 돌려줍니다.
  ///
  /// 반환 키
  ///  * `success`    : bool
  ///  * `data`       : 디코드된 응답 본문
  ///  * `message`    : 서버가 준 안내 문구(있을 때)
  ///  * `error`      : **사용자에게 그대로 보여줘도 되는 한국어 문구**
  ///  * `errorKind`  : ApiFailureKind 이름 (offline/timeout/unauthorized/...)
  ///  * `statusCode` : HTTP 상태 코드
  ///  * `retryable`  : 재시도가 의미 있는 오류인지
  ///  * `debugDetail`: 로그 전용 원문. UI 에 띄우지 마세요.
  Future<Map<String, dynamic>> _send(
    String method,
    String endpoint, {
    Object? body,
    Duration? timeout,
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    final limit = timeout ?? (method == 'GET' ? readTimeout : writeTimeout);
    final started = DateTime.now();

    try {
      final headers = _headers();
      final encoded = body == null ? null : json.encode(body);

      final future = switch (method) {
        'GET' => _client.get(uri, headers: headers),
        'POST' => _client.post(uri, headers: headers, body: encoded),
        'PUT' => _client.put(uri, headers: headers, body: encoded),
        'DELETE' => _client.delete(uri, headers: headers),
        _ => throw ArgumentError('지원하지 않는 method: $method'),
      };

      final response = await future.timeout(limit);
      final elapsed = DateTime.now().difference(started).inMilliseconds;

      // 응답 본문은 개인정보를 담을 수 있어 크기만 기록합니다.
      AppLog.debug('ApiService',
          '$method $endpoint -> ${response.statusCode} (${elapsed}ms, ${response.bodyBytes.length}B)');

      dynamic decoded;
      if (response.body.isNotEmpty) {
        try {
          decoded = json.decode(response.body);
        } catch (_) {
          // 서버가 HTML 오류 페이지를 준 경우 등. 아래에서 상태 코드로 처리합니다.
        }
      }
      final serverMessage =
          decoded is Map ? decoded['message']?.toString() : null;

      final isOk = switch (method) {
        'POST' => response.statusCode == 200 || response.statusCode == 201,
        'DELETE' => response.statusCode == 200 || response.statusCode == 204,
        _ => response.statusCode == 200,
      };

      if (isOk) {
        // 200 이면서 본문에 success:false 를 담아 보내는 엔드포인트가 있습니다.
        final nestedFailure = decoded is Map && decoded['success'] == false;
        return {
          'success': !nestedFailure,
          'data': decoded,
          'message': serverMessage,
          'statusCode': response.statusCode,
          if (nestedFailure)
            'error': serverMessage ?? '요청을 처리하지 못했습니다.',
          if (nestedFailure) 'errorKind': ApiFailureKind.badRequest.name,
          if (nestedFailure) 'retryable': false,
        };
      }

      final failure = ApiFailure.fromStatus(response.statusCode,
          serverMessage: serverMessage);
      AppLog.warn('ApiService',
          '$method $endpoint 실패 ${response.statusCode} ${failure.kind.name}');
      return _failureMap(failure, data: decoded, serverMessage: serverMessage);
    } catch (e, stack) {
      final failure = ApiFailure.from(e);
      // 오프라인·타임아웃은 흔한 상황이라 예외 리포트까지 올리지 않습니다.
      if (failure.kind == ApiFailureKind.unknown) {
        AppLog.error('ApiService', e,
            stack: stack, message: '$method $endpoint');
      } else {
        AppLog.warn('ApiService', '$method $endpoint ${failure.kind.name}');
      }
      return _failureMap(failure);
    }
  }

  Map<String, dynamic> _failureMap(
    ApiFailure failure, {
    dynamic data,
    String? serverMessage,
  }) {
    return {
      'success': false,
      'data': data,
      'message': serverMessage,
      'error': failure.message,
      'errorKind': failure.kind.name,
      'statusCode': failure.statusCode,
      'retryable': failure.isRetryable,
      'debugDetail': failure.debugDetail,
    };
  }

  static String? _bearerToken;
  static void setBearerToken(String? token) {
    _bearerToken = token;
  }
  static String? get currentBearerToken => _bearerToken;

  /// 로그인 시점에 저장한 토큰은 약 1시간 후 만료됩니다.
  /// supabase_flutter가 자동 갱신하는 현재 세션 토큰을 우선 사용하고,
  /// 세션이 없을 때만 저장된 토큰으로 폴백합니다.
  static String? _accessToken() {
    try {
      final sessionToken =
          Supabase.instance.client.auth.currentSession?.accessToken;
      if (sessionToken != null && sessionToken.isNotEmpty) return sessionToken;
    } catch (_) {
      // Supabase 초기화 전 호출 등 — 저장된 토큰으로 폴백
    }
    return _bearerToken;
  }

  Map<String, String> _headers() {
    final token = _accessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  // GET 요청
  Future<Map<String, dynamic>> get(String endpoint, {Duration? timeout}) =>
      _send('GET', endpoint, timeout: timeout);

  // POST 요청
  Future<Map<String, dynamic>> post(
    String endpoint,
    Map<String, dynamic> data, {
    Duration? timeout,
  }) =>
      _send('POST', endpoint, body: data, timeout: timeout);

  // PUT 요청
  Future<Map<String, dynamic>> put(
    String endpoint,
    Map<String, dynamic> data, {
    Duration? timeout,
  }) =>
      _send('PUT', endpoint, body: data, timeout: timeout);

  // DELETE 요청
  Future<Map<String, dynamic>> delete(String endpoint, {Duration? timeout}) =>
      _send('DELETE', endpoint, timeout: timeout);

  // 파일 업로드
  Future<Map<String, dynamic>> uploadFile(String endpoint, File file) async {
    try {
      final request =
          http.MultipartRequest('POST', Uri.parse('$baseUrl$endpoint'));
      final token = _accessToken();
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      request.files.add(await http.MultipartFile.fromPath('file', file.path));

      final streamed = await request.send().timeout(uploadTimeout);
      final responseBody = await streamed.stream.bytesToString();
      AppLog.debug('ApiService',
          'UPLOAD $endpoint -> ${streamed.statusCode} (${responseBody.length}B)');

      if (streamed.statusCode == 200 || streamed.statusCode == 201) {
        dynamic decoded;
        try {
          decoded = json.decode(responseBody);
        } catch (_) {}
        return {
          'success': true,
          'data': decoded,
          'message': null,
          'statusCode': streamed.statusCode,
        };
      }
      return _failureMap(ApiFailure.fromStatus(streamed.statusCode));
    } catch (e, stack) {
      final failure = ApiFailure.from(e);
      if (failure.kind == ApiFailureKind.unknown) {
        AppLog.error('ApiService', e, stack: stack, message: 'UPLOAD $endpoint');
      } else {
        AppLog.warn('ApiService', 'UPLOAD $endpoint ${failure.kind.name}');
      }
      return _failureMap(failure);
    }
  }

  // 에러 처리
  void handleError(dynamic error) {
    AppLog.error('ApiService', error is Object ? error : '$error');
  }

  // 알림 설정 관련 메서드들
  Future<Map<String, dynamic>> getNotificationSettings() async {
    return await get('/notifications/settings');
  }

  Future<void> updateNotificationSettings(Map<String, bool> settings) async {
    await put('/notifications/settings', settings);
  }

  Future<void> sendNotification(String userId, String title, String body) async {
    await post('/notifications/send', {
      'userId': userId,
      'title': title,
      'body': body,
    });
  }

  // 채팅 관련 메서드들
  Future<List<Map<String, dynamic>>> getChatRooms() async {
    final response = await get('/chat/rooms');
    if (response['success']) {
      return List<Map<String, dynamic>>.from(response['data'] ?? []);
    }
    return [];
  }

  // 광고 목록 조회 (활성 광고)
  Future<List<Map<String, dynamic>>> getActiveAds() async {
    final response = await get('/ads');
    if (response['success']) {
      return List<Map<String, dynamic>>.from(response['data'] ?? []);
    }
    return [];
  }

  Future<void> trackAdImpression(String adId) async {
    try {
      await post('/ads/$adId/impression', {});
    } catch (_) {}
  }

  Future<void> trackAdClick(String adId) async {
    try {
      await post('/ads/$adId/click', {});
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getMessages(String chatRoomId) async {
    final response = await get('/chat/rooms/$chatRoomId/messages');
    if (response['success']) {
      return List<Map<String, dynamic>>.from(response['data'] ?? []);
    }
    return [];
  }

  Future<void> sendMessage(String chatRoomId, String message) async {
    await post('/chat/rooms/$chatRoomId/messages', {
      'message': message,
    });
  }

  // 채팅방 읽음 처리
  Future<void> markChatRead(String chatRoomId) async {
    await post('/chat/rooms/$chatRoomId/read', {});
  }
}
