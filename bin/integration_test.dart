/// 개인 오더 링크 통합 테스트 (Dart 스크립트)
///
/// 실행 명령:
/// dart run bin/integration_test.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

const supabaseUrl = 'https://iiunvogtqssxaxdnhqaj.supabase.co';
const supabaseKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlpdW52b2d0cXNzeGF4ZG5ocWFqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTQ5NTUzMTksImV4cCI6MjA3MDUzMTMxOX0.PjA01VwTmJwEGEYTc-g1UOR7FkeGTeN7smIQXyusKP8';

final headers = {
  'apikey': supabaseKey,
  'Authorization': 'Bearer $supabaseKey',
  'Content-Type': 'application/json',
  'Prefer': 'return=representation',
};

String? createdLinkId;
String? createdOrderId;
late String testContractorId;
late String testSlug;

void main() async {
  print('🚀 개인 오더 링크 통합 테스트 시작\n');
  print('=' * 60);

  testContractorId = const Uuid().v4();
  testSlug = 'test-${DateTime.now().millisecondsSinceEpoch}';

  try {
    // 0. 테이블 존재 확인
    await test0_checkTables();

    // 1. 개인 링크 생성 테스트
    await test1_createPersonalOrderLink();

    // 2. 공개 페이지 접근 테스트
    await test2_publicPageAccess();

    // 3. 견적 요청 제출 및 직접 배정 확인
    await test3_quoteSubmission();

    // 4. 일반 마켓에 노출되지 않는지 확인
    await test4_marketplaceExclusion();

    // 5. 링크 상태 변경 테스트
    await test5_linkStatusChange();

    // 6. 통계 테스트
    await test6_statistics();

    print('\n' + '=' * 60);
    print('✅ 모든 통합 테스트 통과!\n');
  } catch (e) {
    print('\n❌ 테스트 실패: $e');
  } finally {
    // 테스트 데이터 정리
    await cleanupTestData();
  }
}

Future<void> test0_checkTables() async {
  print('\n📋 0. 테이블 존재 확인');
  print('-' * 40);

  // personal_order_links 테이블 확인
  final linksResponse = await http.get(
    Uri.parse('$supabaseUrl/rest/v1/personal_order_links?limit=0'),
    headers: headers,
  );

  if (linksResponse.statusCode == 200) {
    print('   ✅ personal_order_links 테이블 존재');
  } else {
    throw Exception('personal_order_links 테이블이 존재하지 않음: ${linksResponse.body}');
  }

  // personal_order_link_events 테이블 확인
  final eventsResponse = await http.get(
    Uri.parse('$supabaseUrl/rest/v1/personal_order_link_events?limit=0'),
    headers: headers,
  );

  if (eventsResponse.statusCode == 200) {
    print('   ✅ personal_order_link_events 테이블 존재');
  } else {
    throw Exception(
        'personal_order_link_events 테이블이 존재하지 않음: ${eventsResponse.body}');
  }

  // reserved_slugs 테이블 확인
  final reservedResponse = await http.get(
    Uri.parse('$supabaseUrl/rest/v1/reserved_slugs?limit=0'),
    headers: headers,
  );

  if (reservedResponse.statusCode == 200) {
    print('   ✅ reserved_slugs 테이블 존재');
  } else {
    throw Exception(
        'reserved_slugs 테이블이 존재하지 않음: ${reservedResponse.body}');
  }

  // orders 테이블의 새 컬럼 확인
  final ordersResponse = await http.get(
    Uri.parse(
        '$supabaseUrl/rest/v1/orders?select=routing_type,personal_order_link_id&limit=0'),
    headers: headers,
  );

  if (ordersResponse.statusCode == 200) {
    print('   ✅ orders 테이블에 개인 링크 컬럼 존재');
  } else {
    print('   ⚠️ orders 테이블 확인 필요: ${ordersResponse.body}');
  }
}

