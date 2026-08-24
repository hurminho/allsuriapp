import 'package:allsuriapp/utils/bid_action.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveBidAction', () {
    test('입찰 이력이 없고 일감이 열려 있으면 지원 가능', () {
      for (final status in ['open', 'withdrawn', 'created']) {
        expect(
          resolveBidAction(listingStatus: status, myBidStatus: null),
          BidAction.bid,
          reason: 'listingStatus=$status',
        );
      }
    });

    test('입찰 이력이 없어도 마감된 일감은 지원 불가', () {
      for (final status in ['closed', 'assigned', 'completed', 'cancelled']) {
        expect(
          resolveBidAction(listingStatus: status, myBidStatus: null),
          BidAction.closed,
          reason: 'listingStatus=$status',
        );
      }
    });

    test('pending 입찰이 있으면 취소만 가능', () {
      expect(
        resolveBidAction(listingStatus: 'open', myBidStatus: 'pending'),
        BidAction.cancel,
      );
    });

    // 회귀 방지: 상세 화면이 pending 여부만 보고 분기해
    // 낙찰/미선정된 일감에 재입찰이 열려 있었음
    test('낙찰/미선정 입찰이 있으면 열린 일감이어도 재지원 불가', () {
      for (final myStatus in ['selected', 'rejected', 'awarded']) {
        expect(
          resolveBidAction(listingStatus: 'open', myBidStatus: myStatus),
          BidAction.alreadyBid,
          reason: 'myBidStatus=$myStatus',
        );
      }
    });

    test('빈 문자열/공백 입찰 상태는 입찰 없음으로 취급', () {
      expect(
        resolveBidAction(listingStatus: 'open', myBidStatus: '  '),
        BidAction.bid,
      );
    });
  });

  group('hasAnyBidStatus / hasPendingBidStatus', () {
    test('hasAnyBidStatus는 상태와 무관하게 입찰 존재만 판단', () {
      expect(hasAnyBidStatus(null), isFalse);
      expect(hasAnyBidStatus(''), isFalse);
      expect(hasAnyBidStatus('pending'), isTrue);
      expect(hasAnyBidStatus('rejected'), isTrue);
    });

    test('hasPendingBidStatus는 pending만 참', () {
      expect(hasPendingBidStatus('pending'), isTrue);
      expect(hasPendingBidStatus('selected'), isFalse);
      expect(hasPendingBidStatus(null), isFalse);
    });
  });
}
