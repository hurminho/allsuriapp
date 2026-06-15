import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/date_symbol_data_local.dart';
import 'dart:io' show Platform;
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:flutter/cupertino.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_config.dart';
import 'services/auth_service.dart';
import 'services/order_service.dart';
import 'services/estimate_service.dart';
import 'services/job_service.dart';
import 'services/payment_service.dart';
import 'services/api_service.dart';
import 'services/chat_service.dart';
import 'services/notification_service.dart';
import 'services/local_notification_service.dart';
import 'services/community_service.dart';
import 'services/fcm_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'providers/user_provider.dart';
import 'screens/home/home_screen.dart';
import 'screens/auth/login_screen.dart';
import 'utils/app_deep_links.dart';
import 'app_navigator_key.dart';

/// 앱 포그라운드 진입 시 앱 아이콘 배지 제거 (iOS/Android)
class _BadgeLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      try {
        FlutterAppBadger.removeBadge();
      } catch (_) {}
    }
  }
}

//126e5d87-94e0-4ad2-94ba-51b9c2454a4a
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ko_KR 로케일 초기화 (NumberFormat.currency, DateFormat에서 LocaleDataException 방지)
  await initializeDateFormatting('ko_KR', null);
  FlutterError.onError = (FlutterErrorDetails details) {
    // 무시 가능한 외부 딥링크 예외(Supabase OAuth 등)를 앱 크래시 없이 로그만 남김
    debugPrint('FlutterError: \\n${details.exceptionAsString()}');
  };
  // Kakao SDK 초기화 (dart-define)
  final kakaoKey = const String.fromEnvironment('KAKAO_NATIVE_APP_KEY', defaultValue: '');
  print('🔍 [Main] KAKAO_NATIVE_APP_KEY: ${kakaoKey.isNotEmpty ? "로드됨(***)" : "❌ 비어있음"}');
  
  if (kakaoKey.isNotEmpty) {
    kakao.KakaoSdk.init(nativeAppKey: kakaoKey);
    print('✅ [Main] Kakao SDK 초기화 완료');
  } else {
    print('⚠️ [Main] Kakao SDK 키가 없어 초기화를 건너뜁니다.');
  }
  // Supabase 초기화 (Auth 포함)
  // ⚠️ SUPABASE_URL / SUPABASE_ANON_KEY 는 빌드 시 --dart-define-from-file 로 넣어야 함.
  //    비어 있으면 "No host specified in URI /auth/v1/token" 등 오류가 난다 (Apple 로그인 포함).
  print('🔍 Supabase URL: ${SupabaseConfig.url.isNotEmpty ? "${SupabaseConfig.url.length > 40 ? "${SupabaseConfig.url.substring(0, 40)}..." : SupabaseConfig.url}" : "❌ 비어 있음"}');
  print('🔍 Supabase Key: ${SupabaseConfig.anonKey.isNotEmpty ? "✅ 로드됨" : "❌ 비어있음"}');

  if (SupabaseConfig.url.isEmpty || SupabaseConfig.anonKey.isEmpty) {
    print('');
    print('❌ [Main] SUPABASE_URL 또는 SUPABASE_ANON_KEY가 주입되지 않았습니다.');
    print('   → 프로젝트 루트에 dart_defines.json 을 만들고 Supabase 값을 넣은 뒤:');
    print('   → flutter run --release --dart-define-from-file=dart_defines.json');
    print('   → 또는 ./run_release.sh / ./run_app.sh 사용');
    print('   → 템플릿: example_dart_defines.json 참고 (복사 후 dart_defines.json 으로 저장)');
    print('');
  }

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );
  
  // 알림 서비스 초기화 (서로 독립적이므로 병렬 실행)
  await Future.wait([
    NotificationService().initialize(),
    LocalNotificationService().initialize(
      onSelectNotification: (String? payload) {
        debugPrint('🔔 [Main] 알림 클릭: $payload');
        // TODO: 페이로드를 처리하여 적절한 화면으로 이동
      },
    ),
  ]);
  
  // iOS/Android: 앱 포그라운드 진입 시 앱 아이콘 배지 제거
  if (!kIsWeb) {
    WidgetsBinding.instance.addObserver(_BadgeLifecycleObserver());
  }

  runZonedGuarded(() {
    runApp(const MyApp());
    // Firebase/FCM 초기화(최대 10초)는 첫 프레임을 막지 않도록 runApp 이후로 지연
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initFirebaseMessaging();
    });
  }, (error, stack) {
    // Supabase OAuth 미사용 시 Code verifier 에러 무시 (Kakao 리다이렉트 등으로 인한 오탐)
    if (error.toString().contains('Code verifier could not be found')) {
      debugPrint('ℹ️ [Main] Supabase OAuth 관련 에러 무시 (카카오 로그인 사용 중)');
      return;
    }
    debugPrint('Top-level error caught: $error');
  });
}

