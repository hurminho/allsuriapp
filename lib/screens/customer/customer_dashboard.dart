import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../../theme/business_theme.dart';
import '../../services/auth_service.dart';
import '../../services/order_service.dart';
import '../../services/estimate_service.dart';
import '../../models/order.dart';
import '../order/create_order_screen.dart';
import '../customer/my_estimates_screen.dart';
import '../chat/chat_list_page.dart';
import '../profile/profile_screen.dart';
import '../home/home_screen.dart';

class CustomerDashboard extends StatefulWidget {
  const CustomerDashboard({super.key});

  @override
  State<CustomerDashboard> createState() => _CustomerDashboardState();
}

class _CustomerDashboardState extends State<CustomerDashboard> {
  bool _loading = true;
  int _countPending = 0;
  int _countReceived = 0;
  int _countInProgress = 0;
  int _countCompleted = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final auth = context.read<AuthService>();
    final orderService = context.read<OrderService>();
    final estimateService = context.read<EstimateService>();
    setState(() => _loading = true);

    try {
      await orderService.loadOrders();
      final user = auth.currentUser;
      List<Order> all = orderService.orders;

      // 고객 식별: 전화번호 우선, 없으면 customerId
      List<Order> mine;
      if (user?.phoneNumber != null && user!.phoneNumber!.isNotEmpty) {
        final normalized = user.phoneNumber!.replaceAll(RegExp(r'[-\\s()]'), '');
        mine = all
            .where((o) => o.customerPhone.replaceAll(RegExp(r'[-\\s()]'), '') == normalized)
            .toList();
      } else if (user?.id != null) {
        mine = all.where((o) => o.customerId == user!.id).toList();
      } else {
        mine = [];
      }

      int pending = 0, received = 0, inProgress = 0, completed = 0;
      for (final order in mine) {
        await estimateService.loadEstimates(orderId: order.id);
        final estimates = List.of(estimateService.estimates);
        if (order.status == Order.STATUS_COMPLETED) {
          completed++;
        } else if (order.isAwarded) {
          inProgress++;
        } else if (estimates.isNotEmpty) {
          received++;
        } else {
          pending++;
        }
      }

      setState(() {
        _countPending = pending;
        _countReceived = received;
        _countInProgress = inProgress;
        _countCompleted = completed;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final user = authService.currentUser;

    return Scaffold(
      backgroundColor: BusinessTheme.background,
      appBar: AppBar(
        title: const Text('고객 대시보드'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const HomeScreen()),
                (route) => false,
              );
            },
            child: const Text('홈', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 헤더 섹션 (그라디언트 카드)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [CupertinoColors.systemBlue, CupertinoColors.activeBlue],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '환영합니다!',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: CupertinoColors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '사용자: ${user?.name ?? '고객님'}',
                      style: const TextStyle(
                        fontSize: 16,
                        color: CupertinoColors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 프로필 배너
              if ((user?.phoneNumber == null || (user!.phoneNumber?.isEmpty ?? true)))
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemYellow.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: CupertinoColors.systemYellow),
                  ),
                  child: Row(
                    children: [
                      const Icon(CupertinoIcons.person_crop_circle_badge_exclam, color: CupertinoColors.systemYellow),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          '빠른 연결을 위해 프로필(전화번호)을 완료해 주세요.',
                          style: TextStyle(color: CupertinoColors.label),
                        ),
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        color: CupertinoColors.systemYellow,
                        onPressed: () {
                          Navigator.push(
                            context,
                            CupertinoPageRoute(builder: (context) => const ProfileScreen()),
                          );
                        },
                        child: const Text('완료'),
                      ),
                    ],
                  ),
                ),
              if ((user?.phoneNumber == null || (user!.phoneNumber?.isEmpty ?? true)))
                const SizedBox(height: 16),

              // 진행 현황 카드
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: CupertinoColors.systemBackground,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: CupertinoColors.separator),
                ),
                child: _loading
                    ? const Center(child: CupertinoActivityIndicator())
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildStatChip('대기', _countPending, CupertinoColors.systemOrange),
                          _buildStatChip('수신', _countReceived, CupertinoColors.systemBlue),
                          _buildStatChip('진행', _countInProgress, CupertinoColors.systemGreen),
                          _buildStatChip('완료', _countCompleted, CupertinoColors.systemGrey),
                        ],
                      ),
              ),
              const SizedBox(height: 24),
              
              // 기능 그리드
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  children: [
                    _buildMenuCard(
                      context,
                      '견적 내기',
                      CupertinoIcons.plus_circle,
                      CupertinoColors.systemBlue,
                      () {
                        Navigator.push(
                          context,
                          CupertinoPageRoute(
                            builder: (context) => const CreateOrderScreen(),
                          ),
                        );
                      },
                    ),
                    _buildMenuCard(
                      context,
                      '내 견적',
                      CupertinoIcons.list_bullet,
                      CupertinoColors.systemGreen,
                      () {
                        Navigator.push(
                          context,
                          CupertinoPageRoute(
                            builder: (context) => const CustomerMyEstimatesScreen(),
                          ),
                        );
                      },
                    ),
                    _buildMenuCard(
                      context,
                      '채팅',
                      CupertinoIcons.chat_bubble_2,
                      CupertinoColors.systemOrange,
                      () {
                        Navigator.push(
                          context,
                          CupertinoPageRoute(
                            builder: (context) => const ChatListPage(),
                          ),
                        );
                      },
                    ),
                    _buildMenuCard(
                      context,
                      '프로필',
                      CupertinoIcons.person_circle,
                      CupertinoColors.systemGrey,
                      () {
                        Navigator.push(
                          context,
                          CupertinoPageRoute(
                            builder: (context) => const ProfileScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: CupertinoColors.systemBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: CupertinoColors.separator,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: CupertinoColors.systemGrey.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 32,
                  color: color,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.label,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
} 

Widget _buildStatChip(String label, int count, Color color) {
  return Column(
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Text(
          count.toString(),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        label,
        style: const TextStyle(fontSize: 12, color: CupertinoColors.secondaryLabel),
      ),
    ],
  );
}