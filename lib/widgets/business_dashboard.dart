import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import '../services/ad_service.dart';
import '../models/ad.dart';
import 'announcement_banner.dart';
import '../theme/business_theme.dart';
import 'business/business_metric_card.dart';
import 'business/business_lead_card.dart';
import 'business/business_primary_button.dart';
import 'business/business_empty_state.dart';
import '../screens/business/estimate_requests_screen.dart';
import '../screens/business/my_estimates_screen.dart';
import '../screens/business/job_management_screen.dart';
import '../screens/chat/chat_list_page.dart';
import '../screens/business/business_profile_screen.dart';
import '../screens/notification/notification_screen.dart';
import '../screens/business/order_marketplace_screen.dart';
import '../screens/business/my_order_management_screen.dart';
import '../screens/business/pending_approval_screen.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../widgets/bottom_navigation.dart';
import 'package:lottie/lottie.dart';
import 'package:allsuriapp/services/api_service.dart';
import 'package:allsuriapp/services/marketplace_service.dart';
import '../services/order_service.dart';
import '../services/push_permission_service.dart';
import '../screens/community/community_board_screen.dart';

class BusinessDashboard extends StatefulWidget {
  const BusinessDashboard({Key? key}) : super(key: key);

  @override
  State<BusinessDashboard> createState() => _BusinessDashboardState();
}

class _BusinessDashboardState extends State<BusinessDashboard> with TickerProviderStateMixin {
  int _currentIndex = 0;
  final MarketplaceService _market = MarketplaceService();
  late Future<int> _callOpenCountFuture;
  late Future<int> _estimateRequestsCountFuture;
  late Future<int> _completedJobsCountFuture;
  late Future<int> _myOrdersCountFuture;
  late Future<int> _inProgressJobsCountFuture;
  late Future<int> _myBidsCountFuture;
  Future<List<dynamic>> _priorityOrdersFuture = Future.value([]);
  // 광고/알림 Future도 캐싱해 build 마다 재요청되지 않게 한다.
  Future<List<Ad>>? _adBannerFuture;
  Future<int>? _notifCountFuture;
  
  RealtimeChannel? _marketplaceChannel;
  RealtimeChannel? _ordersChannel;
  
  // 웨이브 애니메이션용
  late AnimationController _waveController;
  late Animation<double> _waveAnimation;

  @override
  void initState() {
    super.initState();
    _setupRealtimeListeners();
    
    // 웨이브 애니메이션 초기화
    _waveController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
    _waveAnimation = Tween<double>(begin: 0, end: 1).animate(_waveController);

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
            if (mounted) _refreshCounts();
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
            if (mounted) _refreshCounts();
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _marketplaceChannel?.unsubscribe();
    _ordersChannel?.unsubscribe();
    _waveController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshCounts();
  }

  void _refreshCounts() {
    final userId = context.read<AuthService>().currentUser?.id ?? '';
    setState(() {
      _callOpenCountFuture = _getCallOpenCount();
      _estimateRequestsCountFuture = _getEstimateRequestsCount();
      _completedJobsCountFuture = _getMyCompletedJobsCount();
      _myOrdersCountFuture = _getMyOrdersCount();
      _inProgressJobsCountFuture = _getInProgressJobsCount();
      _myBidsCountFuture = _getMyBidsCount();
      _priorityOrdersFuture = _getPriorityOrders();
      _adBannerFuture = Future.wait([
        AdService().getAdsByLocation('dashboard_ad_1'),
        AdService().getAdsByLocation('dashboard_ad_2'),
      ]).then((results) => [...results[0], ...results[1]]);
      _notifCountFuture =
          userId.isEmpty ? Future.value(0) : NotificationService().getUnreadCount(userId);
    });
  }

  Future<List<dynamic>> _getPriorityOrders() async {
    try {
      final orderService = Provider.of<OrderService>(context, listen: false);
      final all = await orderService.getOrders();
      final available = all.where((o) => o.status == 'pending' && !o.isAwarded).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return available.take(3).toList();
    } catch (_) {
      return [];
    }
  }

  Future<int> _getInProgressJobsCount() async {
    try {
      final currentUserId = Provider.of<AuthService>(context, listen: false).currentUser?.id;
      if (currentUserId == null) return 0;
      final count = await Supabase.instance.client
          .from('jobs')
          .count(CountOption.exact)
          .eq('assigned_business_id', currentUserId)
          .inFilter('status', ['assigned', 'in_progress', 'awaiting_confirmation']);
      return count;
    } catch (_) {
      return 0;
    }
  }

  Future<int> _getCallOpenCount() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUserId = authService.currentUser?.id;
      
