import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import '../services/ad_service.dart';
import '../models/ad.dart';
import 'announcement_banner.dart';
import '../theme/business_theme.dart';
import 'business/business_metric_card.dart';
import 'business/business_primary_button.dart';
import '../screens/business/estimate_requests_screen.dart';
import '../screens/business/my_estimates_screen.dart';
import '../screens/chat/chat_list_page.dart';
import '../screens/notification/notification_screen.dart';
import '../screens/business/job_management_screen.dart';
import '../screens/business/order_marketplace_screen.dart';
import '../screens/business/my_order_management_screen.dart';
import '../screens/business/pending_approval_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/marketplace_service.dart';
import '../services/order_service.dart';
import '../services/push_permission_service.dart';
import '../widgets/bottom_navigation.dart';
import '../screens/community/community_board_screen.dart';

/// 프로페셔널 스타일 C - 데이터 중심 대시보드
class ProfessionalDashboard extends StatefulWidget {
  const ProfessionalDashboard({Key? key}) : super(key: key);

  @override
  State<ProfessionalDashboard> createState() => _ProfessionalDashboardState();
}

class _ProfessionalDashboardState extends State<ProfessionalDashboard> {
  int _currentIndex = 0;
  final MarketplaceService _market = MarketplaceService();
  
  late Future<Map<String, int>> _dashboardDataFuture;
  // 광고/알림 Future 캐싱 (build 마다 재요청 방지)
  Future<List<Ad>>? _adBannerFuture;
  Future<int>? _notifCountFuture;
  
  RealtimeChannel? _marketplaceChannel;
  RealtimeChannel? _ordersChannel;

