import 'package:flutter/material.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/business_theme.dart';

/// Onboarding 화면 데이터 모델
class OnboardingData {
  final String title;
  final String description;
  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;

  OnboardingData({
    required this.title,
    required this.description,
    required this.icon,
    required this.backgroundColor,
    required this.iconColor,
  });
}

/// Onboarding 메인 화면
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({Key? key, required this.onComplete}) : super(key: key);

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();

  /// 온보딩 완료 여부 체크 (Static 메서드)
  static Future<bool> isOnboardingCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('onboarding_completed') ?? false;
  }

  /// 온보딩 완료 상태 초기화 (지원·내부 확인용)
  static Future<void> resetOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('onboarding_completed');
  }
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<OnboardingData> _pages = [
    OnboardingData(
      title: '환영합니다! 올수리입니다',
      description: '전문가와 빠르게 연결되어\n신뢰할 수 있는 서비스를 받아보세요',
      icon: Icons.handyman_rounded,
      backgroundColor: BusinessTheme.lightBlue,
      iconColor: BusinessTheme.navy,
    ),
    OnboardingData(
      title: '오더에 입찰하세요',
      description: '고객의 요청을 확인하고\n경쟁력 있는 견적으로 공사를 수주하세요',
      icon: Icons.work_outline_rounded,
      backgroundColor: BusinessTheme.lightBlue,
      iconColor: BusinessTheme.blue,
    ),
    OnboardingData(
      title: '실시간 채팅으로 소통',
      description: '고객과 빠르게 소통하고\n원활한 공사 진행을 경험하세요',
      icon: Icons.chat_bubble_outline_rounded,
      backgroundColor: BusinessTheme.lightBlue,
      iconColor: BusinessTheme.navy,
    ),
    OnboardingData(
      title: '지금 바로 시작하세요!',
      description: '올수리에서 더 많은 일감을 찾고\n성공적인 사업을 만들어가세요',
      icon: Icons.rocket_launch_rounded,
      backgroundColor: BusinessTheme.lightBlue,
      iconColor: BusinessTheme.success,
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);
    widget.onComplete();
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _completeOnboarding();
    }
  }

  void _skipOnboarding() {
    _completeOnboarding();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BusinessTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // 상단 Skip 버튼
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_currentPage < _pages.length - 1)
                    TextButton(
                      onPressed: _skipOnboarding,
                      child: Text(
                        'Skip',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // 페이지 뷰
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemCount: _pages.length,
                itemBuilder: (context, index) {
                  return _buildPage(_pages[index]);
                },
              ),
            ),

            // 인디케이터
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: SmoothPageIndicator(
                controller: _pageController,
                count: _pages.length,
                effect: ExpandingDotsEffect(
                  activeDotColor: Theme.of(context).primaryColor,
                  dotColor: Colors.grey[300]!,
                  dotHeight: 10,
                  dotWidth: 10,
                  expansionFactor: 3,
                ),
              ),
            ),

            // 하단 버튼
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _nextPage,
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    _currentPage == _pages.length - 1 ? '시작하기' : '다음',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(OnboardingData data) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 아이콘 컨테이너 (애니메이션 효과)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    color: data.backgroundColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: data.iconColor.withOpacity(0.2),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Icon(
                    data.icon,
                    size: 100,
                    color: data.iconColor,
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 60),

          // 제목 (Fade-in 애니메이션)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 800),
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 20 * (1 - value)),
                  child: Text(
                    data.title,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 24),

          // 설명 (Fade-in 애니메이션 - 약간 지연)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 1000),
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 20 * (1 - value)),
                  child: Text(
                    data.description,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.grey[600],
                          height: 1.8,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