      final count = await _market.countListings(
        status: 'all',
        excludePostedBy: currentUserId,
      );
      return count;
    } catch (e) {
      print('❌ [_getCallOpenCount] 에러: $e');
      return 0;
    }
  }

  Future<int> _getEstimateRequestsCount() async {
    try {
      final orderService = Provider.of<OrderService>(context, listen: false);
      final all = await orderService.getOrders();
      final available = all.where((o) => o.status == 'pending' && !o.isAwarded).length;
      return available;
    } catch (e) {
      print('❌ [_getEstimateRequestsCount] 에러: $e');
      return 0;
    }
  }

  Future<int> _getMyCompletedJobsCount() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUserId = authService.currentUser?.id;
      
      if (currentUserId == null) return 0;
      
      final user = await Supabase.instance.client
          .from('users')
          .select('jobs_accepted_count')
          .eq('id', currentUserId)
          .single();
          
      final count = user['jobs_accepted_count'] as int? ?? 0;
      return count;
    } catch (e) {
      try {
        final authService = Provider.of<AuthService>(context, listen: false);
        final currentUserId = authService.currentUser?.id;
        if (currentUserId == null) return 0;
        
        final count = await Supabase.instance.client
            .from('jobs')
            .count(CountOption.exact)
            .eq('assigned_business_id', currentUserId)
            .eq('status', 'completed');
        return count;
      } catch (_) {
        return 0;
      }
    }
  }

  Future<int> _getMyOrdersCount() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUserId = authService.currentUser?.id;
      
      if (currentUserId == null) return 0;
      
      final count = await _market.countListings(
        status: 'all',
        postedBy: currentUserId,
      );
      return count;
    } catch (e) {
      print('❌ [_getMyOrdersCount] 에러: $e');
      return 0;
    }
  }

  Future<int> _getMyBidsCount() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUserId = authService.currentUser?.id;
      
      if (currentUserId == null) return 0;
      
      final api = ApiService();
      final response = await api.get(
        '/market/bids?bidderId=$currentUserId&statuses=pending,selected,awaiting_confirmation',
      );
      
      if (response['success'] == true) {
        final bids = List<Map<String, dynamic>>.from(response['data'] ?? []);
        
        final uniqueListingIds = bids
            .map((b) => b['listing_id']?.toString())
            .where((id) => id != null && id.isNotEmpty)
            .toSet();
            
        if (uniqueListingIds.isNotEmpty) {
          final listings = await Supabase.instance.client
              .from('marketplace_listings')
              .select('id, status')
              .inFilter('id', uniqueListingIds.toList());
              
          final activeListings = listings.where((l) {
            final status = l['status']?.toString();
            return status == 'open' || status == 'created';
          }).length;
          
          return activeListings;
        }
            
        return 0;
      } else {
        return await _getMyBidsCountFallback(currentUserId);
      }
    } catch (e) {
      return 0;
    }
  }

  Future<int> _getMyBidsCountFallback(String currentUserId) async {
    try {
      final bids = await Supabase.instance.client
          .from('order_bids')
          .select('listing_id, status')
          .eq('bidder_id', currentUserId);
          
      final uniqueIds = <String>{};
      for (final bid in bids) {
        final status = bid['status']?.toString() ?? '';
        if (status == 'pending') {
          final listingId = bid['listing_id']?.toString();
          if (listingId != null) uniqueIds.add(listingId);
        }
      }
      return uniqueIds.length;
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
          onWillPop: () async {
            // 뒤로가기 방지 - 대시보드가 홈이므로
            return false;
          },
          child: Theme(
            data: BusinessTheme.theme(Theme.of(context)),
            child: Scaffold(
          backgroundColor: BusinessTheme.background,
          appBar: AppBar(
            title: const Text('오늘의 업무'),
            centerTitle: true,
            actions: [
              FutureBuilder<int>(
                future: _notifCountFuture,
                builder: (context, snapshot) {
                  final unread = snapshot.data ?? 0;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.notifications),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const NotificationScreen()),
                          );
                        },
                        tooltip: '알림',
                      ),
                      if (unread > 0)
                        Positioned(
                          right: 10,
                          top: 10,
                          child: Row(
                            children: [
                              SizedBox(
                                width: 26,
                                height: 26,
                                child: Lottie.asset(
                                  'assets/lottie/notification_bell.json',
                                  repeat: false,
                                  fit: BoxFit.contain,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                                child: Text(
                                  unread.toString(),
                                  style: const TextStyle(color: Colors.white, fontSize: 6, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
          body: Column(
            children: [
              // 관리자 공지 배너 (앱 업데이트 없이 즉시 반영)
              const AnnouncementBanner(),
              Expanded(
                child: SingleChildScrollView(
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
                FutureBuilder<List<int>>(
                  future: Future.wait([
                    _estimateRequestsCountFuture,
                    _myBidsCountFuture,
                    _inProgressJobsCountFuture,
                  ]),
                  builder: (context, snapshot) {
                    final newRequests = snapshot.data?[0] ?? 0;
                    final pendingBids = snapshot.data?[1] ?? 0;
                    final openOrders = snapshot.data?[2] ?? 0;
                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: BusinessMetricCard(
                                label: '신규 견적 요청',
                                value: '$newRequests',
                                icon: Icons.inbox_outlined,
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EstimateRequestsScreen())),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: BusinessMetricCard(
                                label: '입찰 대기',
                                value: '$pendingBids',
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
                          value: '$openOrders',
                          icon: Icons.handyman_outlined,
                          accent: BusinessTheme.success,
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const JobManagementScreen())),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                FutureBuilder<int>(
                  future: _notifCountFuture,
                  builder: (context, snapshot) {
                    final unread = snapshot.data ?? 0;
                    if (unread <= 0) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(14),
                      decoration: BusinessTheme.cardDecoration(),
                      child: Row(
                        children: [
                          const Icon(Icons.notifications_active_outlined, color: BusinessTheme.warning),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '읽지 않은 알림 $unread건',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationScreen())),
                            child: const Text('확인'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const Text('우선 대응 일감', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 8),
                FutureBuilder<List<dynamic>>(
                  future: _priorityOrdersFuture,
                  builder: (context, snapshot) {
                    final leads = snapshot.data ?? [];
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      );
                    }
                    if (leads.isEmpty) {
                      return const BusinessEmptyState(
                        icon: Icons.task_alt,
                        title: '지금 바로 볼 신규 일감이 없습니다',
                      );
                    }
                    return Column(
                      children: leads.map((lead) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: BusinessLeadCard(
                            title: lead.title,
                            category: lead.equipmentType,
                            region: BusinessTheme.regionFromAddress(lead.address),
                            timeLabel: BusinessTheme.relativeTime(lead.createdAt),
                            symptom: lead.description,
                            isNew: BusinessTheme.isNewLead(lead.createdAt),
                            isUrgent: BusinessTheme.isVisitSoon(lead.visitDate),
                            canBid: true,
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EstimateRequestsScreen())),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 8),
                BusinessPrimaryButton(
                  label: '새 일감 보기',
                  icon: Icons.arrow_forward,
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const EstimateRequestsScreen()));
                  },
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
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
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BusinessProfileScreen())),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.groups_outlined, size: 16),
                      label: const Text('커뮤니티'),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CommunityBoardScreen())),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildAdBanner(context),
                const SizedBox(height: 20),
              ],
            ),
          ),
              ),
            ],
          ),
          bottomNavigationBar: BottomNavigation(
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
          ),
        )));
      },
    );
  }

  Widget _buildCleanMenuCard(
    BuildContext context,
    String title,
    IconData icon,
    Color backgroundColor,
    Color iconColor,
    VoidCallback? onTap, {
    Future<int>? badgeFuture,
    bool isDisabled = false,
  }) {
    return CleanMenuCard(
      title: title,
      icon: icon,
      backgroundColor: backgroundColor,
      iconColor: iconColor,
      onTap: onTap,
      badgeFuture: badgeFuture,
      isDisabled: isDisabled,
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

  Widget _buildStatRow(BuildContext context, String label, int count, Color color) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$count건',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
            fontSize: 12,
          ),
        ),
      ],
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
                      ? Theme.of(context).primaryColor
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