  @override
  void initState() {
    super.initState();
    _setupRealtimeListeners();
    _refreshData();

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
      _notifCountFuture =
          userId.isEmpty ? Future.value(0) : NotificationService().getUnreadCount(userId);
    });
  }

  Future<Map<String, int>> _loadDashboardData() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUserId = authService.currentUser?.id;

      if (currentUserId == null) return {};

      // 병렬로 데이터 로드
      final results = await Future.wait([
        _getCompletedJobsCount(currentUserId),
        _getInProgressJobsCount(currentUserId),
        _getNewOrdersCount(currentUserId),
        _getMyBidsCount(currentUserId),
        _getMyOrdersCount(currentUserId),
        _getEstimateRequestsCount(),
      ]);

      return {
        'completed': results[0],
        'inProgress': results[1],
        'newOrders': results[2],
        'myBids': results[3],
        'myOrders': results[4],
        'estimateRequests': results[5],
      };
    } catch (e) {
      debugPrint('❌ [_loadDashboardData] 에러: $e');
      return {};
    }
  }

  Future<int> _getEstimateRequestsCount() async {
    try {
      final orderService = Provider.of<OrderService>(context, listen: false);
      final all = await orderService.getOrders();
      return all.where((o) => o.status == 'pending' && !o.isAwarded).length;
    } catch (_) {
      return 0;
    }
  }

  Future<int> _getCompletedJobsCount(String userId) async {
    try {
      // 실제 완료된 공사 카운트 (매출 페이지와 동일한 로직)
      final response = await Supabase.instance.client
          .from('jobs')
          .select('id')
          .eq('assigned_business_id', userId)
          .inFilter('status', ['completed', 'awaiting_confirmation'])
          .count(CountOption.exact);
      
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
          .eq('status', 'in_progress')
          .count(CountOption.exact);
      return response.count;
    } catch (e) {
      print('❌ [_getInProgressJobsCount] 에러: $e');
      return 0;
    }
  }

  // ⚡ 성능 개선: 서버사이드 필터링 및 count 쿼리 최적화
  Future<int> _getNewOrdersCount(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('marketplace_listings')
          .select('id')
          .inFilter('status', ['open', 'created'])
          .neq('posted_by', userId)
          .count(CountOption.exact);
      
      return response.count;
    } catch (e) {
      print('❌ [_getNewOrdersCount] 에러: $e');
      return 0;
    }
  }

  // ⚡ 성능 개선: 이중 쿼리 제거, 서버에서 직접 count
  Future<int> _getMyBidsCount(String userId) async {
    try {
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('🔍 [_getMyBidsCount] 입찰 대기 중 카운트 시작');
      print('   userId: $userId');
      print('   현재 시각: ${DateTime.now()}');
      
      // 디버그: 모든 입찰 먼저 확인 (더 상세한 정보)
      final allBids = await Supabase.instance.client
          .from('order_bids')
          .select('id, listing_id, bidder_id, status, created_at')
          .eq('bidder_id', userId)
          .order('created_at', ascending: false);
      
      print('   전체 입찰: ${allBids.length}개');
      if (allBids.isEmpty) {
        print('   ⚠️ 이 사용자의 입찰이 order_bids 테이블에 없습니다!');
      } else {
        for (var bid in allBids) {
          print('      입찰 ID: ${bid['id']}');
          print('         listing_id: ${bid['listing_id']}');
          print('         status: ${bid['status']}');
          print('         created_at: ${bid['created_at']}');
        }
      }
      
      // pending 상태만 카운트
      final response = await Supabase.instance.client
          .from('order_bids')
          .select('listing_id')
          .eq('bidder_id', userId)
          .eq('status', 'pending')
          .count(CountOption.exact);
      
      print('   ✅ pending 상태 입찰: ${response.count}개');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
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
        
        final businessName = (user?.businessName != null && user!.businessName!.trim().isNotEmpty)
            ? user.businessName!
            : (user?.name ?? "사업자");
        
        return WillPopScope(
          onWillPop: () async => false,
          child: Scaffold(
            backgroundColor: BusinessTheme.background,
            appBar: _buildAppBar(context, user),
            body: FutureBuilder<Map<String, int>>(
              future: _dashboardDataFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = snapshot.data ?? {};
                return Column(
                  children: [
                    const AnnouncementBanner(),
                    Expanded(
                      child: RefreshIndicator(
                  onRefresh: () async => _refreshData(),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '$businessName 님',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: BusinessTheme.navy,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '오늘 처리할 일감을 한눈에 확인하세요',
                          style: TextStyle(color: BusinessTheme.textMuted),
                        ),
                        const SizedBox(height: 16),
                        _buildKPICards(data),
                        const SizedBox(height: 16),
                        BusinessPrimaryButton(
                          label: '새 일감 보기',
                          icon: Icons.arrow_forward,
                          onPressed: () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const EstimateRequestsScreen()));
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildMainMenu(context, data),
                        const SizedBox(height: 24),
                        _buildAdBanner(context),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                      ),
                    ),
                  ],
                );
              },
            ),
            bottomNavigationBar: BottomNavigation(
              currentIndex: _currentIndex,
              onTap: (index) {
                setState(() => _currentIndex = index);
              },
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, dynamic user) {
    return AppBar(
      title: const Text('오늘의 업무'),
      actions: [
        FutureBuilder<int>(
          future: _notifCountFuture,
          builder: (context, snapshot) {
            final unread = snapshot.data ?? 0;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NotificationScreen()),
                    );
                    if (mounted) {
                      setState(() {
                        _dashboardDataFuture = _loadDashboardData();
                      });
                    }
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
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        unread > 9 ? '9+' : unread.toString(),
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
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

  Widget _buildKPICards(Map<String, int> data) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: BusinessMetricCard(
                label: '신규 견적 요청',
                value: '${data['estimateRequests'] ?? 0}',
                icon: Icons.inbox_outlined,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EstimateRequestsScreen())),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: BusinessMetricCard(
                label: '입찰 대기',
                value: '${data['myBids'] ?? 0}',
                icon: Icons.hourglass_empty,
                accent: BusinessTheme.warning,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BusinessMyEstimatesScreen(initialStatus: 'pending'))),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        BusinessMetricCard(
          label: '수주 진행 작업',
          value: '${data['inProgress'] ?? 0}',
          icon: Icons.handyman_outlined,
          accent: BusinessTheme.success,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const JobManagementScreen())),
        ),
      ],
    );
  }

  Widget _buildMainMenu(BuildContext context, Map<String, int> data) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ActionChip(
          avatar: const Icon(Icons.shopping_bag_outlined, size: 16),
          label: Text('오더 ${(data['newOrders'] ?? 0)}'),
          onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const OrderMarketplaceScreen(showSuccessMessage: false)));
            if (mounted) _refreshData();
          },
        ),
        ActionChip(
          avatar: const Icon(Icons.description_outlined, size: 16),
          label: const Text('내 견적'),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BusinessMyEstimatesScreen())),
        ),
        ActionChip(
          avatar: const Icon(Icons.work_outline, size: 16),
          label: const Text('수주 관리'),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const JobManagementScreen())),
        ),
        ActionChip(
          avatar: const Icon(Icons.folder_open_outlined, size: 16),
          label: const Text('내 오더'),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyOrderManagementScreen())),
        ),
        ActionChip(
          avatar: const Icon(Icons.chat_bubble_outline, size: 16),
          label: const Text('채팅'),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatListPage())),
        ),
        ActionChip(
          avatar: const Icon(Icons.person_outline, size: 16),
          label: const Text('프로필'),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
        ),
        ActionChip(
          avatar: const Icon(Icons.groups_outlined, size: 16),
          label: const Text('커뮤니티'),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CommunityBoardScreen())),
        ),
      ],
    );
  }

  Widget _buildAdBanner(BuildContext context) {
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
      if (!await url_launcher.launchUrl(url, mode: url_launcher.LaunchMode.externalApplication)) {
        throw Exception('Could not launch $url');
      }
    } catch (e) {
      print('❌ 링크 열기 실패: $e');
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


