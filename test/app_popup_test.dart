import 'package:allsuriapp/services/app_popup_service.dart';
import 'package:allsuriapp/widgets/app_popup_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppPopup.fromRow: 빈 값은 null, 빈도 기본값 once', () {
    final p = AppPopup.fromRow({'id': 'a', 'title': ' 공지 ', 'body': '내용', 'button_url': '', 'image_url': null});
    expect(p.title, '공지');
    expect(p.buttonUrl, isNull);
    expect(p.imageUrl, isNull);
    expect(p.frequency, 'once');
    expect(p.canHide, isFalse);
    expect(AppPopup.fromRow({'id': 'b', 'title': 't', 'body': 'b', 'frequency': 'daily'}).canHide, isTrue);
  });

  Future<String?> open(WidgetTester tester, AppPopup popup) async {
    String? result = 'none';
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await showDialog<String>(context: context, builder: (_) => AppPopupDialog(popup: popup));
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('버튼 있는 하루 한 번 팝업: 버튼·다시 보지 않기·닫기', (tester) async {
    const popup = AppPopup(
      id: 'a', title: '새 소식', body: '본문', buttonLabel: '보러 가기',
      buttonUrl: 'https://allsuri.app', frequency: 'daily',
    );
    await open(tester, popup);
    expect(find.text('새 소식'), findsOneWidget);
    expect(find.text('보러 가기'), findsOneWidget);
    expect(find.text('다시 보지 않기'), findsOneWidget);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(find.text('새 소식'), findsNothing);
  });

  testWidgets('한 번만 팝업·버튼 없음: 닫기만', (tester) async {
    const popup = AppPopup(id: 'a', title: '안내', body: '본문');
    await open(tester, popup);
    expect(find.text('다시 보지 않기'), findsNothing);
    expect(find.text('자세히 보기'), findsNothing);
    expect(find.text('닫기'), findsOneWidget);
  });
}
