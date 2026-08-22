import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/order_service.dart';
import '../../services/estimate_service.dart';
import '../../theme/business_theme.dart';
import '../../widgets/business/business_app_shell.dart';
import '../../widgets/business/business_empty_state.dart';
import '../../widgets/business/business_lead_card.dart';
import '../../widgets/business/business_metric_card.dart';
import '../../widgets/business/business_primary_button.dart';
import '../chat/chat_list_page.dart';
import '../home/home_screen.dart';
import '../community/community_board_screen.dart';
import 'estimate_requests_screen.dart';
import 'my_estimates_screen.dart';
import 'job_management_screen.dart';
import 'business_profile_screen.dart';

class BusinessDashboard extends StatefulWidget {
  const BusinessDashboard({super.key});

  @override
  State<BusinessDashboard> createState() => _BusinessDashboardState();
}

class _BusinessDashboardState extends State<BusinessDashboard> {
  int _newRequests = 0;
  int _pendingBids = 0;
  int _inProgressJobs = 0;
  List<dynamic> _priorityLeads = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final orders = Provider.of<OrderService>(context, listen: false);
    final estimates = Provider.of<EstimateService>(context, listen: false);
    final userId = auth.currentUser?.id;
    try {
      final all = await orders.getOrders();
      final available = all.where((o) => o.status == 'pending' && !o.isAwarded).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (userId != null) {
        await estimates.loadEstimates(businessId: userId);
      }
      final mine = estimates.estimates;
      setState(() {
        _newRequests = available.length;
        _pendingBids = mine.where((e) => e.status == 'pending').length;
        _inProgressJobs = mine.where((e) => e.status == 'accepted' || e.status == 'awarded' || e.status == 'approved').length;
        _priorityLeads = available.take(3).toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final user = authService.currentUser;
    final businessName = (user?.businessName != null && user!.businessName!.trim().isNotEmpty)
        ? user.businessName!
        : (user?.name ?? '사업자');

    return BusinessAppShell(
      title: '오늘의 업무',
      showBackButton: true,
      onBack: () {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      },
      body: _loading
          ? const BusinessListSkeleton()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    '$businessName 님',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: BusinessTheme.navy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '오늘 처리할 일감을 한눈에 확인하세요',
                    style: TextStyle(color: BusinessTheme.textMuted),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: BusinessMetricCard(
                          label: '신규 견적 요청',
                          value: '$_newRequests',
                          icon: Icons.inbox_outlined,
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EstimateRequestsScreen())),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: BusinessMetricCard(
                          label: '입찰 대기',
                          value: '$_pendingBids',
                          icon: Icons.hourglass_empty,
                          accent: BusinessTheme.warning,
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BusinessMyEstimatesScreen(initialStatus: 'pending'))),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  BusinessMetricCard(
                    label: '수주 진행 작업',
                    value: '$_inProgressJobs',
                    icon: Icons.handyman_outlined,
                    accent: BusinessTheme.success,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const JobManagementScreen())),
                  ),
                  const SizedBox(height: 20),
                  const Text('우선 대응 일감', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 8),
                  if (_priorityLeads.isEmpty)
                    const BusinessEmptyState(
                      icon: Icons.task_alt,
                      title: '지금 바로 볼 신규 일감이 없습니다',
                    )
                  else
                    ..._priorityLeads.map((lead) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: BusinessLeadCard(
                            title: lead.title,
                            category: lead.equipmentType,
                            region: BusinessTheme.regionFromAddress(lead.address),
                            timeLabel: BusinessTheme.relativeTime(lead.createdAt),
                            symptom: lead.description,
                            isNew: BusinessTheme.isNewLead(lead.createdAt),
                            isUrgent: BusinessTheme.isVisitSoon(lead.visitDate),
                            canBid: true,
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EstimateRequestsScreen())),
                          ),
                        )),
                  const SizedBox(height: 8),
                  BusinessPrimaryButton(
                    label: '새 일감 보기',
                    icon: Icons.arrow_forward,
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const EstimateRequestsScreen()));
                    },
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _navChip('내 견적', Icons.description_outlined, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BusinessMyEstimatesScreen()))),
                      _navChip('수주 관리', Icons.work_outline, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const JobManagementScreen()))),
                      _navChip('채팅', Icons.chat_bubble_outline, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatListPage()))),
                      _navChip('프로필', Icons.person_outline, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BusinessProfileScreen()))),
                      _navChip('커뮤니티', Icons.groups_outlined, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CommunityBoardScreen()))),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _navChip(String label, IconData icon, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: BusinessTheme.navy),
      label: Text(label),
      onPressed: onTap,
      backgroundColor: BusinessTheme.surface,
      side: const BorderSide(color: BusinessTheme.border),
    );
  }
}
