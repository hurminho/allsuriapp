/// 사용자가 입력한 금액·일수 문자열을 안전하게 숫자로 바꿉니다.
///
/// 기존 코드는 `double.parse(text)` 를 바로 호출해서, 고객이 "10만원" 이나
/// "1,000,000원" 처럼 입력하면 FormatException 이 나고 "견적 제출 중 오류가
/// 발생했습니다: FormatException..." 같은 개발자 문구가 노출됐습니다.
abstract final class InputParsers {
  /// 금액 문자열을 파싱합니다. 파싱할 수 없으면 null.
  ///
  /// 천단위 구분자, 원/₩ 표기, 공백을 허용합니다.
  /// "10만원" 처럼 한글 단위가 섞인 경우는 자릿수를 잘못 읽을 위험이 있어
  /// 거부하고 사용자에게 다시 입력하도록 안내합니다.
  static double? money(String? raw) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) return null;

    final cleaned = text
        .replaceAll(',', '')
        .replaceAll(' ', '')
        .replaceAll('₩', '')
        .replaceAll('원', '');
    if (cleaned.isEmpty) return null;

    // 숫자와 소수점 하나만 남아야 합니다. 한글 단위(만·천)는 여기서 걸립니다.
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(cleaned)) return null;

    final value = double.tryParse(cleaned);
    if (value == null || value.isNaN || value.isInfinite) return null;
    return value;
  }

  /// 0 이상의 정수(일수·시간 등)를 파싱합니다.
  static int? count(String? raw) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) return null;
    final cleaned = text.replaceAll(',', '').replaceAll(' ', '');
    if (!RegExp(r'^\d+$').hasMatch(cleaned)) return null;
    return int.tryParse(cleaned);
  }

  /// 견적 금액 검증. 통과하면 null, 실패하면 사용자에게 보여줄 문구를 돌려줍니다.
  ///
  /// [max] 는 오타로 0 을 더 붙이는 실수를 막기 위한 상한입니다.
  static String? validateBidAmount(
    String? raw, {
    double min = 1000,
    double max = 100000000,
  }) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) return '견적 금액을 입력해주세요';
    final value = money(text);
    if (value == null) return '견적 금액은 숫자로 입력해주세요 (예: 150000)';
    if (value < min) {
      return '견적 금액이 너무 작습니다. ${min.toInt()}원 이상 입력해주세요';
    }
    if (value > max) {
      return '견적 금액을 다시 확인해주세요. 입력 가능한 최대 금액을 넘었습니다';
    }
    return null;
  }

  /// 예상 소요일 검증.
  static String? validateEstimatedDays(String? raw, {int max = 365}) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) return '예상 소요일을 입력해주세요';
    final value = count(text);
    if (value == null) return '예상 소요일은 숫자로 입력해주세요 (예: 3)';
    if (value < 1) return '예상 소요일은 1일 이상이어야 합니다';
    if (value > max) return '예상 소요일은 $max일 이하로 입력해주세요';
    return null;
  }
}
