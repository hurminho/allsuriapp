import 'package:allsuriapp/models/bid_breakdown.dart';
import 'package:allsuriapp/widgets/business/bid_cost_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late BidCostFormController controller;

  setUp(() => controller = BidCostFormController());
  tearDown(() => controller.dispose());

  Future<void> pump(WidgetTester tester, {bool expanded = false}) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BidCostFields(
            controller: controller,
            initiallyExpanded: expanded,
          ),
        ),
      ),
    ));
  }

  testWidgets('기본은 접혀 있어 기존 입찰 흐름을 방해하지 않습니다', (tester) async {
    await pump(tester);

    expect(find.text('견적 상세 (선택)'), findsOneWidget);
    expect(find.text('인건비'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('펼치면 원가 항목이 모두 나옵니다', (tester) async {
    await pump(tester);
    await tester.tap(find.text('견적 상세 (선택)'));
    await tester.pumpAndSettle();

    for (final label in ['출장비', '인건비', '자재비', '추가 비용', '예상 작업 시간', 'AS 기간', '방문 가능 시점']) {
      expect(find.text(label), findsOneWidget, reason: '$label 필드가 없습니다');
    }
    expect(find.text('부가세 포함 금액'), findsOneWidget);
    expect(find.text('현장 확인 후 금액 변동 가능'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('금액을 넣으면 세부 합계가 보입니다', (tester) async {
    await pump(tester, expanded: true);

    await tester.enterText(find.widgetWithText(TextField, '인건비'), '70000');
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, '자재비'), '30000');
    await tester.pump();

    expect(find.text('세부 합계 100,000원'), findsOneWidget);
    expect(controller.build().partsSum, 100000);
    expect(controller.build().hasBreakdown, isTrue);
  });

  testWidgets('아무것도 입력하지 않으면 빈 breakdown 을 만듭니다', (tester) async {
    await pump(tester, expanded: true);

    final breakdown = controller.build();
    expect(breakdown.partsSum, isNull);
    expect(breakdown.hasBreakdown, isFalse);
    expect(breakdown.toApiJson()['siteVisitRequired'], isTrue);
  });

  testWidgets('부가세 토글이 breakdown 에 반영됩니다', (tester) async {
    await pump(tester, expanded: true);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(controller.build().vatIncluded, isTrue);
  });

  test('컨트롤러는 입력 텍스트를 정규화합니다', () {
    controller.visitFee.text = '15,000원';
    controller.laborCost.text = '70000';
    controller.estimatedHours.text = '2.5시간';
    controller.asPeriodMonths = 6;
    controller.availability = 'today';

    final b = controller.build();
    expect(b.visitFee, 15000);
    expect(b.laborCost, 70000);
    expect(b.estimatedHours, 2.5);
    expect(b.asPeriodMonths, 6);
    expect(b.availability, 'today');
    expect(BidBreakdown.availabilityOptions['today'], '오늘 가능');
  });
}
