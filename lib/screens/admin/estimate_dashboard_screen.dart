import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/estimate.dart';
import '../../providers/estimate_provider.dart';
import '../../widgets/common_app_bar.dart';
import 'package:go_router/go_router.dart';

class EstimateDashboardScreen extends StatefulWidget {
  const EstimateDashboardScreen({Key? key}) : super(key: key);

  @override
  State<EstimateDashboardScreen> createState() => _EstimateDashboardScreenState();
}

class _EstimateDashboardScreenState extends State<EstimateDashboardScreen> {
  String _selectedStatus = 'all';
  bool _isLoading = false;

  final List<String> _statusFilters = [
    'all',
    'pending',
    'accepted',
    'rejected',
    'awarded',
    'completed',
  ];

  @override
  void initState() {
    super.initState();
    _loadEstimates();
  }

  Future<void> _loadEstimates() async {
    setState(() => _isLoading = true);
    try {
      final estimateProvider = Provider.of<EstimateProvider>(context, listen: false);
      await estimateProvider.fetchEstimates();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('견적 목록을 불러오는 중 오류가 발생했습니다: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Estimate> _getFilteredEstimates(List<Estimate> estimates) {
    switch (_selectedStatus) {
      case 'pending':
        return estimates.where((e) => e.status == Estimate.STATUS_PENDING).toList();
      case 'accepted':
        return estimates.where((e) => e.status == Estimate.STATUS_ACCEPTED).toList();
      case 'rejected':
        return estimates.where((e) => e.status == Estimate.STATUS_REJECTED).toList();
      case 'awarded':
        return estimates.where((e) => e.status == Estimate.STATUS_AWARDED).toList();
      case 'completed':
        return estimates.where((e) => e.status == 'COMPLETED').toList();
      default:
        return estimates;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonAppBar(
        title: '견적 현황 대시보드',
        showBackButton: true,
        showHomeButton: true,
      ),
      body: Column(
        children: [
          // 통계 카드
          _buildStatisticsCards(),
          
          // 필터 칩
          _buildFilterChips(),
          
          // 견적 목록
          Expanded(
            child: Consumer<EstimateProvider>(
              builder: (context, estimateProvider, child) {
                if (_isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                final estimates = estimateProvider.estimates;
                final filteredEstimates = _getFilteredEstimates(estimates);

                if (filteredEstimates.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.assignment_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _selectedStatus == 'all' 
                              ? '등록된 견적이 없습니다.'
                              : '선택한 상태의 견적이 없습니다.',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _loadEstimates,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredEstimates.length,
                    itemBuilder: (context, index) {
                      final estimate = filteredEstimates[index];
                      return _buildEstimateCard(estimate);
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

  Widget _buildStatisticsCards() {
    return Consumer<EstimateProvider>(
      builder: (context, estimateProvider, child) {
        final estimates = estimateProvider.estimates;
        
        final pendingCount = estimates.where((e) => e.status == Estimate.STATUS_PENDING).length;
        final acceptedCount = estimates.where((e) => e.status == Estimate.STATUS_ACCEPTED).length;
        final awardedCount = estimates.where((e) => e.status == Estimate.STATUS_AWARDED).length;
        final completedCount = estimates.where((e) => e.status == 'COMPLETED').length;

        return Container(
          padding: const EdgeInsets.all(16),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.8,
            children: [
              _buildStatCard('대기 중', pendingCount.toString(), Icons.pending, Colors.orange),
              _buildStatCard('수락됨', acceptedCount.toString(), Icons.check_circle, Colors.blue),
              _buildStatCard('낙찰됨', awardedCount.toString(), Icons.star, Colors.green),
              _buildStatCard('완료됨', completedCount.toString(), Icons.done_all, Colors.purple),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard(String title, String count, IconData icon, Color color) {
    return Card(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withOpacity(0.1),
              color.withOpacity(0.05),
            ],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              count,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildFilterChip('전체', 'all'),
          const SizedBox(width: 8),
          _buildFilterChip('대기 중', 'pending'),
          const SizedBox(width: 8),
          _buildFilterChip('수락됨', 'accepted'),
          const SizedBox(width: 8),
          _buildFilterChip('거절됨', 'rejected'),
          const SizedBox(width: 8),
          _buildFilterChip('낙찰됨', 'awarded'),
          const SizedBox(width: 8),
          _buildFilterChip('완료됨', 'completed'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedStatus == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedStatus = value;
        });
      },
      selectedColor: const Color(0xFF2E74B5).withOpacity(0.2),
      checkmarkColor: const Color(0xFF2E74B5),
      labelStyle: TextStyle(
        color: isSelected ? const Color(0xFF2E74B5) : Colors.grey[600],
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildEstimateCard(Estimate estimate) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
                        '견적 ID: ${estimate.id}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '사업자: ${estimate.technicianName}',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusChip(estimate.status),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '견적 금액',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '${estimate.price.toStringAsFixed(0)}원',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFF2E74B5),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '예상 기간',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '${estimate.estimatedDays}일',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _viewEstimateDetails(estimate),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2E74B5),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    child: const Text('상세 보기'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _updateEstimateStatus(estimate),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E74B5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    child: const Text('상태 변경'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color backgroundColor;
    String statusText;

    switch (status) {
      case Estimate.STATUS_PENDING:
        backgroundColor = Colors.orange;
        statusText = '대기';
        break;
      case Estimate.STATUS_ACCEPTED:
        backgroundColor = Colors.blue;
        statusText = '수락';
        break;
      case Estimate.STATUS_REJECTED:
        backgroundColor = Colors.red;
        statusText = '거절';
        break;
      case Estimate.STATUS_AWARDED:
        backgroundColor = Colors.green;
        statusText = '낙찰';
        break;
      case 'COMPLETED':
        backgroundColor = Colors.purple;
        statusText = '완료';
        break;
      default:
        backgroundColor = Colors.grey;
        statusText = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        statusText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _viewEstimateDetails(Estimate estimate) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('견적 상세 정보'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('견적 ID: ${estimate.id}'),
              const SizedBox(height: 8),
              Text('사업자: ${estimate.technicianName}'),
              const SizedBox(height: 8),
              Text('견적 금액: ${estimate.price.toStringAsFixed(0)}원'),
              const SizedBox(height: 8),
              Text('예상 기간: ${estimate.estimatedDays}일'),
              const SizedBox(height: 8),
              Text('상태: ${_getStatusText(estimate.status)}'),
              const SizedBox(height: 8),
              Text('생성일: ${_formatDate(estimate.createdAt)}'),
              const SizedBox(height: 8),
              Text('방문일: ${_formatDate(estimate.visitDate)}'),
              const SizedBox(height: 8),
              Text('설명: ${estimate.description}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  void _updateEstimateStatus(Estimate estimate) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('견적 상태 변경'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('현재 상태: ${_getStatusText(estimate.status)}'),
            const SizedBox(height: 16),
            const Text('새로운 상태를 선택하세요:'),
            const SizedBox(height: 8),
            _buildStatusOption(context, '대기', Estimate.STATUS_PENDING, estimate),
            _buildStatusOption(context, '수락', Estimate.STATUS_ACCEPTED, estimate),
            _buildStatusOption(context, '거절', Estimate.STATUS_REJECTED, estimate),
            _buildStatusOption(context, '낙찰', Estimate.STATUS_AWARDED, estimate),
            _buildStatusOption(context, '완료', 'COMPLETED', estimate),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusOption(BuildContext context, String label, String status, Estimate estimate) {
    return ListTile(
      title: Text(label),
      leading: Radio<String>(
        value: status,
        groupValue: estimate.status,
        onChanged: (value) async {
          Navigator.of(context).pop();
          try {
            final estimateProvider = Provider.of<EstimateProvider>(context, listen: false);
            await estimateProvider.updateEstimate(estimate.copyWith(status: value!));
            await _loadEstimates();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('견적 상태가 $label로 변경되었습니다.')),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('상태 변경 중 오류가 발생했습니다: $e')),
              );
            }
          }
        },
      ),
    );
  }

  String _getStatusText(String status) {
    switch (status) {
      case Estimate.STATUS_PENDING:
        return '대기';
      case Estimate.STATUS_ACCEPTED:
        return '수락';
      case Estimate.STATUS_REJECTED:
        return '거절';
      case Estimate.STATUS_AWARDED:
        return '낙찰';
      case 'COMPLETED':
        return '완료';
      default:
        return status;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
  }
} 