import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_logger.dart';

/// 광고성 정보 수신 동의 안내 문구. 웹 동의 페이지(allsuri-web lib/marketing-consent-notice.ts)와 같은 내용입니다.
abstract final class MarketingConsentNotice {
  static const sender = '올수리';
  static const purpose = '올수리와 올수리가 함께 운영하는 서비스의 새 기능·이벤트·혜택 안내';
  static const items = '휴대폰 번호, 이름(상호)';
  static const channels = '문자(SMS·LMS), 앱 푸시';
  static const retention = '동의를 철회하거나 탈퇴할 때까지';
  static const refusal = '동의하지 않아도 올수리의 모든 기능을 그대로 이용할 수 있습니다.';
  static const webUrl = 'https://allsuri.app/consent';
}

class MarketingConsentState {
  final bool consent;
  final bool night;
  final DateTime? consentAt;
  final DateTime? withdrawnAt;
  final DateTime? askedAt;

  const MarketingConsentState({
    required this.consent,
    required this.night,
    this.consentAt,
    this.withdrawnAt,
    this.askedAt,
  });

  static DateTime? _date(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

  factory MarketingConsentState.fromRow(Map<String, dynamic> row) =>
      MarketingConsentState(
        consent: row['marketing_consent'] == true,
        night: row['marketing_night_consent'] == true,
        consentAt: _date(row['marketing_consent_at']),
        withdrawnAt: _date(row['marketing_withdrawn_at']),
        askedAt: _date(row['marketing_consent_asked_at']),
      );
}

/// 본인 users 행의 동의 칸만 바꿉니다. 동의 일자·이력·처리 결과 알림은 DB 트리거가 처리합니다
/// (database/marketing_consent_2026_10.sql). SQL 실행 전이면 조회가 실패하므로 null 을 돌려줍니다.
class MarketingConsentService {
  static const _columns =
      'marketing_consent, marketing_night_consent, marketing_consent_at, marketing_withdrawn_at, marketing_consent_asked_at';

  SupabaseClient get _sb => Supabase.instance.client;

  Future<MarketingConsentState?> load(String userId) async {
    try {
      final row = await _sb.from('users').select(_columns).eq('id', userId).maybeSingle();
      return row == null ? null : MarketingConsentState.fromRow(row);
    } catch (e) {
      AppLog.warn('MarketingConsent', '동의 상태 조회 실패: $e');
      return null;
    }
  }

  Future<MarketingConsentState?> save(
    String userId, {
    required bool consent,
    bool night = false,
  }) async {
    try {
      final row = await _sb
          .from('users')
          .update({
            'marketing_consent': consent,
            'marketing_night_consent': consent && night,
            'marketing_consent_channel': 'app',
            'marketing_consent_asked_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', userId)
          .select(_columns)
          .single();
      return MarketingConsentState.fromRow(row);
    } catch (e) {
      AppLog.warn('MarketingConsent', '동의 저장 실패: $e');
      return null;
    }
  }

  /// 처음 안내에서 '괜찮아요'를 고른 경우. 동의 상태는 그대로 두고 다시 묻지 않게만 합니다.
  Future<void> markAsked(String userId) async {
    try {
      await _sb.from('users').update({
        'marketing_consent_asked_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', userId);
    } catch (e) {
      AppLog.warn('MarketingConsent', '안내 기록 실패: $e');
    }
  }
}
