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
}
