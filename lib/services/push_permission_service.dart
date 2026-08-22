import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:app_settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 푸시 알림 권한 요청 서비스
/// - 앱 업데이트 후 / 신규 사용자 로그인 시 권한 안내 다이얼로그 표시
/// - 거부된 경우 시스템 설정으로 안내
class PushPermissionService {
  static const _askedKey = 'push_permission_asked_v1';

  /// 권한 요청이 필요한지 확인하고 필요하면 다이얼로그 표시
  /// [userId]: 권한 허용 시 FCM 토큰을 저장할 사용자 ID
  static Future<void> checkAndRequest(
    BuildContext context, {
    required String userId,
    bool forceShow = false,
  }) async {
    // ── 1. 이미 시스템 권한이 허용된 경우 → 토큰만 저장 후 종료 ──────────
    final currentStatus = await FirebaseMessaging.instance.getNotificationSettings();
    if (currentStatus.authorizationStatus == AuthorizationStatus.authorized) {
      await _saveFCMToken(userId);
      return;
    }

    // ── 2. 이미 영구 거부된 경우 → 설정 안내 다이얼로그 ─────────────────
    if (currentStatus.authorizationStatus == AuthorizationStatus.denied) {
      final prefs = await SharedPreferences.getInstance();
      final alreadyNotified = prefs.getBool('push_denied_notified') ?? false;
      if (!alreadyNotified || forceShow) {
        await prefs.setBool('push_denied_notified', true);
        if (context.mounted) await _showDeniedDialog(context);
      }
      return;
    }

    // ── 3. 아직 물어보지 않은 경우 → 사전 안내 + 시스템 권한 요청 ────────
    final prefs = await SharedPreferences.getInstance();
    final alreadyAsked = prefs.getBool(_askedKey) ?? false;
    if (alreadyAsked && !forceShow) return;

    if (!context.mounted) return;
    final agreed = await _showPrePermissionDialog(context);
    if (!agreed) return;

    // 시스템 권한 요청
    await prefs.setBool(_askedKey, true);
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      await _saveFCMToken(userId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ 알림이 설정되었습니다. 새로운 오더/견적 알림을 받으실 수 있습니다.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } else if (settings.authorizationStatus == AuthorizationStatus.denied) {
      if (context.mounted) await _showDeniedDialog(context);
    }
  }

  /// 앱 최초 실행 여부와 무관하게 권한 상태 확인 (버전 업데이트 등)
  static Future<bool> hasPermission() async {
    final s = await FirebaseMessaging.instance.getNotificationSettings();
    return s.authorizationStatus == AuthorizationStatus.authorized ||
        s.authorizationStatus == AuthorizationStatus.provisional;
  }

  // ── 사전 안내 다이얼로그 ─────────────────────────────────────────────────
  static Future<bool> _showPrePermissionDialog(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B2545).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.notifications_active_rounded,
                    color: Color(0xFF0B2545),
                    size: 34,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '알림을 허용해주세요',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0B2545)),
                ),
                const SizedBox(height: 12),
                const Text(
                  '아래 상황에서 즉시 알림을 받으실 수 있습니다:',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                _buildBenefitRow(
                    Icons.gavel_rounded, '새로운 오더/입찰 등록', Colors.orange),
                _buildBenefitRow(
                    Icons.description_rounded, '견적 요청 도착', Colors.blue),
                _buildBenefitRow(
                    Icons.chat_rounded, '채팅 메시지 수신', Colors.green),
                _buildBenefitRow(
                    Icons.check_circle_rounded, '낙찰/완료 알림', Colors.purple),
                const SizedBox(height: 8),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('나중에',
                    style: TextStyle(color: Colors.grey, fontSize: 14)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0B2545),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                child: const Text('알림 허용하기',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              ),
            ],
          ),
        ) ??
        false;
  }

  // ── 거부 시 설정 안내 다이얼로그 ────────────────────────────────────────
  static Future<void> _showDeniedDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.notifications_off_rounded,
                color: Colors.orange, size: 24),
            SizedBox(width: 8),
            Text('알림이 꺼져 있습니다',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
        content: const Text(
          '새로운 오더·견적·채팅 알림을 받으려면\n기기 설정에서 알림을 허용해주세요.',
          style: TextStyle(fontSize: 14, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              AppSettings.openAppSettings(type: AppSettingsType.notification);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0B2545),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('설정으로 이동'),
          ),
        ],
      ),
    );
  }

  static Widget _buildBenefitRow(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Text(text,
              style: const TextStyle(fontSize: 13, color: Colors.black87)),
        ],
      ),
    );
  }

  // ── FCM 토큰 저장 ───────────────────────────────────────────────────────
  static Future<void> _saveFCMToken(String userId) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || userId.isEmpty) return;
      await Supabase.instance.client
          .from('users')
          .update({'fcm_token': token})
          .eq('id', userId);
      debugPrint('✅ FCM 토큰 저장 완료: $userId');
    } catch (e) {
      debugPrint('⚠️ FCM 토큰 저장 실패: $e');
    }
  }
}
