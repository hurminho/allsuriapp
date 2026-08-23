import 'package:flutter/material.dart';

import 'business_tokens.dart';

class BusinessAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final bool showBackButton;
  final bool navy;
  final VoidCallback? onBack;
  final PreferredSizeWidget? bottom;

  const BusinessAppBar({
    super.key,
    required this.title,
    this.actions,
    this.showBackButton = true,
    this.navy = false,
    this.onBack,
    this.bottom,
  });

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    final foreground = navy ? Colors.white : BusinessTokens.text;
    return AppBar(
      title: Text(
        title,
        style: TextStyle(
          color: foreground,
          fontSize: 17,
          fontWeight: FontWeight.w800,
        ),
      ),
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: navy ? BusinessTokens.navy : BusinessTokens.surface,
      foregroundColor: foreground,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: false,
      leading: showBackButton
          ? IconButton(
              onPressed: onBack ?? () => Navigator.maybePop(context),
              tooltip: '뒤로가기',
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
            )
          : null,
      actions: actions,
      bottom: bottom,
      shape: navy
          ? null
          : const Border(
              bottom: BorderSide(color: BusinessTokens.border),
            ),
    );
  }
}
