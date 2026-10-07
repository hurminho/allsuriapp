import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import '../config/feature_flags.dart';
import '../services/ad_service.dart';
import '../models/ad.dart';
import '../models/order.dart' as app_models;
import 'announcement_banner.dart';
import '../theme/business_theme.dart';
import '../screens/business/estimate_requests_screen.dart';
import '../screens/business/order_marketplace_screen.dart';
import '../screens/business/work_hub_screen.dart';
import '../screens/create_estimate_screen.dart';
import '../screens/notification/notification_screen.dart';
import '../screens/business/my_order_management_screen.dart';
import '../screens/business/pending_approval_screen.dart';
import 'business/business_tab_scope.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/marketplace_service.dart';
import '../services/order_service.dart';
import '../services/push_permission_service.dart';
import '../utils/new_order_feed.dart';
import 'business/business_app_bar.dart';
import 'business/business_empty_state.dart';
import 'business/business_primary_button.dart';
import 'business/business_section_header.dart';
import 'business/business_tokens.dart';

/// 프로페셔널 스타일 C - 데이터 중심 대시보드
class ProfessionalDashboard extends StatefulWidget {
  const ProfessionalDashboard({Key? key}) : super(key: key);

  @override
  State<ProfessionalDashboard> createState() => _ProfessionalDashboardState();
}

class _ProfessionalDashboardState extends State<ProfessionalDashboard> {
  final MarketplaceService _market = MarketplaceService();

  late Future<Map<String, dynamic>> _dashboardDataFuture;
  // 광고/알림 Future 캐싱 (build 마다 재요청 방지)
  Future<List<Ad>>? _adBannerFuture;
  Future<int>? _notifCountFuture;

  RealtimeChannel? _marketplaceChannel;
  RealtimeChannel? _ordersChannel;

