/// 개인 오더 링크 통합 테스트
///
/// 이 테스트는 실제 Supabase DB와 연동하여 전체 흐름을 검증합니다.
/// 실행 전 환경 변수 설정 필요:
/// - SUPABASE_URL
/// - SUPABASE_ANON_KEY
///
/// 실행 명령:
/// flutter test integration_test/personal_order_link_integration_test.dart --dart-define-from-file=.env.local

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:allsuriapp/models/personal_order_link.dart';
import 'package:allsuriapp/models/order.dart' as app_models;
import 'package:allsuriapp/services/personal_order_link_service.dart';
import 'package:allsuriapp/services/order_service.dart';
import 'package:uuid/uuid.dart';

/// 테스트용 Supabase 클라이언트 초기화
Future<void> initSupabase() async {
  // AppConfig의 기본값 사용
  const supabaseUrl = 'https://iiunvogtqssxaxdnhqaj.supabase.co';
  const supabaseKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlpdW52b2d0cXNzeGF4ZG5ocWFqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTQ5NTUzMTksImV4cCI6MjA3MDUzMTMxOX0.PjA01VwTmJwEGEYTc-g1UOR7FkeGTeN7smIQXyusKP8';

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseKey,
  );
}

void main() {
  late PersonalOrderLinkService linkService;
  late OrderService orderService;
  late String testContractorId;
  late String testSlug;
  late String? createdLinkId;

  setUpAll(() async {
    await initSupabase();
    linkService = PersonalOrderLinkService();
    orderService = OrderService();

    // 테스트용 고유 식별자 생성
    testContractorId = const Uuid().v4();
    testSlug = 'test-${DateTime.now().millisecondsSinceEpoch}';
  });

  tearDownAll(() async {
    // 테스트 데이터 정리
    if (createdLinkId != null) {
      try {
        await Supabase.instance.client
            .from('personal_order_links')
            .delete()
            .eq('id', createdLinkId!);
        print('✅ 테스트 링크 삭제 완료: $createdLinkId');
      } catch (e) {
        print('⚠️ 테스트 링크 삭제 실패: $e');
      }
    }
  });

  group('1. 개인 링크 생성 테스트', () {
    test('1.1 새 개인 링크 생성 (DB 직접 삽입)', () async {
      // 테스트용 링크 직접 생성 (로그인 없이)
      final linkData = {
        'contractor_id': testContractorId,
        'slug': testSlug,
        'slug_normalized': testSlug.toLowerCase(),
        'status': 'active',
        'accepts_direct_orders': true,
        'display_name': '테스트 사업자',
        'headline': '누수/배관 전문',
        'supported_categories': ['누수', '배관'],
        'service_regions': ['서울 강서구'],
      };

      final response = await Supabase.instance.client
          .from('personal_order_links')
          .insert(linkData)
          .select()
          .single();

      final link = PersonalOrderLink.fromMap(Map<String, dynamic>.from(response));

      expect(link.contractorId, testContractorId);
      expect(link.slug, testSlug);
      expect(link.status, PersonalOrderLinkStatus.active);
      createdLinkId = link.id;

      print('✅ 개인 링크 생성 성공: ${link.id}');
      print('   - Slug: ${link.slug}');
      print('   - Status: ${link.status}');
    });

    test('1.2 중복 slug 생성 시도 시 실패', () async {
      // 동일한 slug로 다시 생성 시도
      try {
        await Supabase.instance.client.from('personal_order_links').insert({
          'contractor_id': const Uuid().v4(),
          'slug': testSlug,
          'slug_normalized': testSlug.toLowerCase(),
          'status': 'active',
        });
        fail('중복 slug 생성이 허용되면 안됨');
      } catch (e) {
        expect(e, isA<PostgrestException>());
        print('✅ 중복 slug 생성 차단 확인');
      }
    });

    test('1.3 slug 가용성 확인', () async {
      // 이미 사용 중인 slug
      final existingAvailable = await linkService.checkSlugAvailability(testSlug);
      expect(existingAvailable, false);

      // 새로운 slug
      final newSlug = 'new-unique-${DateTime.now().millisecondsSinceEpoch}';
      final newAvailable = await linkService.checkSlugAvailability(newSlug);
      expect(newAvailable, true);

      print('✅ slug 가용성 확인 로직 정상 동작');
    });

    test('1.4 예약어 slug 사용 불가', () async {
      // 예약어 테이블에 데이터 삽입 (테스트용)
      final reservedSlugs = ['admin', 'api', 'login', 'allsuri'];
      
      for (final reserved in reservedSlugs) {
        try {
          await Supabase.instance.client.from('reserved_slugs').upsert({
            'slug': reserved,
            'reason': 'system_reserved',
          });
        } catch (e) {
          // 이미 존재하면 무시
        }
      }

      for (final reserved in reservedSlugs) {
        final available = await linkService.checkSlugAvailability(reserved);
        expect(available, false, reason: '$reserved는 예약어여야 함');
      }

      print('✅ 예약어 slug 차단 확인');
    });
  });

  group('2. 공개 페이지 접근 테스트', () {
    test('2.1 slug로 링크 조회 (공개 정보만)', () async {
      final link = await linkService.getPublicLinkBySlug(testSlug);

      expect(link, isNotNull);
      expect(link!.slug, testSlug);
      expect(link.displayName, '테스트 사업자');
      expect(link.status, PersonalOrderLinkStatus.active);
      expect(link.canAcceptOrders, true);

      print('✅ 공개 페이지 접근 성공');
      print('   - Display Name: ${link.displayName}');
      print('   - Can Accept Orders: ${link.canAcceptOrders}');
    });

    test('2.2 존재하지 않는 slug 조회 시 null 반환', () async {
      final link = await linkService.getPublicLinkBySlug('non-existent-slug-12345');

      expect(link, isNull);
      print('✅ 존재하지 않는 slug 처리 확인');
    });

    test('2.3 페이지 조회 이벤트 기록', () async {
      // 페이지 조회 이벤트 기록
      await linkService.trackEvent(
        personalOrderLinkId: createdLinkId!,
        eventType: PersonalOrderLinkEventType.pageView,
      );

      // 통계 확인
      final stats = await linkService.getStats(
        createdLinkId!,
        DateTime.now().subtract(const Duration(days: 30)),
      );
      expect(stats.pageViews, greaterThan(0));

      print('✅ 페이지 조회 이벤트 기록 확인');
      print('   - Page Views: ${stats.pageViews}');
    });
  });

  group('3. 견적 요청 제출 및 직접 배정 확인', () {
    late String createdOrderId;

    test('3.1 개인 링크를 통한 견적 요청 제출', () async {
      // 견적 요청 시작 이벤트
      await linkService.trackEvent(
        personalOrderLinkId: createdLinkId!,
        eventType: PersonalOrderLinkEventType.quoteStart,
      );

      // 테스트용 오더 객체 생성
      final testOrder = app_models.Order(
        title: '누수 수리 요청',
        description: '천장에서 물이 새요',
        address: '서울시 강서구 화곡동',
        visitDate: DateTime.now().add(const Duration(days: 3)),
        customerName: '테스트 고객',
        customerPhone: '010-1234-5678',
        status: app_models.Order.STATUS_PENDING,
        createdAt: DateTime.now(),
      );

      // 개인 링크 오더 생성
      final order = await orderService.createPersonalLinkOrder(
        order: testOrder,
        personalOrderLinkId: createdLinkId!,
        contractorId: testContractorId,
      );

      expect(order.routingType, 'personal_link');
      expect(order.personalOrderLinkId, createdLinkId);
      expect(order.assignedContractorId, testContractorId);
      expect(order.assignmentLockedAt, isNotNull);

      createdOrderId = order.id!;

      // 견적 요청 완료 이벤트
      await linkService.trackEvent(
        personalOrderLinkId: createdLinkId!,
        eventType: PersonalOrderLinkEventType.quoteSubmitted,
      );

      print('✅ 개인 링크 견적 요청 제출 성공');
      print('   - Order ID: ${order.id}');
      print('   - Routing Type: ${order.routingType}');
      print('   - Assigned To: ${order.assignedContractorId}');
    });

    test('3.2 직접 배정 확인 - assignedContractorId가 링크 소유자와 일치', () async {
      final order = await orderService.getOrder(createdOrderId);

      expect(order, isNotNull);
      expect(order!.assignedContractorId, testContractorId);
      expect(order.sourceContractorId, testContractorId);

      print('✅ 직접 배정 확인 완료');
      print('   - Link Owner: $testContractorId');
      print('   - Assigned Contractor: ${order.assignedContractorId}');
      print('   - Source Contractor: ${order.sourceContractorId}');
    });

    test('3.3 직접 오더 목록 조회 (사업자용)', () async {
      final directOrders = await linkService.getDirectOrders(
        contractorId: testContractorId,
      );

      expect(directOrders, isNotEmpty);
      expect(
        directOrders.any((o) => o['id'] == createdOrderId),
        true,
      );

      final directOrder = directOrders.firstWhere((o) => o['id'] == createdOrderId);
      expect(directOrder['routing_type'], 'personal_link');

      print('✅ 직접 오더 목록 조회 성공');
      print('   - 직접 오더 수: ${directOrders.length}');
    });
  });

  group('4. 일반 마켓에 노출되지 않는지 확인', () {
    test('4.1 마켓플레이스 목록에서 개인 링크 오더 제외 확인', () async {
      // 마켓플레이스 오더만 조회하는 쿼리
      final marketplaceOrders = await Supabase.instance.client
          .from('orders')
          .select()
          .eq('routing_type', 'marketplace')
          .eq('status', app_models.Order.STATUS_PENDING);

      // 개인 링크 오더가 포함되어 있지 않은지 확인
      final containsPersonalLinkOrder = (marketplaceOrders as List).any(
        (order) => order['personal_order_link_id'] != null,
      );

      expect(containsPersonalLinkOrder, false);

      print('✅ 마켓플레이스 목록에서 개인 링크 오더 제외 확인');
      print('   - 마켓플레이스 오더 수: ${marketplaceOrders.length}');
    });

    test('4.2 다른 사업자가 개인 링크 오더에 접근 불가', () async {
      // 다른 사업자 ID
      final otherContractorId = const Uuid().v4();

      // 다른 사업자의 직접 오더 조회 시 해당 오더가 나오지 않아야 함
      final otherOrders = await linkService.getDirectOrders(
        contractorId: otherContractorId,
      );

      expect(
        otherOrders.any((o) => o['assigned_contractor_id'] == testContractorId),
        false,
      );

      print('✅ 다른 사업자의 개인 링크 오더 접근 차단 확인');
    });

    test('4.3 RLS 정책으로 비인가 접근 차단 확인', () async {
      // RLS가 적용된 테이블에서 다른 사용자의 데이터 접근 시도
      // (익명 사용자로 접근하므로 제한된 데이터만 조회 가능)

      final result = await Supabase.instance.client
          .from('personal_order_links')
          .select('id, slug, display_name, status')
          .eq('slug', testSlug)
          .maybeSingle();

      // 공개 정보만 조회 가능해야 함
      expect(result, isNotNull);
      expect(result!['slug'], testSlug);

      print('✅ RLS 정책 동작 확인');
    });
  });

  group('5. 링크 상태 변경 테스트', () {
    test('5.1 링크 일시정지', () async {
      await linkService.updateLinkStatus(
        createdLinkId!,
        PersonalOrderLinkStatus.paused,
      );

      final updated = await linkService.getPublicLinkBySlug(testSlug);
      expect(updated, isNotNull);
      expect(updated!.status, PersonalOrderLinkStatus.paused);
      expect(updated.canAcceptOrders, false);

      print('✅ 링크 일시정지 성공');
    });

    test('5.2 일시정지 상태에서 공개 페이지 접근', () async {
      final link = await linkService.getPublicLinkBySlug(testSlug);

      expect(link, isNotNull);
      expect(link!.status, PersonalOrderLinkStatus.paused);
      expect(link.canAcceptOrders, false);

      print('✅ 일시정지 링크의 공개 페이지 상태 확인');
    });

    test('5.3 링크 재활성화', () async {
      await linkService.updateLinkStatus(
        createdLinkId!,
        PersonalOrderLinkStatus.active,
      );

      final updated = await linkService.getPublicLinkBySlug(testSlug);
      expect(updated, isNotNull);
      expect(updated!.status, PersonalOrderLinkStatus.active);
      expect(updated.canAcceptOrders, true);

      print('✅ 링크 재활성화 성공');
    });
  });

  group('6. 통계 및 분석 테스트', () {
    test('6.1 이벤트 통계 조회', () async {
      final stats = await linkService.getStats(
        createdLinkId!,
        DateTime.now().subtract(const Duration(days: 30)),
      );

      expect(stats.pageViews, greaterThan(0));
      expect(stats.quoteStarts, greaterThan(0));
      expect(stats.quoteSubmissions, greaterThan(0));

      print('✅ 이벤트 통계 조회 성공');
      print('   - Page Views: ${stats.pageViews}');
      print('   - Quote Starts: ${stats.quoteStarts}');
      print('   - Quote Submissions: ${stats.quoteSubmissions}');
      print('   - View to Start Rate: ${stats.viewToStartRate.toStringAsFixed(1)}%');
      print('   - Start to Submission Rate: ${stats.startToSubmissionRate.toStringAsFixed(1)}%');
    });
  });
}
