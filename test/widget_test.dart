import 'package:allsuriapp/widgets/business/business_app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('사업자 화면 셸이 전역 서비스 초기화 없이 렌더링된다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BusinessAppShell(
          title: '신규 일감',
          showBackButton: false,
          body: Center(child: Text('업무 목록')),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('신규 일감'), findsOneWidget);
    expect(find.text('업무 목록'), findsOneWidget);
  });
}
