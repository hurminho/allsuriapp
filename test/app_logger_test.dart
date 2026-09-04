import 'package:flutter_test/flutter_test.dart';
import 'package:allsuriapp/utils/app_logger.dart';

/// 개인정보가 로그로 새어 나가는 것은 P0 이슈입니다.
/// 마스킹이 풀리면 여기서 바로 깨지도록 고정합니다.
///
/// 주의: 이 테스트에는 실제 고객 번호·주소·키를 쓰지 않습니다.
/// 모두 형식만 맞춘 가짜 값입니다.
void main() {
  group('AppLog.mask 전화번호', () {
    test('하이픈 있는 번호를 가립니다', () {
      final masked = AppLog.mask('연락처: 010-1234-5678');
      expect(masked, contains('010****5678'));
      expect(masked, isNot(contains('1234')));
    });

    test('하이픈 없는 번호도 가립니다', () {
      expect(AppLog.mask('01098765432'), contains('010****5432'));
    });

    test('011·016 등 구형 번호도 가립니다', () {
      expect(AppLog.mask('011-222-3333'), isNot(contains('222')));
    });

    test('문장 안 여러 번호를 모두 가립니다', () {
      final masked = AppLog.mask('고객 010-1111-2222 / 기사 010-3333-4444');
      expect(masked, isNot(contains('1111')));
      expect(masked, isNot(contains('3333')));
    });
  });

  group('AppLog.mask 토큰·키', () {
    test('JWT 를 가립니다', () {
      const jwt =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ0ZXN0In0.fakesignature';
      final masked = AppLog.mask('Authorization: Bearer $jwt');
      expect(masked, contains('<token>'));
      expect(masked, isNot(contains('fakesignature')));
    });

    test('Bearer 뒤 임의 토큰을 가립니다', () {
      final masked = AppLog.mask('Bearer abcdef1234567890xyz');
      expect(masked, isNot(contains('abcdef1234567890xyz')));
    });

    test('sk- 형식 API 키를 가립니다', () {
      final masked = AppLog.mask('key=sk-abcdefghijklmnopqrstuvwxyz');
      expect(masked, contains('<apikey>'));
      expect(masked, isNot(contains('abcdefghijklmnop')));
    });
  });

  group('AppLog.mask 이메일·주소', () {
    test('이메일 아이디를 부분만 남깁니다', () {
      final masked = AppLog.mask('email: tester@example.com');
      expect(masked, contains('@example.com'));
      expect(masked, isNot(contains('tester@')));
    });

    test('상세 주소를 가립니다', () {
      final masked = AppLog.mask('주소: 서울특별시 강남구 테헤란로 123-45');
      expect(masked, isNot(contains('테헤란로')));
      expect(masked, contains('주소 생략'));
    });
  });

  group('AppLog.mask 안전성', () {
    test('빈 문자열을 그대로 돌려줍니다', () {
      expect(AppLog.mask(''), '');
    });

    test('민감정보가 없으면 문장을 바꾸지 않습니다', () {
      const plain = '주문 3건 조회 완료';
      expect(AppLog.mask(plain), plain);
    });

    test('금액은 전화번호로 오인하지 않습니다', () {
      const text = '견적 금액 150000원';
      expect(AppLog.mask(text), text);
    });
  });

  group('AppLog.shortId', () {
    test('UUID 를 앞 8자로 줄입니다', () {
      expect(AppLog.shortId('7cdd586f-e527-46a8-a4a1-db9ed4812248'),
          '7cdd586f…');
    });

    test('짧은 값은 그대로 둡니다', () {
      expect(AppLog.shortId('abc'), 'abc');
    });

    test('null 은 빈 문자열입니다', () {
      expect(AppLog.shortId(null), '');
    });
  });

  group('AppLog 출력', () {
    tearDown(() => AppLog.onLog = null);

    test('출력 직전에 마스킹을 적용합니다', () {
      final captured = <String>[];
      AppLog.onLog = (level, message) => captured.add(message);

      AppLog.info('Test', '고객 연락처 010-1234-5678 확인');

      expect(captured, hasLength(1));
      expect(captured.single, isNot(contains('1234-5678')));
    });

    test('error 는 리포터 훅으로 전달됩니다', () {
      Object? reported;
      String? context;
      AppLog.onReport = (e, s, ctx) {
        reported = e;
        context = ctx;
      };
      addTearDown(() => AppLog.onReport = null);

      final failure = StateError('boom');
      AppLog.error('Test', failure, message: '입찰 제출');

      expect(reported, same(failure));
      expect(context, contains('입찰 제출'));
    });
  });
}
