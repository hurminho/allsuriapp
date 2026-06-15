import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import '../../services/auth_service.dart';
import '../../services/order_service.dart';
import '../../services/ad_service.dart';
import '../../models/ad.dart';
import '../../widgets/interactive_card.dart';
import '../../widgets/business_dashboard.dart';
import '../../widgets/professional_dashboard.dart';
import '../business/business_profile_screen.dart';
import '../business/business_pending_screen.dart';
import '../../models/order.dart' as app_models;
import '../customer/create_request_screen.dart';
import '../customer/my_estimates_screen.dart';
import '../../services/api_service.dart';
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

  Future<void> _loadStatistics() async {
    try {
      // 플랫폼 전체 완료 건수: jobs RLS는 본인 관련 행만 보이므로
      // Supabase에 `get_completed_jobs_public_count` RPC가 있어야 정확함 (database/get_completed_jobs_public_count.sql).
      int total = 0;
      try {
        final raw = await Supabase.instance.client
            .rpc('get_completed_jobs_public_count');
        if (raw is int) {
          total = raw;
        } else if (raw is num) {
          total = raw.toInt();
        }
      } catch (rpcErr) {
        debugPrint('⚠️ [HomeScreen] 공개 집계 RPC 없음/실패, RLS 기준 count로 폴백: $rpcErr');
        final response = await Supabase.instance.client
            .from('jobs')
            .select('id')
            .inFilter('status', ['completed', 'awaiting_confirmation'])
            .count(CountOption.exact);
        total = response.count;
      }

      if (mounted) {
        setState(() {
          _totalCompletedJobs = total;
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
            return const ProfessionalDashboard();
          }

          if (!hasBusinessName) {
            return const BusinessProfileScreen();
          }

          return const BusinessPendingScreen();
        }

        return WillPopScope(
          onWillPop: () async => false,
          child: Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: const Text(
                '올수리',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
              centerTitle: false,
              actions: authService.isAuthenticated
                  ? [
                      IconButton(
                        tooltip: '로그아웃',
                        onPressed: () => authService.signOut(),
                        icon: const Icon(Icons.logout, color: Colors.black),
                      ),
                    ]
                  : null,
            ),
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final buttonWidth = width * 0.6; // 너비 60%
                  
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const SizedBox(height: 20),
                              
                              // 1. 상단 환영 메시지 (통계 정보 포함)
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      const Color(0xFF1E3A8A),
                                      const Color(0xFF3B82F6),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF1E3A8A).withOpacity(0.3),
                                      blurRadius: 12,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
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
                                                '환영합니다!',
                                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                '올수리에서 번창하세요!',
                                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                  color: Colors.white.withOpacity(0.9),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Icon(
                                            Icons.handyman_rounded,
                                            size: 48,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),
                                    // 통계 정보
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.3),
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.emoji_events,
                                            color: Colors.amber[300],
                                            size: 28,
                                          ),
                                          const SizedBox(width: 12),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '올수리에서 완료된 공사',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.white.withOpacity(0.9),
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              _isLoadingStats
                                                  ? SizedBox(
                                                      width: 20,
                                                      height: 20,
                                                      child: CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                                      ),
                                                    )
                                                  : RichText(
                                                      text: TextSpan(
                                                        children: [
                                                          TextSpan(
                                                            text: '$_totalCompletedJobs',
                                                            style: const TextStyle(
                                                              fontSize: 24,
                                                              fontWeight: FontWeight.w800,
                                                              color: Colors.white,
                                                              letterSpacing: -0.5,
                                                            ),
                                                          ),
                                                          const TextSpan(
                                                            text: ' 건',
                                                            style: TextStyle(
                                                              fontSize: 16,
                                                              fontWeight: FontWeight.w600,
                                                              color: Colors.white,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              
                              const Spacer(),
                              
                              // 2. 홈 화면 광고 배너
                              _buildHomeBanner(context),
                              
                              const Spacer(),
                              
                              // 3. 로그인 (Guideline 4.8: Apple을 카카오와 동등·상단 배치 — Apple HIG)
                              if (!authService.isAuthenticated) ...[
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Text(
                                    'Apple 또는 카카오로 로그인할 수 있습니다',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[800],
                                    ),
                                  ),
                                ),
                                if (!kIsWeb &&
                                    defaultTargetPlatform == TargetPlatform.iOS) ...[
                                  SizedBox(
                                    width: double.infinity,
                                    child: SignInWithAppleButton(
                                      style: SignInWithAppleButtonStyle.black,
                                      height: 48,
                                      onPressed: () => _handleAppleLogin(context),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                InkWell(
                                  onTap: () => _handleKakaoLogin(context),
                                  borderRadius: BorderRadius.circular(12),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.asset(
                                      'assets/images/kakao_login_large_narrow.png',
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              ],
                              
                              const SizedBox(height: 40),
                              
                              // 4. 하단 푸터 (서비스 특징) - 유지
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _buildFeatureItem(Icons.verified_user_outlined, '신뢰할 수 있는\n전문가'),
                                  Container(height: 30, width: 1, color: Colors.grey[300], margin: const EdgeInsets.symmetric(horizontal: 24)),
                                  _buildFeatureItem(Icons.speed, '빠르고 간편한\n매칭'),
                                  Container(height: 30, width: 1, color: Colors.grey[300], margin: const EdgeInsets.symmetric(horizontal: 24)),
                                  _buildFeatureItem(Icons.thumb_up_outlined, '만족스러운\n결과'),
                                ],
                              ),
                              
                              const SizedBox(height: 40),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHomeBanner(BuildContext context) {
    return FutureBuilder<List<Ad>>(
      future: _homeBannerFuture,
      builder: (context, snapshot) {
        final ads = snapshot.data ?? [];
        
        // 광고가 없으면 빈 placeholder만 노출 — 연락처 표시 금지
        if (ads.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 40),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.grey[300]!),
            ),
          );
        }
        
        // 광고가 있으면 첫 번째 광고 표시
        final ad = ads.first;
        return GestureDetector(
          onTap: () {
            if (ad.linkUrl != null && ad.linkUrl!.isNotEmpty) {
              _launchAdUrl(ad.linkUrl!);
            }
          },
          child: Container(
            width: double.infinity,
            height: 150,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.grey[300]!),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: ad.imageUrl.isNotEmpty
                  ? Image.network(
                      ad.imageUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey[100],
                        child: Center(
                          child: Text(
                            ad.title ?? '광고',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    )
                  : Container(
                      color: Colors.grey[100],
                      child: Center(
                        child: Text(
                          ad.title ?? '광고',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
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
    return Column(
      children: [
        Icon(icon, size: 28, color: Colors.grey[400]),
        const SizedBox(height: 8),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[500],
            height: 1.2,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildCustomerMenu(BuildContext context) {
    // ... (기존 코드 유지 가능하지만 현재 사용 안함)
    return const SizedBox.shrink(); 
  }

  Future<int> _fetchMyOrderCount(BuildContext context) async {
    try {
      return 0; // 임시 반환
    } catch (_) {
      return 0;
    }
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
    // 로딩 다이얼로그 표시
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return WillPopScope(
          onWillPop: () async => false,
          child: Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 애니메이션 효과 (아이콘 바운스 등)
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(seconds: 1),
                    builder: (context, value, child) {
                      return Transform.translate(
                        offset: Offset(0, -10 * (1 - value).abs() * (value < 0.5 ? 1 : -1)), // 간단한 바운스
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE500).withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.work_outline, size: 48, color: Color(0xFFFEE500)),
                        ),
                      );
                    },
                    onEnd: () {}, // 반복하려면 StatefulWidget 필요
                  ),
                  const SizedBox(height: 24),
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFEE500)),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '일감을 챙겨 오고 있어요!! 🏃',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '잠시만 기다려주세요',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    try {
      // 카카오 로그인 실행
      await Provider.of<AuthService>(context, listen: false).signInWithKakao();
      
      if (context.mounted) {
        // 로그인 성공 시 로딩 닫기
        Navigator.of(context, rootNavigator: true).pop();
        
        // 화면은 자동으로 BusinessDashboard로 전환됨 (HomeScreen 빌더에서 역할에 따라 위젯 교체)
      }
    } catch (e) {
      if (context.mounted) {
        // 로딩 닫기
        Navigator.of(context, rootNavigator: true).pop();
        
        // 에러 메시지 표시
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
