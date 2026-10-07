import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'dart:convert';

/// 로컬 알림 전용 서비스
/// 
/// flutter_local_notifications를 사용하여 로컬 알림을 표시하고 관리합니다.
/// 각 알림에는 "바로가기" 버튼이 포함되며, 클릭 시 해당 화면으로 이동합니다.
class LocalNotificationService {
  static final LocalNotificationService _instance = LocalNotificationService._internal();
  factory LocalNotificationService() => _instance;
  LocalNotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  
  // 알림 클릭 콜백
  Function(String? payload)? onNotificationTapped;
  
  bool _initialized = false;

  /// 초기화
  Future<void> initialize({Function(String? payload)? onSelectNotification}) async {
    if (_initialized) return;
    
    try {
      // Timezone 초기화
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
      
      // Android 초기화 설정 (앱 아이콘과 동일한 이름 사용)
      const AndroidInitializationSettings androidInitSettings =
          AndroidInitializationSettings('@mipmap/launcher_icon');
      
      // iOS 초기화 설정
      const DarwinInitializationSettings iosInitSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      
      // 초기화 설정
      const InitializationSettings initSettings = InitializationSettings(
        android: androidInitSettings,
        iOS: iosInitSettings,
      );
      
      // 초기화 및 콜백 등록
      await _flutterLocalNotificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          print('🔔 [LocalNotification] 알림 탭됨: ${response.payload}');
          if (response.payload != null) {
            onNotificationTapped?.call(response.payload);
            onSelectNotification?.call(response.payload);
          }
        },
      );
      
      _initialized = true;
      print('✅ [LocalNotification] 초기화 완료');
    } catch (e) {
      print('❌ [LocalNotification] 초기화 실패: $e');
    }
  }

  /// 새 오더 알림 표시
  /// 
  /// 예: "천안 지역에 새로운 오더가 들어왔어요!"
  Future<void> showNewOrderNotification({
    required String region,
    required String jobTitle,
    required String jobId,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'allsuri_notifications',
      '올수리 알림',
      channelDescription: '올수리 앱의 알림을 받습니다',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(''),
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'view',
          '바로가기',
          showsUserInterface: true,
        ),
      ],
    );
    
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    final payload = jsonEncode({
      'type': 'new_order',
      'jobId': jobId,
      'screen': 'order_marketplace',
    });
    
    await _flutterLocalNotificationsPlugin.show(
      jobId.hashCode,
      '$region 지역에 새로운 오더가 들어왔어요!',
      jobTitle,
      details,
      payload: payload,
    );
    
    print('✅ [LocalNotification] 새 오더 알림 표시: $jobTitle');
  }

  /// 공사 완료 알림 표시
  /// 
  /// 예: "공사가 완료되었습니다. 오더를 확인하고 후기를 입력해주세요"
  Future<void> showJobCompletedNotification({
    required String jobTitle,
    required String jobId,
    required String listingId,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'allsuri_notifications',
      '올수리 알림',
      channelDescription: '올수리 앱의 알림을 받습니다',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(''),
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'view',
          '바로가기',
          showsUserInterface: true,
        ),
      ],
    );
    
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    final payload = jsonEncode({
      'type': 'job_completed',
      'jobId': jobId,
      'listingId': listingId,
      'screen': 'review',
    });
    
    await _flutterLocalNotificationsPlugin.show(
      jobId.hashCode + 1000, // Unique ID
      '공사가 완료되었습니다',
      '오더를 확인하고 후기를 입력해주세요: $jobTitle',
      details,
      payload: payload,
    );
    
    print('✅ [LocalNotification] 공사 완료 알림 표시: $jobTitle');
  }

  /// 채팅 시작 알림 표시
  /// 
  /// 예: "낙찰된 오더를 위해 사업자와의 채팅이 시작됩니다"
  Future<void> showChatStartNotification({
    required String jobTitle,
    required String chatRoomId,
    required String otherUserName,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'allsuri_notifications',
      '올수리 알림',
      channelDescription: '올수리 앱의 알림을 받습니다',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(''),
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'view',
          '바로가기',
          showsUserInterface: true,
        ),
      ],
    );
    
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    final payload = jsonEncode({
      'type': 'chat_start',
      'chatRoomId': chatRoomId,
      'screen': 'chat',
    });
    
    await _flutterLocalNotificationsPlugin.show(
      chatRoomId.hashCode,
      '낙찰된 오더를 위해 $otherUserName님과의 채팅이 시작됩니다',
      jobTitle,
      details,
      payload: payload,
    );
    
    print('✅ [LocalNotification] 채팅 시작 알림 표시: $jobTitle');
  }

  /// 입찰 알림 표시
  /// 
  /// 예: "새로운 입찰자가 있습니다"
  Future<void> showNewBidNotification({
    required String jobTitle,
    required String bidderName,
    required String jobId,
    required String listingId,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'allsuri_notifications',
      '올수리 알림',
      channelDescription: '올수리 앱의 알림을 받습니다',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(''),
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'view',
          '바로가기',
          showsUserInterface: true,
        ),
      ],
    );
    
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    final payload = jsonEncode({
      'type': 'new_bid',
      'jobId': jobId,
      'listingId': listingId,
      'screen': 'bidders',
    });
    
    await _flutterLocalNotificationsPlugin.show(
      (jobId + bidderName).hashCode,
      '새로운 입찰자가 있습니다',
      '$bidderName님이 "$jobTitle"에 입찰했습니다',
      details,
      payload: payload,
    );
    
    print('✅ [LocalNotification] 입찰 알림 표시: $bidderName');
  }

  /// 일반 알림 표시
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'allsuri_notifications',
      '올수리 알림',
      channelDescription: '올수리 앱의 알림을 받습니다',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(''),
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'view',
          '바로가기',
          showsUserInterface: true,
        ),
      ],
    );
    
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    await _flutterLocalNotificationsPlugin.show(
      id,
      title,
      body,
      details,
      payload: payload,
    );
    
    print('✅ [LocalNotification] 일반 알림 표시: $title');
  }

  /// 모든 알림 취소
  Future<void> cancelAll() async {
    await _flutterLocalNotificationsPlugin.cancelAll();
  }

  /// 특정 알림 취소
  Future<void> cancel(int id) async {
    await _flutterLocalNotificationsPlugin.cancel(id);
  }

  /// 권한 요청 (iOS)
  Future<bool> requestPermissions() async {
    final result = await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
    
    return result ?? false;
  }
}

