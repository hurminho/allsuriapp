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
import '../../widgets/business/business_section_header.dart';
import '../../widgets/business/business_tokens.dart';
import 'estimate_requests_screen.dart';
import 'my_estimates_screen.dart';
import 'job_management_screen.dart';
import 'create_job_screen.dart';

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
      final available = all
          .where((o) => o.status == 'pending' && !o.isAwarded)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (userId != null) {
        await estimates.loadEstimates(businessId: userId);
      }
      final mine = estimates.estimates;
      setState(() {
        _newRequests = available.length;
        _pendingBids = mine.where((e) => e.status == 'pending').length;
        _inProgressJobs = mine
            .where((e) =>
                e.status == 'accepted' ||
                e.status == 'awarded' ||
                e.status == 'approved')
            .length;
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
    final businessName =
        (user?.businessName != null && user!.businessName!.trim().isNotEmpty)
            ? user.businessName!
            : (user?.name ?? '사업자');

    return BusinessAppShell(
      title: '오늘의 업무',
      showBackButton: false,
      navyAppBar: true,
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
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const EstimateRequestsScreen())),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: BusinessMetricCard(
                          label: '입찰 대기',
                          value: '$_pendingBids',
                          icon: Icons.hourglass_empty,
                          accent: BusinessTheme.warning,
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const BusinessMyEstimatesScreen(
                                          initialStatus: 'pending'))),
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
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const JobManagementScreen())),
                  ),
                  const SizedBox(height: 20),
                  const BusinessSectionHeader(
                    title: '핵심 업무',
                    subtitle: '수주와 협업 업무를 구분해 관리하세요',
                  ),
                  const SizedBox(height: 12),
                  _workCard(
                    icon: Icons.search_rounded,
                    title: '고객 요청 찾기',
                    description: '내 지역의 신규 견적 요청을 확인하세요',
                    action: '새 일감 보기',
                    background: BusinessTokens.blueLight,
                    border: BusinessTokens.blue.withValues(alpha: 0.35),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const EstimateRequestsScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _workCard(
                    icon: Icons.add_business_outlined,
                    title: '협업 일감 만들기',
                    description: '다른 전문 사업자와 공사를 함께 진행하세요',
                    action: '공사 만들기',
                    background: BusinessTokens.surface,
                    border: BusinessTokens.yellow,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CreateJobScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('우선 대응 일감',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
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
                            region:
                                BusinessTheme.regionFromAddress(lead.address),
                            timeLabel:
                                BusinessTheme.relativeTime(lead.createdAt),
                            symptom: lead.description,
                            isNew: BusinessTheme.isNewLead(lead.createdAt),
                            isUrgent: BusinessTheme.isVisitSoon(lead.visitDate),
                            canBid: true,
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const EstimateRequestsScreen())),
                          ),
                        )),
                  const SizedBox(height: 8),
                  BusinessPrimaryButton(
                    label: '새 일감 보기',
                    icon: Icons.arrow_forward,
                    onPressed: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const EstimateRequestsScreen()));
                    },
                  ),
                ],
              ),
            ),
    );
  }

  Widget _workCard({
    required IconData icon,
    required String title,
    required String description,
    required String action,
    required Color background,
    required Color border,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(BusinessTokens.cardRadius),
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BusinessTokens.card(
            color: background,
            borderColor: border,
          ),
          child: Row(
            children: [
              Icon(icon, color: BusinessTokens.navy, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: BusinessTokens.sectionTitle),
                    const SizedBox(height: 4),
                    Text(description, style: BusinessTokens.caption),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  Text(
                    action,
                    style: const TextStyle(
                      color: BusinessTokens.blue,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: BusinessTokens.blue,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
