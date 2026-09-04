import 'package:flutter_test/flutter_test.dart';
import 'package:allsuriapp/utils/input_parsers.dart';

/// 견적 금액·소요일 입력 검증.
///
/// 예전에는 `double.parse` 를 바로 호출해서 사용자가 "10만원" 을 넣으면
/// FormatException 문구가 스낵바에 그대로 떴습니다.
void main() {
  group('InputParsers.money', () {
    test('평범한 숫자', () {
      expect(InputParsers.money('150000'), 150000);
    });

    test('천단위 구분자를 허용합니다', () {
      expect(InputParsers.money('1,500,000'), 1500000);
    });

    test('원·₩ 표기와 공백을 허용합니다', () {
      expect(InputParsers.money(' 150,000 원 '), 150000);
      expect(InputParsers.money('₩80000'), 80000);
    });

    test('소수점을 허용합니다', () {
      expect(InputParsers.money('1000.5'), 1000.5);
    });

    test('한글 단위는 자릿수를 오해할 수 있어 거부합니다', () {
      expect(InputParsers.money('10만'), isNull);
      expect(InputParsers.money('10만원'), isNull);
    });

    test('문자·기호가 섞이면 거부합니다', () {
      expect(InputParsers.money('약 15만'), isNull);
      expect(InputParsers.money('abc'), isNull);
      expect(InputParsers.money('1e5'), isNull);
      expect(InputParsers.money('-5000'), isNull);
    });

    test('빈 값과 null 을 거부합니다', () {
      expect(InputParsers.money(''), isNull);
      expect(InputParsers.money('   '), isNull);
      expect(InputParsers.money(null), isNull);
    });

    test('단위 문자만 있으면 거부합니다', () {
      expect(InputParsers.money('원'), isNull);
    });
  });

  group('InputParsers.count', () {
    test('정수를 파싱합니다', () {
      expect(InputParsers.count('3'), 3);
      expect(InputParsers.count(' 12 '), 12);
    });

    test('소수·문자·음수를 거부합니다', () {
      expect(InputParsers.count('3.5'), isNull);
      expect(InputParsers.count('사흘'), isNull);
      expect(InputParsers.count('-1'), isNull);
    });
  });

  group('validateBidAmount', () {
    test('정상 금액은 통과합니다', () {
      expect(InputParsers.validateBidAmount('150000'), isNull);
    });

    test('빈 입력을 안내합니다', () {
      expect(InputParsers.validateBidAmount(''), '견적 금액을 입력해주세요');
    });

    test('숫자가 아니면 예시를 포함해 안내합니다', () {
      final message = InputParsers.validateBidAmount('10만원');
      expect(message, isNotNull);
      expect(message, contains('숫자'));
      expect(message, contains('150000'));
    });

    test('너무 작은 금액을 막습니다', () {
      expect(InputParsers.validateBidAmount('100'), contains('너무 작습니다'));
    });

    test('0 을 더 붙인 오타를 막습니다', () {
      expect(InputParsers.validateBidAmount('999999999999'),
          contains('최대 금액'));
    });

    test('안내 문구에 개발자 용어가 없습니다', () {
      for (final input in ['', '10만원', '1', '9' * 15]) {
        final message = InputParsers.validateBidAmount(input);
        expect(message, isNotNull);
        expect(message, isNot(contains('Exception')));
        expect(message, isNot(contains('null')));
      }
    });
  });

  group('validateEstimatedDays', () {
    test('정상 일수는 통과합니다', () {
      expect(InputParsers.validateEstimatedDays('3'), isNull);
    });

    test('빈 입력·0·상한 초과를 막습니다', () {
      expect(InputParsers.validateEstimatedDays(''), contains('입력'));
      expect(InputParsers.validateEstimatedDays('0'), contains('1일 이상'));
      expect(InputParsers.validateEstimatedDays('400'), contains('365일'));
    });

    test('숫자가 아니면 안내합니다', () {
      expect(InputParsers.validateEstimatedDays('사흘'), contains('숫자'));
    });
  });
}
