import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:allsuriapp/services/api_service.dart';
import 'package:allsuriapp/utils/app_logger.dart';

/// ApiService 계약 테스트.
///
/// 실제 서버·운영 DB 에 요청하지 않습니다. MockClient 로 응답을 만들어
/// 타임아웃·오류 매핑·로그 안전성만 검증합니다.
void main() {
  final logs = <String>[];

  setUp(() {
    logs.clear();
    AppLog.onLog = (level, message) => logs.add(message);
  });

  tearDown(() {
    ApiService.testClient = null;
    AppLog.onLog = null;
  });

  ApiService serviceReturning(
    int status,
    Object? body, {
    Duration delay = Duration.zero,
  }) {
    ApiService.testClient = MockClient((request) async {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      return http.Response(
        body == null ? '' : json.encode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    return ApiService();
  }

  group('성공 응답', () {
    test('GET 200 은 success:true 와 data 를 돌려줍니다', () async {
      final api = serviceReturning(200, {'items': [1, 2, 3]});
      final result = await api.get('/market/bids');

      expect(result['success'], isTrue);
      expect(result['data'], {'items': [1, 2, 3]});
      expect(result['statusCode'], 200);
    });

    test('POST 201 도 성공으로 봅니다', () async {
      final api = serviceReturning(201, {'id': 'abc'});
      final result = await api.post('/market/listings/x/bid', {'amount': 1});
      expect(result['success'], isTrue);
    });

    test('200 + success:false 는 실패로 봅니다', () async {
      final api =
          serviceReturning(200, {'success': false, 'message': '이미 입찰했습니다.'});
      final result = await api.post('/market/listings/x/bid', {'amount': 1});

      expect(result['success'], isFalse);
      // 서버가 보낸 한국어 안내는 그대로 살립니다.
      expect(result['message'], '이미 입찰했습니다.');
      expect(result['error'], '이미 입찰했습니다.');
    });
  });

  group('오류 응답 매핑', () {
    test('401 은 인증 만료 안내', () async {
      final api = serviceReturning(401, {'error': 'invalid token'});
      final result = await api.get('/market/bids');

      expect(result['success'], isFalse);
      expect(result['errorKind'], 'unauthorized');
      expect(result['error'], contains('로그인'));
    });

    test('500 은 재시도 가능으로 표시합니다', () async {
      final api = serviceReturning(500, {'message': 'Internal Error'});
      final result = await api.get('/market/bids');

      expect(result['errorKind'], 'server');
      expect(result['retryable'], isTrue);
    });

    test('404 는 statusCode 로 구분할 수 있습니다', () async {
      // 입찰 취소 화면이 "이미 삭제됨"을 판별하는 데 씁니다.
      final api = serviceReturning(404, null);
      final result = await api.delete('/market/bids/x?bidderId=y');

      expect(result['success'], isFalse);
      expect(result['statusCode'], 404);
    });

    test('오류 문구에 예외 클래스명이 들어가지 않습니다', () async {
      final api = serviceReturning(500, {'message': 'TypeError: boom'});
      final result = await api.post('/x', {});

      expect(result['error'], isNot(contains('TypeError')));
      expect(result['error'], isNot(contains('Exception')));
    });

    test('JSON 이 아닌 오류 본문도 크래시 없이 처리합니다', () async {
      ApiService.testClient = MockClient(
        (_) async => http.Response('<html>502 Bad Gateway</html>', 502),
      );
      final result = await ApiService().get('/x');

      expect(result['success'], isFalse);
      expect(result['errorKind'], 'server');
      expect(result['error'], isNot(contains('html')));
    });
  });

  group('타임아웃', () {
    test('제한 시간을 넘기면 timeout 으로 분류합니다', () async {
      final api = serviceReturning(200, {'ok': true},
          delay: const Duration(milliseconds: 200));

      final result =
          await api.get('/slow', timeout: const Duration(milliseconds: 20));

      expect(result['success'], isFalse);
      expect(result['errorKind'], 'timeout');
      expect(result['retryable'], isTrue);
      expect(result['error'], contains('잠시 후'));
    });

    test('쓰기 요청 기본 제한이 조회보다 깁니다', () {
      // 입찰 제출이 조회보다 먼저 끊기면 안 됩니다.
      expect(ApiService.writeTimeout, greaterThan(ApiService.readTimeout));
    });

    test('제한 시간 안에 오면 정상 처리합니다', () async {
      final api = serviceReturning(200, {'ok': true},
          delay: const Duration(milliseconds: 10));
      final result =
          await api.get('/fast', timeout: const Duration(seconds: 2));
      expect(result['success'], isTrue);
    });
  });

  group('네트워크 예외', () {
    test('연결 실패는 오프라인 안내로 바뀝니다', () async {
      ApiService.testClient = MockClient(
        (_) async => throw http.ClientException('Connection refused'),
      );
      final result = await ApiService().get('/x');

      expect(result['errorKind'], 'offline');
      expect(result['error'], contains('인터넷 연결'));
    });
  });

  group('로그 안전성', () {
    test('응답 본문을 로그에 남기지 않습니다', () async {
      // 실제 응답에는 고객 연락처가 들어오는 경우가 있습니다.
      final api = serviceReturning(200, {
        'customerPhone': '010-1234-5678',
        'address': '서울특별시 강남구 테헤란로 1',
      });
      await api.get('/market/listings');

      final joined = logs.join('\n');
      expect(joined, isNot(contains('1234-5678')));
      expect(joined, isNot(contains('테헤란로')));
      // 진단에 필요한 상태 코드는 남아 있어야 합니다.
      expect(joined, contains('200'));
    });

    test('Authorization 헤더 값을 로그에 남기지 않습니다', () async {
      ApiService.setBearerToken(
          'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ0ZXN0In0.fakesig');
      addTearDown(() => ApiService.setBearerToken(null));

      final api = serviceReturning(200, {'ok': true});
      await api.get('/x');

      expect(logs.join('\n'), isNot(contains('fakesig')));
    });
  });

  group('릴리즈 URL 설정', () {
    test('기본 base URL 이 https 운영 주소입니다', () {
      expect(ApiService.baseUrl, startsWith('https://'));
      expect(ApiService.baseUrl, isNot(contains('localhost')));
      expect(ApiService.baseUrl, isNot(contains('10.0.2.2')));
      expect(ApiService.baseUrl, endsWith('/api'));
    });
  });
}
