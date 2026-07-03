/// Semantic 버전 비교 유틸.
///
/// 단순 문자열 비교("1.10.0" < "1.9.9" 로 잘못 판단하는 문제)를 피하기 위해
/// 각 자리(major.minor.patch...)를 숫자로 분리하여 비교합니다.
///
/// - "1.10.0" > "1.9.9"
/// - "1.4.2" > "1.4.1"
///
/// "1.0.6+56", "1.2.3-beta.1" 처럼 빌드 번호/프리릴리즈 접미사가 붙어 있어도
/// 앞의 숫자 버전만 추출해서 비교하며, 잘못된 형식의 문자열이 들어와도
/// 예외를 던지지 않고 안전하게 0으로 처리합니다.
class VersionCompare {
  const VersionCompare._();

  /// "1.2.3" -> [1, 2, 3]. 파싱 실패한 자리는 0으로 대체합니다.
  static List<int> parse(String version) {
    try {
      // 빌드 메타데이터(+56)나 프리릴리즈 태그(-beta) 제거
      final core = version.trim().split(RegExp(r'[+\-]')).first;
      if (core.isEmpty) return const [0];

      final segments = core.split('.');
      final numbers = segments.map((segment) {
        final match = RegExp(r'^\d+').firstMatch(segment.trim());
        if (match == null) return 0;
        return int.tryParse(match.group(0)!) ?? 0;
      }).toList();

      return numbers.isEmpty ? const [0] : numbers;
    } catch (_) {
      return const [0];
    }
  }

  /// a > b 이면 1, a < b 이면 -1, 같으면 0.
  static int compare(String a, String b) {
    final partsA = parse(a);
    final partsB = parse(b);
    final length = partsA.length > partsB.length ? partsA.length : partsB.length;

    for (var i = 0; i < length; i++) {
      final valueA = i < partsA.length ? partsA[i] : 0;
      final valueB = i < partsB.length ? partsB[i] : 0;
      if (valueA != valueB) return valueA > valueB ? 1 : -1;
    }
    return 0;
  }

  static bool isLessThan(String a, String b) => compare(a, b) < 0;
  static bool isGreaterThan(String a, String b) => compare(a, b) > 0;
  static bool isEqual(String a, String b) => compare(a, b) == 0;
  static bool isGreaterOrEqual(String a, String b) => compare(a, b) >= 0;
  static bool isLessOrEqual(String a, String b) => compare(a, b) <= 0;
}
