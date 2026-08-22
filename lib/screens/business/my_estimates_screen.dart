import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/estimate.dart';
import '../../services/estimate_service.dart';
import '../../services/auth_service.dart';
import '../../theme/business_theme.dart';
import '../../widgets/business/business_app_shell.dart';
import '../../widgets/business/business_empty_state.dart';
import '../../widgets/business/business_filter_chip.dart';
import '../../widgets/business/business_lead_card.dart';
import '../../widgets/business/business_primary_button.dart';
import '../../widgets/business/business_status_badge.dart';
import 'transfer_estimate_screen.dart';
import 'job_management_screen.dart';
import 'create_job_screen.dart';

class BusinessMyEstimatesScreen extends StatefulWidget {
  final String? initialStatus;
  const BusinessMyEstimatesScreen({super.key, this.initialStatus});

  @override
  State<BusinessMyEstimatesScreen> createState() => _BusinessMyEstimatesScreenState();
}

class _BusinessMyEstimatesScreenState extends State<BusinessMyEstimatesScreen> {
  String _selectedStatus = 'all';

  @override
  void initState() {
    super.initState();
    if (widget.initialStatus != null && widget.initialStatus!.isNotEmpty) {
      _selectedStatus = widget.initialStatus!;
    }
    _loadEstimates();
  }

  Future<void> _loadEstimates() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final estimateService = Provider.of<EstimateService>(context, listen: false);
    if (authService.currentUser != null) {
      await estimateService.loadEstimates(businessId: authService.currentUser!.id);
    }
  }

  bool _matchesFilter(Estimate estimate) {
    switch (_selectedStatus) {
      case 'all':
        return true;
      case 'progress':
        return estimate.status == Estimate.STATUS_ACCEPTED;
      default:
        return estimate.status == _selectedStatus;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BusinessAppShell(
      title: '내 견적',
      body: Consumer<EstimateService>(
        builder: (context, estimateService, child) {
          if (estimateService.isLoading) {
            return const BusinessListSkeleton();
          }
          final filtered = estimateService.estimates.where(_matchesFilter).toList();
          return Column(
            children: [
              Container(
                color: BusinessTheme.surface,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      BusinessFilterChip(label: '전체', selected: _selectedStatus == 'all', onTap: () => setState(() => _selectedStatus = 'all')),
                      const SizedBox(width: 8),
                      BusinessFilterChip(label: '입찰 대기', selected: _selectedStatus == Estimate.STATUS_PENDING, onTap: () => setState(() => _selectedStatus = Estimate.STATUS_PENDING)),
                      const SizedBox(width: 8),
                      BusinessFilterChip(label: '채택됨', selected: _selectedStatus == Estimate.STATUS_AWARDED, onTap: () => setState(() => _selectedStatus = Estimate.STATUS_AWARDED)),
                      const SizedBox(width: 8),
                      BusinessFilterChip(label: '작업 진행', selected: _selectedStatus == 'progress', onTap: () => setState(() => _selectedStatus = 'progress')),
                      const SizedBox(width: 8),
                      BusinessFilterChip(label: '완료', selected: _selectedStatus == Estimate.STATUS_COMPLETED, onTap: () => setState(() => _selectedStatus = Estimate.STATUS_COMPLETED)),
                      const SizedBox(width: 8),
                      BusinessFilterChip(label: '미선정', selected: _selectedStatus == Estimate.STATUS_REJECTED, onTap: () => setState(() => _selectedStatus = Estimate.STATUS_REJECTED)),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? BusinessEmptyState(
                        icon: Icons.description_outlined,
                        title: '해당 상태의 견적이 없습니다',
                        subtitle: '견적 요청을 받으면 여기에 표시됩니다',
                      )
                    : RefreshIndicator(
                        onRefresh: _loadEstimates,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final estimate = filtered[index];
                            final info = BusinessStatusInfo.forEstimate(estimate.status);
                            final showComplete = estimate.status == Estimate.STATUS_APPROVED;
                            return BusinessLeadCard(
                              title: estimate.customerName.isNotEmpty ? estimate.customerName : '고객 요청',
                              category: estimate.equipmentType,
                              symptom: estimate.description,
                              amountLabel: BusinessTheme.formatWon(estimate.amount),
                              timeLabel: BusinessTheme.relativeTime(estimate.createdAt),
                              statusLabel: info.label,
                              statusColor: info.color,
                              nextAction: BusinessStatusInfo.nextActionForEstimate(estimate.status),
                              trailingAction: showComplete
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        TextButton(
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => TransferEstimateScreen(estimate: estimate),
                                              ),
                                            );
                                          },
                                          child: const Text('이관'),
                                        ),
                                        FilledButton(
                                          onPressed: () => estimateService.completeEstimate(estimate.id),
                                          child: const Text('완료'),
                                        ),
                                      ],
                                    )
                                  : null,
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: BusinessPrimaryButton(
                  label: '공사 만들기',
                  icon: Icons.add_business,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CreateJobScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: BusinessPrimaryButton(
                  label: '공사 관리',
                  secondary: true,
                  icon: Icons.work_outline,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const JobManagementScreen()),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
