import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/estimate.dart';
import '../../services/auth_service.dart';
import '../../services/estimate_service.dart';
import '../../services/marketplace_service.dart';
import '../../widgets/business/business_app_shell.dart';
import '../../widgets/business/business_empty_state.dart';
import '../../widgets/business/business_filter_chip.dart';
import '../../widgets/business/business_section_header.dart';
import '../../widgets/business/business_status_chip.dart';
import '../../widgets/business/business_tokens.dart';
import 'order_marketplace_screen.dart';

class BusinessMyEstimatesScreen extends StatefulWidget {
  final String? initialStatus;
  final bool embedded;
  const BusinessMyEstimatesScreen({
    super.key,
    this.initialStatus,
    this.embedded = false,
  });

  @override
  State<BusinessMyEstimatesScreen> createState() =>
      _BusinessMyEstimatesScreenState();
}

class _BusinessMyEstimatesScreenState extends State<BusinessMyEstimatesScreen> {
  final MarketplaceService _market = MarketplaceService();
  String _selectedStatus = 'all';
  String _selectedOrigin = 'all';
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
      final estimateService = Provider.of<EstimateService>(context, listen: false);
      List<Estimate> estimates = const [];
      try {
        estimates = await estimateService.getEstimates(businessId: userId);
      } catch (e) {
        debugPrint('⚠️ [BusinessMyEstimates] estimates 병합 건너뜀: $e');
      }
      final webOrderIds = <String>{};
      for (final bid in bids) {
        final listing = bid['listing'];
        if (listing is Map) {
          final webId = listing['web_order_id']?.toString() ?? '';
          if (webId.isNotEmpty) webOrderIds.add(webId);
        }
      }
      final merged = [
        ...bids,
        ...estimates
            .where((e) => e.orderId.isNotEmpty && !webOrderIds.contains(e.orderId))
            .map(_bidFromEstimate),
      ];
      merged.sort((a, b) {
        final aAt = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bAt = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bAt.compareTo(aAt);
      });
      if (!mounted) return;
      setState(() {
        _bids = merged;
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

  Map<String, dynamic> _bidFromEstimate(Estimate estimate) {
    final title = estimate.equipmentType.trim().isNotEmpty
        ? estimate.equipmentType
        : (estimate.customerName.trim().isNotEmpty
            ? '${estimate.customerName} 고객 오더'
            : '소비자 오더');
    return {
      'id': estimate.id,
      'source': 'estimates',
      'origin': 'consumer',
      'status': _mapEstimateStatus(estimate.status),
      'bid_amount': estimate.amount,
      'estimated_days': estimate.estimatedDays,
      'created_at': estimate.createdAt.toIso8601String(),
      'order_id': estimate.orderId,
      'listing': {
        'title': title,
        'region': estimate.customerName,
        'web_order_id': estimate.orderId,
      },
    };
  }

  String _mapEstimateStatus(String status) {
    switch (status) {
      case Estimate.STATUS_AWARDED:
      case Estimate.STATUS_APPROVED:
      case Estimate.STATUS_ACCEPTED:
        return 'selected';
      default:
        return status;
    }
  }

  bool _matchesFilter(Map<String, dynamic> bid) {
    final origin = MarketplaceService.bidOrigin(bid);
    if (_selectedOrigin != 'all' && origin != _selectedOrigin) return false;
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
            listingStatus == 'awaiting_confirmation' ||
            status == 'completed';
      default:
        return status == _selectedStatus;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _bids.where(_matchesFilter).toList();
    final body = Column(
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
                          title: '해당 조건의 입찰이 없습니다',
                          subtitle: '소비자 오더와 사업자 오더에 넣은 입찰이 여기에 함께 표시됩니다.',
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
    );
    if (widget.embedded) return body;
    return BusinessAppShell(
      title: '내 입찰',
      actions: [
        IconButton(
          onPressed: _loadBids,
          tooltip: '새로고침',
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      body: body,
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
            subtitle: '소비자 오더와 사업자 오더 입찰을 한곳에서 확인하세요.',
          ),
          const SizedBox(height: BusinessTokens.space12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                BusinessFilterChip(
                  label: '모든 견적',
                  selected: _selectedOrigin == 'all',
                  onTap: () => setState(() => _selectedOrigin = 'all'),
                ),
                const SizedBox(width: BusinessTokens.space8),
                BusinessFilterChip(
                  label: '소비자 견적',
                  selected: _selectedOrigin == 'consumer',
                  onTap: () => setState(() => _selectedOrigin = 'consumer'),
                ),
                const SizedBox(width: BusinessTokens.space8),
                BusinessFilterChip(
                  label: '사업자 견적',
                  selected: _selectedOrigin == 'business',
                  onTap: () => setState(() => _selectedOrigin = 'business'),
                ),
              ],
            ),
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
    final origin = MarketplaceService.bidOrigin(bid);
    final fallbackTitle = origin == 'consumer' ? '소비자 오더' : '사업자 오더';
    final title = (listing['title'] ?? listing['description'] ?? fallbackTitle)
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: BusinessTokens.space8,
                      runSpacing: BusinessTokens.space8,
                      children: [
                        BusinessStatusChip.forOrderOrigin(origin),
                        BusinessStatusChip.forEstimate(status),
                      ],
                    ),
                  ),
                  if (createdAt != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8, top: 4),
                      child: Text(
                        _formatDateTime(createdAt),
                        style: BusinessTokens.caption,
                      ),
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
                      _nextAction(status, origin),
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

  String _nextAction(String status, String origin) {
    final waiter = origin == 'consumer' ? '고객' : '발주 사업자';
    switch (status) {
      case 'pending':
        return '$waiter의 선택을 기다리고 있습니다.';
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
