import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../services/version_service.dart';
import '../utils/app_deep_links.dart';
import '../widgets/update_dialog.dart';
import 'home/home_screen.dart';

/// 앱 시작 화면.
///
/// 1) 앱 버전 체크 (강제 업데이트 대상이면 여기서 진행을 막음)
/// 2) 자동 로그인 체크 후 홈 화면으로 이동
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final VersionService _versionService = VersionService();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Future.delayed(const Duration(milliseconds: 150)); // 최소 스플래시 시간(깜빡임 방지)
    if (!mounted) return;

    // 강제 업데이트 대상이면 아래 await가 다이얼로그가 닫히기 전까지 완료되지 않으므로
    // 자연스럽게 앱 사용(자동 로그인/홈 진입)을 막게 됩니다.
    await _checkVersion();
    if (!mounted) return;

    await _checkAutoLogin();
  }

  /// 서버(Supabase)의 버전 정보를 조회해 업데이트 안내 팝업을 노출합니다.
  /// 조회/비교 과정에서 어떤 예외가 발생해도 앱은 정상적으로 계속 진행됩니다.
  Future<void> _checkVersion() async {
    try {
      final result = await _versionService.checkForUpdate();
      final info = result.info;
      if (!mounted || info == null) return;

      if (result.severity == UpdateSeverity.forced) {
        print('🚫 [SplashScreen] 강제 업데이트 대상 - 팝업 표시 (업데이트 전까지 진행 불가)');
        await UpdateDialog.show(context, info: info, isForced: true);
        // 강제 다이얼로그는 닫을 수 없으므로 이 지점 이후 코드는 실행되지 않습니다.
      } else if (result.severity == UpdateSeverity.optional) {
        final alreadyShownToday =
            await _versionService.wasOptionalPromptShownToday(info.latestVersion);
        if (alreadyShownToday) {
          print('ℹ️ [SplashScreen] 선택 업데이트 팝업 - 오늘 이미 노출됨(스킵)');
          return;
        }
        if (!mounted) return;
        print('ℹ️ [SplashScreen] 선택 업데이트 대상 - 팝업 표시');
        await _versionService.markOptionalPromptShownToday(info.latestVersion);
        if (!mounted) return;
        await UpdateDialog.show(context, info: info, isForced: false);
      }
    } catch (e) {
      // 버전 체크 자체는 앱 진입을 막는 필수 조건이 아니므로 로그만 남기고 계속 진행합니다.
      print('⚠️ [SplashScreen] 버전 체크 중 오류 발생 (무시하고 진행): $e');
    }
  }

  /// 홈이 올라온 뒤 딥링크를 붙여 [Splash, 마켓] 같은 잘못된 스택을 방지합니다.
  void _scheduleDeepLinksAfterHome() {
    Future.delayed(const Duration(milliseconds: 400), initAppDeepLinksAfterSplash);
  }

  Future<void> _checkAutoLogin() async {
    if (!mounted) return;

    final authService = Provider.of<AuthService>(context, listen: false);

    // Supabase 세션 확인
    final session = Supabase.instance.client.auth.currentSession;

    if (session != null) {
      print('✅ [SplashScreen] 기존 세션 발견 - 자동 로그인 시도');
      try {
        // AuthService에서 사용자 정보 로드 (타임아웃은 AuthService.loadUserFromSession 내부)
        await authService.loadUserFromSession();

        if (mounted && authService.isAuthenticated) {
          print('✅ [SplashScreen] 자동 로그인 성공');
          // 홈 화면으로 이동 (역할에 따라 자동으로 대시보드 표시)
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
          _scheduleDeepLinksAfterHome();
          return;
        }
      } catch (e) {
        print('⚠️ [SplashScreen] 자동 로그인 실패: $e');
      }
    }

    // 세션이 없거나 실패한 경우 홈 화면으로 (온보딩/로그인 표시)
    if (mounted) {
      print('ℹ️ [SplashScreen] 세션 없음 - 홈 화면으로 이동');
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
      _scheduleDeepLinksAfterHome();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 로고 또는 앱 이름
            Icon(
              Icons.construction,
              size: 80,
              color: Theme.of(context).primaryColor,
            ),
            const SizedBox(height: 24),
            const Text(
              '올수리',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 48),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
