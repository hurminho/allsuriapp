import 'package:flutter/material.dart';

/// 하단 5탭 셸 안에 있을 때 하위 화면에 전달된다.
/// 탭 루트에서는 뒤로가기를 숨기고, 상단 홈 아이콘으로 대시보드를 연다.
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

  static bool isTabRoot(BuildContext context) => maybeOf(context) != null;

  @override
  bool updateShouldNotify(BusinessTabScope oldWidget) {
    return currentIndex != oldWidget.currentIndex;
  }
}