  @override
  void initState() {
    super.initState();
    _setupRealtimeListeners();

    // 로그인 후 푸시 알림 권한 체크 (딜레이 후 표시)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        final userId = context.read<AuthService>().currentUser?.id ?? '';
        if (userId.isNotEmpty) {
          PushPermissionService.checkAndRequest(context, userId: userId);
        }
      });
    });
  }

  void _setupRealtimeListeners() {
    _marketplaceChannel = Supabase.instance.client
        .channel('public:marketplace_listings')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'marketplace_listings',
          callback: (payload) {
            if (mounted) _refreshData();
          },
        )
        .subscribe();

    _ordersChannel = Supabase.instance.client
        .channel('public:orders')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (payload) {
            if (mounted) _refreshData();
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _marketplaceChannel?.unsubscribe();
    _ordersChannel?.unsubscribe();
    super.dispose();
  }

  bool _didLoad = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoad) return;
    _didLoad = true;
    _refreshData();
  }

  void _refreshData() {
    final userId = context.read<AuthService>().currentUser?.id ?? '';
    setState(() {
      _dashboardDataFuture = _loadDashboardData();
      _adBannerFuture = Future.wait([
        AdService().getAdsByLocation('dashboard_ad_1'),
        AdService().getAdsByLocation('dashboard_ad_2'),
      ]).then((results) => [...results[0], ...results[1]]);
      _notifCountFuture = userId.isEmpty
          ? Future.value(0)
          : NotificationService().getUnreadCount(userId);
    });
  }

  Future<Map<String, dynamic>> _loadDashboardData() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUserId = authService.currentUser?.id;

      if (currentUserId == null) return {};

      // 병렬로 데이터 로드
      final results = await Future.wait([
        _getCompletedJobsCount(currentUserId),
        _getInProgressJobsCount(currentUserId),
        _getMyBidsCount(currentUserId),
        _getMyOrdersCount(currentUserId),
        _getNewOrderFeed(currentUserId),
      ]);

      final newOrderItems = results[4] as List<NewOrderItem>;
      return {
        'completed': results[0],
        'inProgress': results[1],
        'newOrders': newOrderItems.length,
        'myBids': results[2],
        'myOrders': results[3],
        'estimateRequests': newOrderItems.length,
        'newOrderItems': newOrderItems,
      };
    } catch (e) {
      debugPrint('❌ [_loadDashboardData] 에러: $e');
      return {};
    }
  }

  Future<List<NewOrderItem>> _getNewOrderFeed(String userId) async {
    try {
      final orderService = Provider.of<OrderService>(context, listen: false);
      final results = await Future.wait([
        _market.listListings(status: 'all', enrichOwners: false),
        orderService.getOrders(assignedContractorId: userId),
      ]);
      return mergeNewOrderFeed(
        listings: results[0] as List<Map<String, dynamic>>,
        orders: results[1] as List<app_models.Order>,
        contractorId: userId,
      );
    } catch (e) {
      debugPrint('❌ [_getNewOrderFeed] 에러: $e');
      return [];
    }
  }

  void _openNewOrderItem(NewOrderItem item) {
    if (item.listing != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              OrderMarketplaceScreen(initialListing: item.listing),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateEstimateScreen(order: item.order),
      ),
    );
  }

  Future<int> _getCompletedJobsCount(String userId) async {
    try {
      // 실제 완료된 공사 카운트 (매출 페이지와 동일한 로직)
      final response = await Supabase.instance.client
          .from('jobs')
          .select('id')
          .eq('assigned_business_id', userId)
          .inFilter('status', ['completed', 'awaiting_confirmation']).count(
              CountOption.exact);

      print('🔍 [_getCompletedJobsCount] 완료한 공사: ${response.count}개');
      return response.count;
    } catch (e) {
      print('❌ [_getCompletedJobsCount] 에러: $e');
      return 0;
    }
  }

  // ⚡ 성능 개선: count 쿼리 최적화
  Future<int> _getInProgressJobsCount(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('jobs')
          .select('id')
          .eq('assigned_business_id', userId)
          // 가져가기·웹 낙찰 공사는 'assigned' 로 시작합니다. 진행 중에 함께 셉니다.
          .inFilter('status', ['assigned', 'in_progress'])
          .count(CountOption.exact);
      return response.count;
    } catch (e) {
      print('❌ [_getInProgressJobsCount] 에러: $e');
      return 0;
    }
  }

  // ⚡ 성능 개선: 이중 쿼리 제거, 서버에서 직접 count
  Future<int> _getMyBidsCount(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('order_bids')
          .select('listing_id')
          .eq('bidder_id', userId)
          .eq('status', 'pending')
          .count(CountOption.exact);

      return response.count;
    } catch (e) {
      print('❌ [_getMyBidsCount] 에러: $e');
      return 0;
    }
  }

  Future<int> _getMyOrdersCount(String userId) async {
    try {
      return await _market.countListings(
        status: 'all',
        postedBy: userId,
      );
    } catch (_) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, child) {
        final user = authService.currentUser;
        final businessStatus = user?.businessStatus?.toLowerCase() ?? '';
        final isApproved = businessStatus == 'approved';

        if (!isApproved) {
          return const PendingApprovalScreen();
        }

        final businessName = (user?.businessName != null &&
                user!.businessName!.trim().isNotEmpty)
            ? user.businessName!
            : (user?.name ?? "사업자");

        return PopScope(
          canPop: BusinessTabScope.maybeOf(context) == null,
          child: Theme(
            data: BusinessTheme.theme(Theme.of(context)),
            child: Scaffold(
              backgroundColor: BusinessTokens.canvas,
              appBar: _buildAppBar(context, '$businessName 사장님'),
              body: FutureBuilder<Map<String, dynamic>>(
                future: _dashboardDataFuture,
                builder: (context, snapshot) {
                  final loading =
                      snapshot.connectionState == ConnectionState.waiting;
                  final data = snapshot.data ?? {};
                  return Column(
                    children: [
                      const AnnouncementBanner(),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: () async => _refreshData(),
                          child: loading
                              ? const BusinessListSkeleton(itemCount: 4)
                              : ListView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 16, 16, 32),
                                  children: [
                                    _buildSummaryCard(data),
                                    const SizedBox(height: 24),
                                    BusinessSectionHeader(
                                      title: '신규 오더',
                                      actionLabel: '전체 보기',
                                      onAction: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const EstimateRequestsScreen(),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    _buildNewOrderPreview(data),
                                    const SizedBox(height: 24),
                                    const BusinessSectionHeader(
                                      title: '오더 진행 현황',
                                    ),
                                    const SizedBox(height: 12),
                                    _buildWorkQueue(data),
                                    const SizedBox(height: 24),
                                    _buildAdBanner(context),
                                    if (FeatureFlags.adsEnabled)
                                      const SizedBox(height: 24),
                                    BusinessPrimaryButton(
                                      label: '내 입찰 목록',
                                      icon: Icons.description_outlined,
                                      onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const WorkHubScreen(initialTab: 0),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, String title) {
    return BusinessAppBar(
      title: title,
      showBackButton: BusinessTabScope.maybeOf(context) == null,
      actions: [
        FutureBuilder<int>(
          future: _notifCountFuture,
          builder: (context, snapshot) {
            final unread = snapshot.data ?? 0;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  tooltip: '알림',
                  icon: const Icon(
                    Icons.notifications_outlined,
                    color: BusinessTokens.text,
                  ),
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const NotificationScreen()),
                    );
                    if (mounted) _refreshData();
                  },
                ),
                if (unread > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: BusinessTheme.danger,
                        shape: BoxShape.circle,
                      ),
                      constraints:
                          const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        unread > 9 ? '9+' : unread.toString(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildSummaryCard(Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BusinessTokens.hero(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _summaryMetric(
                  '신규 오더',
                  data['estimateRequests'] ?? 0,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const EstimateRequestsScreen(),
                    ),
                  ),
                ),
              ),
              _summaryDivider(),
              Expanded(
                child: _summaryMetric(
                  '입찰 대기',
                  data['myBids'] ?? 0,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const WorkHubScreen(initialTab: 0),
                    ),
                  ),
                ),
              ),
              _summaryDivider(),
              Expanded(
                child: _summaryMetric(
                  '진행 중인 오더',
                  data['inProgress'] ?? 0,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const WorkHubScreen(initialTab: 1),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryMetric(String label, int value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            Text(
              '$value',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryDivider() {
    return Container(
      width: 1,
      height: 45,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Colors.white24,
    );
  }

  Widget _buildNewOrderPreview(Map<String, dynamic> data) {
    final rawItems = data['newOrderItems'];
    final orders = rawItems is List
        ? rawItems.whereType<NewOrderItem>().toList()
        : const <NewOrderItem>[];

    // 컴팩트 카드 높이: 약 72px, 항상 5개 영역 확보
    const double compactCardHeight = 72.0;
    const double cardSpacing = 8.0;
    const int fixedSlotCount = 5;
    const double containerHeight = 
        (compactCardHeight * fixedSlotCount) + (cardSpacing * (fixedSlotCount - 1));

    // 5개를 넘으면 스크롤, 아니면 빈 슬롯으로 5칸 고정
    final bool hasMoreThanSlots = orders.length > fixedSlotCount;
    final int displayCount = hasMoreThanSlots ? orders.length : fixedSlotCount;

    return SizedBox(
      height: containerHeight,
      child: ListView.separated(
        physics: hasMoreThanSlots
            ? const AlwaysScrollableScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        itemCount: displayCount,
        separatorBuilder: (_, __) => const SizedBox(height: cardSpacing),
        itemBuilder: (context, index) {
          // 오더가 있으면 카드 표시, 없으면 빈 슬롯 표시
          if (index < orders.length) {
            final item = orders[index];
            final order = item.order;
            return _CompactOrderCard(
              title: order.title,
              category: order.equipmentType,
              region: order.address.isNotEmpty
                  ? BusinessTheme.regionFromAddress(order.address)
                  : order.address,
              timeLabel: BusinessTheme.relativeTime(order.createdAt),
              isNew: BusinessTheme.isNewLead(order.createdAt),
              isUrgent: order.hasVisitDate &&
                  BusinessTheme.isVisitSoon(order.visitDate),
              isDirectRequest: order.routingType == 'personal_link',
              onTap: () => _openNewOrderItem(item),
            );
          } else {
            // 빈 슬롯 - 오더를 기다리는 상태
            return _EmptyOrderSlot();
          }
        },
      ),
    );
  }

  Widget _buildWorkQueue(Map<String, dynamic> data) {
    return Container(
      decoration: BusinessTokens.card(),
      child: Column(
        children: [
          _workQueueItem(
            icon: Icons.handyman_outlined,
            label: '오더 관리',
            value: '${data['inProgress'] ?? 0}건 진행',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const WorkHubScreen(initialTab: 1),
              ),
            ),
          ),
          const Divider(height: 1, color: BusinessTokens.border),
          _workQueueItem(
            icon: Icons.hub_outlined,
            label: '내가 낸 오더',
            value: '${data['myOrders'] ?? 0}건',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const MyOrderManagementScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _workQueueItem({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      minTileHeight: 62,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: BusinessTokens.blueLight,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, size: 20, color: BusinessTokens.blue),
      ),
      title: Text(
        label,
        style: const TextStyle(
          color: BusinessTokens.text,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: BusinessTokens.caption),
          const SizedBox(width: 4),
          const Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: BusinessTokens.mutedText,
          ),
        ],
      ),
    );
  }

  Widget _buildAdBanner(BuildContext context) {
    // 광고를 끈 동안에는 회색 placeholder 자리도 남기지 않는다.
    if (!FeatureFlags.adsEnabled) return const SizedBox.shrink();
    return FutureBuilder<List<Ad>>(
      future: _adBannerFuture,
      builder: (context, snapshot) {
        // 광고 데이터 로드
        final ads = snapshot.data ?? [];

        // 광고가 없으면 빈 자리(placeholder)만 표시 — 연락처 노출 금지
        if (ads.isEmpty) {
          return Container(
            height: 80,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
          );
        }

        return SizedBox(
          height: 80,
          child: _DashboardAdCarousel(ads: ads),
        );
      },
    );
  }
}

class _DashboardAdCarousel extends StatefulWidget {
  final List<Ad> ads;
  const _DashboardAdCarousel({Key? key, required this.ads}) : super(key: key);

  @override
  State<_DashboardAdCarousel> createState() => _DashboardAdCarouselState();
}

class _DashboardAdCarouselState extends State<_DashboardAdCarousel> {
  final PageController _controller = PageController();
  int _current = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.ads.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 3), (Timer timer) {
        if (_current < widget.ads.length - 1) {
          _current++;
        } else {
          _current = 0;
        }

        if (_controller.hasClients) {
          _controller.animateToPage(
            _current,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeIn,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _handleAdTap(Ad ad) {
    if (ad.linkUrl != null && ad.linkUrl!.isNotEmpty) {
      _launchUrl(ad.linkUrl!);
    }
  }

  Future<void> _launchUrl(String urlString) async {
    try {
      final Uri url = Uri.parse(urlString);
      if (!await url_launcher.launchUrl(url,
          mode: url_launcher.LaunchMode.externalApplication)) {
        throw Exception('Could not launch $url');
      }
    } catch (e) {
      print('❌ 링크 열기 실패: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('링크를 열 수 없습니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _controller,
            onPageChanged: (index) {
              setState(() {
                _current = index;
              });
            },
            itemCount: widget.ads.length,
            itemBuilder: (context, index) {
              final ad = widget.ads[index];
              return GestureDetector(
                onTap: () => _handleAdTap(ad),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: ad.imageUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CachedNetworkImage(
                            imageUrl: ad.imageUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            memCacheHeight: 240,
                            errorWidget: (_, __, ___) => Center(
                              child: Text(
                                ad.title ?? '광고 ${index + 1}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            ad.title ?? '광고 ${index + 1}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                ),
              );
            },
          ),
        ),
        if (widget.ads.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: widget.ads.asMap().entries.map((entry) {
              return Container(
                width: 6.0,
                height: 6.0,
                margin: const EdgeInsets.symmetric(horizontal: 2.0),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _current == entry.key
                      ? const Color(0xFF0B2545)
                      : Colors.grey.withOpacity(0.4),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}

/// 신규 오더용 컴팩트 카드 - 높이 축소, 입찰 가능/견적 작성 우측 배치
class _CompactOrderCard extends StatelessWidget {
  final String title;
  final String? category;
  final String? region;
  final String? timeLabel;
  final bool isNew;
  final bool isUrgent;
  // 개인 링크로 나에게 직접 온 요청. 경쟁 입찰이 아니므로 '입찰 가능' 대신 '직접 요청'으로 표시합니다.
  final bool isDirectRequest;
  final VoidCallback? onTap;

  const _CompactOrderCard({
    required this.title,
    this.category,
    this.region,
    this.timeLabel,
    this.isNew = false,
    this.isUrgent = false,
    this.isDirectRequest = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: BusinessTokens.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // 좌측: 제목 및 메타 정보
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        if (category != null && category!.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: BusinessTokens.blueLight,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              category!,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: BusinessTokens.blue,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (isNew)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: BusinessTokens.blue,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '신규',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        if (isUrgent) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: BusinessTokens.danger,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '방문 임박',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: BusinessTokens.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (region != null) ...[
                          Icon(Icons.place_outlined,
                              size: 12, color: BusinessTokens.mutedText),
                          const SizedBox(width: 2),
                          Text(
                            region!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: BusinessTokens.mutedText,
                            ),
                          ),
                        ],
                        if (region != null && timeLabel != null)
                          const SizedBox(width: 8),
                        if (timeLabel != null) ...[
                          Icon(Icons.schedule_outlined,
                              size: 12, color: BusinessTokens.mutedText),
                          const SizedBox(width: 2),
                          Text(
                            timeLabel!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: BusinessTokens.mutedText,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // 우측: 입찰 가능(또는 직접 요청) + 견적 작성
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle_outline_rounded,
                        size: 14,
                        color: BusinessTokens.success,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        isDirectRequest ? '직접 요청' : '입찰 가능',
                        style: const TextStyle(
                          color: BusinessTokens.success,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isDirectRequest ? '견적 보내기' : '견적 작성',
                        style: const TextStyle(
                          color: BusinessTokens.blue,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: BusinessTokens.blue,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 빈 오더 슬롯 - 오더가 없는 자리 표시
class _EmptyOrderSlot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: BusinessTokens.canvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: BusinessTokens.border,
          style: BorderStyle.solid,
        ),
      ),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.hourglass_empty_rounded,
              size: 18,
              color: BusinessTokens.mutedText.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 8),
            Text(
              '오더를 기다리고 있어요..',
              style: TextStyle(
                fontSize: 13,
                color: BusinessTokens.mutedText.withValues(alpha: 0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
