/// 입찰 세부 원가.
///
/// 사업자에게 긴 설문을 요구하지 않기 위해 모든 항목이 선택 입력입니다.
/// 총 견적가만 넣어도 입찰은 그대로 성립하고, 이때 [hasBreakdown] 이 false 가 됩니다.
///
/// 서버(`netlify/lib/bid_breakdown.ts`)와 같은 규칙을 씁니다.
class BidBreakdown {
  const BidBreakdown({
    this.visitFee,
    this.laborCost,
    this.materialCost,
    this.additionalCost,
    this.additionalNote,
    this.vatIncluded,
    this.estimatedHours,
    this.asPeriodMonths,
    this.availability,
    this.siteVisitRequired,
    this.workScopeTags = const [],
  });

  final int? visitFee;
  final int? laborCost;
  final int? materialCost;
  final int? additionalCost;
  final String? additionalNote;
  final bool? vatIncluded;
  final double? estimatedHours;
  final int? asPeriodMonths;
  final String? availability;
  final bool? siteVisitRequired;
  final List<String> workScopeTags;

  static const empty = BidBreakdown();

  /// 방문 가능 시점 선택지. 서버 enum 과 값을 맞춥니다.
  static const availabilityOptions = <String, String>{
    'today': '오늘 가능',
    'tomorrow': '내일 가능',
    'within_3days': '3일 내',
    'this_week': '이번 주',
    'scheduled': '일정 협의',
  };

  /// 입력된 세부 항목의 합계. 하나도 없으면 null.
  int? get partsSum {
    final parts = [visitFee, laborCost, materialCost, additionalCost]
        .whereType<int>()
        .toList();
    if (parts.isEmpty) return null;
    return parts.reduce((a, b) => a + b);
  }

  /// 인건비나 자재비가 있으면 "세부 항목을 낸 입찰"로 봅니다.
  bool get hasBreakdown => laborCost != null || materialCost != null;

  bool get isEmpty =>
      visitFee == null &&
      laborCost == null &&
      materialCost == null &&
      additionalCost == null &&
      (additionalNote == null || additionalNote!.isEmpty) &&
      vatIncluded == null &&
      estimatedHours == null &&
      asPeriodMonths == null &&
      availability == null &&
      siteVisitRequired == null &&
      workScopeTags.isEmpty;

  /// 총액을 확정합니다. 직접 입력한 총액이 있으면 그 값이 우선입니다.
  int? resolvedTotal(int? explicitTotal) {
    if (explicitTotal != null && explicitTotal > 0) return explicitTotal;
    final sum = partsSum;
    if (sum != null && sum > 0) return sum;
    return null;
  }

  /// 사업자에게 보여줄 안내. 입찰을 막지는 않습니다.
  List<String> warnings(int? explicitTotal) {
    final messages = <String>[];
    final sum = partsSum;
    final parts = [visitFee, laborCost, materialCost, additionalCost]
        .whereType<int>()
        .length;
    if (explicitTotal != null &&
        explicitTotal > 0 &&
        sum != null &&
        hasBreakdown &&
        parts >= 2 &&
        (sum - explicitTotal).abs() > 1000) {
      messages.add('세부 항목 합계와 총 견적가가 다릅니다. 총 견적가로 저장됩니다.');
    }
    if (!hasBreakdown && explicitTotal != null && explicitTotal > 0) {
      messages.add('인건비·자재비를 나눠 적으면 고객이 금액을 더 신뢰합니다.');
    }
    return messages;
  }

  Map<String, dynamic> toApiJson() {
    final json = <String, dynamic>{};
    void put(String key, Object? value) {
      if (value != null) json[key] = value;
    }

    put('visitFee', visitFee);
    put('laborCost', laborCost);
    put('materialCost', materialCost);
    put('additionalCost', additionalCost);
    put('additionalNote',
        (additionalNote?.trim().isNotEmpty ?? false) ? additionalNote!.trim() : null);
    put('vatIncluded', vatIncluded);
    put('estimatedHours', estimatedHours);
    put('asPeriodMonths', asPeriodMonths);
    put('availability', availability);
    put('siteVisitRequired', siteVisitRequired);
    if (workScopeTags.isNotEmpty) put('workScopeTags', workScopeTags);
    return json;
  }

  /// "1,200,000원" 같은 입력도 받습니다. 음수·비숫자는 null.
  static int? parseWon(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.replaceAll(RegExp(r'[,\s원]'), '');
    if (cleaned.isEmpty) return null;
    final value = num.tryParse(cleaned);
    if (value == null || value < 0) return null;
    return value.round();
  }

  static double? parseHours(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.replaceAll(RegExp(r'[\s시간]'), '');
    if (cleaned.isEmpty) return null;
    final value = double.tryParse(cleaned);
    if (value == null || value <= 0 || value > 240) return null;
    return (value * 10).round() / 10;
  }
}

/// 완료 시 기록하는 최종 확정금액. 입찰가와 분리해 저장합니다.
class CompletedJobDraft {
  const CompletedJobDraft({
    required this.finalTotalAmount,
    this.finalLaborCost,
    this.finalMaterialCost,
    this.finalAdditionalCost,
    this.vatIncluded = false,
    this.paymentMethod,
    this.asOccurred = false,
    this.finalWorkScopeTags = const [],
  });

  final int finalTotalAmount;
  final int? finalLaborCost;
  final int? finalMaterialCost;
  final int? finalAdditionalCost;
  final bool vatIncluded;
  final String? paymentMethod;
  final bool asOccurred;
  final List<String> finalWorkScopeTags;

  static const paymentMethods = <String, String>{
    'cash': '현금',
    'card': '카드',
    'transfer': '계좌이체',
    'other': '기타',
  };

  /// 세부 항목을 셋 다 적었는데 합계가 총액과 다르면 저장하지 않습니다.
  String? validate() {
    if (finalTotalAmount <= 0) return '최종 확정금액을 입력해 주세요.';
    final parts = [finalLaborCost, finalMaterialCost, finalAdditionalCost]
        .whereType<int>()
        .toList();
    if (parts.length == 3) {
      final sum = parts.reduce((a, b) => a + b);
      if ((sum - finalTotalAmount).abs() > 1000) {
        return '세부 항목 합계($sum원)와 총액($finalTotalAmount원)이 맞지 않습니다.';
      }
    }
    return null;
  }

  Map<String, dynamic> toApiJson() {
    final json = <String, dynamic>{
      'finalTotalAmount': finalTotalAmount,
      'vatIncluded': vatIncluded,
      'asOccurred': asOccurred,
    };
    if (finalLaborCost != null) json['finalLaborCost'] = finalLaborCost;
    if (finalMaterialCost != null) json['finalMaterialCost'] = finalMaterialCost;
    if (finalAdditionalCost != null) json['finalAdditionalCost'] = finalAdditionalCost;
    if (paymentMethod != null) json['paymentMethod'] = paymentMethod;
    if (finalWorkScopeTags.isNotEmpty) json['finalWorkScopeTags'] = finalWorkScopeTags;
    return json;
  }
}
