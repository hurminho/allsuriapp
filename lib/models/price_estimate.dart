/// 가격 엔진(`/api/price`) 응답 모델.
///
/// 금액은 서버 가격 엔진만 만들 수 있습니다. 앱에서 절대 계산하지 않고,
/// 데이터가 부족하면 숫자 없이 [PriceState.insufficient] 를 그대로 보여줍니다.
enum PriceState { sufficient, preliminary, insufficient }

PriceState _parseState(Object? raw) {
  switch (raw?.toString()) {
    case 'sufficient':
      return PriceState.sufficient;
    case 'preliminary':
      return PriceState.preliminary;
    default:
      return PriceState.insufficient;
  }
}

/// 공정 정의 요약. 카탈로그(`/api/price/catalog`)에서 옵니다.
class TradeSummary {
  const TradeSummary({
    required this.id,
    required this.category,
    required this.subcategory,
    this.priceFactors = const [],
    this.workScopeTags = const [],
    this.symptomTags = const [],
    this.materialIncludedByDefault = false,
    this.visitFeeApplies = true,
  });

  final String id;
  final String category;
  final String subcategory;
  final List<String> priceFactors;
  final List<String> workScopeTags;
  final List<String> symptomTags;
  final bool materialIncludedByDefault;
  final bool visitFeeApplies;

  String get label => '$category · $subcategory';

  factory TradeSummary.fromJson(Map<String, dynamic> json) {
    List<String> tags(Object? value) =>
        value is List ? value.map((e) => e.toString()).toList() : const <String>[];
    return TradeSummary(
      id: json['id']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      subcategory: json['subcategory']?.toString() ?? '',
      priceFactors: tags(json['priceFactors']),
      workScopeTags: tags(json['workScopeTags']),
      symptomTags: tags(json['symptomTags']),
      materialIncludedByDefault: json['materialIncludedByDefault'] == true,
      visitFeeApplies: json['visitFeeApplies'] != false,
    );
  }
}

/// 가격 엔진 결과. [showAmount] 가 false 면 어떤 숫자도 표시하지 않습니다.
class PriceEstimate {
  const PriceEstimate({
    required this.state,
    required this.headline,
    required this.body,
    required this.showAmount,
    this.cta = '',
    this.min,
    this.typical,
    this.max,
    this.confidenceLevel = 'low',
    this.evidenceCount = 0,
    this.completedJobCount = 0,
    this.factors = const [],
    this.disclaimer = '',
    this.engineVersion = '',
    this.trade,
    this.candidates = const [],
    this.needsTradeSelection = false,
    this.available = true,
  });

  final PriceState state;
  final String headline;
  final String body;
  final bool showAmount;
  final String cta;
  final int? min;
  final int? typical;
  final int? max;
  final String confidenceLevel;
  final int evidenceCount;
  final int completedJobCount;
  final List<String> factors;
  final String disclaimer;
  final String engineVersion;
  final TradeSummary? trade;
  final List<TradeSummary> candidates;
  final bool needsTradeSelection;

  /// 엔진에 닿지 못했을 때 false. UI 는 데이터 부족과 같은 화면을 보여줍니다.
  final bool available;

  /// 범위를 실제로 그릴 수 있는지. 상태와 값이 모두 맞아야 true.
  bool get hasRange =>
      available && showAmount && state != PriceState.insufficient && min != null && max != null;

  String get confidenceLabel {
    switch (confidenceLevel) {
      case 'high':
        return '높음';
      case 'medium':
        return '보통';
      default:
        return '낮음';
    }
  }

  /// 엔진 호출 실패·미설정 시 쓰는 값. 절대 숫자를 만들지 않습니다.
  static const unavailable = PriceEstimate(
    state: PriceState.insufficient,
    headline: '현장 조건에 따라 차이가 큰 작업',
    body: '지금은 예상 범위를 계산할 수 없습니다.\n실제 업체 견적을 받아 비교해 주세요.',
    showAmount: false,
    available: false,
  );

  factory PriceEstimate.fromJson(Map<String, dynamic> json) {
    final ui = json['uiCopy'];
    final uiMap = ui is Map ? ui.cast<String, dynamic>() : const <String, dynamic>{};
    final state = _parseState(json['priceState']);
    int? intOrNull(Object? v) {
      if (v == null) return null;
      final n = num.tryParse(v.toString());
      return n?.round();
    }

    List<TradeSummary> trades(Object? value) => value is List
        ? value
            .whereType<Map>()
            .map((e) => TradeSummary.fromJson(e.cast<String, dynamic>()))
            .toList()
        : const <TradeSummary>[];

    final tradeJson = json['trade'];
    return PriceEstimate(
      state: state,
      headline: uiMap['headline']?.toString() ?? unavailable.headline,
      body: uiMap['body']?.toString() ?? unavailable.body,
      showAmount: uiMap['showAmount'] == true,
      cta: uiMap['cta']?.toString() ?? '',
      min: intOrNull(json['estimatedMin']),
      typical: intOrNull(json['estimatedTypical']),
      max: intOrNull(json['estimatedMax']),
      confidenceLevel: json['confidenceLevel']?.toString() ?? 'low',
      evidenceCount: intOrNull(json['evidenceCount']) ?? 0,
      completedJobCount: intOrNull(json['completedJobCount']) ?? 0,
      factors: json['factors'] is List
          ? (json['factors'] as List).map((e) => e.toString()).toList()
          : const <String>[],
      disclaimer: json['disclaimer']?.toString() ?? '',
      engineVersion: json['engineVersion']?.toString() ?? '',
      trade: tradeJson is Map ? TradeSummary.fromJson(tradeJson.cast<String, dynamic>()) : null,
      candidates: trades(json['candidates']),
      needsTradeSelection: json['needsTradeSelection'] == true,
    );
  }
}
