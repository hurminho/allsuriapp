import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../screens/business/create_job_screen.dart';
import '../screens/chat/chat_list_page.dart';
import '../screens/profile/profile_screen.dart';
import '../widgets/professional_dashboard.dart';

class BottomNavigation extends StatefulWidget {
  final int currentIndex;
  final Function(int) onTap;

  const BottomNavigation({
    Key? key,
    required this.currentIndex,
    required this.onTap,
  }) : super(key: key);

  @override
  State<BottomNavigation> createState() => _BottomNavigationState();
}

class _BottomNavigationState extends State<BottomNavigation> {
  Future<int>? _unreadChatFuture;
  String _loadedUserId = '';

  /// userId가 바뀔 때만 안읽음 카운트 Future를 새로 만든다.
  /// (build 마다 새 쿼리를 쏘던 문제 해결)
  void _ensureUnreadFuture(String userId) {
    if (userId != _loadedUserId) {
      _loadedUserId = userId;
      _unreadChatFuture =
          userId.isEmpty ? Future.value(0) : NotificationService().getUnreadChatCount(userId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, child) {
        final userId = authService.currentUser?.id ?? '';
        _ensureUnreadFuture(userId);

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Container(
              height: 62,
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNavItem(
                    context: context,
                    index: 0,
                    icon: Icons.home_rounded,
                    outlinedIcon: Icons.home_outlined,
                    label: '홈',
                  ),
                  _buildNavItem(
                    context: context,
                    index: 1,
                    icon: Icons.construction_rounded,
                    outlinedIcon: Icons.construction_outlined,
                    label: '공사 만들기',
                  ),
                  FutureBuilder<int>(
                    future: _unreadChatFuture,
                    builder: (context, snapshot) {
                      final chatBadge = snapshot.data ?? 0;
                      return _buildNavItem(
                        context: context,
                        index: 2,
                        icon: Icons.chat_bubble_rounded,
                        outlinedIcon: Icons.chat_bubble_outline_rounded,
                        label: '채팅',
                        badgeCount: chatBadge,
                      );
                    },
                  ),
                  _buildNavItem(
                    context: context,
                    index: 3,
                    icon: Icons.account_circle_rounded,
                    outlinedIcon: Icons.account_circle_outlined,
                    label: '프로필',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required int index,
    required IconData icon,
    required IconData outlinedIcon,
    required String label,
    int? badgeCount,
  }) {
    final isSelected = widget.currentIndex == index;
    final primaryColor = Theme.of(context).primaryColor;
    
    return Expanded(
      child: InkWell(
        onTap: () {
          switch (index) {
            case 0:
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (context) => const ProfessionalDashboard(),
                ),
                (route) => false,
              );
              break;
            case 1:
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CreateJobScreen(),
                ),
              ).then((_) => widget.onTap(0)); // 돌아오면 홈으로 초기화
              break;
            case 2:
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ChatListPage(),
                ),
              ).then((_) => widget.onTap(0)); // 돌아오면 홈으로 초기화
              break;
            case 3:
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ProfileScreen(),
                ),
              ).then((_) => widget.onTap(0)); // 돌아오면 홈으로 초기화
              break;
          }
          widget.onTap(index);
        },
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: EdgeInsets.all(isSelected ? 6 : 4),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? primaryColor.withOpacity(0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isSelected ? icon : outlinedIcon,
                      size: isSelected ? 24 : 22,
                      color: isSelected ? primaryColor : Colors.grey[600],
                    ),
                  ),
                  if (badgeCount != null && badgeCount > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          badgeCount > 9 ? '9+' : badgeCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? primaryColor : Colors.grey[700],
                  letterSpacing: -0.3,
                  height: 1.0,
                ),
                maxLines: 1,
                overflow: TextOverflow.clip,
              ),
            ],
          ),
        ),
      ),
    );
  }
} 