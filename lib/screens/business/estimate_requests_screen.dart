import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/order.dart' as app_models;
import '../../services/order_service.dart';
import '../../theme/business_theme.dart';
import '../../widgets/business/business_app_shell.dart';
import '../../widgets/business/business_empty_state.dart';
import '../../widgets/business/business_filter_chip.dart';
import '../../widgets/business/business_lead_card.dart';
import '../../widgets/business/business_primary_button.dart';
import '../create_estimate_screen.dart';

class EstimateRequestsScreen extends StatefulWidget {
  const EstimateRequestsScreen({super.key});

  @override
  State<EstimateRequestsScreen> createState() => _EstimateRequestsScreenState();
}

class _EstimateRequestsScreenState extends State<EstimateRequestsScreen> {
  late OrderService _orderService;
  List<app_models.Order> _requests = [];
  List<app_models.Order> _filteredRequests = [];
  bool _isLoading = true;
  String _selectedCategory = 'all';
  String _selectedRegion = 'all';
  String _selectedUrgency = 'all';
  String _selectedPrice = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRequests();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _orderService = Provider.of<OrderService>(context, listen: false);
  }

  Future<void> _loadRequests() async {
    try {
      setState(() => _isLoading = true);
      final allOrders = await _orderService.getOrders();
      final availableOrders = allOrders.where((order) =>
        order.status == 'pending' && !order.isAwarded
      ).toList();
      availableOrders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      setState(() {
        _requests = availableOrders;
        _filteredRequests = _applyFilters(availableOrders);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('견적 요청 목록을 불러오는 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  String _mapCategory(String? raw) {
    final v = (raw ?? '').trim();
    if (v.contains('누수')) return '누수';
    if (v.contains('배관') || v.contains('보일러') || v.contains('난방')) return '배관';
    if (v.contains('화장실') || v.contains('욕실') || v.contains('변기')) return '화장실';
    return '기타';
  }

  String _regionKey(String address) {
    final parts = address.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? '기타' : parts.first;
  }

  List<app_models.Order> _applyFilters(List<app_models.Order> requests) {
    return requests.where((request) {
      if (_selectedCategory != 'all' &&
          _mapCategory(request.equipmentType) != _selectedCategory) {
        return false;
      }
      if (_selectedRegion != 'all' && _regionKey(request.address) != _selectedRegion) {
        return false;
      }
      final soon = BusinessTheme.isVisitSoon(request.visitDate);
      if (_selectedUrgency == 'urgent' && !soon) return false;
      if (_selectedUrgency == 'normal' && soon) return false;
      final price = request.estimatedPrice;
      if (_selectedPrice == 'low' && price >= 100000) return false;
      if (_selectedPrice == 'mid' && (price < 100000 || price >= 500000)) return false;
      if (_selectedPrice == 'high' && price < 500000) return false;
      return true;
    }).toList();
  }

  void _refilter() {
    setState(() {
      _filteredRequests = _applyFilters(_requests);
    });
  }

  void _onCategoryChanged(String category) {
    setState(() => _selectedCategory = category);
    _refilter();
  }

  List<String> get _regions {
    final set = <String>{};
    for (final r in _requests) {
      set.add(_regionKey(r.address));
    }
    final list = set.where((e) => e.isNotEmpty).toList()..sort();
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return BusinessAppShell(
      title: '신규 일감',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loadRequests,
          tooltip: '새로고침',
        ),
      ],
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: BusinessTheme.surface,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              '현재 ${_filteredRequests.length}건',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: BusinessTheme.textMuted,
              ),
            ),
          ),
          Container(
            color: BusinessTheme.surface,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      BusinessFilterChip(
                        label: '전체',
                        selected: _selectedCategory == 'all',
                        onTap: () => _onCategoryChanged('all'),
                        count: _requests.length,
                      ),
                      const SizedBox(width: 8),
                      BusinessFilterChip(
                        label: '누수',
                        icon: Icons.water_drop_outlined,
                        selected: _selectedCategory == '누수',
                        onTap: () => _onCategoryChanged('누수'),
                      ),
                      const SizedBox(width: 8),
                      BusinessFilterChip(
                        label: '배관',
                        icon: Icons.plumbing_outlined,
                        selected: _selectedCategory == '배관',
                        onTap: () => _onCategoryChanged('배관'),
                      ),
                      const SizedBox(width: 8),
                      BusinessFilterChip(
                        label: '화장실',
                        icon: Icons.bathroom_outlined,
                        selected: _selectedCategory == '화장실',
                        onTap: () => _onCategoryChanged('화장실'),
                      ),
                      const SizedBox(width: 8),
                      BusinessFilterChip(
                        label: '기타',
                        selected: _selectedCategory == '기타',
                        onTap: () => _onCategoryChanged('기타'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      BusinessFilterChip(
                        label: '지역 전체',
                        selected: _selectedRegion == 'all',
                        onTap: () {
                          setState(() => _selectedRegion = 'all');
                          _refilter();
                        },
                      ),
                      ..._regions.map((region) => Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: BusinessFilterChip(
                              label: region,
                              selected: _selectedRegion == region,
                              onTap: () {
                                setState(() => _selectedRegion = region);
                                _refilter();
                              },
                            ),
                          )),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      BusinessFilterChip(
                        label: '긴급도 전체',
                        selected: _selectedUrgency == 'all',
                        onTap: () {
                          setState(() => _selectedUrgency = 'all');
                          _refilter();
                        },
                      ),
                      const SizedBox(width: 8),
                      BusinessFilterChip(
                        label: '방문 임박',
                        selected: _selectedUrgency == 'urgent',
                        onTap: () {
                          setState(() => _selectedUrgency = 'urgent');
                          _refilter();
                        },
                      ),
                      const SizedBox(width: 8),
                      BusinessFilterChip(
                        label: '일반',
                        selected: _selectedUrgency == 'normal',
                        onTap: () {
                          setState(() => _selectedUrgency = 'normal');
                          _refilter();
                        },
                      ),
                      const SizedBox(width: 8),
                      BusinessFilterChip(
                        label: '~10만',
                        selected: _selectedPrice == 'low',
                        onTap: () {
                          setState(() => _selectedPrice = _selectedPrice == 'low' ? 'all' : 'low');
                          _refilter();
                        },
                      ),
                      const SizedBox(width: 8),
                      BusinessFilterChip(
                        label: '10~50만',
                        selected: _selectedPrice == 'mid',
                        onTap: () {
                          setState(() => _selectedPrice = _selectedPrice == 'mid' ? 'all' : 'mid');
                          _refilter();
                        },
                      ),
                      const SizedBox(width: 8),
                      BusinessFilterChip(
                        label: '50만+',
                        selected: _selectedPrice == 'high',
                        onTap: () {
                          setState(() => _selectedPrice = _selectedPrice == 'high' ? 'all' : 'high');
                          _refilter();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const BusinessListSkeleton()
                : _filteredRequests.isEmpty
                    ? BusinessEmptyState(
                        icon: Icons.inbox_outlined,
                        title: _selectedCategory == 'all'
                            ? '새로운 견적 요청이 없습니다'
                            : '$_selectedCategory 견적 요청이 없습니다',
                        subtitle: '필터를 바꾸거나 새로고침해 보세요.',
                        actionLabel: '새로고침',
                        onAction: _loadRequests,
                      )
                    : RefreshIndicator(
                        onRefresh: _loadRequests,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredRequests.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final request = _filteredRequests[index];
                            return BusinessLeadCard(
                              title: request.title,
                              category: request.equipmentType,
                              region: BusinessTheme.regionFromAddress(request.address),
                              timeLabel: BusinessTheme.relativeTime(request.createdAt),
                              symptom: request.description,
                              amountLabel: request.estimatedPrice > 0
                                  ? '예상 ${BusinessTheme.formatWon(request.estimatedPrice)}'
                                  : null,
                              hasPhoto: request.images.isNotEmpty,
                              isNew: BusinessTheme.isNewLead(request.createdAt),
                              isUrgent: BusinessTheme.isVisitSoon(request.visitDate),
                              isClosingSoon: BusinessTheme.isVisitSoon(request.visitDate),
                              canBid: true,
                              onTap: () => _showRequestDetail(request),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  void _showRequestDetail(app_models.Order request) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: BusinessTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(context).padding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      request.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: BusinessTheme.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(request.description, style: const TextStyle(color: BusinessTheme.textMuted)),
              const SizedBox(height: 12),
              Text('지역  ${BusinessTheme.regionFromAddress(request.address)}'),
              Text('방문일  ${request.visitDate.toString().split(' ').first}'),
              Text('요청일  ${request.createdAt.toString().split('.').first}'),
              const SizedBox(height: 8),
              const Text('고객 정보는 낙찰 후 공개됩니다.', style: TextStyle(fontSize: 12, color: BusinessTheme.textMuted)),
              const SizedBox(height: 16),
              BusinessPrimaryButton(
                label: '견적 작성',
                icon: Icons.send_rounded,
                onPressed: () {
                  Navigator.pop(context);
                  _goToBidding(request);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _goToBidding(app_models.Order request) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateEstimateScreen(order: request),
      ),
    );
  }
}
