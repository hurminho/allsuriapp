import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/feature_flags.dart';
import '../models/ad.dart';

class AdService {
  final SupabaseClient _sb = Supabase.instance.client;

  // 특정 위치의 활성 광고 조회
  Future<List<Ad>> getAdsByLocation(String location) async {
    if (!FeatureFlags.adsEnabled) return [];
    try {
      final response = await _sb
          .from('ads')
          .select()
          .eq('is_active', true)
          .eq('location', location)
          .order('created_at', ascending: false);

      final data = List<Map<String, dynamic>>.from(response);
      return data.map((json) => Ad.fromJson(json)).toList();
    } catch (e) {
      print('❌ [AdService] 광고 로드 실패 ($location): $e');
      return [];
    }
  }

  // 기존 메서드 유지 (대시보드 호환용, 기본값 dashboard_banner)
  Future<List<Ad>> getActiveAds() async {
    return getAdsByLocation('dashboard_banner');
  }

  // [관리자용] 모든 광고 조회
  Future<List<Ad>> getAllAds() async {
    try {
      final response = await _sb
          .from('ads')
          .select()
          .order('created_at', ascending: false);

      final data = List<Map<String, dynamic>>.from(response);
      return data.map((json) => Ad.fromJson(json)).toList();
    } catch (e) {
      print('❌ [AdService] 전체 광고 로드 실패: $e');
      return [];
    }
  }

  // [관리자용] 광고 추가
  Future<void> createAd({
    required String title,
    required String imageUrl,
    String? linkUrl,
    required String location,
    bool isActive = true,
  }) async {
    await _sb.from('ads').insert({
      'title': title,
      'image_url': imageUrl,
      'link_url': linkUrl,
      'location': location,
      'is_active': isActive,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  // [관리자용] 광고 수정
  Future<void> updateAd(String id, Map<String, dynamic> updates) async {
    await _sb.from('ads').update(updates).eq('id', id);
  }

  // [관리자용] 광고 삭제
  Future<void> deleteAd(String id) async {
    await _sb.from('ads').delete().eq('id', id);
  }
}

