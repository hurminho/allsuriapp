import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:allsuriapp/utils/api_failure.dart';

/// 오류 매핑 테스트.
///
/// 목표는 "사용자에게 개발자 문구가 절대 보이지 않는다" 입니다.
void main() {
  group('ApiFailure.from 예외 분류', () {
    test('타임아웃', () {
      final f = ApiFailure.from(TimeoutException('x'));
      expect(f.kind, ApiFailureKind.timeout);
      expect(f.isRetryable, isTrue);
    });

    test('소켓 오류는 오프라인으로 봅니다', () {
      final f = ApiFailure.from(const SocketException('Failed host lookup'));
      expect(f.kind, ApiFailureKind.offline);
      expect(f.message, contains('인터넷 연결'));
    });

    test('http 패키지의 ClientException 도 오프라인으로 봅니다', () {
      final f = ApiFailure.from(Exception('ClientException: Connection closed'));
      expect(f.kind, ApiFailureKind.offline);
    });

    test('분류 못한 예외는 unknown 이지만 안내 문구는 한국어입니다', () {
      final f = ApiFailure.from(StateError('무엇인가 잘못됨'));
      expect(f.kind, ApiFailureKind.unknown);
      expect(f.message, contains('다시 시도'));
    });

    test('ApiFailure 를 다시 감싸지 않습니다', () {
      const original = ApiFailure(ApiFailureKind.server, '서버 오류');
      expect(ApiFailure.from(original), same(original));
    });
  });

  group('ApiFailure.fromStatus 상태 코드 분류', () {
    test('401 은 인증 만료', () {
      final f = ApiFailure.fromStatus(401);
      expect(f.kind, ApiFailureKind.unauthorized);
      expect(f.isRetryable, isFalse);
    });

    test('500 은 서버 오류이고 재시도 가능', () {
      final f = ApiFailure.fromStatus(503);
      expect(f.kind, ApiFailureKind.server);
      expect(f.isRetryable, isTrue);
    });

    test('404 는 badRequest 이고 재시도 대상이 아닙니다', () {
      final f = ApiFailure.fromStatus(404);
      expect(f.kind, ApiFailureKind.badRequest);
      expect(f.isRetryable, isFalse);
      expect(f.statusCode, 404);
    });
  });

  group('서버 문구 채택 규칙', () {
    test('짧은 한국어 안내는 그대로 보여줍니다', () {
      final f =
          ApiFailure.fromStatus(400, serverMessage: '이미 입찰한 일감입니다.');
      expect(f.message, '이미 입찰한 일감입니다.');
    });

    test('영문 예외 문구는 사용자에게 노출하지 않습니다', () {
      final f = ApiFailure.fromStatus(500,
          serverMessage: 'TypeError: cannot read property of undefined');
      expect(f.message, isNot(contains('TypeError')));
      expect(f.message, contains('서버'));
    });

    test('DB 오류 문구는 한국어가 섞여도 거부합니다', () {
      final f = ApiFailure.fromStatus(400,
          serverMessage: '저장 실패: null value in column "amount" violates');
      expect(f.message, isNot(contains('null value')));
    });

    test('너무 긴 문구는 거부합니다', () {
      final f = ApiFailure.fromStatus(400, serverMessage: '가' * 200);
      expect(f.message.length, lessThan(120));
    });

    test('원문은 debugDetail 에만 남습니다', () {
      const raw = 'TypeError: boom';
      final f = ApiFailure.fromStatus(500, serverMessage: raw);
      expect(f.debugDetail, raw);
      expect(f.message, isNot(contains(raw)));
    });
  });
}
