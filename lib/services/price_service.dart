import 'package:flutter/foundation.dart';

import '../models/bid_breakdown.dart';
import '../models/price_estimate.dart';
import 'api_service.dart';

/// 가격 엔진(`/api/price/*`) 클라이언트.
///
/// 앱은 금액을 계산하지 않습니다. 서버가 실거래·입찰·표준 단가·운영자 기준표로
/// 만든 결과만 받아 그대로 보여줍니다. 실패하면 [PriceEstimate.unavailable] 로
/// 내려가 데이터 부족 화면을 띄웁니다.
class PriceService {
  PriceService({ApiService? api}) : _api = api ?? ApiService();

  final ApiService _api;

  static List<TradeSummary>? _tradeCache;
  static DateTime? _tradeCachedAt;
  static const _tradeCacheTtl = Duration(minutes: 10);

  /// 테스트에서 캐시를 비웁니다.
  static void resetCache() {
    _tradeCache = null;
    _tradeCachedAt = null;
  }

  Future<List<TradeSummary>> trades({bool force = false}) async {
    final cachedAt = _tradeCachedAt;
    if (!force &&
        _tradeCache != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _tradeCacheTtl) {
      return _tradeCache!;
    }
    try {
      final res = await _api.get('/price/catalog');
      final data = _payload(res);
      final raw = data?['trades'];
      if (raw is! List) return _tradeCache ?? const [];
      final parsed = raw
          .whereType<Map>()
          .map((e) => TradeSummary.fromJson(e.cast<String, dynamic>()))
          .where((t) => t.id.isNotEmpty)
          .toList();
      _tradeCache = parsed;
      _tradeCachedAt = DateTime.now();
      return parsed;
    } catch (e) {
      debugPrint('[PriceService] 카탈로그 조회 실패: $e');
      return _tradeCache ?? const [];
    }
  }

  /// 예상 범위 조회. 실패해도 예외를 던지지 않습니다.
  Future<PriceEstimate> estimate({
    String? listingId,
    String? tradeId,
    String? category,
    String? subcategory,
    String? text,
    String? address,
    String? propertyType,
    String? urgency,
    List<String>? workScopeTags,
    bool? visitRequired,
    Map<String, dynamic>? answers,
  }) async {
    final body = <String, dynamic>{};
    void put(String key, Object? value) {
      if (value == null) return;
      if (value is String && value.trim().isEmpty) return;
      if (value is List && value.isEmpty) return;
      body[key] = value;
    }

    put('listingId', listingId);
    put('tradeId', tradeId);
    put('category', category);
    put('subcategory', subcategory);
    put('text', text);
    put('address', address);
    put('propertyType', propertyType);
    put('urgency', urgency);
    put('workScopeTags', workScopeTags);
    put('visitRequired', visitRequired);
    put('answers', answers);

    try {
      final res = await _api.post('/price/estimate', body);
      final data = _payload(res);
      if (data == null) return PriceEstimate.unavailable;
      return PriceEstimate.fromJson(data);
    } catch (e) {
      debugPrint('[PriceService] 예상 범위 조회 실패: $e');
      return PriceEstimate.unavailable;
    }
  }

  /// 내 표준 단가 목록.
  Future<List<Map<String, dynamic>>> rateCards() async {
    try {
      final res = await _api.get('/price/rate-cards');
      final raw = _payload(res)?['rateCards'];
      if (raw is! List) return const [];
      return raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    } catch (e) {
      debugPrint('[PriceService] 표준 단가 조회 실패: $e');
      return const [];
    }
  }

  /// 표준 단가 빠른 등록. 성공하면 null, 실패하면 사용자에게 보여줄 메시지.
  Future<String?> saveRateCard({
    required String tradeId,
    required int baseLaborCost,
    int materialAvgCost = 0,
    bool materialIncluded = false,
    int visitFee = 0,
    bool vatIncluded = false,
    List<String> additionalCostConditions = const [],
    List<String> serviceRegions = const [],
  }) async {
    try {
      final res = await _api.post('/price/rate-cards', {
        'tradeId': tradeId,
        'baseLaborCost': baseLaborCost,
        'materialAvgCost': materialAvgCost,
        'materialIncluded': materialIncluded,
        'visitFee': visitFee,
        'vatIncluded': vatIncluded,
        'additionalCostConditions': additionalCostConditions,
        'serviceRegions': serviceRegions,
      });
      if (_payload(res)?['success'] == true) return null;
      return _errorMessage(res) ?? '표준 단가를 저장하지 못했습니다.';
    } catch (e) {
      debugPrint('[PriceService] 표준 단가 저장 실패: $e');
      return '네트워크 오류로 저장하지 못했습니다. 잠시 후 다시 시도해 주세요.';
    }
  }

  /// 최종 확정금액 기록. 성공하면 null, 실패하면 메시지.
  Future<String?> recordCompletedJob({
    required CompletedJobDraft draft,
    String? listingId,
    String? jobId,
    String? orderId,
    String? bidId,
    String? tradeId,
    String? address,
    String? propertyType,
    String? urgency,
  }) async {
    final validation = draft.validate();
    if (validation != null) return validation;

    final body = <String, dynamic>{...draft.toApiJson()};
    void put(String key, String? value) {
      if (value != null && value.isNotEmpty) body[key] = value;
    }

    put('listingId', listingId);
    put('jobId', jobId);
    put('orderId', orderId);
    put('bidId', bidId);
    put('tradeId', tradeId);
    put('address', address);
    put('propertyType', propertyType);
    put('urgency', urgency);

    try {
      final res = await _api.post('/price/completed-jobs', body);
      if (_payload(res)?['success'] == true) return null;
      return _errorMessage(res) ?? '완료 금액을 저장하지 못했습니다.';
    } catch (e) {
      debugPrint('[PriceService] 완료 금액 저장 실패: $e');
      return '네트워크 오류로 저장하지 못했습니다.';
    }
  }

  /// 지역·공정별 시장 리포트. 표본이 부족하면 서버가 숫자를 감춥니다.
  Future<Map<String, dynamic>?> marketReport({
    required String tradeId,
    String? region,
  }) async {
    try {
      final query = region == null || region.isEmpty
          ? '/price/market-report?tradeId=$tradeId'
          : '/price/market-report?tradeId=$tradeId&region=${Uri.encodeQueryComponent(region)}';
      final res = await _api.get(query);
      return _payload(res);
    } catch (e) {
      debugPrint('[PriceService] 시장 리포트 조회 실패: $e');
      return null;
    }
  }

  /// ApiService 는 {success, data, error} 를 돌려줍니다.
  Map<String, dynamic>? _payload(Map<String, dynamic> response) {
    // 실패 응답의 본문({error: ...})을 데이터로 오해하면 안 됩니다.
    // 그렇게 되면 엔진이 죽었는데도 available=true 인 결과가 만들어져
    // "데이터 부족"과 "엔진 응답 실패"를 화면에서 구분할 수 없습니다.
    if (response['success'] != true) return null;
    final data = response['data'];
    if (data is Map) return data.cast<String, dynamic>();
    return const {};
  }

  String? _errorMessage(Map<String, dynamic> response) {
    final data = response['data'];
    if (data is Map && data['error'] != null) return data['error'].toString();
    final error = response['error'] ?? response['message'];
    return error?.toString();
  }
}
