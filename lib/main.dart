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
import 'config.dart';
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
import 'screens/splash_screen.dart';
import 'theme/business_theme.dart';
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
  // Kakao SDK 초기화 (dart-define, 없으면 프로덕션 기본값)
  final kakaoKey = AppConfig.kakaoNativeAppKey;
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
        builder: (ColorScheme? _, ColorScheme? __) {
          final theme = BusinessTheme.theme(ThemeData(useMaterial3: true));
          return MaterialApp(
            title: 'Allsuri',
            navigatorKey: navigatorKey,
            theme: theme,
            darkTheme: theme,
            themeMode: ThemeMode.light,
            debugShowCheckedModeBanner: false,
            home: const SplashScreen(),
          );
        },
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