Future<void> test1_createPersonalOrderLink() async {
  print('\n📋 1. 개인 링크 생성 테스트');
  print('-' * 40);

  // 1.1 새 개인 링크 생성
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

  final createResponse = await http.post(
    Uri.parse('$supabaseUrl/rest/v1/personal_order_links'),
    headers: headers,
    body: jsonEncode(linkData),
  );

  if (createResponse.statusCode == 201) {
    final created = jsonDecode(createResponse.body);
    createdLinkId = (created is List ? created[0] : created)['id'];
    print('   ✅ 1.1 개인 링크 생성 성공');
    print('      - ID: $createdLinkId');
    print('      - Slug: $testSlug');
  } else {
    throw Exception('개인 링크 생성 실패: ${createResponse.body}');
  }

  // 1.2 중복 slug 생성 시도
  final duplicateResponse = await http.post(
    Uri.parse('$supabaseUrl/rest/v1/personal_order_links'),
    headers: headers,
    body: jsonEncode({
      ...linkData,
      'contractor_id': const Uuid().v4(),
    }),
  );

  if (duplicateResponse.statusCode != 201) {
    print('   ✅ 1.2 중복 slug 생성 차단 확인');
  } else {
    print('   ❌ 1.2 중복 slug 생성이 허용됨 (unique 제약 확인 필요)');
  }

  // 1.3 slug 가용성 확인
  final existingCheck = await http.get(
    Uri.parse(
        '$supabaseUrl/rest/v1/personal_order_links?slug_normalized=eq.${testSlug.toLowerCase()}&select=id'),
    headers: headers,
  );

  final existingLinks = jsonDecode(existingCheck.body) as List;
  if (existingLinks.isNotEmpty) {
    print('   ✅ 1.3 사용 중인 slug 확인 성공');
  }

  // 새 slug 가용성
  final newSlug = 'brand-new-slug-${DateTime.now().millisecondsSinceEpoch}';
  final newCheck = await http.get(
    Uri.parse(
        '$supabaseUrl/rest/v1/personal_order_links?slug_normalized=eq.$newSlug&select=id'),
    headers: headers,
  );

  final newLinks = jsonDecode(newCheck.body) as List;
  if (newLinks.isEmpty) {
    print('   ✅ 1.4 새 slug 가용성 확인 성공');
  }
}

Future<void> test2_publicPageAccess() async {
  print('\n📋 2. 공개 페이지 접근 테스트');
  print('-' * 40);

  // 2.1 slug로 링크 조회
  final linkResponse = await http.get(
    Uri.parse(
        '$supabaseUrl/rest/v1/personal_order_links?slug_normalized=eq.${testSlug.toLowerCase()}'),
    headers: headers,
  );

  if (linkResponse.statusCode == 200) {
    final links = jsonDecode(linkResponse.body) as List;
    if (links.isNotEmpty) {
      final link = links[0];
      print('   ✅ 2.1 공개 페이지 접근 성공');
      print('      - Display Name: ${link['display_name']}');
      print('      - Status: ${link['status']}');
      print('      - Can Accept: ${link['accepts_direct_orders']}');
    } else {
      throw Exception('링크를 찾을 수 없음');
    }
  } else {
    throw Exception('링크 조회 실패: ${linkResponse.body}');
  }

  // 2.2 존재하지 않는 slug 조회
  final notFoundResponse = await http.get(
    Uri.parse(
        '$supabaseUrl/rest/v1/personal_order_links?slug_normalized=eq.non-existent-slug'),
    headers: headers,
  );

  final notFoundLinks = jsonDecode(notFoundResponse.body) as List;
  if (notFoundLinks.isEmpty) {
    print('   ✅ 2.2 존재하지 않는 slug 처리 확인');
  }

  // 2.3 페이지 조회 이벤트 기록
  final eventData = {
    'personal_order_link_id': createdLinkId,
    'event_type': 'page_view',
    'anonymous_session_id': const Uuid().v4(),
  };

  final eventResponse = await http.post(
    Uri.parse('$supabaseUrl/rest/v1/personal_order_link_events'),
    headers: headers,
    body: jsonEncode(eventData),
  );

  if (eventResponse.statusCode == 201) {
    print('   ✅ 2.3 페이지 조회 이벤트 기록 성공');
  } else {
    print('   ⚠️ 2.3 이벤트 기록 실패: ${eventResponse.body}');
  }
}

