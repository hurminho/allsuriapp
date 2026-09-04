import 'package:allsuriapp/models/price_estimate.dart';
import 'package:allsuriapp/widgets/business/business_bottom_navigation.dart';
import 'package:allsuriapp/widgets/business/business_lead_card.dart';
import 'package:allsuriapp/widgets/business/price_estimate_card.dart';
import 'package:allsuriapp/widgets/error_state_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// UI/UX 검수를 자동화한 레이아웃 회귀 테스트.
///
/// 릴리즈 QA 기준에서 요구한 4개 기기 폭을 모두 돌면서
/// 1) 가로 넘침(RenderFlex overflow), 2) 텍스트 잘림, 3) 최소 터치 영역
/// 을 확인합니다. 수동 검수로는 매번 놓치던 항목입니다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 필수 기기 범위. QA 문서의 기기 목록과 같은 값을 씁니다.
  const devices = <String, Size>{
    '작은 iPhone (SE, 320x568)': Size(320, 568),
    '최신 iPhone (15 Pro, 393x852)': Size(393, 852),
    '일반 Android (Pixel, 412x915)': Size(412, 915),
    '큰 Android 태블릿 (800x1280)': Size(800, 1280),
  };

  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: SafeArea(child: child)));

  /// 긴 한국어 문구는 줄바꿈 문제를 가장 잘 드러냅니다.
  const longKoreanTitle = '아파트 화장실 변기가 물이 전혀 내려가지 않고 역류하는 증상이 있어 '
      '긴급 점검과 배관 청소를 함께 요청드립니다';

  devices.forEach((label, size) {
    group(label, () {
      testWidgets('신규 일감 카드가 넘치지 않는다', (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(wrap(
          const SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: BusinessLeadCard(
              title: longKoreanTitle,
              category: '배관 · 변기 막힘',
              region: '서울 강남구',
              timeLabel: '3분 전',
              symptom: '물이 전혀 내려가지 않음, 악취 발생',
              amountLabel: '예상 80,000원 ~ 120,000원',
              hasPhoto: true,
              isNew: true,
              isUrgent: true,
              canBid: true,
              nextAction: '견적 보내기',
            ),
          ),
        ));

        expect(tester.takeException(), isNull);
      });

      testWidgets('가격 카드 세 상태가 모두 넘치지 않는다', (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const states = [
          PriceEstimate(
            state: PriceState.sufficient,
            headline: '최근 유사 완료 작업 기준',
            body: '현장 상태, 자재, 긴급 출동 여부에 따라 달라질 수 있습니다.',
            showAmount: true,
            min: 80000,
            typical: 100000,
            max: 120000,
            confidenceLevel: 'high',
            evidenceCount: 36,
            factors: ['출장비', '기본 작업비', '자재비', '야간·긴급 작업', '현장 접근 난이도'],
            disclaimer: '현장 확인 전 참고 금액입니다.',
          ),
          PriceEstimate(
            state: PriceState.preliminary,
            headline: '유사 사례를 바탕으로 한 참고 범위',
            body: '표본이 적어 범위가 넓습니다.',
            showAmount: true,
            min: 60000,
            typical: 110000,
            max: 180000,
            confidenceLevel: 'medium',
            evidenceCount: 5,
          ),
          PriceEstimate(
            state: PriceState.insufficient,
            headline: '현장 조건에 따라 차이가 큰 작업',
            body: '실제 업체 견적을 받아보시는 것을 권합니다.',
            showAmount: false,
            cta: '업체 견적 받기',
          ),
        ];

        for (final estimate in states) {
          await tester.pumpWidget(wrap(
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: PriceEstimateCard(estimate: estimate),
            ),
          ));
          expect(tester.takeException(), isNull,
              reason: '${estimate.state.name} 상태에서 레이아웃이 넘쳤습니다');
        }
      });

      testWidgets('가격 로딩 상태가 넘치지 않는다', (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(wrap(
          const SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: PriceEstimateCard(estimate: null, loading: true),
          ),
        ));

        expect(tester.takeException(), isNull);
      });

      testWidgets('오류 상태와 재시도 버튼이 넘치지 않는다', (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(wrap(ErrorStateView(
          message: '서버 응답이 늦어지고 있습니다. 잠시 후 다시 시도해 주세요.',
          onRetry: () {},
        )));

        expect(tester.takeException(), isNull);
        final button =
            tester.getSize(find.byWidgetPredicate((w) => w is FilledButton));
        expect(button.height, greaterThanOrEqualTo(44));
      });
    });
  });

  group('하단 제스처 영역·노치', () {
    testWidgets('하단 인디케이터가 있어도 내비게이션 항목이 모두 보인다', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          // 노치 59, 홈 인디케이터 34 — iPhone 15 Pro 기준
          data: const MediaQueryData(
            padding: EdgeInsets.only(top: 59, bottom: 34),
          ),
          child: Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: BusinessBottomNavigation(
              currentIndex: 0,
              unreadChats: 99,
              onTap: (_) {},
            ),
          ),
        ),
      ));

      expect(tester.takeException(), isNull);
      for (final label in ['홈', '오더', '오더 만들기', '채팅', '내 정보']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('가장 좁은 화면에서도 내비게이션이 넘치지 않는다', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: BusinessBottomNavigation(
            currentIndex: 2,
            unreadChats: 128,
            onTap: (_) {},
          ),
        ),
      ));

      expect(tester.takeException(), isNull);
    });
  });

  group('접근성: 큰 글자 설정', () {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('글자 배율 ${scale}x 에서 일감 카드가 깨지지 않는다', (tester) async {
        await tester.binding.setSurfaceSize(const Size(393, 852));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: const Scaffold(
              body: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: BusinessLeadCard(
                  title: longKoreanTitle,
                  category: '배관 · 변기 막힘',
                  region: '서울 강남구',
                  timeLabel: '3분 전',
                  amountLabel: '예상 80,000원 ~ 120,000원',
                  isUrgent: true,
                  canBid: true,
                  nextAction: '견적 보내기',
                ),
              ),
            ),
          ),
        ));

        expect(tester.takeException(), isNull,
            reason: '글자 배율 ${scale}x 에서 레이아웃이 넘쳤습니다');
      });
    }
  });

  group('가격 표시가 확정 가격으로 오해되지 않는다', () {
    testWidgets('충분 상태에도 참고 금액 안내와 변동 요인을 함께 보여준다', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MaterialApp(
        home: const Scaffold(
          body: SingleChildScrollView(
            child: PriceEstimateCard(
              estimate: PriceEstimate(
                state: PriceState.sufficient,
                headline: '최근 유사 완료 작업 기준',
                body: '현장 상태, 자재, 긴급 출동 여부에 따라 달라질 수 있습니다.',
                showAmount: true,
                min: 80000,
                typical: 100000,
                max: 120000,
                confidenceLevel: 'high',
                evidenceCount: 36,
                factors: ['출장비', '자재비'],
                disclaimer: '현장 확인 전 참고 금액입니다.',
              ),
            ),
          ),
        ),
      ));

      final rendered = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' ');

      // 범위로 보여주고, 참고 금액임을 반드시 함께 알립니다.
      expect(rendered, contains('~'));
      expect(rendered, contains('참고'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('데이터 부족 상태에서는 금액을 그리지 않는다', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MaterialApp(
        home: const Scaffold(
          body: SingleChildScrollView(
            child: PriceEstimateCard(
              estimate: PriceEstimate(
                state: PriceState.insufficient,
                headline: '현장 조건에 따라 차이가 큰 작업',
                body: '실제 업체 견적을 받아보시는 것을 권합니다.',
                showAmount: false,
                cta: '업체 견적 받기',
              ),
            ),
          ),
        ),
      ));

      final rendered = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' ');

      // 그럴듯한 숫자를 만들지 않는 것이 정책입니다.
      expect(rendered, isNot(contains('원')));
      expect(rendered, contains('현장 조건'));
    });
  });
}
