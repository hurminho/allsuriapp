import 'package:allsuriapp/models/bid_breakdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BidBreakdown.parseWon', () {
    test('쉼표·원 표기를 받습니다', () {
      expect(BidBreakdown.parseWon('1,200,000원'), 1200000);
      expect(BidBreakdown.parseWon(' 80000 '), 80000);
    });

    test('빈 값·음수·문자는 null', () {
      expect(BidBreakdown.parseWon(''), isNull);
      expect(BidBreakdown.parseWon(null), isNull);
      expect(BidBreakdown.parseWon('-5000'), isNull);
      expect(BidBreakdown.parseWon('열만원'), isNull);
    });

    test('소수는 반올림합니다', () {
      expect(BidBreakdown.parseWon('80000.6'), 80001);
    });
  });

  group('BidBreakdown.parseHours', () {
    test('상식 범위만 받습니다', () {
      expect(BidBreakdown.parseHours('2.5'), 2.5);
      expect(BidBreakdown.parseHours('0'), isNull);
      expect(BidBreakdown.parseHours('999'), isNull);
      expect(BidBreakdown.parseHours(''), isNull);
    });
  });

  group('세부 항목 합계와 총액', () {
    test('총액을 비워도 세부 합계로 입찰할 수 있습니다', () {
      const b = BidBreakdown(
        visitFee: 15000,
        laborCost: 70000,
        materialCost: 30000,
        additionalCost: 5000,
      );
      expect(b.partsSum, 120000);
      expect(b.resolvedTotal(null), 120000);
      expect(b.hasBreakdown, isTrue);
    });

    test('직접 입력한 총액이 세부 합계보다 우선입니다', () {
      const b = BidBreakdown(laborCost: 70000, materialCost: 30000);
      expect(b.resolvedTotal(200000), 200000);
    });

    test('세부 항목이 없으면 partsSum 은 null', () {
      expect(BidBreakdown.empty.partsSum, isNull);
      expect(BidBreakdown.empty.resolvedTotal(null), isNull);
      expect(BidBreakdown.empty.hasBreakdown, isFalse);
      expect(BidBreakdown.empty.isEmpty, isTrue);
    });
  });

  group('경고 문구', () {
    test('합계와 총액이 다르면 안내합니다', () {
      const b = BidBreakdown(laborCost: 70000, materialCost: 30000);
      expect(b.warnings(200000).first, contains('다릅니다'));
    });

    test('1000원 이내 차이는 경고하지 않습니다', () {
      const b = BidBreakdown(laborCost: 70000, materialCost: 30000);
      expect(b.warnings(100500).where((w) => w.contains('다릅니다')), isEmpty);
    });

    test('총액만 넣으면 세부 입력을 권합니다', () {
      expect(BidBreakdown.empty.warnings(120000).first, contains('인건비'));
    });

    test('금액이 없으면 경고도 없습니다', () {
      expect(BidBreakdown.empty.warnings(null), isEmpty);
    });
  });

  group('toApiJson', () {
    test('null 항목은 전송하지 않습니다', () {
      const b = BidBreakdown(laborCost: 70000);
      final json = b.toApiJson();
      expect(json['laborCost'], 70000);
      expect(json.containsKey('materialCost'), isFalse);
      expect(json.containsKey('visitFee'), isFalse);
    });

    test('빈 메모는 전송하지 않습니다', () {
      const b = BidBreakdown(laborCost: 1000, additionalNote: '   ');
      expect(b.toApiJson().containsKey('additionalNote'), isFalse);
    });

    test('빈 breakdown 은 빈 맵', () {
      expect(BidBreakdown.empty.toApiJson(), isEmpty);
    });
  });

  group('CompletedJobDraft', () {
    test('총액이 없으면 저장하지 않습니다', () {
      expect(const CompletedJobDraft(finalTotalAmount: 0).validate(), isNotNull);
    });

    test('세부 항목 3개 합계가 총액과 다르면 막습니다', () {
      const draft = CompletedJobDraft(
        finalTotalAmount: 200000,
        finalLaborCost: 50000,
        finalMaterialCost: 30000,
        finalAdditionalCost: 10000,
      );
      expect(draft.validate(), contains('맞지 않습니다'));
    });

    test('세부 항목이 일부만 있으면 합계를 검사하지 않습니다', () {
      const draft = CompletedJobDraft(
        finalTotalAmount: 200000,
        finalLaborCost: 50000,
      );
      expect(draft.validate(), isNull);
    });

    test('합계가 맞으면 통과합니다', () {
      const draft = CompletedJobDraft(
        finalTotalAmount: 90000,
        finalLaborCost: 50000,
        finalMaterialCost: 30000,
        finalAdditionalCost: 10000,
      );
      expect(draft.validate(), isNull);
      expect(draft.toApiJson()['finalTotalAmount'], 90000);
    });
  });
}
