import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app_navigator_key.dart';
import '../../models/user.dart';
import '../../services/auth_service.dart';
import '../business/business_profile_screen.dart';
import '../admin/ad_management_screen.dart';
import '../home/home_screen.dart';
import 'my_revenue_screen.dart';
import 'package:app_settings/app_settings.dart';

/// RPC 실패 시 안내용 (웹에서 마무리 — dart-define으로 교체 가능)
const String _kAccountDeleteWebUrl = String.fromEnvironment(
  'ACCOUNT_DELETE_WEB_URL',
  defaultValue: 'https://allsuri.app',
);

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, child) {
        final user = authService.currentUser;
        
        // 로그인하지 않은 사용자에게 안내
        if (user == null) {
          return Scaffold(
            backgroundColor: const Color(0xFFF7FAFC),
            appBar: AppBar(
              title: const Text('프로필'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            body: _buildLoginGuide(context),
          );
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF7FAFC),
          appBar: AppBar(
            title: const Text('프로필'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: _buildProfileContent(context, user),
        );
      },
    );
  }

  Widget _buildLoginGuide(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.person_outline,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 24),
          const Text(
            '프로필을 보려면\n로그인하세요',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0B2545),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: const Text(
              '로그인',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileContent(BuildContext context, User user) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          _buildProfileHeader(context, user),
          const SizedBox(height: 20),
          _buildProfileActions(context, user),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context, User user) {
    return SizedBox(
      width: double.infinity,
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        elevation: 4,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 20.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0B2545),
                Color(0xFF2E74B5),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0xFF0B2545).withOpacity(0.3),
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(4), // 테두리 두께
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      user.name.isNotEmpty ? user.name[0].toUpperCase() : 'U',
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0B2545),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                (user.role == 'business' && (user.businessName != null && user.businessName!.trim().isNotEmpty))
                    ? user.businessName!
                    : user.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _getRoleDisplayName(user.role),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    if (user.role == 'business' && (user.businessName == null || user.businessName!.trim().isEmpty)) ...[
                      const SizedBox(width: 8),
                      Container(
                        width: 1,
                        height: 12,
                        color: Colors.white.withOpacity(0.5),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '상호명 미입력',
                        style: TextStyle(
                          fontSize: 13, 
                          color: Colors.white, 
                          fontWeight: FontWeight.w500
                        ),
                      ),
                    ]
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileActions(BuildContext context, User user) {
    return Column(
      children: [
        _buildActionTile(
          context,
          Icons.notifications,
          '알림 설정',
          () {
            AppSettings.openAppSettings();
          },
        ),
        if (user.role == 'business')
          _buildActionTile(
            context,
            Icons.business,
            '사업자 관리',
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BusinessProfileScreen()),
              );
            },
          ),
        // 사업자 매출 메뉴 (사업자만 표시)
        if (user.role == 'business' && user.businessStatus == 'approved')
          _buildActionTile(
            context,
            Icons.analytics_outlined,
            '내 매출',
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MyRevenueScreen()),
              );
            },
          ),
        // 관리자 메뉴 (관리자만 표시)
        if (user.role == 'admin' || user.email == 'admin@allsuri.app')
          _buildActionTile(
            context,
            Icons.admin_panel_settings,
            '광고 관리 (관리자)',
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdManagementScreen()),
              );
            },
          ),
        _buildActionTile(
          context,
          Icons.person_off_outlined,
          '회원 탈퇴',
          () => showDeleteAccountDialog(context),
          isDestructive: true,
        ),
        _buildActionTile(
          context,
          Icons.logout,
          '로그아웃',
          () => _showLogoutDialog(context),
          isDestructive: true,
        ),
      ],
    );
  }

  Widget _buildActionTile(
    BuildContext context,
    IconData icon,
    String title,
    VoidCallback onTap, {
    bool isDestructive = false,
  }) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDestructive
                      ? const Color(0xFFFF6B6B).withOpacity(0.1)
                      : const Color(0xFF2E74B5).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 24,
                  color: isDestructive
                      ? const Color(0xFFFF6B6B)
                      : const Color(0xFF2E74B5),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF102A43),
                  ),
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Color(0xFF102A43),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getRoleDisplayName(String role) {
    switch (role) {
      case 'admin':
        return '관리자';
      case 'business':
        return '사업자';
      case 'customer':
        return '고객';
      default:
        return '사용자';
    }
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('로그아웃'),
          content: const Text('정말 로그아웃하시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Provider.of<AuthService>(context, listen: false).signOut();
              },
              child: const Text('로그아웃'),
            ),
          ],
        );
      },
    );
  }
}

/// 계정 영구 삭제 (앱에서 시작 → Supabase RPC `delete_my_account`)
Future<void> showDeleteAccountDialog(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('회원 탈퇴'),
        content: const Text(
          '탈퇴 시 계정과 연결된 데이터가 삭제되며 복구할 수 없습니다.\n계속하시겠습니까?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('탈퇴'),
          ),
        ],
      );
    },
  );
  if (confirmed != true || !context.mounted) return;

  final auth = Provider.of<AuthService>(context, listen: false);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const AlertDialog(
      content: Row(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 20),
          Expanded(child: Text('탈퇴 처리 중…')),
        ],
      ),
    ),
  );

  try {
    await auth.deleteAccount();
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (!context.mounted) return;
    final openWeb = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('탈퇴를 완료할 수 없습니다'),
        content: Text(
          '앱에서 계정 삭제 처리에 실패했습니다. 아래 웹 페이지에서 탈퇴를 완료하거나, 잠시 후 다시 시도해 주세요.\n\n$_kAccountDeleteWebUrl',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('닫기'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('웹에서 열기'),
          ),
        ],
      ),
    );
    if (openWeb == true) {
      final uri = Uri.parse(_kAccountDeleteWebUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }
}