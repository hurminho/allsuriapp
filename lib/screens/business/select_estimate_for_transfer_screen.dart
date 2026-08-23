import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/estimate.dart';
import '../../providers/estimate_provider.dart';
import '../../widgets/business/business_app_shell.dart';
import '../../widgets/business/business_empty_state.dart';
import '../../widgets/business/business_filter_chip.dart';
import '../../widgets/business/business_section_header.dart';
import '../../widgets/business/business_status_chip.dart';
import '../../widgets/business/business_tokens.dart';
import 'package:go_router/go_router.dart';

class SelectEstimateForTransferScreen extends StatefulWidget {
  const SelectEstimateForTransferScreen({Key? key}) : super(key: key);

  @override
  State<SelectEstimateForTransferScreen> createState() =>
      _SelectEstimateForTransferScreenState();
}

class _SelectEstimateForTransferScreenState
    extends State<SelectEstimateForTransferScreen> {
  String _selectedStatus = 'All';
  bool _isLoading = false;

  final List<String> _statusFilters = [
    'All',
    'Pending',
    'Accepted',
    'Rejected',
  ];

  @override
  void initState() {
    super.initState();
    // 빌드 완료 후 데이터 로드
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMyEstimates();
    });
  }

  Future<void> _loadMyEstimates() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final estimateProvider =
          Provider.of<EstimateProvider>(context, listen: false);
      await estimateProvider.loadMyEstimates();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('견적 목록을 불러오는 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  List<Estimate> _getFilteredEstimates(List<Estimate> estimates) {
    if (_selectedStatus == 'All') {
      return estimates
          .where((estimate) => !estimate.isTransferEstimate)
          .toList();
    }

    return estimates.where((estimate) {
      if (estimate.isTransferEstimate) return false;

      switch (_selectedStatus) {
        case 'Pending':
          return estimate.status == Estimate.STATUS_PENDING;
        case 'Accepted':
          return estimate.status == Estimate.STATUS_ACCEPTED;
        case 'Rejected':
          return estimate.status == Estimate.STATUS_REJECTED;
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return BusinessAppShell(
      title: '협업 이관 견적 선택',
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
                  title: '이관할 견적을 선택하세요',
                  subtitle: '기존 견적을 동료 사업자에게 협업 이관합니다',
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _statusFilters.map((status) {
                      final isSelected = _selectedStatus == status;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: BusinessFilterChip(
                          label: _getStatusLabel(status),
                          selected: isSelected,
                          onTap: () {
                            setState(() {
                              _selectedStatus = status;
                            });
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
            child: Consumer<EstimateProvider>(
              builder: (context, estimateProvider, child) {
                if (_isLoading) {
                  return const BusinessListSkeleton();
                }

                List<Estimate> myEstimates = [];
                try {
                  myEstimates = estimateProvider.myEstimates;
                } catch (e) {
                  // 예외 발생 시 빈 리스트로 처리
                  myEstimates = [];
                }
                List<Estimate> filteredEstimates = [];
                try {
                  filteredEstimates = _getFilteredEstimates(myEstimates);
                } catch (e) {
                  filteredEstimates = [];
                }

                if (filteredEstimates.isEmpty) {
                  return BusinessEmptyState(
                    icon: Icons.assignment_outlined,
                    title: myEstimates.isEmpty
                        ? '이관할 견적이 없습니다'
                        : '선택한 상태의 견적이 없습니다',
                    subtitle: '제출한 견적이 있으면 협업 이관을 진행할 수 있습니다.',
                  );
                }

                return RefreshIndicator(
                  onRefresh: _loadMyEstimates,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredEstimates.length,
                    itemBuilder: (context, index) {
                      if (index < 0 || index >= filteredEstimates.length) {
                        return const SizedBox.shrink();
                      }
                      final estimate = filteredEstimates[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BusinessTokens.card(),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(
                            BusinessTokens.cardRadius,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () {
                              context.push('/business/transfer-estimate',
                                  extra: estimate);
                            },
                            borderRadius: BorderRadius.circular(
                              BusinessTokens.cardRadius,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              estimate.equipmentType.isNotEmpty
                                                  ? estimate.equipmentType
                                                  : '견적',
                                              style:
                                                  BusinessTokens.sectionTitle,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              estimate.customerName.isNotEmpty
                                                  ? estimate.customerName
                                                  : '고객 정보 없음',
                                              style: BusinessTokens.caption,
                                            ),
                                          ],
                                        ),
                                      ),
                                      _transferStatusChip(estimate.status),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    '${_formatAmount(estimate.price)}원',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 18,
                                      color: BusinessTokens.blue,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  if (estimate.description.isNotEmpty)
                                    Text(
                                      estimate.description,
                                      style: BusinessTokens.body,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.calendar_today_outlined,
                                        size: 15,
                                        color: BusinessTokens.mutedText,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          '방문 ${_formatDate(estimate.visitDate)}',
                                          style: BusinessTokens.caption,
                                        ),
                                      ),
                                      const Text(
                                        '협업 이관',
                                        style: TextStyle(
                                          color: BusinessTokens.blue,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      const Icon(
                                        Icons.chevron_right_rounded,
                                        size: 18,
                                        color: BusinessTokens.blue,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
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

  String _formatAmount(double amount) {
    return amount.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (match) => '${match[1]},',
        );
  }

  String _formatDate(DateTime date) {
    return '${date.year}.${date.month.toString().padLeft(2, '0')}.'
        '${date.day.toString().padLeft(2, '0')}';
  }

  Widget _transferStatusChip(String status) {
    switch (status) {
      case Estimate.STATUS_PENDING:
        return const BusinessStatusChip(
          label: '대기',
          tone: BusinessStatusTone.warning,
        );
      case Estimate.STATUS_ACCEPTED:
        return const BusinessStatusChip(
          label: '수락',
          tone: BusinessStatusTone.success,
        );
      case Estimate.STATUS_REJECTED:
        return const BusinessStatusChip(
          label: '거절',
          tone: BusinessStatusTone.danger,
        );
      case Estimate.STATUS_AWARDED:
        return const BusinessStatusChip(
          label: '선정',
          tone: BusinessStatusTone.info,
        );
      default:
        return BusinessStatusChip(label: status);
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'All':
        return '전체';
      case 'Pending':
        return '대기중';
      case 'Accepted':
        return '수락됨';
      case 'Rejected':
        return '거절됨';
      default:
        return status;
    }
  }
}
