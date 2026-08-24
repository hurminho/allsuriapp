import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/business_review.dart';
import '../models/business_stats.dart';

/// 사업자 평점 조회. 후기는 협업(B2B)·웹 오더(B2C) 구분 없이 order_reviews
/// 한 곳에 쌓이므로 여기서도 그 테이블만 본다.
class ReviewService {
  final SupabaseClient _sb = Supabase.instance.client;

  /// 사업자가 받은 후기 목록
  Future<List<BusinessReview>> getBusinessReviews(String businessId, {int? limit, int? offset}) async {
    try {
      var query = _sb
          .from('order_reviews')
          .select()
          .eq('reviewee_id', businessId)
          .order('created_at', ascending: false);

      if (limit != null) {
        query = query.limit(limit);
      }
      if (offset != null) {
        query = query.range(offset, offset + (limit ?? 10) - 1);
      }

      final response = await query;
      return response.map((review) => BusinessReview.fromMap(review)).toList();
    } catch (e) {
      debugPrint('사업자 후기 목록 조회 실패: $e');
      return [];
    }
  }

  /// 특정 웹 오더에 대한 후기
  Future<BusinessReview?> getReviewByOrder(String orderId) async {
    try {
      final response = await _sb
          .from('order_reviews')
          .select()
          .eq('order_id', orderId)
          .maybeSingle();

      return response == null ? null : BusinessReview.fromMap(response);
    } catch (e) {
      debugPrint('오더별 후기 조회 실패: $e');
      return null;
    }
  }

  /// 사업자 평점 통계. totalOrders/completedOrders 는 이 화면들에서 쓰지 않아
  /// 채우지 않는다.
  Future<BusinessStats?> getBusinessStats(String businessId) async {
    try {
      final rows = await _sb
          .from('order_reviews')
          .select('rating')
          .eq('reviewee_id', businessId);

      final ratings = rows
          .map((r) => (r['rating'] as num?)?.toDouble())
          .whereType<double>()
          .toList();

      return BusinessStats(
        businessId: businessId,
        totalReviews: ratings.length,
        averageRating: ratings.isEmpty
            ? 0.0
            : ratings.reduce((a, b) => a + b) / ratings.length,
        totalOrders: 0,
        completedOrders: 0,
        updatedAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('사업자 평점 통계 조회 실패: $e');
      return null;
    }
  }

  /// 웹 오더 완료 후 고객이 후기를 쓸 수 있는지
  Future<bool> canWriteReview(String orderId, String customerId) async {
    try {
      if (await getReviewByOrder(orderId) != null) return false;

      final order = await _sb
          .from('orders')
          .select('status, customerid')
          .eq('id', orderId)
          .maybeSingle();

      if (order == null) return false;
      return order['status'] == 'completed' && order['customerid'] == customerId;
    } catch (e) {
      debugPrint('후기 작성 가능 여부 확인 실패: $e');
      return false;
    }
  }

  /// 사업자별 평균 별점
  Future<double> calculateAverageRating(String businessId) async {
    final stats = await getBusinessStats(businessId);
    return stats?.averageRating ?? 0.0;
  }

  /// 별점 분포까지 포함한 요약
  Future<Map<String, dynamic>> getReviewSummary(String businessId) async {
    try {
      final rows = await _sb
          .from('order_reviews')
          .select('rating')
          .eq('reviewee_id', businessId);

      final ratings = rows
          .map((r) => (r['rating'] as num?)?.round())
          .whereType<int>()
          .toList();

      if (ratings.isEmpty) {
        return {'totalReviews': 0, 'averageRating': 0.0, 'ratingDistribution': <int, int>{}};
      }

      return {
        'totalReviews': ratings.length,
        'averageRating': ratings.reduce((a, b) => a + b) / ratings.length,
        'ratingDistribution': {
          for (int i = 1; i <= 5; i++) i: ratings.where((r) => r == i).length,
        },
      };
    } catch (e) {
      debugPrint('후기 통계 요약 실패: $e');
      return {'totalReviews': 0, 'averageRating': 0.0, 'ratingDistribution': <int, int>{}};
    }
  }
}
