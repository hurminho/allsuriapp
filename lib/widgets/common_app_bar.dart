import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../utils/navigation_utils.dart';
import '../screens/notification/notification_screen.dart';
import '../theme/business_theme.dart';

class CommonAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showBackButton;
  final bool showHomeButton;
  final bool showNotificationButton;
  final List<Widget>? actions;

  const CommonAppBar({
    super.key,
    required this.title,
    this.showBackButton = true,
    this.showHomeButton = true,
    this.showNotificationButton = true,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title),
      leading: showBackButton
          ? IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              onPressed: () => NavigationUtils.navigateToRoleHome(context),
            )
          : null,
      actions: [
        if (showNotificationButton) const _NotificationButton(),
        if (showHomeButton)
          IconButton(
            icon: const Icon(Icons.home_outlined),
            onPressed: () => NavigationUtils.navigateToRoleHome(context),
          ),
        if (actions != null) ...actions!,
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _NotificationButton extends StatefulWidget {
  const _NotificationButton();

  @override
  State<_NotificationButton> createState() => _NotificationButtonState();
}

class _NotificationButtonState extends State<_NotificationButton> {
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
  }

  Future<void> _loadUnreadCount() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final userId = authService.currentUser?.id;
      if (userId == null) return;
      final count = await NotificationService().getUnreadCount(userId);
      if (mounted) setState(() => _unreadCount = count);
    } catch (e) {
      debugPrint('❌ [NotificationButton] 읽지 않은 알림 개수 로드 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_outlined),
          if (_unreadCount > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: BusinessTheme.danger,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Center(
                  child: Text(
                    _unreadCount > 99 ? '99+' : '$_unreadCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      onPressed: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NotificationScreen()),
        );
        _loadUnreadCount();
      },
    );
  }
}
