import 'package:allsuriapp/models/price_estimate.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> sufficientJson() => {
      'priceState': 'sufficient',
      'estimatedMin': 80000,
      'estimatedTypical': 95000,
      'estimatedMax': 120000,
      'confidenceLevel': 'high',
      'evidenceCount': 36,
      'completedJobCount': 12,
      'factors': ['출장비', '기본 작업비'],
      'disclaimer': '현장 확인 전 참고 금액입니다.',
      'engineVersion': 'v1',
      'trade': {
        'id': 'plumbing.toilet_clog',
        'category': '배관',
        'subcategory': '변기 막힘',
        'priceFactors': ['출장비'],
      },
      'uiCopy': {
        'headline': '최근 유사 완료 작업 기준',
        'body': '참고 금액입니다.',
        'showAmount': true,
        'cta': '이 조건으로 견적 요청',
      },
    };

void main() {
  group('PriceEstimate.fromJson', () {
    test('충분 상태는 범위를 그립니다', () {
      final e = PriceEstimate.fromJson(sufficientJson());
      expect(e.state, PriceState.sufficient);
      expect(e.hasRange, isTrue);
      expect(e.min, 80000);
      expect(e.max, 120000);
      expect(e.confidenceLabel, '높음');
      expect(e.trade?.subcategory, '변기 막힘');
    });

    test('일부 상태는 참고 범위로 표시됩니다', () {
      final json = sufficientJson()
        ..['priceState'] = 'preliminary'
        ..['confidenceLevel'] = 'medium';
      (json['uiCopy'] as Map)['headline'] = '유사 사례를 바탕으로 한 참고 범위';
      final e = PriceEstimate.fromJson(json);
      expect(e.state, PriceState.preliminary);
      expect(e.hasRange, isTrue);
      expect(e.confidenceLabel, '보통');
      expect(e.headline, '유사 사례를 바탕으로 한 참고 범위');
    });

    test('부족 상태는 숫자를 그리지 않습니다', () {
      final e = PriceEstimate.fromJson({
        'priceState': 'insufficient',
        'estimatedMin': null,
        'estimatedMax': null,
        'insufficientReason': 'below_threshold',
        'uiCopy': {
          'headline': '현장 조건에 따라 차이가 큰 작업',
          'body': '예상 금액을 표시하지 않습니다.',
          'showAmount': false,
        },
      });
      expect(e.state, PriceState.insufficient);
      expect(e.hasRange, isFalse);
      expect(e.min, isNull);
    });

    test('showAmount 가 false 면 값이 있어도 범위를 그리지 않습니다', () {
      final json = sufficientJson();
      (json['uiCopy'] as Map)['showAmount'] = false;
      expect(PriceEstimate.fromJson(json).hasRange, isFalse);
    });

    test('알 수 없는 상태는 insufficient 로 떨어집니다', () {
      final e = PriceEstimate.fromJson({'priceState': '이상한값'});
      expect(e.state, PriceState.insufficient);
      expect(e.hasRange, isFalse);
    });

    test('빈 응답도 안전하게 처리합니다', () {
      final e = PriceEstimate.fromJson({});
      expect(e.state, PriceState.insufficient);
      expect(e.factors, isEmpty);
      expect(e.evidenceCount, 0);
      expect(e.headline, PriceEstimate.unavailable.headline);
    });

    test('문자열 숫자도 파싱합니다', () {
      final json = sufficientJson()
        ..['estimatedMin'] = '80000'
        ..['evidenceCount'] = '36';
      final e = PriceEstimate.fromJson(json);
      expect(e.min, 80000);
      expect(e.evidenceCount, 36);
    });

    test('공정 미확정이면 후보를 담습니다', () {
      final e = PriceEstimate.fromJson({
        'priceState': 'insufficient',
        'needsTradeSelection': true,
        'candidates': [
          {'id': 'a', 'category': '배관', 'subcategory': '변기 막힘'},
          {'id': 'b', 'category': '배관', 'subcategory': '싱크대 막힘'},
        ],
        'uiCopy': {'headline': 'h', 'body': 'b', 'showAmount': false},
      });
      expect(e.needsTradeSelection, isTrue);
      expect(e.candidates.map((c) => c.subcategory), ['변기 막힘', '싱크대 막힘']);
    });
  });

  group('PriceEstimate.unavailable', () {
    test('엔진에 닿지 못하면 숫자 없이 데이터 부족으로 보여줍니다', () {
      const e = PriceEstimate.unavailable;
      expect(e.available, isFalse);
      expect(e.hasRange, isFalse);
      expect(e.state, PriceState.insufficient);
      expect(e.body, contains('실제 업체 견적'));
    });
  });

  group('TradeSummary', () {
    test('라벨은 카테고리와 공정을 함께 보여줍니다', () {
      const t = TradeSummary(id: 'x', category: '배관', subcategory: '변기 막힘');
      expect(t.label, '배관 · 변기 막힘');
    });

    test('태그가 없어도 빈 배열입니다', () {
      final t = TradeSummary.fromJson({'id': 'x'});
      expect(t.priceFactors, isEmpty);
      expect(t.workScopeTags, isEmpty);
      expect(t.visitFeeApplies, isTrue);
    });
  });
}
