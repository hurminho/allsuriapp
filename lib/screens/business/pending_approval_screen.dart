import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/business_theme.dart';
import '../../services/auth_service.dart';

/// 사업자 승인 대기 화면
/// 관리자가 승인하기 전까지 표시되는 화면
class PendingApprovalScreen extends StatelessWidget {
  const PendingApprovalScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final user = authService.currentUser;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('올수리'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await authService.signOut();
              if (context.mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
              }
            },
            tooltip: '로그아웃',
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 일러스트레이션 (시계 아이콘)
              Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  color: BusinessTheme.warning.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.access_time_rounded,
                  size: 80,
                  color: BusinessTheme.warning,
                ),
              ),
              
              const SizedBox(height: 40),
              
              // 안내 문구
              Text(
                '승인 대기 중',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 16),
              
              Text(
                '관리자의 승인을 기다리고 있습니다.\n1~2일 정도 기다려 주시기 바랍니다.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey[600],
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 32),
              
              // 사업자 정보 카드
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.blue.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.business,
                          size: 20,
                          color: Colors.blue[700],
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '등록된 정보',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[700],
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildInfoRow(
                      context,
                      Icons.person,
                      '상호명',
                      user?.businessName ?? user?.name ?? '미등록',
                    ),
                    const SizedBox(height: 8),
                    _buildInfoRow(
                      context,
                      Icons.email,
                      '이메일',
                      user?.email ?? '미등록',
                    ),
                    if (user?.phoneNumber != null) ...[
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        context,
                        Icons.phone,
                        '연락처',
                        user!.phoneNumber!,
                      ),
                    ],
                  ],
                ),
              ),
              
              const SizedBox(height: 32),
              
              // 안내 메시지
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.amber.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.amber[800],
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '승인이 완료되면 알림으로 안내해 드립니다.',
                        style: TextStyle(
                          color: Colors.amber[900],
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // 새로고침 버튼
              OutlinedButton.icon(
                onPressed: () {
                  authService.refreshCurrentUser();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('승인 상태 확인'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 16,
          color: Colors.grey[600],
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