class CleanMenuCard extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;
  final VoidCallback? onTap;
  final Future<int>? badgeFuture;
  final bool isDisabled;

  const CleanMenuCard({
    super.key,
    required this.title,
    required this.icon,
    required this.backgroundColor,
    required this.iconColor,
    this.onTap,
    this.badgeFuture,
    this.isDisabled = false,
  });

  @override
  State<CleanMenuCard> createState() => _CleanMenuCardState();
}

class _CleanMenuCardState extends State<CleanMenuCard> with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setPressed(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
    if (v) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.isDisabled ? null : (_) => _setPressed(true),
      onTapCancel: widget.isDisabled ? null : () => _setPressed(false),
      onTapUp: widget.isDisabled ? null : (_) {
        _setPressed(false);
        widget.onTap?.call();
      },
      child: Opacity(
        opacity: widget.isDisabled ? 0.5 : 1.0,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: Container(
            decoration: BoxDecoration(
              color: widget.backgroundColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        widget.icon,
                        size: 44,
                        color: widget.iconColor,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.badgeFuture != null)
                Positioned(
                  right: 10,
                  top: 10,
                  child: FutureBuilder<int>(
                    future: widget.badgeFuture,
                    builder: (context, snapshot) {
                      final count = snapshot.data ?? 0;
                      if (count <= 0) return const SizedBox.shrink();
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF5252),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withOpacity(0.4),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          count > 99 ? '99+' : count.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}
