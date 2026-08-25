import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../screens/business/create_job_screen.dart';
import '../../screens/business/work_hub_screen.dart';
import '../../screens/chat/chat_list_page.dart';
import '../../screens/profile/my_revenue_screen.dart';
import '../../screens/profile/profile_screen.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../theme/business_theme.dart';
import '../professional_dashboard.dart';
import 'business_bottom_navigation.dart';
import 'business_tab_scope.dart';
import 'business_tokens.dart';

/// 승인된 사업자의 루트 셸. 하단 5탭은 IndexedStack 으로 유지하고,
/// 오늘의 업무 대시보드는 상단 홈 아이콘에서 연다.
class BusinessTabShell extends StatefulWidget {
  final int initialIndex;

  const BusinessTabShell({super.key, this.initialIndex = 0});

  @override
  State<BusinessTabShell> createState() => _BusinessTabShellState();
}

class _BusinessTabShellState extends State<BusinessTabShell> {
  late int _index;
  int _unreadChats = 0;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshUnread());
  }

  Future<void> _refreshUnread() async {
    final userId = context.read<AuthService>().currentUser?.id ?? '';
    if (userId.isEmpty) return;
    final count = await NotificationService().getUnreadChatCount(userId);
    if (mounted) setState(() => _unreadChats = count);
  }

  void _openDashboard() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfessionalDashboard()),
    ).then((_) {
      if (mounted) _refreshUnread();
    });
  }

  @override
  Widget build(BuildContext context) {
    return BusinessTabScope(
      openDashboard: _openDashboard,
      currentIndex: _index,
      onSelectTab: (i) => setState(() => _index = i),
      child: PopScope(
        canPop: false,
        child: Theme(
          data: BusinessTheme.theme(Theme.of(context)),
          child: Scaffold(
            backgroundColor: BusinessTokens.canvas,
            body: IndexedStack(
              index: _index,
              children: const [
                MyRevenueScreen(),
                WorkHubScreen(),
                CreateJobScreen(),
                ChatListPage(),
                ProfileScreen(),
              ],
            ),
            bottomNavigationBar: BusinessBottomNavigation(
              currentIndex: _index,
              unreadChats: _unreadChats,
              onTap: (i) {
                setState(() => _index = i);
                if (i == 3) _refreshUnread();
              },
            ),
          ),
        ),
      ),
    );
  }
}
