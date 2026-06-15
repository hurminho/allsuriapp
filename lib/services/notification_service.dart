import 'dart:async' show unawaited;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'api_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final SupabaseClient _sb = Supabase.instance.client;
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  
  // 알림 권한 상태 저장용
  static const String _notificationPermissionKey = 'notification_permission';

  /// 초기화
  Future<void> initialize() async {
    try {
      // 알림 권한 요청 (iOS)
      await _requestNotificationPermissions();
      print('NotificationService 초기화 완료');
    } catch (e) {
      print('NotificationService 초기화 실패: $e');
    }
  }

  /// 알림 권한 요청 (iOS)
  Future<void> _requestNotificationPermissions() async {
    try {
      // iOS 권한 요청은 단순화 (실제로는 필요시에만 구현)
      print('알림 권한 요청 완료');
    } catch (e) {
      print('알림 권한 요청 실패: $e');
    }
  }

  /// 알림 목록 가져오기
  Future<List<Map<String, dynamic>>> getNotifications(String userId) async {
    try {
      debugPrint('🔍 [NotificationService] 알림 조회: userId=$userId');

      // 1차: 백엔드 API (service role)로 조회
      try {
        final api = ApiService();
        final apiResponse = await api.get('/notifications?userId=$userId');
        if (apiResponse['success'] == true) {
          final data = List<Map<String, dynamic>>.from(apiResponse['data'] ?? []);
          debugPrint('✅ [NotificationService] API에서 ${data.length}개 알림 조회');
          if (data.isNotEmpty) {
            debugPrint('   첫 번째 알림(API): ${data.first}');
          }
          return data;
        } else {
          debugPrint('⚠️ [NotificationService] API 조회 실패: ${apiResponse['error']}');
        }
      } catch (apiError) {
        debugPrint('⚠️ [NotificationService] API 조회 예외: $apiError');
      }
      
      // 2차: Supabase 직접 조회 (세션이 유효한 경우)
      final response = await _sb
          .from('notifications')
          .select()
          .eq('userid', userId)
          .order('createdat', ascending: false);
      
      debugPrint('✅ [NotificationService] ${response.length}개 알림 조회 완료 (Supabase)');
      
      if (response.isNotEmpty) {
        debugPrint('   첫 번째 알림: ${response.first}');
      }
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ [NotificationService] 알림 목록 가져오기 실패: $e');
      return [];
    }
  }

  /// 읽지 않은 알림 개수 가져오기
  Future<int> getUnreadCount(String userId) async {
    try {
      print('🔍 [NotificationService] 읽지 않은 알림 개수 조회 중...');
      print('   userId: $userId');
      
      final response = await _sb
          .from('notifications')
          .select('id, title, type, isread')
          .eq('userid', userId)
          .eq('isread', false);
      
      print('✅ [NotificationService] 읽지 않은 알림: ${response.length}개');
      if (response.isNotEmpty) {
        print('   알림 목록:');
        for (var notif in response) {
          print('   - ${notif['title']} (type: ${notif['type']})');
        }
      }
      
      return response.length;
    } catch (e) {
      print('❌ [NotificationService] 읽지 않은 알림 개수 가져오기 실패: $e');
      return 0;
    }
  }

  /// 읽지 않은 알림 개수 실시간 스트림
  Stream<int> getUnreadCountStream(String userId) {
    if (userId.isEmpty) {
      return Stream.value(0);
    }
    
    return _sb
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('userid', userId)
        .map((data) {
          // isread가 false인 것만 필터링
          return data.where((item) => item['isread'] == false).length;
        });
  }

  /// 읽지 않은 채팅 메시지 총 개수 (모든 채팅방의 읽지 않은 메시지 합계)
  ///
  /// 성능: 방마다 쿼리하던 N+1 패턴을 2쿼리로 축소.
  /// 1) 사용자의 활성 채팅방 + 각 방의 last_read 조회
  /// 2) 모든 방의 상대방 메시지를 inFilter 로 한 번에 조회 후 클라이언트 집계
  Future<int> getUnreadChatCount(String userId) async {
    if (userId.isEmpty) return 0;
    try {
      final rooms = await _sb
          .from('chat_rooms')
          .select('id, participant_a, participant_b, participant_a_last_read_at, participant_b_last_read_at')
          .or('participant_a.eq.$userId,participant_b.eq.$userId')
          .eq('active', true);

      if (rooms.isEmpty) return 0;

      // roomId -> 내가 마지막으로 읽은 시각(없으면 null)
      final Map<String, DateTime?> lastReadByRoom = {};
      for (final room in rooms) {
        final roomId = room['id']?.toString();
        if (roomId == null) continue;
        final isParticipantA = room['participant_a']?.toString() == userId;
        final lastReadRaw = isParticipantA
            ? room['participant_a_last_read_at']
            : room['participant_b_last_read_at'];
        DateTime? lastRead;
        if (lastReadRaw != null) {
          lastRead = DateTime.tryParse(lastReadRaw.toString());
        }
        lastReadByRoom[roomId] = lastRead;
      }

      final roomIds = lastReadByRoom.keys.toList();

      // 상대방이 보낸 메시지만 한 번에 조회 (room_id, createdat)
      final messages = await _sb
          .from('chat_messages')
          .select('room_id, createdat, sender_id')
          .inFilter('room_id', roomIds)
          .neq('sender_id', userId);

      int totalUnread = 0;
      for (final msg in messages) {
        final roomId = msg['room_id']?.toString();
        if (roomId == null) continue;
        final lastRead = lastReadByRoom[roomId];
        if (lastRead == null) {
          // 한 번도 안 읽은 방: 상대방 메시지 전부 미읽음
          totalUnread++;
          continue;
        }
        final createdAt = DateTime.tryParse(msg['createdat']?.toString() ?? '');
        if (createdAt != null && createdAt.isAfter(lastRead)) {
          totalUnread++;
        }
      }

      return totalUnread;
    } catch (e) {
      debugPrint('❌ [NotificationService] 읽지 않은 채팅 메시지 개수 가져오기 실패: $e');
      return 0;
    }
  }

  /// 알림을 읽음으로 표시
  Future<void> markAsRead(String notificationId) async {
    try {
      await _sb
          .from('notifications')
          .update({'isread': true})
          .eq('id', notificationId);
    } catch (e) {
      print('알림 읽음 표시 실패: $e');
    }
  }

  /// 모든 알림을 읽음으로 표시
  Future<void> markAllAsRead(String userId) async {
    try {
      await _sb
          .from('notifications')
          .update({'isread': true})
          .eq('userid', userId)
          .eq('isread', false);
    } catch (e) {
      print('모든 알림 읽음 표시 실패: $e');
    }
  }

  /// 알림 삭제
  Future<bool> deleteNotification(String notificationId) async {
    try {
      print('🗑️ [NotificationService] 알림 삭제: $notificationId');
      await _sb
          .from('notifications')
          .delete()
          .eq('id', notificationId);
      print('✅ [NotificationService] 알림 삭제 완료');
      return true;
    } catch (e) {
      print('❌ [NotificationService] 알림 삭제 실패: $e');
      return false;
    }
  }

  /// 알림 전송: Supabase DB 저장 + Netlify Function 통해 FCM 푸시
  Future<void> sendNotification({
    required String userId,
    required String title,
    required String body,
    String? type,
    String? jobId,
    String? jobTitle,
    String? region,
    String? orderId,
    String? estimateId,
    String? chatRoomId,
  }) async {
    // 1. Supabase DB에 알림 저장 (앱 내 알림 센터용)
    try {
      final insertData = {
        'userid': userId,
        'title': title,
        'body': body,
        'type': type,
        'isread': false,
        'createdat': DateTime.now().toIso8601String(),
        if (jobId != null && jobId.isNotEmpty) 'jobid': jobId,
        if (jobTitle != null && jobTitle.isNotEmpty) 'jobtitle': jobTitle,
        if (region != null && region.isNotEmpty) 'region': region,
        if (orderId != null && orderId.isNotEmpty) 'orderid': orderId,
        if (estimateId != null && estimateId.isNotEmpty) 'estimateid': estimateId,
        if (chatRoomId != null && chatRoomId.isNotEmpty) 'chatroom_id': chatRoomId,
      };
      await _sb.from('notifications').insert(insertData);
      debugPrint('✅ [NotificationService] DB 저장 완료: $userId - $title');
    } catch (e) {
      debugPrint('❌ [NotificationService] DB 저장 실패: $e');
      rethrow;
    }

    // 2. FCM 푸시 전송 (백엔드 API 호출)
    final pushData = <String, String?>{
      if (type != null) 'type': type,
      if (jobId != null) 'jobId': jobId,
      if (jobTitle != null) 'jobTitle': jobTitle,
      if (region != null) 'region': region,
      if (orderId != null) 'orderId': orderId,
      if (estimateId != null) 'estimateId': estimateId,
      if (chatRoomId != null) 'chatRoomId': chatRoomId,
    };
    unawaited(_sendFCMPush(
      userId: userId,
      title: title,
      body: body,
      data: pushData,
    ));
  }

  /// 일괄 알림 전송: DB 저장 + FCM 푸시를 서버에서 처리 (앱 1회 API 호출)
  /// - Netlify 403/Bot Protection 회피: 앱→서버 1회, 서버가 내부에서 FCM 전송
  Future<Map<String, int>> sendBulkNotification({
    required List<String> userIds,
    required String title,
    required String body,
    String? type,
    String? orderId,
    String? jobTitle,
    String? region,
  }) async {
    if (userIds.isEmpty) {
      return {'total': 0, 'sent': 0, 'failed': 0};
    }

    try {
      final sessionToken = _sb.auth.currentSession?.accessToken;
      final bearerToken = sessionToken ?? ApiService.currentBearerToken;

      if (bearerToken == null || bearerToken.isEmpty) {
        debugPrint('⚠️ [FCM Bulk] 인증 토큰 없음 - 푸시 스킵');
        return {'total': userIds.length, 'sent': 0, 'failed': userIds.length};
      }

      const apiBase = String.fromEnvironment('API_BASE_URL',
          defaultValue: 'https://api.allsuri.app/api');
      final url = Uri.parse('$apiBase/notifications/send-bulk');

      final data = <String, String>{};
      if (type != null) data['type'] = type;
      if (orderId != null) data['orderId'] = orderId;
      if (jobTitle != null) data['jobTitle'] = jobTitle;
      if (region != null) data['region'] = region;

      debugPrint('📤 [FCM Bulk] 요청 → $url 수신자 ${userIds.length}명');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $bearerToken',
          'User-Agent': 'AllSuriApp/1.0 (Flutter; Mobile)',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'userIds': userIds,
          'title': title,
          'body': body,
          'data': data,
        }),
      ).timeout(const Duration(seconds: 120));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        final total = result['total'] as int? ?? userIds.length;
        final sent = result['sent'] as int? ?? 0;
        final failed = result['failed'] as int? ?? 0;
        debugPrint('✅ [FCM Bulk] 완료: total=$total, sent=$sent, failed=$failed');
        return {'total': total, 'sent': sent, 'failed': failed};
      } else {
        debugPrint('❌ [FCM Bulk] 서버 오류 ${response.statusCode}: ${response.body}');
        return {'total': userIds.length, 'sent': 0, 'failed': userIds.length};
      }
    } catch (e) {
      debugPrint('❌ [FCM Bulk] 예외: $e');
      return {'total': userIds.length, 'sent': 0, 'failed': userIds.length};
    }
  }

  /// Netlify Function(/api/notifications/send-push)으로 FCM 푸시 전송
  /// - 비동기 fire-and-forget: 실패해도 앱 흐름에 영향 없음
  Future<void> _sendFCMPush({
    required String userId,
    required String title,
    required String body,
    Map<String, String?> data = const {},
  }) async {
    try {
      // 세션 또는 ApiService 베어러 토큰 사용 (Kakao 로그인 시 세션이 null일 수 있음)
      final sessionToken = _sb.auth.currentSession?.accessToken;
      final bearerToken = sessionToken ?? ApiService.currentBearerToken;

      if (bearerToken == null || bearerToken.isEmpty) {
        debugPrint('⚠️ [FCM Push] 인증 토큰 없음 - 푸시 스킵');
        debugPrint('   currentSession: ${_sb.auth.currentSession != null ? "있음" : "없음"}');
        debugPrint('   ApiService.currentBearerToken: ${ApiService.currentBearerToken != null ? "있음(${ApiService.currentBearerToken!.substring(0, 10)}...)" : "없음"}');
        return;
      }

      const apiBase = String.fromEnvironment('API_BASE_URL',
          defaultValue: 'https://api.allsuri.app/api');
      final url = Uri.parse('$apiBase/notifications/send-push');

      // data 값 중 null 제거
      final safeData = <String, String>{};
      data.forEach((k, v) { if (v != null) safeData[k] = v; });

      print('📤 [FCM Push] 요청 → $url 수신자: $userId');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $bearerToken',
          'User-Agent': 'AllSuriApp/1.0 (Flutter; Mobile)',
          'X-App-Version': '1.0',
          'Accept': 'application/json',
        },
        // Netlify Function은 { userId, title, body, data } 플랫 형식 기대
        body: jsonEncode({
          'userId': userId,
          'title': title,
          'body': body,
          'data': safeData,
        }),
      ).timeout(const Duration(seconds: 30));

      print('📥 [FCM Push] 응답 ${response.statusCode}: ${response.body}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        // API 응답: { sent: true, messageId } 또는 { sent: false, reason }
        if (result['sent'] == true) {
          print('✅ [FCM Push] 전송 성공: $userId');
        } else {
          final reason = result['reason'] ?? result['message'] ?? 'unknown';
          print('⚠️ [FCM Push] 전송 실패: $reason');
        }
      } else {
        final body = response.body;
        final reason = body.length > 200 ? '${body.substring(0, 200)}...' : body;
        print('❌ [FCM Push] 서버 오류 ${response.statusCode}: $reason');
      }
    } catch (e) {
      print('❌ [FCM Push] 예외: $e');
    }
  }

  /// 채팅 메시지 알림 전송
  Future<void> sendChatNotification({
    required String recipientUserId,
    required String senderName,
    required String message,
    required String chatRoomId,
  }) async {
    try {
      if (recipientUserId.isEmpty) {
        print('📩 [sendChatNotification] 수신자 ID 없음, 알림 스킵');
        return;
      }
      print('📩 [sendChatNotification] 채팅 알림 전송 시작');
      print('   수신자: $recipientUserId');
      print('   발신자: $senderName');
      print('   메시지: $message');
      print('   채팅방: $chatRoomId');
      
      // 1. Supabase에 알림 저장
      await sendNotification(
        userId: recipientUserId,
        title: '$senderName님의 메시지',
        body: message,
        type: 'chat_message',
        chatRoomId: chatRoomId,
      );
      
      print('✅ [sendChatNotification] 채팅 알림 저장 완료');

      // 2. Supabase Edge Function으로 FCM 전송 시도 (일시 비활성화)
      // TODO: Edge Function 배포 후 활성화
      /*
      try {
        await _sendFCMViaEdgeFunction(
          recipientUserId: recipientUserId,
          senderName: senderName,
          message: message,
          chatRoomId: chatRoomId,
        );
      } catch (e) {
        print('FCM 전송 실패 (무시됨): $e');
        // FCM 실패해도 Supabase 알림은 성공
      }
      */
      
      print('FCM 전송은 일시 비활성화됨 (Edge Function 미배포)');
      
      print('채팅 알림 전송 완료: $recipientUserId');
    } catch (e) {
      print('채팅 알림 전송 실패: $e');
    }
  }

  /// Supabase Edge Function으로 FCM 전송
  Future<void> _sendFCMViaEdgeFunction({
    required String recipientUserId,
    required String senderName,
    required String message,
    required String chatRoomId,
  }) async {
    try {
      final response = await _sb.functions.invoke(
        'send-chat-notification',
        body: {
          'recipientUserId': recipientUserId,
          'senderName': senderName,
          'message': message,
          'chatRoomId': chatRoomId,
        },
      );
      
      if (response.status != 200) {
        throw Exception('Edge Function 호출 실패: ${response.status}');
      }
      
      print('FCM 전송 성공 (Edge Function)');
    } catch (e) {
      print('Edge Function FCM 전송 실패: $e');
      rethrow;
    }
  }

  /// 배지 카운트 업데이트 (앱 아이콘에 표시)
  Future<void> updateBadgeCount(int count) async {
    try {
      // Android/iOS 배지 업데이트 로직
      // 실제 구현은 플랫폼별로 다를 수 있음
      print('배지 카운트 업데이트: $count');
    } catch (e) {
      print('배지 카운트 업데이트 실패: $e');
    }
  }

  /// 알림 설정 상태 확인
  Future<bool> isNotificationEnabled() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_notificationPermissionKey) ?? true;
    } catch (e) {
      print('알림 설정 상태 확인 실패: $e');
      return true;
    }
  }

  /// 알림 설정 상태 저장
  Future<void> setNotificationEnabled(bool enabled) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_notificationPermissionKey, enabled);
    } catch (e) {
      print('알림 설정 상태 저장 실패: $e');
    }
  }

  /// 사용자별 알림 모두 삭제
  Future<void> deleteAllNotifications(String userId) async {
    try {
      await _sb
          .from('notifications')
          .delete()
          .eq('userid', userId);
    } catch (e) {
      print('사용자 알림 모두 삭제 실패: $e');
    }
  }

  /// 로컬 푸시 알림 표시 (오더 추가 시)
  Future<void> showNewJobNotification({
    required String title,
    required String body,
    required String jobId,
  }) async {
    try {
      print('🔔 [NotificationService] 로컬 알림 표시: $title');
      
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'order_jobs_channel',
        '오더 알림',
        channelDescription: '새로운 오더 등록 알림',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        fullScreenIntent: true,
      );
      
      const DarwinNotificationDetails iosPlatformChannelSpecifics =
          DarwinNotificationDetails(
        sound: 'default',
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      
      const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iosPlatformChannelSpecifics,
      );
      
      await _flutterLocalNotificationsPlugin.show(
        jobId.hashCode, // notification ID (unique per job)
        title,
        body,
        platformChannelSpecifics,
        payload: jobId, // payload to handle tap
      );
      
      print('✅ [NotificationService] 알림 표시 완료');
    } catch (e) {
      print('❌ [NotificationService] 알림 표시 실패: $e');
    }
  }

  /// FCM 토큰 초기화 및 저장
  Future<void> initializeFCM(String userId) async {
    try {
      print('🔔 [NotificationService] FCM 초기화 시작');
      
      // FCM 권한 요청
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      
      print('   FCM 권한 상태: ${settings.authorizationStatus}');
      
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        // FCM 토큰 가져오기
        final token = await messaging.getToken();
        print('   FCM 토큰: ${token?.substring(0, 20)}...');
        
        if (token != null) {
          // Supabase에 토큰 저장
          await _sb.from('users').update({
            'fcm_token': token,
          }).eq('id', userId);
          
          print('✅ [NotificationService] FCM 토큰 저장 완료');
          
          // 토큰 갱신 리스너
          messaging.onTokenRefresh.listen((newToken) {
            print('🔄 [NotificationService] FCM 토큰 갱신: ${newToken.substring(0, 20)}...');
            _sb.from('users').update({
              'fcm_token': newToken,
            }).eq('id', userId);
          });
        }
        
        // 포그라운드 메시지 리스너
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          print('🔔 [NotificationService] 포그라운드 메시지 수신');
          print('   제목: ${message.notification?.title}');
          print('   내용: ${message.notification?.body}');
          
          // 로컬 알림으로 표시
          if (message.notification != null) {
            showNewJobNotification(
              title: message.notification!.title ?? '새 알림',
              body: message.notification!.body ?? '',
              jobId: message.data['jobId'] ?? 'unknown',
            );
          }
        });
        
        // 백그라운드 메시지 탭 리스너
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
          print('🔔 [NotificationService] 백그라운드 메시지 탭');
          print('   데이터: ${message.data}');
          // TODO: 알림 타입에 따라 적절한 화면으로 이동
        });
      } else {
        print('❌ [NotificationService] FCM 권한 거부됨');
      }
    } catch (e) {
      print('❌ [NotificationService] FCM 초기화 실패: $e');
    }
  }

  /// FCM 토큰 가져오기
  Future<String?> getFCMToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      return token;
    } catch (e) {
      print('❌ [NotificationService] FCM 토큰 가져오기 실패: $e');
      return null;
    }
  }
}


