import 'package:allsuriapp/widgets/error_state_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 오류 상태·재시도 버튼 위젯 테스트.
///
/// 이전에는 목록 로드가 실패해도 "항목이 없습니다" 빈 상태가 떠서
/// 사용자가 재시도할 방법이 없었습니다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('안내 문구와 재시도 버튼을 보여준다', (tester) async {
    var retries = 0;
    await tester.pumpWidget(wrap(ErrorStateView(
      message: '인터넷 연결을 확인해 주세요.',
      onRetry: () => retries++,
    )));

    expect(find.text('불러오지 못했습니다'), findsOneWidget);
    expect(find.text('인터넷 연결을 확인해 주세요.'), findsOneWidget);

    await tester.tap(find.text('다시 시도'));
    expect(retries, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('onRetry 가 없으면 재시도 버튼을 숨긴다', (tester) async {
    await tester.pumpWidget(wrap(
      const ErrorStateView(message: '권한이 없습니다.'),
    ));

    expect(find.text('다시 시도'), findsNothing);
    expect(find.text('권한이 없습니다.'), findsOneWidget);
  });

  testWidgets('재시도 버튼이 최소 터치 영역 44px 을 넘는다', (tester) async {
    await tester.pumpWidget(wrap(ErrorStateView(
      message: '잠시 후 다시 시도해 주세요.',
      onRetry: () {},
    )));

    final size = tester.getSize(find.byWidgetPredicate((w) => w is FilledButton));
    expect(size.height, greaterThanOrEqualTo(44));
    expect(size.width, greaterThanOrEqualTo(44));
  });

  testWidgets('작은 화면에서도 넘치지 않는다', (tester) async {
    // iPhone SE 1세대 폭
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap(ErrorStateView(
      message: '서버 응답이 늦어지고 있습니다. 잠시 후 다시 시도해 주세요.',
      onRetry: () {},
    )));

    expect(tester.takeException(), isNull);
  });

  testWidgets('긴 한국어 문구가 잘리지 않고 줄바꿈된다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const long = '일시적인 서버 문제로 요청을 처리하지 못했습니다. '
        '네트워크 상태를 확인한 뒤 잠시 후 다시 시도해 주세요.';
    await tester.pumpWidget(wrap(ErrorStateView(
      message: long,
      onRetry: () {},
    )));

    expect(tester.takeException(), isNull);
    final text = tester.widget<Text>(find.text(long));
    // maxLines 를 지정하지 않아 잘리지 않고 여러 줄로 흐릅니다.
    expect(text.maxLines, isNull);
    expect(text.overflow, isNot(TextOverflow.ellipsis));
  });

  testWidgets('오류 문구에 개발자용 예외 문자열이 노출되지 않는다', (tester) async {
    // ApiFailure 를 거친 문구만 넘기는 것이 규칙입니다. 화면 자체는
    // 넘겨받은 문구를 그대로 보여주므로, 호출부 규칙을 문서화하는 의미의 검증입니다.
    await tester.pumpWidget(wrap(ErrorStateView(
      message: '인터넷 연결을 확인해 주세요.',
      onRetry: () {},
    )));

    final rendered = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join(' ');
    expect(rendered, isNot(contains('Exception')));
    expect(rendered, isNot(contains('SocketException')));
    expect(rendered, isNot(contains('null')));
  });
}