/// Firebase + FCM 초기화 (첫 프레임 이후 비동기 실행).
/// 실패해도 앱 동작에는 영향이 없으므로 모든 예외를 흡수한다.
Future<void> _initFirebaseMessaging() async {
  if (kIsWeb) return;
  bool firebaseReady = false;
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('⚠️ Firebase 초기화 타임아웃');
          throw TimeoutException('Firebase init timeout');
        },
      );
    } else {
      debugPrint('ℹ️ [Main] Firebase 이미 초기화됨 (네이티브)');
    }
    firebaseReady = true;
  } catch (e) {
    if (e.toString().contains('duplicate-app') || e.toString().contains('already exists')) {
      debugPrint('ℹ️ [Main] Firebase 네이티브 초기화됨 - FCM 계속 진행');
      firebaseReady = true;
    } else {
      debugPrint('⚠️ Firebase 초기화 실패: $e');
    }
  }
  if (!firebaseReady) return;
  try {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await FCMService().initialize().timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        debugPrint('⚠️ FCM 초기화 타임아웃');
        throw TimeoutException('FCM init timeout');
      },
    );
    FCMService().setNavigatorKey(navigatorKey);
    debugPrint('✅ FCM 기능이 활성화되었습니다. (${Platform.isIOS ? "iOS" : "Android"})');
  } catch (e) {
    debugPrint('⚠️ FCM 초기화 실패 (앱은 계속 실행됨): $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // AuthService를 먼저 생성
        ChangeNotifierProvider(create: (context) => AuthService()),
        // 다른 서비스들을 생성
        ChangeNotifierProvider(create: (context) => ApiService()),
        ChangeNotifierProvider(create: (context) => OrderService()),
        ChangeNotifierProvider(create: (context) => EstimateService()),
        ChangeNotifierProvider(create: (context) => JobService()),
        ChangeNotifierProvider(create: (context) => PaymentService()),
        ChangeNotifierProvider(create: (context) => ChatService()),
        ChangeNotifierProvider(create: (context) => CommunityService()),
        // UserProvider는 AuthService에 의존하므로 마지막에 생성
        ChangeNotifierProxyProvider<AuthService, UserProvider>(
          create: (context) => UserProvider(Provider.of<AuthService>(context, listen: false)),
          // AuthService는 싱글톤이므로 매번 새 UserProvider를 만들지 않고 재사용한다.
          // (auth notify마다 새 인스턴스 생성 + 리스너 재등록으로 인한 광역 rebuild/누수 방지)
          update: (context, authService, previous) => previous ?? UserProvider(authService),
        ),
      ],
      child: DynamicColorBuilder(
        builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
          // Modern Google-inspired color scheme
          const seed = Color(0xFF1A73E8); // Google Blue
          final ColorScheme lightScheme = ColorScheme.fromSeed(
            seedColor: seed,
            brightness: Brightness.light,
            primary: const Color(0xFF1A73E8),
            secondary: const Color(0xFF34A853),
            error: const Color(0xFFEA4335),
            surface: Colors.white,
            background: const Color(0xFFF8F9FA),
          );
          final ColorScheme darkScheme = ColorScheme.fromSeed(
            seedColor: seed,
            brightness: Brightness.dark,
            primary: const Color(0xFF4285F4),
            secondary: const Color(0xFF34A853),
            error: const Color(0xFFEA4335),
          );

          ThemeData buildTheme(ColorScheme colorScheme) {
            return ThemeData(
              useMaterial3: true,
              colorScheme: colorScheme,
              // iOS: GoogleFonts 네트워크 로드가 첫 프레임 블로킹 → 기본 시스템 폰트 사용
              appBarTheme: AppBarTheme(
                centerTitle: true,
                elevation: 0,
                scrolledUnderElevation: 2,
                backgroundColor: colorScheme.surface,
                foregroundColor: colorScheme.onSurface,
                shadowColor: Colors.black.withOpacity(0.1),
              ),
              cardTheme: CardThemeData(
                elevation: 2,
                shadowColor: Colors.black.withOpacity(0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              navigationBarTheme: NavigationBarThemeData(
                elevation: 3,
                indicatorShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                backgroundColor: colorScheme.surface,
                indicatorColor: colorScheme.primaryContainer,
                shadowColor: Colors.black.withOpacity(0.1),
              ),
              filledButtonTheme: FilledButtonThemeData(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  elevation: 1,
                  shadowColor: Colors.black.withOpacity(0.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  elevation: 2,
                  shadowColor: Colors.black.withOpacity(0.15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              outlinedButtonTheme: OutlinedButtonThemeData(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                  side: BorderSide(color: colorScheme.outline, width: 1.5),
                ),
              ),
              textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
              chipTheme: ChipThemeData(
                elevation: 0,
                pressElevation: 1,
                backgroundColor: colorScheme.surfaceVariant,
                selectedColor: colorScheme.primaryContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              floatingActionButtonTheme: FloatingActionButtonThemeData(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              dialogTheme: DialogThemeData(
                elevation: 8,
                shadowColor: Colors.black.withOpacity(0.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              bottomSheetTheme: BottomSheetThemeData(
                elevation: 8,
                shadowColor: Colors.black.withOpacity(0.2),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
              ),
              inputDecorationTheme: InputDecorationTheme(
                filled: true,
                fillColor: colorScheme.surfaceVariant.withOpacity(0.4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: colorScheme.primary,
                    width: 2.5,
                  ),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: colorScheme.error,
                    width: 1.5,
                  ),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: colorScheme.error,
                    width: 2.5,
                  ),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                labelStyle: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurfaceVariant,
                ),
                hintStyle: TextStyle(
                  fontSize: 15,
                  color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                ),
              ),
              dividerTheme: DividerThemeData(
                color: colorScheme.outlineVariant,
                thickness: 1,
                space: 1,
              ),
              listTileTheme: ListTileThemeData(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
          }

           return MaterialApp(
            title: 'Allsuri',
            navigatorKey: navigatorKey, // 딥링크 처리용 네비게이터 키
             theme: buildTheme(lightScheme.copyWith(
               surface: Colors.white,
               background: Colors.white,
             )),
             darkTheme: buildTheme(darkScheme.copyWith(
               surface: Colors.white,
               background: Colors.white,
             )),
             themeMode: ThemeMode.light,
            debugShowCheckedModeBanner: false,
             home: const SplashScreen(), // 스플래시 화면으로 변경하여 자동 로그인 체크
          );
        },
      ),
    );
  }
}

/// 자동 로그인을 체크하는 스플래시 화면
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAutoLogin();
  }

  /// 홈이 올라온 뒤 딥링크를 붙여 [Splash, 마켓] 같은 잘못된 스택을 방지합니다.
  void _scheduleDeepLinksAfterHome() {
    Future.delayed(const Duration(milliseconds: 400), initAppDeepLinksAfterSplash);
  }

  Future<void> _checkAutoLogin() async {
    await Future.delayed(const Duration(milliseconds: 150)); // 최소 스플래시 시간(깜빡임 방지)
    
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

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, child) {
        if (authService.isLoading) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }
        if (!authService.isAuthenticated) {
          return const LoginScreen();
        }
        return const HomeScreen();
      },
    );
  }
}
