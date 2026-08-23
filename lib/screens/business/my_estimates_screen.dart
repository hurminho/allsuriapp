import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/estimate.dart';
import '../../services/estimate_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/business/business_app_shell.dart';
import '../../widgets/business/business_empty_state.dart';
import '../../widgets/business/business_filter_chip.dart';
import '../../widgets/business/business_primary_button.dart';
import '../../widgets/business/business_section_header.dart';
import '../../widgets/business/business_status_chip.dart';
import '../../widgets/business/business_tokens.dart';
import 'transfer_estimate_screen.dart';
import 'job_management_screen.dart';
import 'create_job_screen.dart';

class BusinessMyEstimatesScreen extends StatefulWidget {
  final String? initialStatus;
  const BusinessMyEstimatesScreen({super.key, this.initialStatus});

  @override
  State<BusinessMyEstimatesScreen> createState() =>
      _BusinessMyEstimatesScreenState();
}

class _BusinessMyEstimatesScreenState extends State<BusinessMyEstimatesScreen> {
  String _selectedStatus = 'all';
  String? _loadError;

  @override
  void initState() {
    super.initState();
    if (widget.initialStatus != null && widget.initialStatus!.isNotEmpty) {
      _selectedStatus = widget.initialStatus!;
    }
    _loadEstimates();
  }

