import 'package:allsuriapp/models/price_estimate.dart';
import 'package:allsuriapp/widgets/business/price_estimate_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PriceEstimate sufficient() => PriceEstimate.fromJson({
      'priceState': 'sufficient',
      'estimatedMin': 80000,
      'estimatedTypical': 95000,
      'estimatedMax': 120000,
      'confidenceLevel': 'high',
      'evidenceCount': 36,
      'completedJobCount': 12,
      'factors': ['출장비', '기본 작업비', '자재비'],
      'disclaimer': '현장 확인 전 참고 금액입니다.',
      'uiCopy': {
        'headline': '최근 유사 완료 작업 기준',
        'body': '최근 유사 완료 사례 기준 참고 금액입니다.',
        'showAmount': true,
      },
    });

Widget wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets('충분 상태는 범위와 변동 요인을 보여줍니다', (tester) async {
    await tester.pumpWidget(wrap(PriceEstimateCard(estimate: sufficient())));

    expect(find.text('AI 예상 가격 범위'), findsOneWidget);
    expect(find.text('80,000원 ~ 120,000원'), findsOneWidget);
    expect(find.text('최근 유사 완료 작업 기준'), findsOneWidget);
    expect(find.text('가격 변동 요인'), findsOneWidget);
    expect(find.text('출장비'), findsOneWidget);
    expect(
      find.text('유사 완료 사례 12건 · 전체 표본 36건 · 신뢰도 높음'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('일부 상태는 참고 배지를 붙입니다', (tester) async {
    final json = {
      'priceState': 'preliminary',
      'estimatedMin': 60000,
      'estimatedTypical': 95000,
      'estimatedMax': 150000,
      'confidenceLevel': 'medium',
      'evidenceCount': 4,
      'completedJobCount': 0,
      'uiCopy': {
        'headline': '유사 사례를 바탕으로 한 참고 범위',
        'body': '범위를 넓게 잡았습니다.',
        'showAmount': true,
      },
    };
    await tester.pumpWidget(wrap(PriceEstimateCard(estimate: PriceEstimate.fromJson(json))));

    expect(find.text('참고'), findsOneWidget);
    expect(find.text('60,000원 ~ 150,000원'), findsOneWidget);
    expect(find.text('유사 사례를 바탕으로 한 참고 범위'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('부족 상태는 숫자를 전혀 표시하지 않습니다', (tester) async {
    final estimate = PriceEstimate.fromJson({
      'priceState': 'insufficient',
      'uiCopy': {
        'headline': '현장 조건에 따라 차이가 큰 작업',
        'body': '실제 업체 견적을 받아 비교하시는 편이 정확합니다.',
        'showAmount': false,
      },
    });
    await tester.pumpWidget(wrap(PriceEstimateCard(estimate: estimate)));

    expect(find.text('현장 조건에 따라 차이가 큰 작업'), findsOneWidget);
    expect(find.text('AI 예상 가격 범위'), findsNothing);
    expect(find.textContaining('원 ~'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('엔진에 닿지 못하면 데이터 부족 화면을 씁니다', (tester) async {
    await tester.pumpWidget(wrap(const PriceEstimateCard(estimate: null)));

    expect(find.text(PriceEstimate.unavailable.headline), findsOneWidget);
    expect(find.textContaining('원 ~'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('로딩 중에는 안내만 보여줍니다', (tester) async {
    await tester.pumpWidget(wrap(const PriceEstimateCard(estimate: null, loading: true)));

    expect(find.text('예상 범위를 확인하는 중…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('공정 미확정이면 후보를 눌러 고를 수 있습니다', (tester) async {
    TradeSummary? picked;
    final estimate = PriceEstimate.fromJson({
      'priceState': 'insufficient',
      'needsTradeSelection': true,
      'candidates': [
        {'id': 'plumbing.toilet_clog', 'category': '배관', 'subcategory': '변기 막힘'},
        {'id': 'plumbing.sink_clog', 'category': '배관', 'subcategory': '싱크대 막힘'},
      ],
      'uiCopy': {'headline': '어떤 작업인지 확인이 필요해요', 'body': '선택해 주세요.', 'showAmount': false},
    });

    await tester.pumpWidget(wrap(PriceEstimateCard(
      estimate: estimate,
      onSelectTrade: (t) => picked = t,
    )));

    expect(find.text('어떤 작업에 가까운가요?'), findsOneWidget);
    await tester.tap(find.text('싱크대 막힘'));
    await tester.pump();

    expect(picked?.id, 'plumbing.sink_clog');
  });

  testWidgets('compact 모드에서도 레이아웃이 깨지지 않습니다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap(PriceEstimateCard(
      estimate: sufficient(),
      compact: true,
      title: '이 공정 최근 완료 범위',
    )));

    expect(find.text('이 공정 최근 완료 범위'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
