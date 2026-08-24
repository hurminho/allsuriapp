/// 협업 일감 카드/상세에서 사업자가 취할 수 있는 행동.
enum BidAction {
  /// 아직 입찰하지 않았고 일감이 열려 있음 → 지원 가능
  bid,

  /// pending 입찰 보유 → 지원 취소만 가능
  cancel,

  /// 낙찰(selected)/미선정(rejected) 입찰 보유 → 재지원·취소 모두 불가
  alreadyBid,

  /// 일감이 마감되어 지원 불가
  closed,
}

const Set<String> _openListingStatuses = {'open', 'withdrawn', 'created'};

/// 이미 입찰(상태 무관)한 일감인지 여부.
bool hasAnyBidStatus(String? myBidStatus) =>
    (myBidStatus ?? '').trim().isNotEmpty;

/// 취소 가능한 pending 입찰 보유 여부.
bool hasPendingBidStatus(String? myBidStatus) =>
    (myBidStatus ?? '').trim() == 'pending';

/// 일감 상태와 내 입찰 상태로부터 가능한 행동을 결정합니다.
///
/// 목록 카드, 그리드 카드, 상세 화면이 각각 따로 판단하다가 상세 화면만 `pending`
/// 여부로 분기해 이미 입찰한 일감에 재입찰이 열리는 버그가 있었습니다.
/// 세 곳 모두 이 함수를 쓰도록 통일합니다.
BidAction resolveBidAction({
  required String listingStatus,
  String? myBidStatus,
}) {
  if (hasPendingBidStatus(myBidStatus)) return BidAction.cancel;
  if (hasAnyBidStatus(myBidStatus)) return BidAction.alreadyBid;
  return _openListingStatuses.contains(listingStatus.trim())
      ? BidAction.bid
      : BidAction.closed;
}
