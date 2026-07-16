import 'dart:convert';
import 'dart:io' show Platform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../firebase_options.dart';
import '../screens/chat_screen.dart';
import '../screens/business/job_management_screen.dart';
import 'version_service.dart';

/// Firebase Cloud Messaging 서비스
/// 실시간 푸시 알림을 처리하고 FCM 토큰을 관리합니다.
class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  /// Firebase 초기화 전 접근 시 크래시 방지 - 필요할 때만 접근
  FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  final SupabaseClient _sb = Supabase.instance.client;
  
  // 로컬 알림 플러그인 (포그라운드 알림용)
  final FlutterLocalNotificationsPlugin _localNotifications = 
      FlutterLocalNotificationsPlugin();
  
  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  /// FCM 초기화
  Future<void> initialize() async {
    try {
      print('🔔 FCM 초기화 시작...');

      // Firebase 초기화 확인 (iOS: 네이티브 자동 초기화 시 duplicate-app 무시)
      if (Firebase.apps.isEmpty) {
        try {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
        } catch (e) {
          if (!e.toString().contains('duplicate-app') && !e.toString().contains('already exists')) {
            rethrow;
          }
          // duplicate-app = 이미 초기화됨, 계속 진행
        }
      }

      // 알림 권한 요청
      final settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('✅ FCM 권한 승인됨');
      } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
        print('⚠️ FCM 임시 권한 승인됨');
      } else {
        print('❌ FCM 권한 거부됨');
        return;
      }

      // FCM 토큰 가져오기
      _fcmToken = await _messaging.getToken();
      print('🔑 FCM 토큰: $_fcmToken');

      // 로컬 알림 초기화
      await _initializeLocalNotifications();

      // 포그라운드에서는 시스템 배너 끄고, 아래 onMessage → 로컬 알림만 표시.
      // alert:true 이면 iOS가 시스템 알림 + 로컬 알림을 둘 다 띄워 2회처럼 보임.
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: true,
        sound: false,
      );

      // 메시지 핸들러 설정
      _setupMessageHandlers();

      // 토큰 갱신 리스너
      _messaging.onTokenRefresh.listen((newToken) {
        print('🔄 FCM 토큰 갱신: $newToken');
        _fcmToken = newToken;
        // 서버에 토큰 업데이트 (로그인 후 자동으로 업데이트됨)
      });

      print('✅ FCM 초기화 완료');
    } catch (e) {
      print('❌ FCM 초기화 실패: $e');
      print('   Firebase 설정을 확인하세요:');
      print('   1. google-services.json (Android)');
      print('   2. GoogleService-Info.plist (iOS)');
      print('   3. Firebase Console에서 앱이 등록되어 있는지 확인');
      rethrow; // 에러를 다시 던져서 main.dart에서 catch하도록 함
    }
  }

  /// 로컬 알림 초기화 + Android 알림 채널 생성
  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/launcher_icon');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        print('📱 로컬 알림 클릭: ${details.payload}');
        _handleNotificationTap(details.payload);
      },
    );

    // iOS: 로컬 알림 표시를 위해 권한 명시적 요청
    final iosPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (iosPlugin != null) {
      await iosPlugin.requestPermissions(alert: true, badge: true, sound: true);
      print('✅ iOS 로컬 알림 권한 요청 완료');
    }

    // Android 8.0+ 필수: 알림 채널 생성
    // 채널이 없으면 시스템 알림이 전혀 표시되지 않음
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'allsuri_notifications', // FCM channelId와 반드시 일치
          '올수리 알림',
          description: '새로운 오더, 견적, 채팅 알림',
          importance: Importance.max,
          enableVibration: true,
          playSound: true,
          showBadge: true,
        ),
      );
      print('✅ Android 알림 채널 생성 완료');
    }
  }

  /// 메시지 핸들러 설정
  void _setupMessageHandlers() {
    // 포그라운드 메시지 (앱이 실행 중일 때)
    FirebaseMessaging.onMessage.listen((message) {
      print('📩 포그라운드 메시지 수신: ${message.notification?.title}');
      _showLocalNotification(message);
    });

    // 백그라운드 메시지에서 앱 열림 → 뱃지 클리어
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      print('🚀 백그라운드 메시지에서 앱 열림: ${message.notification?.title}');
      _clearBadge();
      _handleNotificationTap(jsonEncode(message.data));
    });

    // 앱이 종료된 상태에서 알림 탭으로 앱 시작 → 뱃지 클리어
    _messaging.getInitialMessage().then((message) {
      if (message != null) {
        print('🌟 종료 상태에서 알림으로 앱 시작: ${message.notification?.title}');
        _clearBadge();
        _handleNotificationTap(jsonEncode(message.data));
      }
    });
  }

  /// iOS 앱 아이콘 뱃지 클리어
  Future<void> _clearBadge() async {
    try {
      // 주의: setForegroundNotificationPresentationOptions(alert:true)를 여기서
      // 호출하면 이후 포그라운드 알림이 시스템+로컬로 2회 표시됨. 호출 금지.
      await _localNotifications
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(badge: true);
    } catch (e) {
      print('뱃지 클리어 실패 (무시): $e');
    }
  }

  /// 포그라운드에서 로컬 알림 표시
  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    const androidDetails = AndroidNotificationDetails(
      'allsuri_notifications',
      '올수리 알림',
      channelDescription: '올수리 서비스의 일반 알림',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _localNotifications.show(
        notification.hashCode,
        notification.title ?? '알림',
        notification.body ?? '',
        details,
        payload: jsonEncode(message.data),
      );
      print('✅ 포그라운드 로컬 알림 표시: ${notification.title}');
    } catch (e) {
      print('❌ 포그라운드 로컬 알림 표시 실패: $e');
    }
  }

  /// 알림 탭 처리
  void _handleNotificationTap(String? payload) {
    if (payload == null) return;
    
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final type = data['type'] as String?;
      
      print('🔔 알림 타입: $type, 데이터: $data');
      
      // main.dart의 전역 navigatorKey 사용
      // ignore: avoid_dynamic_calls
      final navigatorKey = _getNavigatorKey();
      if (navigatorKey?.currentState == null) return;

      final navigator = navigatorKey!.currentState!;

      switch (type) {
        // 채팅 알림 → 해당 채팅방으로 이동
        case 'chat_message':
          final chatRoomId = data['chatRoomId'] as String?;
          if (chatRoomId != null && chatRoomId.isNotEmpty) {
            print('💬 채팅방으로 이동: $chatRoomId');
            navigator.push(MaterialPageRoute(
              builder: (_) => ChatScreen(chatRoomId: chatRoomId),
            ));
          }
          break;

        // 낙찰 알림 → 내 공사 관리 (해당 공사 하이라이트 + 진행중 필터)
        case 'bid_selected':
          final orderId = data['orderId'] as String?;
          print('🏆 내 공사 관리로 이동: orderId=$orderId');
          navigator.push(MaterialPageRoute(
            builder: (_) => JobManagementScreen(
              highlightedJobId: orderId,
              initialFilter: 'in_progress', // 진행중 탭으로 바로 이동
            ),
          ));
          break;

        // 새 오더 알림 → 오더 마켓플레이스
        case 'new_order':
          // 오더 목록은 대시보드에서 접근 가능하므로 별도 네비게이션 생략
          break;

        // 앱 업데이트 안내(관리자 발송) → 화면 이동 없이 스토어로 바로 이동
        case 'app_update':
          print('📲 업데이트 알림 클릭 - 스토어로 이동');
          _openAppStoreForUpdate();
          break;

        default:
          break;
      }
    } catch (e) {
      print('❌ 알림 데이터 파싱 실패: $e');
    }
  }

  /// 관리자가 보낸 "앱 업데이트" 알림을 탭했을 때 플랫폼에 맞는 스토어로 이동합니다.
  /// 스토어 URL은 항상 Supabase `app_version` 테이블에서 최신 값을 조회합니다
  /// (알림 발송 시점의 URL이 아니라 탭하는 시점의 최신 URL을 사용하기 위함).
  Future<void> _openAppStoreForUpdate() async {
    try {
      final info = await VersionService().fetchLatestVersionInfo();
      final storeUrl = Platform.isIOS ? info?.iosStoreUrl : info?.androidStoreUrl;
      if (storeUrl == null || storeUrl.isEmpty) {
        print('⚠️ [FCMService] 스토어 URL이 설정되어 있지 않습니다.');
        return;
      }
      final uri = Uri.parse(storeUrl);
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        print('⚠️ [FCMService] 스토어 링크를 열지 못했습니다: $storeUrl');
      }
    } catch (e) {
      print('❌ [FCMService] 업데이트 스토어 이동 실패: $e');
    }
  }

  /// main.dart의 전역 navigatorKey 접근 (순환 import 방지용)
  GlobalKey<NavigatorState>? _getNavigatorKey() {
    try {
      // main.dart의 navigatorKey를 동적으로 가져오는 대신
      // FCMService를 초기화할 때 주입받음
      return _navigatorKey;
    } catch (_) {
      return null;
    }
  }

  GlobalKey<NavigatorState>? _navigatorKey;

  /// navigatorKey 주입 (main.dart에서 호출)
  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  /// FCM 토큰을 Supabase에 저장
  Future<void> saveFCMToken(String userId) async {
    if (_fcmToken == null) {
      print('⚠️ FCM 토큰이 없습니다.');
      return;
    }

    try {
      print('💾 FCM 토큰 저장 중: $userId');
      
      await _sb
          .from('users')
          .update({'fcm_token': _fcmToken})
          .eq('id', userId);

      print('✅ FCM 토큰 저장 완료');
    } catch (e) {
      print('❌ FCM 토큰 저장 실패: $e');
    }
  }

  /// FCM 토큰 삭제 (로그아웃 시)
  Future<void> deleteFCMToken(String userId) async {
    try {
      print('🗑️ FCM 토큰 삭제 중: $userId');
      
      await _sb
          .from('users')
          .update({'fcm_token': null})
          .eq('id', userId);

      print('✅ FCM 토큰 삭제 완료');
    } catch (e) {
      print('❌ FCM 토큰 삭제 실패: $e');
    }
  }

  /// 백그라운드 메시지 핸들러 (앱 외부에서 처리)
  static Future<void> backgroundMessageHandler(RemoteMessage message) async {
    print('🌙 백그라운드 메시지 수신: ${message.notification?.title}');
    // 여기서는 Supabase에 알림 저장 등의 작업만 가능
    // UI 작업은 불가능
  }
}

/// 백그라운드 메시지 핸들러 (최상위 함수여야 함)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }
  await FCMService.backgroundMessageHandler(message);
}