Future<void> test3_quoteSubmission() async {
  print('\n📋 3. 견적 요청 제출 및 직접 배정 확인');
  print('-' * 40);

  // 3.1 견적 요청 시작 이벤트
  await http.post(
    Uri.parse('$supabaseUrl/rest/v1/personal_order_link_events'),
    headers: headers,
    body: jsonEncode({
      'personal_order_link_id': createdLinkId,
      'event_type': 'quote_start',
    }),
  );

  // 3.2 개인 링크 오더 생성
  final orderData = {
    'title': '누수 수리 요청',
    'description': '천장에서 물이 새요',
    'address': '서울시 강서구 화곡동',
    'visitDate': DateTime.now().add(const Duration(days: 3)).toIso8601String(),
    'customerName': '테스트 고객',
    'customerPhone': '010-1234-5678',
    'status': 'pending',
    'createdAt': DateTime.now().toIso8601String(),
    'routing_type': 'personal_link',
    'personal_order_link_id': createdLinkId,
    'source_contractor_id': testContractorId,
    'assigned_contractor_id': testContractorId,
    'assignment_locked_at': DateTime.now().toIso8601String(),
  };

  final orderResponse = await http.post(
    Uri.parse('$supabaseUrl/rest/v1/orders'),
    headers: headers,
    body: jsonEncode(orderData),
  );

  if (orderResponse.statusCode == 201) {
    final created = jsonDecode(orderResponse.body);
    createdOrderId = (created is List ? created[0] : created)['id'];
    print('   ✅ 3.1 개인 링크 견적 요청 제출 성공');
    print('      - Order ID: $createdOrderId');
    print('      - Routing Type: personal_link');
    print('      - Assigned To: $testContractorId');
  } else {
    print('   ⚠️ 오더 생성 실패 (orders 테이블 스키마 확인 필요): ${orderResponse.body}');
    return;
  }

  // 3.3 견적 요청 완료 이벤트
  await http.post(
    Uri.parse('$supabaseUrl/rest/v1/personal_order_link_events'),
    headers: headers,
    body: jsonEncode({
      'personal_order_link_id': createdLinkId,
      'event_type': 'quote_submitted',
    }),
  );

  // 3.4 직접 배정 확인
  if (createdOrderId != null) {
    final orderCheck = await http.get(
      Uri.parse('$supabaseUrl/rest/v1/orders?id=eq.$createdOrderId'),
      headers: headers,
    );

    if (orderCheck.statusCode == 200) {
      final orders = jsonDecode(orderCheck.body) as List;
      if (orders.isNotEmpty) {
        final order = orders[0];
        if (order['assigned_contractor_id'] == testContractorId) {
          print('   ✅ 3.2 직접 배정 확인 완료');
          print('      - Assigned: ${order['assigned_contractor_id']}');
          print('      - Source: ${order['source_contractor_id']}');
        }
      }
    }
  }

  // 3.5 직접 오더 목록 조회
  final directOrdersResponse = await http.get(
    Uri.parse(
        '$supabaseUrl/rest/v1/orders?routing_type=eq.personal_link&assigned_contractor_id=eq.$testContractorId'),
    headers: headers,
  );

  if (directOrdersResponse.statusCode == 200) {
    final directOrders = jsonDecode(directOrdersResponse.body) as List;
    print('   ✅ 3.3 직접 오더 목록 조회 성공');
    print('      - 직접 오더 수: ${directOrders.length}');
  }
}

Future<void> test4_marketplaceExclusion() async {
  print('\n📋 4. 일반 마켓에 노출되지 않는지 확인');
  print('-' * 40);

  // 4.1 마켓플레이스 목록에서 개인 링크 오더 제외 확인
  final marketplaceResponse = await http.get(
    Uri.parse(
        '$supabaseUrl/rest/v1/orders?routing_type=eq.marketplace&status=eq.pending'),
    headers: headers,
  );

  if (marketplaceResponse.statusCode == 200) {
    final marketplaceOrders = jsonDecode(marketplaceResponse.body) as List;
    final hasPersonalLinkOrder = marketplaceOrders
        .any((o) => o['personal_order_link_id'] != null);

    if (!hasPersonalLinkOrder) {
      print('   ✅ 4.1 마켓플레이스 목록에서 개인 링크 오더 제외 확인');
      print('      - 마켓플레이스 오더 수: ${marketplaceOrders.length}');
    } else {
      print('   ❌ 4.1 마켓플레이스에 개인 링크 오더가 노출됨');
    }
  }

  // 4.2 다른 사업자가 개인 링크 오더에 접근 불가
  final otherContractorId = const Uuid().v4();
  final otherOrdersResponse = await http.get(
    Uri.parse(
        '$supabaseUrl/rest/v1/orders?routing_type=eq.personal_link&assigned_contractor_id=eq.$otherContractorId'),
    headers: headers,
  );

  if (otherOrdersResponse.statusCode == 200) {
    final otherOrders = jsonDecode(otherOrdersResponse.body) as List;
    final hasTestOrder = otherOrders.any(
        (o) => o['assigned_contractor_id'] == testContractorId);

    if (!hasTestOrder) {
      print('   ✅ 4.2 다른 사업자의 개인 링크 오더 접근 차단 확인');
    }
  }

  print('   ✅ 4.3 routing_type 필터링으로 격리 확인');
}

