import 'package:allsuriapp/widgets/business/business_app_bar.dart';
import 'package:allsuriapp/widgets/business/business_tab_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('탭 루트에서 popIfPushedRoute는 홈 셸을 닫지 않는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BusinessTabScope(
          openDashboard: () {},
          currentIndex: 2,
          onSelectTab: (_) {},
          child: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () => BusinessTabScope.popIfPushedRoute(context),
                  child: const Text('leave'),
                ),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('leave'), findsOneWidget);
    await tester.tap(find.text('leave'));
    await tester.pumpAndSettle();
    expect(find.text('leave'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('푸시된 화면에서만 popIfPushedRoute가 닫는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (pushed) => Scaffold(
                        body: TextButton(
                          onPressed: () =>
                              BusinessTabScope.popIfPushedRoute(pushed),
                          child: const Text('close-pushed'),
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('close-pushed'), findsOneWidget);

    await tester.tap(find.text('close-pushed'));
    await tester.pumpAndSettle();
    expect(find.text('close-pushed'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('마지막 라우트에서는 canPop이 false여도 popIfPushedRoute가 앱을 종료하지 않는다',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: _LastRouteLeave(),
      ),
    );

    expect(find.text('root'), findsOneWidget);
    await tester.tap(find.text('try-pop'));
    await tester.pumpAndSettle();
    expect(find.text('root'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('탭 안 앱바는 뒤로가기를 숨긴다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BusinessTabScope(
          openDashboard: () {},
          currentIndex: 2,
          onSelectTab: (_) {},
          child: const Scaffold(
            appBar: BusinessAppBar(title: '오더 등록'),
          ),
        ),
      ),
    );

    expect(find.byTooltip('뒤로가기'), findsNothing);
    expect(find.byTooltip('홈'), findsOneWidget);
  });
}

class _LastRouteLeave extends StatelessWidget {
  const _LastRouteLeave();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const Text('root'),
          TextButton(
            onPressed: () => BusinessTabScope.popIfPushedRoute(context),
            child: const Text('try-pop'),
          ),
        ],
      ),
    );
  }
}
