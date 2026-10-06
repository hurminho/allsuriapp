import '../models/order.dart' as app_models;

/// 홈 '신규 오더'와 오더 찾기가 같은 목록을 쓰도록 합칩니다.
class NewOrderItem {
  final app_models.Order order;
  final Map<String, dynamic>? listing;

  const NewOrderItem({required this.order, this.listing});

  bool get isMarketplaceListing => listing != null;
}

/// [listings]는 오더 찾기와 동일한 marketplace_listings 행입니다.
/// 내 개인 링크 오더는 마켓에 없으므로 [orders]에서만 보강합니다.
List<NewOrderItem> mergeNewOrderFeed({
  required List<Map<String, dynamic>> listings,
  required List<app_models.Order> orders,
  required String contractorId,
}) {
  final items = <NewOrderItem>[];
  final seenIds = <String>{};

  for (final listing in listings) {
    final postedBy = listing['posted_by']?.toString();
    if (postedBy != null &&
        postedBy.isNotEmpty &&
        postedBy == contractorId) {
      continue;
    }
    final order = app_models.Order.fromMarketplaceListing(listing);
    final id = order.id;
    if (id != null && id.isNotEmpty) {
      if (!seenIds.add(id)) continue;
    }
    items.add(NewOrderItem(order: order, listing: listing));
  }

  for (final order in orders) {
    if (order.routingType != 'personal_link') continue;
    if (order.assignedContractorId != contractorId) continue;
    if (order.status != app_models.Order.STATUS_PENDING) continue;
    if (order.isAwarded) continue;
    final id = order.id;
    if (id != null && id.isNotEmpty && !seenIds.add(id)) continue;
    items.add(NewOrderItem(order: order));
  }

  items.sort((a, b) => b.order.createdAt.compareTo(a.order.createdAt));
  return items;
}
