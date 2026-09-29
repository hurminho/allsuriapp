import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/personal_order_link.dart';
import '../utils/app_logger.dart';
import '../utils/hangul_romanize.dart';

/// 개인 오더 링크 서비스
class PersonalOrderLinkService extends ChangeNotifier {
  final SupabaseClient _sb = Supabase.instance.client;

  /// 현재 사용자의 개인 오더 링크 조회
  Future<PersonalOrderLink?> getMyPersonalOrderLink() async {
    try {
      final userId = _sb.auth.currentUser?.id;
      if (userId == null) {
        AppLog.debug('PersonalOrderLinkService', '로그인되지 않음');
        return null;
      }

      final response = await _sb
          .from('personal_order_links')
          .select()
          .eq('contractor_id', userId)
          .neq('status', 'revoked')
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) return null;

      return PersonalOrderLink.fromMap(Map<String, dynamic>.from(response));
    } catch (e, stack) {
      AppLog.error('PersonalOrderLinkService', e,
          stack: stack, message: '개인 링크 조회 실패');
      return null;
    }
  }

  /// slug로 공개 링크 조회 (익명 사용자 접근 가능).
  /// 정규화 규칙이 바뀌기 전에 발급된 링크도 계속 열리도록
  /// 저장된 slug 원문을 먼저 찾고, 없으면 정규화 값으로 다시 찾습니다.
  Future<PersonalOrderLink?> getPublicLinkBySlug(String slug) async {
    try {
      final rawSlug = slug.trim();

      var response = await _sb
          .from('personal_order_links')
          .select()
          .eq('slug', rawSlug)
          .maybeSingle();

      response ??= await _sb
          .from('personal_order_links')
          .select()
          .eq('slug_normalized', _normalizeSlug(rawSlug))
          .maybeSingle();

      if (response == null) return null;

      return PersonalOrderLink.fromMap(Map<String, dynamic>.from(response));
    } catch (e, stack) {
      AppLog.error('PersonalOrderLinkService', e,
          stack: stack, message: 'slug로 링크 조회 실패');
      return null;
    }
  }

  /// 개인 링크 생성
  Future<PersonalOrderLink?> createPersonalOrderLink({
    required String slug,
    String? displayName,
    String? headline,
    String? introduction,
    List<String>? supportedCategories,
    List<String>? serviceRegions,
    String? profileImageUrl,
  }) async {
    try {
      final userId = _sb.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('로그인이 필요합니다');
      }

      // slug 검증
      final normalizedSlug = _normalizeSlug(slug);
      if (!_isValidSlug(normalizedSlug)) {
        throw Exception('유효하지 않은 링크 주소입니다');
      }

      // slug 가용성 확인
      final isAvailable = await checkSlugAvailability(normalizedSlug);
      if (!isAvailable) {
        throw Exception('이미 사용 중인 링크 주소입니다');
      }

      final data = {
        'contractor_id': userId,
        // 공유 URL에 그대로 쓰이므로 정규화된 영문 slug 를 저장합니다.
        'slug': normalizedSlug,
        'slug_normalized': normalizedSlug,
        'status': 'active',
        'accepts_direct_orders': true,
        if (displayName != null) 'display_name': displayName,
        if (headline != null) 'headline': headline,
        if (introduction != null) 'introduction': introduction,
        if (supportedCategories != null)
          'supported_categories': supportedCategories,
        if (serviceRegions != null) 'service_regions': serviceRegions,
        if (profileImageUrl != null) 'profile_image_url': profileImageUrl,
      };

      final response =
          await _sb.from('personal_order_links').insert(data).select().single();

      AppLog.debug('PersonalOrderLinkService', '개인 링크 생성 성공');
      notifyListeners();
      return PersonalOrderLink.fromMap(Map<String, dynamic>.from(response));
    } catch (e, stack) {
      AppLog.error('PersonalOrderLinkService', e,
          stack: stack, message: '개인 링크 생성 실패');
      rethrow;
    }
  }

  /// 개인 링크 수정
  Future<PersonalOrderLink?> updatePersonalOrderLink({
    required String linkId,
    String? slug,
    String? displayName,
    String? headline,
    String? introduction,
    List<String>? supportedCategories,
    List<String>? serviceRegions,
    String? profileImageUrl,
    String? coverImageUrl,
    bool? acceptsDirectOrders,
  }) async {
    try {
      final data = <String, dynamic>{};

      if (slug != null) {
        final normalizedSlug = _normalizeSlug(slug);
        if (!_isValidSlug(normalizedSlug)) {
          throw Exception('유효하지 않은 링크 주소입니다');
        }

        // 다른 링크에서 이미 사용 중인지 확인
        final isAvailable = await checkSlugAvailability(normalizedSlug, excludeLinkId: linkId);
        if (!isAvailable) {
          throw Exception('이미 사용 중인 링크 주소입니다');
        }

        data['slug'] = normalizedSlug;
        data['slug_normalized'] = normalizedSlug;
      }

      if (displayName != null) data['display_name'] = displayName;
      if (headline != null) data['headline'] = headline;
      if (introduction != null) data['introduction'] = introduction;
      if (supportedCategories != null) {
        data['supported_categories'] = supportedCategories;
      }
      if (serviceRegions != null) {
        data['service_regions'] = serviceRegions;
      }
      if (profileImageUrl != null) {
        data['profile_image_url'] = profileImageUrl;
      }
      if (coverImageUrl != null) {
        data['cover_image_url'] = coverImageUrl;
      }
      if (acceptsDirectOrders != null) {
        data['accepts_direct_orders'] = acceptsDirectOrders;
      }

      if (data.isEmpty) {
        throw Exception('수정할 내용이 없습니다');
      }

      final response = await _sb
          .from('personal_order_links')
          .update(data)
          .eq('id', linkId)
          .select()
          .single();

      AppLog.debug('PersonalOrderLinkService', '개인 링크 수정 성공');
      notifyListeners();
      return PersonalOrderLink.fromMap(Map<String, dynamic>.from(response));
    } catch (e, stack) {
      AppLog.error('PersonalOrderLinkService', e,
          stack: stack, message: '개인 링크 수정 실패');
      rethrow;
    }
  }

  /// 개인 링크 상태 변경
  Future<void> updateLinkStatus(
      String linkId, PersonalOrderLinkStatus status) async {
    try {
      await _sb
          .from('personal_order_links')
          .update({
            'status': status.value,
            if (status == PersonalOrderLinkStatus.revoked)
              'revoked_at': DateTime.now().toIso8601String(),
          })
          .eq('id', linkId);

      AppLog.debug('PersonalOrderLinkService', '링크 상태 변경: ${status.value}');
      notifyListeners();
    } catch (e, stack) {
      AppLog.error('PersonalOrderLinkService', e,
          stack: stack, message: '링크 상태 변경 실패');
      rethrow;
    }
  }

  /// slug 가용성 확인
  Future<bool> checkSlugAvailability(String slug, {String? excludeLinkId}) async {
    try {
      final normalizedSlug = _normalizeSlug(slug);

      // 예약어 확인
      final reservedCheck = await _sb
          .from('reserved_slugs')
          .select('slug')
          .eq('slug', normalizedSlug)
          .maybeSingle();

      if (reservedCheck != null) {
        return false;
      }

      // 이미 사용 중인지 확인
      var query = _sb
          .from('personal_order_links')
          .select('id')
          .eq('slug_normalized', normalizedSlug);

      if (excludeLinkId != null) {
        query = query.neq('id', excludeLinkId);
      }

      final existingLink = await query.maybeSingle();

      return existingLink == null;
    } catch (e, stack) {
      AppLog.error('PersonalOrderLinkService', e,
          stack: stack, message: 'slug 가용성 확인 실패');
      return false;
    }
  }

  /// 분석 이벤트 기록
  Future<void> trackEvent({
    required String personalOrderLinkId,
    required PersonalOrderLinkEventType eventType,
    String? anonymousSessionId,
    String? utmSource,
    String? utmMedium,
    String? utmCampaign,
    String? referrerDomain,
  }) async {
    try {
      final data = {
        'personal_order_link_id': personalOrderLinkId,
        'event_type': eventType.value,
        if (anonymousSessionId != null)
          'anonymous_session_id': anonymousSessionId,
        if (utmSource != null) 'utm_source': utmSource,
        if (utmMedium != null) 'utm_medium': utmMedium,
        if (utmCampaign != null) 'utm_campaign': utmCampaign,
        if (referrerDomain != null) 'referrer_domain': referrerDomain,
      };

      await _sb.from('personal_order_link_events').insert(data);

      // 로그는 남기지 않음 (개인정보 수집 안 함)
    } catch (e) {
      // 분석 이벤트 실패는 조용히 무시
      AppLog.debug('PersonalOrderLinkService', '이벤트 기록 실패 (무시됨)');
    }
  }

  /// 개인 링크 통계 조회
  Future<PersonalOrderLinkStats> getStats(
      String personalOrderLinkId, DateTime since) async {
    try {
      // 이벤트 통계
      final events = await _sb
          .from('personal_order_link_events')
          .select('event_type')
          .eq('personal_order_link_id', personalOrderLinkId)
          .gte('created_at', since.toIso8601String());

      int pageViews = 0;
      int quoteStarts = 0;
      int quoteSubmissions = 0;

      for (final event in events) {
        final type = event['event_type'] as String?;
        if (type == 'page_view') pageViews++;
        if (type == 'quote_start') quoteStarts++;
        if (type == 'quote_submitted') quoteSubmissions++;
      }

      // 직접 오더 통계
      final orders = await _sb
          .from('orders')
          .select('status, created_at')
          .eq('personal_order_link_id', personalOrderLinkId)
          .gte('created_at', since.toIso8601String());

      int pendingOrders = 0;
      int completedOrders = 0;

      for (final order in orders) {
        final status = order['status'] as String?;
        if (status == 'pending') pendingOrders++;
        if (status == 'completed') completedOrders++;
      }

      // 응답률 계산 (간략화)
      final responseRate = orders.isEmpty ? 0.0 : (orders.length - pendingOrders) / orders.length * 100;

      return PersonalOrderLinkStats(
        pageViews: pageViews,
        quoteStarts: quoteStarts,
        quoteSubmissions: quoteSubmissions,
        pendingOrders: pendingOrders,
        responseRate: responseRate,
        completedOrders: completedOrders,
      );
    } catch (e, stack) {
      AppLog.error('PersonalOrderLinkService', e,
          stack: stack, message: '통계 조회 실패');
      return PersonalOrderLinkStats();
    }
  }

  /// 직접 배정 오더 목록 조회
  Future<List<Map<String, dynamic>>> getDirectOrders({
    required String contractorId,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _sb
          .from('orders')
          .select()
          .eq('routing_type', 'personal_link')
          .eq('assigned_contractor_id', contractorId)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return response.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e, stack) {
      AppLog.error('PersonalOrderLinkService', e,
          stack: stack, message: '직접 오더 조회 실패');
      return [];
    }
  }

  /// slug 정규화.
  /// 한글은 로마자로 바꿔 남깁니다. 단순히 지워버리면 상호가 다른 사업자끼리
  /// 같은 값으로 뭉개져(예: '서문페인트_9967' → '_9967') 충돌하기 때문입니다.
  String _normalizeSlug(String slug) {
    final romanized = romanizeHangul(slug.trim()).toLowerCase();
    return romanized
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  /// slug 유효성 검사
  bool _isValidSlug(String slug) {
    if (slug.length < 3 || slug.length > 50) return false;
    return RegExp(r'^[a-z0-9_-]+$').hasMatch(slug);
  }

  /// 사업자명 기반 slug 제안 생성.
  /// 공유 링크가 퍼센트 인코딩으로 깨지지 않도록 항상 영문·숫자만 만듭니다.
  String generateSuggestedSlug(String businessName) {
    final random = DateTime.now().millisecondsSinceEpoch % 10000;
    return '${buildSlugBase(businessName)}-$random';
  }

  /// 마지막 공유 시간 업데이트
  Future<void> updateLastShared(String linkId) async {
    try {
      await _sb.from('personal_order_links').update({
        'last_shared_at': DateTime.now().toIso8601String(),
      }).eq('id', linkId);
    } catch (e) {
      // 실패해도 무시
    }
  }
}
