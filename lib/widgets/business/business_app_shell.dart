import 'package:flutter/material.dart';
import '../../theme/business_theme.dart';

/// 사업자 화면에만 Material 3 + 전용 토큰을 적용하는 셸.
class BusinessAppShell extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final Widget? bottomSheet;
  final bool showBackButton;
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
    this.onBack,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: BusinessTheme.theme(Theme.of(context)),
      child: Scaffold(
        backgroundColor: backgroundColor ?? BusinessTheme.background,
        appBar: AppBar(
          title: Text(title),
          automaticallyImplyLeading: showBackButton,
          leading: showBackButton
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                  onPressed: onBack ?? () => Navigator.maybePop(context),
                )
              : null,
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
