import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/estimate.dart';
import '../../providers/estimate_provider.dart';
import '../../widgets/common_app_bar.dart';
import '../../widgets/estimate_list_item.dart';
import 'transfer_estimate_screen.dart';
import 'package:go_router/go_router.dart';

class SelectEstimateForTransferScreen extends StatefulWidget {
  const SelectEstimateForTransferScreen({Key? key}) : super(key: key);

  @override
  State<SelectEstimateForTransferScreen> createState() => _SelectEstimateForTransferScreenState();
}

class _SelectEstimateForTransferScreenState extends State<SelectEstimateForTransferScreen> {
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
      final estimateProvider = Provider.of<EstimateProvider>(context, listen: false);
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
      return estimates.where((estimate) => !estimate.isTransferEstimate).toList();
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
    return Scaffold(
      appBar: CommonAppBar(
        title: '견적 이관하기',
        showBackButton: true,
        showHomeButton: true,
      ),
      body: Column(
        children: [
          // 상태 필터
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '이관할 견적 선택',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF102A43),
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _statusFilters.map((status) {
                      final isSelected = _selectedStatus == status;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(_getStatusLabel(status)),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              _selectedStatus = status;
                            });
                          },
                          backgroundColor: Colors.grey[200],
                          selectedColor: const Color(0xFF2E74B5).withOpacity(0.2),
                          labelStyle: TextStyle(
                            color: isSelected ? const Color(0xFF2E74B5) : Colors.grey[700],
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),

          // 견적 목록
          Expanded(
            child: Consumer<EstimateProvider>(
              builder: (context, estimateProvider, child) {
                if (_isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                List<Estimate> myEstimates = [];
                try {
                  myEstimates = estimateProvider.myEstimates ?? [];
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
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.assignment_outlined,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          (myEstimates.isEmpty)
                              ? '제출한 견적이 없습니다.'
                              : '선택한 상태의 견적이 없습니다.',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '먼저 견적을 제출한 후\n이관할 수 있습니다.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _loadMyEstimates,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filteredEstimates.length,
                    itemBuilder: (context, index) {
                      if (index < 0 || index >= filteredEstimates.length) {
                        return const SizedBox.shrink();
                      }
                      final estimate = filteredEstimates[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          onTap: () {
                            // 견적 이관 화면으로 이동
                            context.push('/business/transfer-estimate', extra: estimate);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '견적 ID: ${estimate.id.length > 8 ? '${estimate.id.substring(0, 8)}...' : estimate.id}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '고객: ${estimate.customerName ?? '고객 정보 없음'}',
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: _getStatusColor(estimate.status).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        _getStatusText(estimate.status),
                                        style: TextStyle(
                                          color: _getStatusColor(estimate.status),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '견적 금액: ${estimate.price.toStringAsFixed(0)}원',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Color(0xFF2E74B5),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '설명: ${estimate.description}',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        context.push('/business/transfer-estimate', extra: estimate);
                                      },
                                      icon: const Icon(Icons.swap_horiz, size: 16),
                                      label: const Text('이관하기'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF2E74B5),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        textStyle: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
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

  String _getStatusText(String status) {
    switch (status) {
      case Estimate.STATUS_PENDING:
        return '대기중';
      case Estimate.STATUS_ACCEPTED:
        return '수락됨';
      case Estimate.STATUS_REJECTED:
        return '거절됨';
      case Estimate.STATUS_AWARDED:
        return '선택됨';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case Estimate.STATUS_PENDING:
        return Colors.orange;
      case Estimate.STATUS_ACCEPTED:
        return Colors.green;
      case Estimate.STATUS_REJECTED:
        return Colors.red;
      case Estimate.STATUS_AWARDED:
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
} 