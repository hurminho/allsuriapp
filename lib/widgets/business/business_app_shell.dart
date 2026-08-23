import 'package:flutter/material.dart';
import '../../theme/business_theme.dart';
import 'business_app_bar.dart';
import 'business_tokens.dart';

/// 사업자 화면에만 Material 3 + 전용 토큰을 적용하는 셸.
class BusinessAppShell extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final Widget? bottomSheet;
  final bool showBackButton;
  final bool navyAppBar;
  final VoidCallback? onBack;
  final Color? backgroundColor;

  const BusinessAppShell({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.bottomSheet,
    this.showBackButton = true,
    this.navyAppBar = false,
    this.onBack,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: BusinessTheme.theme(Theme.of(context)),
      child: Scaffold(
        backgroundColor: backgroundColor ?? BusinessTokens.canvas,
        appBar: BusinessAppBar(
          title: title,
          showBackButton: showBackButton,
          navy: navyAppBar,
          onBack: onBack,
          actions: actions,
        ),
        body: body,
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: bottomNavigationBar,
        bottomSheet: bottomSheet,
      ),
    );
  }
}