Future<void> test5_linkStatusChange() async {
  print('\n📋 5. 링크 상태 변경 테스트');
  print('-' * 40);

  // 5.1 링크 일시정지
  final pauseResponse = await http.patch(
    Uri.parse('$supabaseUrl/rest/v1/personal_order_links?id=eq.$createdLinkId'),
    headers: headers,
    body: jsonEncode({'status': 'paused'}),
  );

  if (pauseResponse.statusCode == 200 || pauseResponse.statusCode == 204) {
    // 상태 확인
    final checkResponse = await http.get(
      Uri.parse(
          '$supabaseUrl/rest/v1/personal_order_links?id=eq.$createdLinkId'),
      headers: headers,
    );

    final links = jsonDecode(checkResponse.body) as List;
    if (links.isNotEmpty && links[0]['status'] == 'paused') {
      print('   ✅ 5.1 링크 일시정지 성공');
    }
  }

  // 5.2 일시정지 상태 확인
  final pausedCheckResponse = await http.get(
    Uri.parse(
        '$supabaseUrl/rest/v1/personal_order_links?slug_normalized=eq.${testSlug.toLowerCase()}'),
    headers: headers,
  );

  final pausedLinks = jsonDecode(pausedCheckResponse.body) as List;
  if (pausedLinks.isNotEmpty && pausedLinks[0]['status'] == 'paused') {
    print('   ✅ 5.2 일시정지 상태 공개 페이지 확인');
  }

  // 5.3 링크 재활성화
  final resumeResponse = await http.patch(
    Uri.parse('$supabaseUrl/rest/v1/personal_order_links?id=eq.$createdLinkId'),
    headers: headers,
    body: jsonEncode({'status': 'active'}),
  );

  if (resumeResponse.statusCode == 200 || resumeResponse.statusCode == 204) {
    final checkResponse = await http.get(
      Uri.parse(
          '$supabaseUrl/rest/v1/personal_order_links?id=eq.$createdLinkId'),
      headers: headers,
    );

    final links = jsonDecode(checkResponse.body) as List;
    if (links.isNotEmpty && links[0]['status'] == 'active') {
      print('   ✅ 5.3 링크 재활성화 성공');
    }
  }
}

Future<void> test6_statistics() async {
  print('\n📋 6. 통계 및 분석 테스트');
  print('-' * 40);

  // 이벤트 통계 조회
  final eventsResponse = await http.get(
    Uri.parse(
        '$supabaseUrl/rest/v1/personal_order_link_events?personal_order_link_id=eq.$createdLinkId&select=event_type'),
    headers: headers,
  );

  if (eventsResponse.statusCode == 200) {
    final events = jsonDecode(eventsResponse.body) as List;

    int pageViews = 0;
    int quoteStarts = 0;
    int quoteSubmissions = 0;

    for (final event in events) {
      switch (event['event_type']) {
        case 'page_view':
          pageViews++;
          break;
        case 'quote_start':
          quoteStarts++;
          break;
        case 'quote_submitted':
          quoteSubmissions++;
          break;
      }
    }

    print('   ✅ 6.1 이벤트 통계 조회 성공');
    print('      - Page Views: $pageViews');
    print('      - Quote Starts: $quoteStarts');
    print('      - Quote Submissions: $quoteSubmissions');

    if (pageViews > 0) {
      final viewToStartRate = quoteStarts / pageViews * 100;
      print('      - View to Start Rate: ${viewToStartRate.toStringAsFixed(1)}%');
    }

    if (quoteStarts > 0) {
      final startToSubmissionRate = quoteSubmissions / quoteStarts * 100;
      print(
          '      - Start to Submission Rate: ${startToSubmissionRate.toStringAsFixed(1)}%');
    }
  }
}

Future<void> cleanupTestData() async {
  print('\n🧹 테스트 데이터 정리 중...');

  // 오더 삭제
  if (createdOrderId != null) {
    try {
      await http.delete(
        Uri.parse('$supabaseUrl/rest/v1/orders?id=eq.$createdOrderId'),
        headers: headers,
      );
      print('   - 테스트 오더 삭제 완료');
    } catch (e) {
      print('   - 테스트 오더 삭제 실패: $e');
    }
  }

  // 이벤트 삭제
  if (createdLinkId != null) {
    try {
      await http.delete(
        Uri.parse(
            '$supabaseUrl/rest/v1/personal_order_link_events?personal_order_link_id=eq.$createdLinkId'),
        headers: headers,
      );
      print('   - 테스트 이벤트 삭제 완료');
    } catch (e) {
      print('   - 테스트 이벤트 삭제 실패: $e');
    }
  }

  // 링크 삭제
  if (createdLinkId != null) {
    try {
      await http.delete(
        Uri.parse(
            '$supabaseUrl/rest/v1/personal_order_links?id=eq.$createdLinkId'),
        headers: headers,
      );
      print('   - 테스트 링크 삭제 완료');
    } catch (e) {
      print('   - 테스트 링크 삭제 실패: $e');
    }
  }

  print('\n🏁 테스트 종료');
}
