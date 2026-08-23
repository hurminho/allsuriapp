import 'package:allsuriapp/widgets/business/business_bottom_navigation.dart';
import 'package:allsuriapp/widgets/business/business_lead_card.dart';
import 'package:allsuriapp/widgets/business/business_status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('사업자 하단 내비게이션이 390 너비에서 잘리지 않는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var tapped = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: BusinessBottomNavigation(
            currentIndex: 0,
            unreadChats: 12,
            onTap: (index) => tapped = index,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('홈'), findsOneWidget);
    expect(find.text('새 일감'), findsOneWidget);
    expect(find.text('공사 만들기'), findsOneWidget);
    expect(find.text('채팅'), findsOneWidget);
    expect(find.text('내 정보'), findsOneWidget);

    await tester.tap(find.text('공사 만들기'));
    expect(tapped, 2);

    await tester.binding.setSurfaceSize(const Size(412, 915));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('신규 일감 카드가 실제 정보와 견적 행동을 표시한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: BusinessLeadCard(
              title: '욕실 배관 점검',
              category: '배관',
              region: '서울 강남구',
              timeLabel: '10분 전',
              symptom: '욕실 하부에서 물이 새는 증상이 있습니다.',
              hasPhoto: true,
              canBid: true,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('입찰 가능'), findsOneWidget);
    expect(find.text('견적 작성'), findsOneWidget);
  });

  testWidgets('기존 상태값을 사업자용 표시 라벨로 변환한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              BusinessStatusChip.forJob('assigned'),
              BusinessStatusChip.forEstimate('pending'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('배정 완료'), findsOneWidget);
    expect(find.text('입찰 대기'), findsOneWidget);
  });
}
