import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/marketplace_service.dart';
import '../../widgets/business/business_app_shell.dart';
import '../../widgets/business/business_empty_state.dart';
import '../../widgets/business/business_filter_chip.dart';
import '../../widgets/business/business_primary_button.dart';
import '../../widgets/business/business_section_header.dart';
import '../../widgets/business/business_status_chip.dart';
import '../../widgets/business/business_tokens.dart';
import 'job_management_screen.dart';
import 'create_job_screen.dart';
import 'order_marketplace_screen.dart';

class BusinessMyEstimatesScreen extends StatefulWidget {
  final String? initialStatus;
  const BusinessMyEstimatesScreen({super.key, this.initialStatus});

  @override
  State<BusinessMyEstimatesScreen> createState() =>
      _BusinessMyEstimatesScreenState();
}

class _BusinessMyEstimatesScreenState extends State<BusinessMyEstimatesScreen> {
  final MarketplaceService _market = MarketplaceService();
  String _selectedStatus = 'all';
  String? _loadError;
  bool _loading = true;
  List<Map<String, dynamic>> _bids = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialStatus != null && widget.initialStatus!.isNotEmpty) {
      _selectedStatus = widget.initialStatus!;
    }
    _loadBids();
  }

  Future<void> _loadBids() async {
    if (mounted) {
      setState(() {
        _loadError = null;
        _loading = true;
      });
    }
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final userId = authService.currentUser?.id;
      if (userId == null) {
        if (mounted) {
          setState(() {
            _loadError = '로그인 정보를 확인할 수 없습니다.';
            _loading = false;
          });
        }
        return;
      }
      final bids = await _market.listMyBids(userId);
      if (!mounted) return;
      setState(() {
        _bids = bids;
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ [BusinessMyEstimates] 입찰 목록 로드 실패: $e');
      if (mounted) {
        setState(() {
          _loadError = '입찰 목록을 불러오지 못했습니다. ($e)';
          _loading = false;
        });
      }
    }
  }

  bool _matchesFilter(Map<String, dynamic> bid) {
    final status = (bid['status'] ?? '').toString();
    final listingStatus =
        (bid['listing'] is Map ? bid['listing']['status'] : null)?.toString();
    switch (_selectedStatus) {
      case 'all':
        return status != 'withdrawn';
      case 'progress':
      case 'awarded':
      case 'accepted':
      case 'approved':
        return status == 'selected';
      case 'completed':
        return listingStatus == 'completed' ||
            listingStatus == 'awaiting_confirmation';
      default:
        return status == _selectedStatus;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _bids.where(_matchesFilter).toList();
    return BusinessAppShell(
      title: '내 입찰',
      actions: [
        IconButton(
          onPressed: _loadBids,
          tooltip: '새로고침',
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: _loadError != null
                ? BusinessEmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: '내 입찰을 불러오지 못했습니다',
                    subtitle: _loadError,
                    actionLabel: '다시 시도',
                    onAction: _loadBids,
                  )
                : _loading
                    ? const BusinessListSkeleton()
                    : filtered.isEmpty
                        ? const BusinessEmptyState(
                            icon: Icons.description_outlined,
                            title: '해당 상태의 입찰이 없습니다',
                            subtitle: '제출한 입찰이 생기면 여기에 표시됩니다.',
                          )
                        : RefreshIndicator(
                            onRefresh: _loadBids,
                            child: ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(
                                BusinessTokens.pagePadding,
                              ),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const SizedBox(
                                height: BusinessTokens.space12,
                              ),
                              itemBuilder: (context, index) =>
                                  _buildBidCard(filtered[index]),
                            ),
                          ),
          ),
        ],
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
                  selected: _selectedStatus == 'pending',
                  onTap: () => setState(() => _selectedStatus = 'pending'),
                ),
                const SizedBox(width: BusinessTokens.space8),
                BusinessFilterChip(
                  label: '채택',
                  selected: _selectedStatus == 'selected' ||
                      _selectedStatus == 'progress',
                  onTap: () => setState(() => _selectedStatus = 'selected'),
                ),
                const SizedBox(width: BusinessTokens.space8),
                BusinessFilterChip(
                  label: '미선정',
                  selected: _selectedStatus == 'rejected',
                  onTap: () => setState(() => _selectedStatus = 'rejected'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBidCard(Map<String, dynamic> bid) {
    final listing =
        bid['listing'] is Map ? Map<String, dynamic>.from(bid['listing']) : {};
    final title = (listing['title'] ?? listing['description'] ?? '협업 일감')
        .toString();
    final region = listing['region']?.toString() ?? '';
    final status = (bid['status'] ?? 'pending').toString();
    final amount = bid['bid_amount'];
    final days = bid['estimated_days'];
    final createdAt = DateTime.tryParse(bid['created_at']?.toString() ?? '');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(BusinessTokens.cardRadius),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const OrderMarketplaceScreen(
                showMyBidsOnly: true,
              ),
            ),
          );
        },
        child: Container(
          decoration: BusinessTokens.card(),
          padding: const EdgeInsets.all(BusinessTokens.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  BusinessStatusChip.forEstimate(status),
                  const Spacer(),
                  if (createdAt != null)
                    Text(
                      _formatDateTime(createdAt),
                      style: BusinessTokens.caption,
                    ),
                ],
              ),
              const SizedBox(height: BusinessTokens.space12),
              Text(title, style: BusinessTokens.sectionTitle),
              if (region.isNotEmpty) ...[
                const SizedBox(height: BusinessTokens.space4),
                Text(region, style: BusinessTokens.caption),
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
                          _formatWon(amount),
                          style: BusinessTokens.title.copyWith(
                            color: BusinessTokens.navy,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (days != null)
                    Text(
                      '예상 $days일',
                      style: BusinessTokens.caption,
                    ),
                ],
              ),
              const SizedBox(height: BusinessTokens.space12),
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
                      _nextAction(status),
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
        ),
      ),
    );
  }

  String _nextAction(String status) {
    switch (status) {
      case 'pending':
        return '발주자의 선택을 기다리고 있습니다.';
      case 'selected':
        return '채택된 입찰입니다.';
      case 'rejected':
        return '이번 입찰은 종료되었습니다.';
      case 'withdrawn':
        return '지원을 취소한 입찰입니다.';
      default:
        return '현재 상태를 확인해주세요.';
    }
  }

  String _formatWon(dynamic amount) {
    final n = amount is num ? amount.toDouble() : double.tryParse('$amount');
    if (n == null || n <= 0) return '협의';
    final formatted = n.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (match) => ',',
        );
    return '$formatted원';
  }

  String _formatDateTime(DateTime date) {
    final local = date.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}.$month.$day';
  }
}
