import 'dart:async';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import '../../services/auth_service.dart';
import '../../services/ad_service.dart';
import '../../models/ad.dart';
import '../../widgets/business/business_tab_shell.dart';
import '../../widgets/kakao_login_button.dart';
import '../../widgets/business/business_metric_card.dart';
import '../business/business_profile_screen.dart';
import '../business/business_pending_screen.dart';
import '../../theme/business_theme.dart';
import '../onboarding/onboarding_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isCheckingOnboarding = true;
  bool _shouldShowOnboarding = false;
  int _totalCompletedJobs = 0;
  int _openListingCount = 0;
  bool _isLoadingStats = true;
  // 홈 배너 광고 Future 캐싱 (build 마다 재요청 방지)
  Future<List<Ad>>? _homeBannerFuture;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
    _loadStatistics();
    _homeBannerFuture = AdService().getAdsByLocation('home_banner');
  }

  Future<void> _checkOnboarding() async {
    final completed = await OnboardingScreen.isOnboardingCompleted();
    if (!mounted) return;
    // 이미 로그인된 사용자(자동 로그인 포함)에게는 온보딩을 보이지 않음.
    // 미로그인 신규 설치만 온보딩 → 로그인 버튼이 있는 홈으로 이어지도록 함.
    final auth = Provider.of<AuthService>(context, listen: false);
    final showOnboarding = !completed && !auth.isAuthenticated;
    setState(() {
      _shouldShowOnboarding = showOnboarding;
      _isCheckingOnboarding = false;
    });
  }

  void _completeOnboarding() {
    setState(() {
      _shouldShowOnboarding = false;
    });
  }

  Future<int> _countByStatus(String table, List<String> statuses) async {
    final response = await Supabase.instance.client
        .from(table)
        .select('id')
        .inFilter('status', statuses)
        .count(CountOption.exact);
    return response.count;
  }

  Future<int> _rpcCount(String fn) async {
    final raw = await Supabase.instance.client.rpc(fn);
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString()) ?? 0;
  }

  Future<void> _loadStatistics() async {
    try {
      int total = 0;
      try {
        total = await _rpcCount('get_completed_jobs_public_count');
      } catch (rpcErr) {
        debugPrint('⚠️ [HomeScreen] 완료 공사 RPC 실패, 테이블 count 폴백: $rpcErr');
        total = await _countByStatus(
          'jobs',
          const ['completed', 'awaiting_confirmation'],
        );
      }

      int openListings = 0;
      try {
        openListings = await _rpcCount('get_open_listings_public_count');
      } catch (e) {
        debugPrint('⚠️ [HomeScreen] 공개 일감 RPC 실패, 테이블 count 폴백: $e');
        openListings = await _countByStatus(
          'marketplace_listings',
          const ['open', 'created'],
        );
      }

      debugPrint('📊 [HomeScreen] completed=$total open=$openListings');
      if (mounted) {
        setState(() {
          _totalCompletedJobs = total;
          _openListingCount = openListings;
          _isLoadingStats = false;
        });
      }
    } catch (e) {
      debugPrint('❌ 통계 로드 실패: $e');
      if (mounted) {
        setState(() {
          _isLoadingStats = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 온보딩 체크 중
    if (_isCheckingOnboarding) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // 온보딩이 필요한 경우
    if (_shouldShowOnboarding) {
      return OnboardingScreen(onComplete: _completeOnboarding);
    }

    // 메인 화면
    return Consumer<AuthService>(
      builder: (context, authService, child) {
        // 로그인 사용자 전원 사업자 플로우 (고객 대시보드 미사용)
        if (authService.isAuthenticated) {
          final u = authService.currentUser!;
          final hasBusinessName = (u.businessName != null && u.businessName!.trim().isNotEmpty);
          final status = (u.businessStatus ?? 'pending').toLowerCase();

          print('🔍 [HomeScreen] 로그인 사용자 → 사업자 플로우:');
          print('   - ID: ${u.id}');
          print('   - Business Status: $status');

          if (status == 'approved') {
            return const BusinessTabShell();
          }

          if (!hasBusinessName) {
            return const BusinessProfileScreen();
          }

          return const BusinessPendingScreen();
        }

        return WillPopScope(
          onWillPop: () async => false,
          child: Scaffold(
            backgroundColor: BusinessTheme.background,
            appBar: AppBar(title: const Text('올수리')),
            body: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  sliver: SliverToBoxAdapter(child: _buildHero()),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  sliver: SliverToBoxAdapter(child: _buildStats()),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  sliver: SliverToBoxAdapter(child: _buildHomeBanner(context)),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  sliver: SliverToBoxAdapter(child: _buildTrustRow()),
                ),
              ],
            ),
            bottomNavigationBar: _buildLoginBar(context, authService),
          ),
        );
      },
    );
  }

  Widget _buildHero() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        color: BusinessTheme.navy,
        borderRadius: BorderRadius.circular(BusinessTheme.radius),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '현장 일감을 더 빠르게',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '견적 요청을 확인하고 바로 입찰하세요.',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final completed = _isLoadingStats ? '—' : _formatCount(_totalCompletedJobs);
    final open = _isLoadingStats ? '—' : _formatCount(_openListingCount);
    return Row(
      children: [
        Expanded(
          child: BusinessMetricCard(
            label: '완료된 공사',
            value: completed,
            icon: Icons.check_circle_outline,
            accent: BusinessTheme.success,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: BusinessMetricCard(
            label: '현재 공개 일감',
            value: open,
            icon: Icons.work_outline,
          ),
        ),
      ],
    );
  }

  String _formatCount(int n) {
    final s = n.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
    return '$s건';
  }

  Widget _buildTrustRow() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BusinessTheme.cardDecoration(),
      child: Row(
        children: [
          _buildFeatureItem(Icons.verified_user_outlined, '검증된\n사업자'),
          _divider(),
          _buildFeatureItem(Icons.bolt_outlined, '빠른\n입찰'),
          _divider(),
          _buildFeatureItem(Icons.forum_outlined, '실시간\n채팅'),
        ],
      ),
    );
  }

  Widget _divider() {
    return Container(
      height: 36,
      width: 1,
      color: BusinessTheme.border,
      margin: const EdgeInsets.symmetric(horizontal: 8),
    );
  }

  Widget _buildLoginBar(BuildContext context, AuthService authService) {
    if (authService.isAuthenticated) return const SizedBox.shrink();
    final showApple = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    return Material(
      color: BusinessTheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Apple 또는 카카오로 로그인할 수 있습니다',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: BusinessTheme.textMuted,
                ),
              ),
              const SizedBox(height: 12),
              if (showApple) ...[
                SizedBox(
                  width: double.infinity,
                  child: SignInWithAppleButton(
                    style: SignInWithAppleButtonStyle.black,
                    height: 56,
                    borderRadius: BorderRadius.circular(12),
                    onPressed: () => _handleAppleLogin(context),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              KakaoLoginButton(onPressed: () => _handleKakaoLogin(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomeBanner(BuildContext context) {
    return FutureBuilder<List<Ad>>(
      future: _homeBannerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: 128,
            decoration: BusinessTheme.cardDecoration(color: BusinessTheme.lightBlue),
          );
        }
        final ads = snapshot.data ?? [];
        if (ads.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BusinessTheme.cardDecoration(),
            child: const Row(
              children: [
                Icon(Icons.campaign_outlined, color: BusinessTheme.blue, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '파트너 안내',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: BusinessTheme.navy,
                          fontSize: 15,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '로그인하면 새 견적 요청과 오더를 바로 확인할 수 있습니다.',
                        style: TextStyle(
                          color: BusinessTheme.textMuted,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8, left: 2),
              child: Text(
                '파트너 소식',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: BusinessTheme.navy,
                ),
              ),
            ),
            _GuestAdCarousel(ads: ads, onLaunchUrl: _launchAdUrl),
          ],
        );
      },
    );
  }

  Future<void> _launchAdUrl(String urlString) async {
    try {
      final Uri url = Uri.parse(urlString);
      if (!await url_launcher.launchUrl(url, mode: url_launcher.LaunchMode.externalApplication)) {
        throw Exception('Could not launch $url');
      }
    } catch (e) {
      print('❌ 링크 열기 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('링크를 열 수 없습니다.')),
        );
      }
    }
  }

  Widget _buildFeatureItem(IconData icon, String text) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 22, color: BusinessTheme.blue),
          const SizedBox(height: 6),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              color: BusinessTheme.textMuted,
              height: 1.25,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleAppleLogin(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return WillPopScope(
          onWillPop: () async => false,
          child: const Dialog(
            backgroundColor: Colors.white,
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Apple로 로그인 중…'),
                ],
              ),
            ),
          ),
        );
      },
    );
    try {
      final ok = await Provider.of<AuthService>(context, listen: false).signInWithApple();
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Apple 로그인에 실패했습니다. Supabase에서 Apple 로그인을 설정했는지 확인하세요.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Apple 로그인 오류: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleKakaoLogin(BuildContext context) async {
    // iOS에서는 로딩 다이얼로그를 먼저 띄우면 Kakao WebAuth 시트가 가려져
    // 버튼이 눌려도 아무 반응이 없는 것처럼 보입니다. SDK 로그인 먼저 호출합니다.
    try {
      final ok = await Provider.of<AuthService>(context, listen: false).signInWithKakao();
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('카카오 로그인에 실패했습니다. 잠시 후 다시 시도해 주세요.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('로그인 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _GuestAdCarousel extends StatefulWidget {
  final List<Ad> ads;
  final Future<void> Function(String url) onLaunchUrl;

  const _GuestAdCarousel({required this.ads, required this.onLaunchUrl});

  @override
  State<_GuestAdCarousel> createState() => _GuestAdCarouselState();
}

class _GuestAdCarouselState extends State<_GuestAdCarousel> {
  final PageController _controller = PageController();
  int _current = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.ads.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (!mounted || !_controller.hasClients) return;
        final next = (_current + 1) % widget.ads.length;
        _controller.animateToPage(
          next,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 3,
          child: PageView.builder(
            controller: _controller,
            onPageChanged: (i) => setState(() => _current = i),
            itemCount: widget.ads.length,
            itemBuilder: (context, index) {
              final ad = widget.ads[index];
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    if (ad.linkUrl != null && ad.linkUrl!.isNotEmpty) {
                      widget.onLaunchUrl(ad.linkUrl!);
                    }
                  },
                  borderRadius: BorderRadius.circular(BusinessTheme.radius),
                  child: Ink(
                    decoration: BusinessTheme.cardDecoration(),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(BusinessTheme.radius),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (ad.imageUrl.isNotEmpty)
                            CachedNetworkImage(
                              imageUrl: ad.imageUrl,
                              fit: BoxFit.cover,
                              memCacheHeight: 400,
                              errorWidget: (_, __, ___) => const ColoredBox(
                                color: BusinessTheme.lightBlue,
                              ),
                            )
                          else
                            const ColoredBox(color: BusinessTheme.lightBlue),
                          if ((ad.title ?? '').isNotEmpty)
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.fromLTRB(14, 28, 14, 12),
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Colors.transparent, Color(0xCC0B2545)],
                                  ),
                                ),
                                child: Text(
                                  ad.title!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                        ],
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
            children: List.generate(widget.ads.length, (i) {
              final active = i == _current;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: active ? 16 : 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: active ? BusinessTheme.blue : BusinessTheme.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}

