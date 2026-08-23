import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/estimate.dart';
import '../../providers/estimate_provider.dart';
import '../../widgets/business/business_app_shell.dart';
import '../../widgets/business/business_empty_state.dart';
import '../../widgets/business/business_filter_chip.dart';
import '../../widgets/business/business_primary_button.dart';
import '../../widgets/business/business_section_header.dart';
import '../../widgets/business/business_status_chip.dart';
import '../../widgets/business/business_tokens.dart';

class TransferredEstimatesScreen extends StatefulWidget {
  const TransferredEstimatesScreen({super.key});

  @override
  State<TransferredEstimatesScreen> createState() =>
      _TransferredEstimatesScreenState();
}

class _TransferredEstimatesScreenState
    extends State<TransferredEstimatesScreen> {
  String _selectedStatus = 'All';
  bool _isLoading = false;
  String? _loadError;

  final _amountFormat = NumberFormat('#,###', 'ko_KR');
  final _dateFormat = DateFormat('yyyy.MM.dd', 'ko_KR');

  final List<String> _statusFilters = [
    'All',
    'Pending',
    'Accepted',
    'Rejected',
    'Completed',
  ];

  @override
  void initState() {
    super.initState();
    _loadTransferredEstimates();
  }

  Future<void> _loadTransferredEstimates() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final estimateProvider =
          Provider.of<EstimateProvider>(context, listen: false);
      await estimateProvider.loadTransferredEstimates();
    } catch (_) {
      if (mounted) {
        setState(() => _loadError = '협업 견적을 불러오지 못했습니다');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Estimate> _getFilteredEstimates(List<Estimate> estimates) {
    if (_selectedStatus == 'All') {
      return estimates;
    }

    return estimates.where((estimate) {
      switch (_selectedStatus) {
        case 'Pending':
          return estimate.status == Estimate.STATUS_PENDING;
        case 'Accepted':
          return estimate.status == Estimate.STATUS_ACCEPTED;
        case 'Rejected':
          return estimate.status == Estimate.STATUS_REJECTED;
        case 'Completed':
          return estimate.status == Estimate.STATUS_AWARDED;
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return BusinessAppShell(
      title: '이관한 견적',
      actions: [
        IconButton(
          onPressed: _loadTransferredEstimates,
          tooltip: '새로고침',
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: BusinessTokens.surface,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BusinessSectionHeader(
                  title: '협업 일감',
                  subtitle: '다른 업체에 이관한 견적의 진행 상태입니다',
                ),
                const SizedBox(height: BusinessTokens.space12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _statusFilters.map((status) {
                      return Padding(
                        padding: const EdgeInsets.only(
                          right: BusinessTokens.space8,
                        ),
                        child: BusinessFilterChip(
                          label: _getStatusLabel(status),
                          selected: _selectedStatus == status,
                          onTap: () {
                            setState(() => _selectedStatus = status);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const BusinessListSkeleton()
                : _loadError != null
                    ? BusinessEmptyState(
                        icon: Icons.refresh_rounded,
                        title: _loadError!,
                        subtitle: '네트워크 상태를 확인한 뒤 다시 시도해 주세요.',
                        actionLabel: '다시 시도',
                        onAction: _loadTransferredEstimates,
                      )
                    : Consumer<EstimateProvider>(
                        builder: (context, estimateProvider, child) {
                          final transferredEstimates =
                              estimateProvider.transferredEstimates;
                          final filteredEstimates =
                              _getFilteredEstimates(transferredEstimates);

                          if (filteredEstimates.isEmpty) {
                            return BusinessEmptyState(
                              icon: Icons.swap_horiz_rounded,
                              title: transferredEstimates.isEmpty
                                  ? '이관한 견적이 없습니다'
                                  : '선택한 상태의 견적이 없습니다',
                              subtitle: transferredEstimates.isEmpty
                                  ? '견적을 다른 업체에 이관하면 여기에 표시됩니다.'
                                  : '다른 상태를 선택해 확인해 주세요.',
                            );
                          }

                          return RefreshIndicator(
                            onRefresh: _loadTransferredEstimates,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(
                                BusinessTokens.space16,
                              ),
                              itemCount: filteredEstimates.length,
                              separatorBuilder: (_, __) => const SizedBox(
                                height: BusinessTokens.space12,
                              ),
                              itemBuilder: (context, index) {
                                return _buildEstimateCard(
                                  filteredEstimates[index],
                                );
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEstimateCard(Estimate estimate) {
    final date = estimate.transferredAt ?? estimate.createdAt;
    return Container(
      padding: const EdgeInsets.all(BusinessTokens.space16),
      decoration: BusinessTokens.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Text('이관 견적', style: BusinessTokens.caption),
              ),
              BusinessStatusChip.forEstimate(estimate.status),
            ],
          ),
          const SizedBox(height: BusinessTokens.space12),
          Text(
            estimate.customerName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: BusinessTokens.title,
          ),
          const SizedBox(height: BusinessTokens.space16),
          const Divider(height: 1, color: BusinessTokens.border),
          const SizedBox(height: BusinessTokens.space12),
          _buildInfoRow(
            Icons.calendar_today_outlined,
            estimate.transferredAt != null ? '이관 일자' : '등록 일자',
            _dateFormat.format(date),
          ),
          const SizedBox(height: BusinessTokens.space12),
          _buildInfoRow(
            Icons.payments_outlined,
            '견적 금액',
            '${_amountFormat.format(estimate.amount)}원',
          ),
          const SizedBox(height: BusinessTokens.space12),
          _buildInfoRow(
            Icons.privacy_tip_outlined,
            '연락 안내',
            '고객 연락은 기존 견적 절차에 따라 진행해 주세요.',
          ),
          const SizedBox(height: BusinessTokens.space16),
          BusinessPrimaryButton(
            label: '진행 상세 보기',
            icon: Icons.chevron_right_rounded,
            onPressed: () {
              context.push('/estimate-detail/${estimate.id}');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: BusinessTokens.blue),
        const SizedBox(width: BusinessTokens.space8),
        SizedBox(
          width: 64,
          child: Text(label, style: BusinessTokens.caption),
        ),
        const SizedBox(width: BusinessTokens.space8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: BusinessTokens.body,
          ),
        ),
      ],
    );
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'All':
        return '전체';
      case 'Pending':
        return '대기 중';
      case 'Accepted':
        return '작업 진행';
      case 'Rejected':
        return '거절됨';
      case 'Completed':
        return '완료';
      default:
        return status;
    }
  }
}
