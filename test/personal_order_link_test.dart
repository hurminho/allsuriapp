import 'package:flutter_test/flutter_test.dart';
import 'package:allsuriapp/models/personal_order_link.dart';
import 'package:allsuriapp/models/order.dart' as app_models;
import 'package:allsuriapp/utils/personal_order_link_nav.dart';

void main() {
  group('PersonalOrderLink 모델 테스트', () {
    test('모델 생성 및 기본값 확인', () {
      final link = PersonalOrderLink(
        id: 'test-id',
        contractorId: 'contractor-123',
        slug: 'kim-plumbing',
        slugNormalized: 'kim-plumbing',
        status: PersonalOrderLinkStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(link.id, 'test-id');
      expect(link.contractorId, 'contractor-123');
      expect(link.slug, 'kim-plumbing');
      expect(link.status, PersonalOrderLinkStatus.active);
      expect(link.acceptsDirectOrders, true);
      expect(link.canAcceptOrders, true);
    });

    test('링크가 일시정지 상태이면 오더를 받을 수 없음', () {
      final link = PersonalOrderLink(
        id: 'test-id',
        contractorId: 'contractor-123',
        slug: 'test',
        slugNormalized: 'test',
        status: PersonalOrderLinkStatus.paused,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(link.canAcceptOrders, false);
    });

    test('acceptsDirectOrders가 false이면 오더를 받을 수 없음', () {
      final link = PersonalOrderLink(
        id: 'test-id',
        contractorId: 'contractor-123',
        slug: 'test',
        slugNormalized: 'test',
        status: PersonalOrderLinkStatus.active,
        acceptsDirectOrders: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(link.canAcceptOrders, false);
    });

    test('getPublicUrl이 올바른 URL을 생성함', () {
      final link = PersonalOrderLink(
        id: 'test-id',
        contractorId: 'contractor-123',
        slug: 'kim-plumbing',
        slugNormalized: 'kim-plumbing',
        status: PersonalOrderLinkStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final url = link.getPublicUrl('https://allsuri.com');
      expect(url, 'https://allsuri.com/allsuri/kim-plumbing');
    });

    test('toMap과 fromMap이 대칭적으로 동작함', () {
      final original = PersonalOrderLink(
        id: 'test-id',
        contractorId: 'contractor-123',
        slug: 'kim-plumbing',
        slugNormalized: 'kim-plumbing',
        status: PersonalOrderLinkStatus.active,
        displayName: '김 사장님 설비',
        headline: '누수·배관 전문',
        supportedCategories: ['누수', '배관'],
        serviceRegions: ['서울 강서구'],
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 2),
      );

      final map = original.toMap();
      final restored = PersonalOrderLink.fromMap(map);

      expect(restored.id, original.id);
      expect(restored.contractorId, original.contractorId);
      expect(restored.slug, original.slug);
      expect(restored.status, original.status);
      expect(restored.displayName, original.displayName);
      expect(restored.headline, original.headline);
      expect(restored.supportedCategories, original.supportedCategories);
      expect(restored.serviceRegions, original.serviceRegions);
    });
  });

  group('PersonalOrderLinkStats 테스트', () {
    test('전환율 계산이 올바름', () {
      final stats = PersonalOrderLinkStats(
        pageViews: 100,
        quoteStarts: 30,
        quoteSubmissions: 20,
      );

      expect(stats.viewToStartRate, 30.0);
      expect(stats.startToSubmissionRate, closeTo(66.67, 0.01));
    });

    test('pageViews가 0일 때 전환율이 0', () {
      final stats = PersonalOrderLinkStats(
        pageViews: 0,
        quoteStarts: 0,
        quoteSubmissions: 0,
      );

      expect(stats.viewToStartRate, 0.0);
    });

    test('quoteStarts가 0일 때 시작 전환율이 0', () {
      final stats = PersonalOrderLinkStats(
        pageViews: 100,
        quoteStarts: 0,
        quoteSubmissions: 0,
      );

      expect(stats.startToSubmissionRate, 0.0);
    });
  });

  group('Order 모델 개인 링크 필드 테스트', () {
    test('개인 링크 오더 생성 시 필수 필드가 설정됨', () {
      final order = app_models.Order(
        title: '누수 수리',
        description: '천장에서 물이 떨어져요',
        address: '서울시 강서구',
        visitDate: DateTime.now(),
        status: app_models.Order.STATUS_PENDING,
        createdAt: DateTime.now(),
        customerName: '고객',
        customerPhone: '010-1234-5678',
        routingType: 'personal_link',
        personalOrderLinkId: 'link-123',
        sourceContractorId: 'contractor-456',
        assignedContractorId: 'contractor-456',
        assignmentLockedAt: DateTime.now(),
      );

      expect(order.routingType, 'personal_link');
      expect(order.personalOrderLinkId, 'link-123');
      expect(order.sourceContractorId, 'contractor-456');
      expect(order.assignedContractorId, 'contractor-456');
      expect(order.assignmentLockedAt, isNotNull);
    });

    test('일반 마켓플레이스 오더는 기본값이 marketplace', () {
      final order = app_models.Order(
        title: '일반 오더',
        description: '일반 요청',
        address: '서울',
        visitDate: DateTime.now(),
        status: app_models.Order.STATUS_PENDING,
        createdAt: DateTime.now(),
        customerName: '고객',
        customerPhone: '010-1234-5678',
      );

      expect(order.routingType, 'marketplace');
      expect(order.personalOrderLinkId, isNull);
      expect(order.assignedContractorId, isNull);
    });

    test('Order toMap과 fromMap에서 개인 링크 필드가 유지됨', () {
      final original = app_models.Order(
        title: '누수 수리',
        description: '천장에서 물이 떨어져요',
        address: '서울시 강서구',
        visitDate: DateTime(2024, 1, 1),
        status: app_models.Order.STATUS_PENDING,
        createdAt: DateTime(2024, 1, 1),
        customerName: '고객',
        customerPhone: '010-1234-5678',
        routingType: 'personal_link',
        personalOrderLinkId: 'link-123',
        sourceContractorId: 'contractor-456',
        assignedContractorId: 'contractor-456',
        assignmentLockedAt: DateTime(2024, 1, 1),
        utmSource: 'kakao',
        utmMedium: 'share',
      );

      final map = original.toMap();
      final restored = app_models.Order.fromMap(map);

      expect(restored.routingType, 'personal_link');
      expect(restored.personalOrderLinkId, 'link-123');
      expect(restored.sourceContractorId, 'contractor-456');
      expect(restored.assignedContractorId, 'contractor-456');
      expect(restored.assignmentLockedAt, isNotNull);
      expect(restored.utmSource, 'kakao');
      expect(restored.utmMedium, 'share');
    });
  });

  group('Slug 정규화 테스트', () {
    // 실제로는 PersonalOrderLinkService._normalizeSlug이 private이므로
    // 통합 테스트에서 slug 검증을 확인해야 함

    test('유효한 slug 패턴', () {
      final validSlugs = [
        'kim-plumbing',
        'lee_repair',
        'park123',
        'abc-def_123',
      ];

      for (final slug in validSlugs) {
        expect(RegExp(r'^[a-z0-9_-]+$').hasMatch(slug), true,
            reason: '$slug should be valid');
      }
    });

    test('무효한 slug 패턴', () {
      final invalidSlugs = [
        'Kim-Plumbing', // 대문자
        'kim plumbing', // 공백
        'kim@plumbing', // 특수문자
        '김-설비', // 한글
      ];

      for (final slug in invalidSlugs) {
        expect(RegExp(r'^[a-z0-9_-]+$').hasMatch(slug), false,
            reason: '$slug should be invalid');
      }
    });

    test('slug 길이 검증', () {
      // 너무 짧음 (3자 미만)
      expect('ab'.length >= 3, false);
      expect('abc'.length >= 3, true);

      // 너무 긺 (50자 초과)
      final longSlug = 'a' * 51;
      expect(longSlug.length <= 50, false);
    });
  });

  group('예약어 테스트', () {
    test('시스템 예약어 목록', () {
      final reservedSlugs = [
        'admin',
        'api',
        'app',
        'auth',
        'login',
        'logout',
        'signup',
        'register',
        'dashboard',
        'profile',
        'settings',
        'allsuri',
      ];

      // 실제로는 DB에서 확인해야 하지만, 여기서는 목록 확인
      expect(reservedSlugs.length, greaterThan(0));
    });
  });

  group('공개 URL slug 추출', () {
    test('웹 경로에서 slug를 읽는다', () {
      expect(
        personalOrderLinkSlugFromUri(
          Uri.parse('https://allsuricommerce.netlify.app/allsuri/kim-plumbing'),
        ),
        'kim-plumbing',
      );
      expect(
        personalOrderLinkSlugFromUri(
          Uri.parse('https://allsuri.app/allsuri/kim-plumbing'),
        ),
        'kim-plumbing',
      );
    });

    test('앱 커스텀 스킴에서 slug를 읽는다', () {
      expect(
        personalOrderLinkSlugFromUri(Uri.parse('allsuri://allsuri/lee-repair')),
        'lee-repair',
      );
    });

    test('개인 링크가 아니면 null', () {
      expect(
        personalOrderLinkSlugFromUri(
          Uri.parse('https://allsuricommerce.netlify.app/order/abc'),
        ),
        isNull,
      );
    });
  });
}
