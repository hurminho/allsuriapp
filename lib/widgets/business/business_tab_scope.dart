import 'package:flutter/material.dart';

/// 하단 5탭 셸 안에 있을 때 하위 화면에 전달된다.
/// 탭 루트에서는 뒤로가기를 숨기고, 상단 홈 아이콘으로 홈 탭을 연다.
class BusinessTabScope extends InheritedWidget {
  final VoidCallback openDashboard;
  final int currentIndex;
  final ValueChanged<int> onSelectTab;

  const BusinessTabScope({
    super.key,
    required this.openDashboard,
    required this.currentIndex,
    required this.onSelectTab,
    required super.child,
  });

  static BusinessTabScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<BusinessTabScope>();
  }

  /// build 밖(비동기 콜백)에서 의존성을 걸지 않고 읽습니다.
  static BusinessTabScope? find(BuildContext context) {
    return context.getInheritedWidgetOfExactType<BusinessTabScope>();
  }

  static bool isTabRoot(BuildContext context) => maybeOf(context) != null;

  /// 푸시된 화면만 닫습니다. 탭 루트에서 pop 하면 앱이 종료됩니다.
  static bool popIfPushedRoute(BuildContext context) {
    if (find(context) != null) return false;
    if (!Navigator.canPop(context)) return false;
    Navigator.pop(context);
    return true;
  }

  @override
  bool updateShouldNotify(BusinessTabScope oldWidget) {
    return currentIndex != oldWidget.currentIndex;
  }
}
