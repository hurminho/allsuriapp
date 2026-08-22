import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/estimate.dart';
import '../../providers/estimate_provider.dart';
import '../../theme/business_theme.dart';
import '../../widgets/business/business_app_shell.dart';
import '../../widgets/business/business_empty_state.dart';
import '../../widgets/business/business_filter_chip.dart';
import '../../widgets/estimate_list_item.dart';
import 'package:go_router/go_router.dart';

class TransferredEstimatesScreen extends StatefulWidget {
  const TransferredEstimatesScreen({Key? key}) : super(key: key);

  @override
  State<TransferredEstimatesScreen> createState() => _TransferredEstimatesScreenState();
}

class _TransferredEstimatesScreenState extends State<TransferredEstimatesScreen> {
  String _selectedStatus = 'All';
  bool _isLoading = false;

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
    });

    try {
      final estimateProvider = Provider.of<EstimateProvider>(context, listen: false);
      await estimateProvider.loadTransferredEstimates();
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
      body: Column(
        children: [
          // 상태 필터
          Container(
            color: BusinessTheme.surface,
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _statusFilters.map((status) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: BusinessFilterChip(
                        label: _getStatusLabel(status),
                        selected: _selectedStatus == status,
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
          ),

          // 견적 목록
          Expanded(
            child: Consumer<EstimateProvider>(
              builder: (context, estimateProvider, child) {
                if (_isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                final transferredEstimates = estimateProvider.transferredEstimates;
                final filteredEstimates = _getFilteredEstimates(transferredEstimates);

                if (filteredEstimates.isEmpty) {
                  return BusinessEmptyState(
                    icon: Icons.swap_horiz_rounded,
                    title: transferredEstimates.isEmpty
                        ? '이관한 견적이 없습니다.'
                        : '선택한 상태의 견적이 없습니다.',
                    subtitle: '다른 사업자에게 견적을 이관하면 여기에 표시됩니다.',
                  );
                }

                return RefreshIndicator(
                  onRefresh: _loadTransferredEstimates,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filteredEstimates.length,
                    itemBuilder: (context, index) {
                      final estimate = filteredEstimates[index];
                      return EstimateListItem(
                        estimate: estimate,
                        onTap: () {
                          // 견적 상세 화면으로 이동
                          context.push('/estimate-detail/${estimate.id}');
                        },
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
      case 'Completed':
        return '완료';
      default:
        return status;
    }
  }
} 