/// 한글 상호명을 URL에 쓸 수 있는 로마자로 바꿉니다.
///
/// 개인 오더 링크 slug 는 카카오톡·문자·명함 QR 등으로 공유되므로
/// 한글이 섞이면 퍼센트 인코딩되어 링크가 깨져 보이고, 일부 앱에서는 잘립니다.
/// 국립국어원 로마자 표기법을 음절 단위로 근사해 변환합니다.
library;

const _choseong = [
  'g', 'kk', 'n', 'd', 'tt', 'r', 'm', 'b', 'pp',
  's', 'ss', '', 'j', 'jj', 'ch', 'k', 't', 'p', 'h',
];

const _jungseong = [
  'a', 'ae', 'ya', 'yae', 'eo', 'e', 'yeo', 'ye', 'o', 'wa',
  'wae', 'oe', 'yo', 'u', 'wo', 'we', 'wi', 'yu', 'eu', 'ui', 'i',
];

const _jongseong = [
  '', 'g', 'kk', 'gs', 'n', 'nj', 'nh', 'd', 'l', 'lg', 'lm',
  'lb', 'ls', 'lt', 'lp', 'lh', 'm', 'b', 'bs', 's', 'ss',
  'ng', 'j', 'ch', 'k', 't', 'p', 'h',
];

const _hangulBase = 0xAC00;
const _hangulLast = 0xD7A3;

/// 한글 음절을 로마자로 바꾸고, 그 외 문자는 그대로 둡니다.
String romanizeHangul(String input) {
  final buffer = StringBuffer();

  for (final rune in input.runes) {
    if (rune < _hangulBase || rune > _hangulLast) {
      buffer.writeCharCode(rune);
      continue;
    }

    final index = rune - _hangulBase;
    buffer
      ..write(_choseong[index ~/ (21 * 28)])
      ..write(_jungseong[(index ~/ 28) % 21])
      ..write(_jongseong[index % 28]);
  }

  return buffer.toString();
}

/// 로마자 변환 후 URL 안전한 slug 형태로 정리합니다.
/// 영문 소문자·숫자·하이픈만 남기며, 연속 하이픈과 양끝 하이픈을 제거합니다.
String slugifyBusinessName(String input) {
  final romanized = romanizeHangul(input).toLowerCase();

  return romanized
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-{2,}'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

/// 개인 오더 링크 slug 의 본문을 만듭니다(임의 숫자 접미사 제외).
///
/// 길이는 반드시 변환된 문자열 자신을 기준으로 자릅니다.
/// 원본 상호명 길이로 자르면 공백·특수문자가 빠진 만큼 짧아져 RangeError 가 납니다.
String buildSlugBase(String businessName, {int maxLength = 20}) {
  var base = slugifyBusinessName(businessName);

  if (base.length > maxLength) {
    base = base.substring(0, maxLength).replaceAll(RegExp(r'-+$'), '');
  }

  return base.isEmpty ? 'allsuri' : base;
}
