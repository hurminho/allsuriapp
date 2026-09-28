import 'package:flutter_test/flutter_test.dart';
import 'package:allsuriapp/utils/hangul_romanize.dart';

void main() {
  group('한글 로마자 변환', () {
    test('상호명을 로마자로 바꾼다', () {
      expect(romanizeHangul('서문페인트'), 'seomunpeinteu');
      expect(romanizeHangul('개발자'), 'gaebalja');
    });

    test('영문·숫자는 그대로 둔다', () {
      expect(romanizeHangul('allsuri 2026'), 'allsuri 2026');
    });
  });

  group('slug 생성', () {
    test('URL 안전한 소문자 slug 를 만든다', () {
      expect(slugifyBusinessName('서문페인트'), 'seomunpeinteu');
      expect(slugifyBusinessName('김 배관 & 설비'), 'gim-baegwan-seolbi');
    });

    test('연속·양끝 하이픈을 정리한다', () {
      expect(slugifyBusinessName('  ((올수리))  '), 'olsuri');
    });

    test('한글이 없어도 동작한다', () {
      expect(slugifyBusinessName('Kim Plumbing'), 'kim-plumbing');
    });

    test('변환 결과에 한글이 남지 않는다', () {
      for (final name in ['서문페인트', '가나다라마바사', '동네철물점']) {
        expect(RegExp(r'^[a-z0-9-]+$').hasMatch(slugifyBusinessName(name)), isTrue,
            reason: name);
      }
    });
  });

  group('slug 본문 생성', () {
    // 이전 구현은 잘라낸 문자열에 원본 상호명 길이로 substring 을 호출해
    // 공백·특수문자가 든 상호명마다 RangeError 로 링크 생성이 실패했습니다.
    test('공백·특수문자가 있어도 예외 없이 만든다', () {
      const names = [
        '김 배관 설비',
        '우리집 수리센터',
        '(주)대성설비',
        'A/S 전문 수리점',
        '서문페인트',
      ];

      for (final name in names) {
        expect(() => buildSlugBase(name), returnsNormally, reason: name);
        expect(RegExp(r'^[a-z0-9-]+$').hasMatch(buildSlugBase(name)), isTrue,
            reason: name);
      }
    });

    test('아주 긴 상호명도 최대 길이로 자른다', () {
      final base = buildSlugBase('서울강남종합설비인테리어리모델링전문업체');
      expect(base.length, lessThanOrEqualTo(20));
      expect(base.endsWith('-'), isFalse);
    });

    test('변환할 글자가 없으면 기본값을 쓴다', () {
      expect(buildSlugBase('!!! @@@'), 'allsuri');
      expect(buildSlugBase(''), 'allsuri');
    });
  });
}