  Future<void> _loadEstimates() async {
    if (mounted) {
      setState(() => _loadError = null);
    }
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final estimateService =
          Provider.of<EstimateService>(context, listen: false);
      if (authService.currentUser != null) {
        await estimateService.loadEstimates(
          businessId: authService.currentUser!.id,
        );
      } else if (mounted) {
        setState(() => _loadError = '로그인 정보를 확인할 수 없습니다.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadError = '입찰 목록을 불러오지 못했습니다.');
      }
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
      title: '내 입찰',
      actions: [
        IconButton(
          onPressed: _loadEstimates,
          tooltip: '새로고침',
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      body: Consumer<EstimateService>(
        builder: (context, estimateService, child) {
          final filtered =
              estimateService.estimates.where(_matchesFilter).toList();
          return Column(
            children: [
              _buildFilterBar(),
              Expanded(
                child: _loadError != null
                    ? BusinessEmptyState(
                        icon: Icons.cloud_off_outlined,
                        title: '내 입찰을 불러오지 못했습니다',
                        subtitle: _loadError,
                        actionLabel: '다시 시도',
                        onAction: _loadEstimates,
                      )
                    : estimateService.isLoading
                        ? const BusinessListSkeleton()
                        : filtered.isEmpty
                            ? const BusinessEmptyState(
                                icon: Icons.description_outlined,
                                title: '해당 상태의 입찰이 없습니다',
                                subtitle: '제출한 입찰이 생기면 여기에 표시됩니다.',
                              )
                            : RefreshIndicator(
                                onRefresh: _loadEstimates,
                                child: ListView.separated(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.all(
                                    BusinessTokens.pagePadding,
                                  ),
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, __) => const SizedBox(
                                    height: BusinessTokens.space12,
                                  ),
                                  itemBuilder: (context, index) =>
                                      _buildEstimateCard(
                                    filtered[index],
                                    estimateService,
                                  ),
                                ),
                              ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            BusinessTokens.pagePadding,
            BusinessTokens.space8,
            BusinessTokens.pagePadding,
            BusinessTokens.space8,
          ),
          child: Row(
            children: [
              Expanded(
                child: BusinessPrimaryButton(
                  label: '공사 만들기',
                  icon: Icons.add_business,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const CreateJobScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(width: BusinessTokens.space12),
              Expanded(
                child: BusinessPrimaryButton(
                  label: '공사 관리',
                  secondary: true,
                  icon: Icons.work_outline,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const JobManagementScreen()),
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

  Widget _buildFilterBar() {
    return Container(
      width: double.infinity,
      color: BusinessTokens.surface,
      padding: const EdgeInsets.fromLTRB(
        BusinessTokens.pagePadding,
        BusinessTokens.space12,
        BusinessTokens.pagePadding,
        BusinessTokens.space12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BusinessSectionHeader(
            title: '입찰 상태',
            subtitle: '상태를 선택해 제출한 입찰을 확인하세요.',
          ),
          const SizedBox(height: BusinessTokens.space12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                BusinessFilterChip(
                  label: '전체',
                  selected: _selectedStatus == 'all',
                  onTap: () => setState(() => _selectedStatus = 'all'),
                ),
                const SizedBox(width: BusinessTokens.space8),
                BusinessFilterChip(
                  label: '대기',
                  selected: _selectedStatus == Estimate.STATUS_PENDING,
                  onTap: () => setState(
                    () => _selectedStatus = Estimate.STATUS_PENDING,
                  ),
                ),
                const SizedBox(width: BusinessTokens.space8),
                BusinessFilterChip(
                  label: '채택',
                  selected: _selectedStatus == Estimate.STATUS_AWARDED,
                  onTap: () => setState(
                    () => _selectedStatus = Estimate.STATUS_AWARDED,
                  ),
                ),
                const SizedBox(width: BusinessTokens.space8),
                BusinessFilterChip(
                  label: '진행',
                  selected: _selectedStatus == 'progress',
                  onTap: () => setState(() => _selectedStatus = 'progress'),
                ),
                const SizedBox(width: BusinessTokens.space8),
                BusinessFilterChip(
                  label: '완료',
                  selected: _selectedStatus == Estimate.STATUS_COMPLETED,
                  onTap: () => setState(
                    () => _selectedStatus = Estimate.STATUS_COMPLETED,
                  ),
                ),
                const SizedBox(width: BusinessTokens.space8),
                BusinessFilterChip(
                  label: '미선정',
                  selected: _selectedStatus == Estimate.STATUS_REJECTED,
                  onTap: () => setState(
                    () => _selectedStatus = Estimate.STATUS_REJECTED,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEstimateCard(
    Estimate estimate,
    EstimateService estimateService,
  ) {
    final canComplete = estimate.status == Estimate.STATUS_APPROVED;
    final title = estimate.customerName.isNotEmpty
        ? estimate.customerName
        : estimate.equipmentType;

    return Container(
      decoration: BusinessTokens.card(),
      padding: const EdgeInsets.all(BusinessTokens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BusinessStatusChip.forEstimate(estimate.status),
              const Spacer(),
              Text(
                _formatDateTime(estimate.createdAt),
                style: BusinessTokens.caption,
              ),
            ],
          ),
          if (title.isNotEmpty) ...[
            const SizedBox(height: BusinessTokens.space12),
            Text(title, style: BusinessTokens.sectionTitle),
          ],
          if (estimate.equipmentType.isNotEmpty &&
              estimate.equipmentType != title) ...[
            const SizedBox(height: BusinessTokens.space4),
            Text(estimate.equipmentType, style: BusinessTokens.caption),
          ],
          if (estimate.description.isNotEmpty) ...[
            const SizedBox(height: BusinessTokens.space8),
            Text(
              estimate.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: BusinessTokens.body.copyWith(
                color: BusinessTokens.mutedText,
              ),
            ),
          ],
          const SizedBox(height: BusinessTokens.space16),
          const Divider(height: 1, color: BusinessTokens.border),
          const SizedBox(height: BusinessTokens.space12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('입찰 금액', style: BusinessTokens.caption),
                    const SizedBox(height: BusinessTokens.space4),
                    Text(
                      _formatWon(estimate.amount),
                      style: BusinessTokens.title.copyWith(
                        color: BusinessTokens.navy,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '예상 ${estimate.estimatedDays}일',
                style: BusinessTokens.caption,
              ),
            ],
          ),
          const SizedBox(height: BusinessTokens.space12),
          if (canComplete)
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            TransferEstimateScreen(estimate: estimate),
                      ),
                    );
                  },
                  child: const Text('이관'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () =>
                      estimateService.completeEstimate(estimate.id),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('완료 처리'),
                ),
              ],
            )
          else
            Row(
              children: [
                const Icon(
                  Icons.arrow_forward_rounded,
                  size: 16,
                  color: BusinessTokens.blue,
                ),
                const SizedBox(width: BusinessTokens.space8),
                Expanded(
                  child: Text(
                    _nextAction(estimate.status),
                    style: BusinessTokens.caption.copyWith(
                      color: BusinessTokens.blue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _nextAction(String status) {
    switch (status) {
      case Estimate.STATUS_PENDING:
        return '고객의 선택을 기다리고 있습니다.';
      case Estimate.STATUS_AWARDED:
        return '채택된 입찰입니다.';
      case Estimate.STATUS_ACCEPTED:
        return '작업이 진행 중입니다.';
      case Estimate.STATUS_COMPLETED:
        return '완료된 입찰입니다.';
      case Estimate.STATUS_REJECTED:
        return '이번 입찰은 종료되었습니다.';
      case Estimate.STATUS_TRANSFERRED:
        return '다른 사업자에게 이관되었습니다.';
      default:
        return '현재 상태를 확인해주세요.';
    }
  }

  String _formatWon(double amount) {
    final formatted = amount.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (match) => ',',
        );
    return '$formatted원';
  }

  String _formatDateTime(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}.$month.$day';
  }
}
