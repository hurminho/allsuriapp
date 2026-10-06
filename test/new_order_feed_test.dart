import 'package:allsuriapp/models/order.dart';
import 'package:allsuriapp/utils/new_order_feed.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const me = 'contractor-1';

  Order personalLinkOrder({
    required String id,
    String assignedTo = me,
    String status = 'pending',
    bool awarded = false,
    DateTime? createdAt,
  }) {
    return Order(
      id: id,
      title: '개인 링크 오더',
      description: '',
      address: '서울',
      visitDate: DateTime(2026, 9, 1),
      status: status,
      createdAt: createdAt ?? DateTime(2026, 9, 1),
      customerName: '고객',
      customerPhone: '010',
      routingType: 'personal_link',
      assignedContractorId: assignedTo,
      isAwarded: awarded,
    );
  }

  test('오더 찾기 리스팅을 신규 오더로 모두 모은다', () {
    final items = mergeNewOrderFeed(
      contractorId: me,
      orders: [
        Order(
          id: 'orders-only-pending',
          title: 'orders 테이블에만 있는 요청',
          description: '',
          address: '부산',
          visitDate: DateTime(2026, 9, 1),
          status: 'pending',
          createdAt: DateTime(2026, 9, 2),
          customerName: '',
          customerPhone: '',
        ),
      ],
      listings: [
        {
          'id': 'listing-1',
          'title': '보일러 수리',
          'region': '서울 강남구',
          'category': '배관',
          'status': 'open',
          'posted_by': 'other',
          'createdat': '2026-09-29T10:00:00Z',
          'budget_amount': 150000,
        },
        {
          'id': 'listing-2',
          'title': '누수 점검',
          'region': '인천',
          'category': '누수',
          'status': 'created',
          'posted_by': 'another',
          'createdat': '2026-09-30T10:00:00Z',
        },
      ],
    );

    expect(items.map((e) => e.order.id), ['listing-2', 'listing-1']);
    expect(items.every((e) => e.isMarketplaceListing), isTrue);
    expect(items.first.order.address, '인천');
    expect(items.last.order.estimatedPrice, 150000);
  });

  test('내가 올린 리스팅은 신규 오더에서 제외한다', () {
    final items = mergeNewOrderFeed(
      contractorId: me,
      orders: const [],
      listings: [
        {
          'id': 'mine',
          'title': '내가 낸 오더',
          'posted_by': me,
          'createdat': '2026-09-29T10:00:00Z',
        },
        {
          'id': 'theirs',
          'title': '남이 올린 오더',
          'posted_by': 'other',
          'createdat': '2026-09-29T11:00:00Z',
        },
      ],
    );

    expect(items.map((e) => e.order.id), ['theirs']);
  });

  test('나에게 배정된 개인 링크 오더만 마켓 목록에 보강한다', () {
    final items = mergeNewOrderFeed(
      contractorId: me,
      listings: [
        {
          'id': 'listing-1',
          'title': '마켓 오더',
          'posted_by': 'other',
          'createdat': '2026-09-29T10:00:00Z',
        },
      ],
      orders: [
        personalLinkOrder(id: 'mine-link', createdAt: DateTime(2026, 9, 30)),
        personalLinkOrder(id: 'other-link', assignedTo: 'someone-else'),
        personalLinkOrder(id: 'done-link', awarded: true),
      ],
    );

    expect(items.map((e) => e.order.id), ['mine-link', 'listing-1']);
    expect(items.first.isMarketplaceListing, isFalse);
  });
}
