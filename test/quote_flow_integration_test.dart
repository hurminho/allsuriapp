import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:allsuriapp/models/bid_breakdown.dart';
import 'package:allsuriapp/models/price_estimate.dart';
import 'package:allsuriapp/services/api_service.dart';
import 'package:allsuriapp/services/price_service.dart';
import 'package:allsuriapp/utils/api_failure.dart';
import 'package:allsuriapp/utils/app_logger.dart';

/// 견적 요청 → 가격 조회 → 사업자 입찰 → 완료 금액 기록까지의 통합 테스트.
///
/// 외부 의존성을 모두 대체합니다.
///  * 운영 API 대신 [FakeApiServer] (MockClient)
///  * OpenAI·Solapi·결제·이미지 업로드는 호출 경로 자체가 없습니다.
///  * 운영 DB 를 건드리지 않습니다.
///
/// 테스트 데이터에는 실제 연락처·주소를 쓰지 않습니다.
void main() {
  /// 요청을 경로별로 받아 주는 가짜 서버.
  ///
  /// 상태를 들고 있어서 "입찰이 저장된 뒤 다시 조회하면 보인다" 같은
  /// 흐름을 검증할 수 있습니다.
  late FakeApiServer server;

  setUp(() {
    server = FakeApiServer();
    ApiService.testClient = server.client;
    PriceService.resetCache();
  });

  tearDown(() {
    ApiService.testClient = null;
    PriceService.resetCache();
    AppLog.onLog = null;
  });

  group('고객: 견적 요청과 가격 조회', () {
    test('데이터가 충분하면 예상 범위를 받는다', () async {
      server.priceEstimate = {
        'priceState': 'sufficient',
        'estimatedMin': 80000,
        'estimatedTypical': 100000,
        'estimatedMax': 120000,
        'confidenceLevel': 'high',
        'evidenceCount': 36,
        'factors': ['출장비', '자재비'],
        // showAmount 는 서버 uiCopy 안에서 내려옵니다.
        'uiCopy': {
          'headline': '최근 유사 완료 작업 기준',
          'body': '현장 상태에 따라 달라질 수 있습니다.',
          'showAmount': true,
        },
        'disclaimer': '현장 확인 전 참고 금액입니다.',
        'engineVersion': 'v1',
      };

      final price = await PriceService().estimate(
        tradeId: 'plumbing.toilet_clog',
        address: '서울 강남구',
      );

      expect(price.state, PriceState.sufficient);
      expect(price.hasRange, isTrue);
      expect(price.min, 80000);
      expect(price.max, 120000);
    });

    test('데이터가 부족하면 숫자를 만들지 않는다', () async {
      server.priceEstimate = {
        'priceState': 'insufficient',
        'evidenceCount': 1,
        'uiCopy': {
          'headline': '현장 조건에 따라 차이가 큰 작업',
          'body': '실제 업체 견적을 받아보세요.',
          'cta': '업체 견적 받기',
          'showAmount': false,
        },
        'engineVersion': 'v1',
      };

      final price = await PriceService().estimate(tradeId: 'plumbing.leak');

      expect(price.state, PriceState.insufficient);
      expect(price.hasRange, isFalse);
      expect(price.min, isNull);
      expect(price.max, isNull);
    });

    test('가격 엔진이 죽어도 앱은 데이터 부족 화면으로 계속 진행한다', () async {
      // 가격 조회 실패가 견적 요청 자체를 막으면 안 됩니다.
      server.priceStatus = 500;

      final price = await PriceService().estimate(tradeId: 'plumbing.leak');

      expect(price.available, isFalse);
      expect(price.hasRange, isFalse);
      expect(price.state, PriceState.insufficient);
    });

    test('가격 조회가 지연되어도 예외로 터지지 않는다', () async {
      server.priceDelay = const Duration(milliseconds: 300);

      final price = await PriceService()
          .estimate(tradeId: 'plumbing.leak')
          .timeout(const Duration(seconds: 5));

      // 타임아웃이든 성공이든 화면을 그릴 수 있는 값이어야 합니다.
      expect(price, isA<PriceEstimate>());
    });
  });

  group('사업자: 입찰 제출', () {
    test('세부 원가를 포함해 제출하면 서버가 그대로 받는다', () async {
      final api = ApiService();
      final breakdown = const BidBreakdown(
        visitFee: 20000,
        laborCost: 60000,
        materialCost: 30000,
        additionalCost: 0,
        vatIncluded: true,
        asPeriodMonths: 6,
      );

      final result = await api.post('/market/listings/listing-1/bid', {
        'businessId': 'biz-1',
        'message': '이 오더를 맡고 싶습니다.',
        'bid_amount': 110000,
        'estimated_days': 1,
        ...breakdown.toApiJson(),
      });

      expect(result['success'], isTrue);
      expect(server.savedBids, hasLength(1));

      // 앱은 camelCase 로 보내고, snake_case 변환은 서버가 담당합니다.
      final saved = server.savedBids.single;
      expect(saved['bid_amount'], 110000);
      expect(saved['visitFee'], 20000);
      expect(saved['laborCost'], 60000);
      expect(saved['materialCost'], 30000);
      expect(saved['vatIncluded'], isTrue);
      expect(saved['asPeriodMonths'], 6);
    });

    test('총액만 넣어도 제출된다', () async {
      // 세부 항목 누락은 막지 않는 정책입니다.
      final result = await ApiService().post('/market/listings/l1/bid', {
        'businessId': 'biz-1',
        'bid_amount': 90000,
      });

      expect(result['success'], isTrue);
      expect(server.savedBids.single['visitFee'], isNull);
    });

    test('같은 입찰을 두 번 보내면 서버가 alreadyBid 로 막는다', () async {
      final api = ApiService();
      final payload = {'businessId': 'biz-1', 'bid_amount': 90000};

      final first = await api.post('/market/listings/l1/bid', payload);
      final second = await api.post('/market/listings/l1/bid', payload);

      expect(first['success'], isTrue);
      expect(second['success'], isTrue, reason: '중복은 오류가 아니라 성공으로 흡수합니다');
      expect((second['data'] as Map)['alreadyBid'], isTrue);
      // 서버 측에서도 한 건만 남아야 합니다.
      expect(server.savedBids, hasLength(1));
    });

    test('제출 중 네트워크가 끊기면 사용자용 안내가 나온다', () async {
      server.failNextWith = http.ClientException('Connection reset');

      final result = await ApiService().post('/market/listings/l1/bid', {
        'businessId': 'biz-1',
        'bid_amount': 90000,
      });

      expect(result['success'], isFalse);
      expect(result['errorKind'], 'offline');
      expect(result['error'], contains('인터넷 연결'));
      expect(result['retryable'], isTrue);
      // 실패한 요청이 저장되면 안 됩니다.
      expect(server.savedBids, isEmpty);
    });

    test('네트워크 실패 후 재시도하면 성공한다', () async {
      final api = ApiService();
      server.failNextWith = http.ClientException('Connection reset');

      final first = await api.post('/market/listings/l1/bid', {
        'businessId': 'biz-1',
        'bid_amount': 90000,
      });
      expect(first['retryable'], isTrue);

      final retry = await api.post('/market/listings/l1/bid', {
        'businessId': 'biz-1',
        'bid_amount': 90000,
      });

      expect(retry['success'], isTrue);
      expect(server.savedBids, hasLength(1));
    });

    test('서버가 거절하면 개발자 문구가 노출되지 않는다', () async {
      server.bidStatus = 409;
      server.bidErrorMessage = 'PGRST116: duplicate key violates constraint';

      final result = await ApiService().post('/market/listings/l1/bid', {
        'businessId': 'biz-1',
        'bid_amount': 90000,
      });

      expect(result['success'], isFalse);
      expect(result['error'], isNot(contains('PGRST')));
      expect(result['error'], isNot(contains('constraint')));
    });
  });

  group('사업자: 완료 확정금액 기록', () {
    test('최종 금액은 입찰가와 분리되어 저장된다', () async {
      await ApiService().post('/market/listings/l1/bid', {
        'businessId': 'biz-1',
        'bid_amount': 110000,
      });

      // recordCompletedJob 은 성공하면 null, 실패하면 안내 문구를 돌려줍니다.
      final error = await PriceService().recordCompletedJob(
        listingId: 'l1',
        draft: const CompletedJobDraft(
          finalTotalAmount: 135000,
          finalLaborCost: 80000,
          finalMaterialCost: 55000,
          finalAdditionalCost: 0,
        ),
      );

      expect(error, isNull);
      expect(server.completedJobs.single['finalTotalAmount'], 135000);
      // 입찰가는 그대로 남아 있어야 합니다.
      expect(server.savedBids.single['bid_amount'], 110000);
    });

    test('세부 항목 합계가 총액과 다르면 서버로 보내지 않는다', () async {
      final error = await PriceService().recordCompletedJob(
        listingId: 'l1',
        draft: const CompletedJobDraft(
          finalTotalAmount: 135000,
          finalLaborCost: 80000,
          finalMaterialCost: 10000,
          finalAdditionalCost: 0,
        ),
      );

      expect(error, isNotNull);
      expect(error, contains('맞지 않습니다'));
      expect(server.completedJobs, isEmpty);
    });

    test('완료 금액 기록이 실패하면 사용자용 안내를 돌려준다', () async {
      server.completedJobStatus = 500;

      final error = await PriceService().recordCompletedJob(
        listingId: 'l1',
        draft: const CompletedJobDraft(finalTotalAmount: 135000),
      );

      // 예외를 던져 공사 완료 처리를 막으면 안 됩니다.
      expect(error, isNotNull);
      expect(error, isNot(contains('Exception')));
    });
  });

  group('로그 안전성 (통합 경로)', () {
    test('전체 흐름 어디에서도 연락처가 로그에 남지 않는다', () async {
      final logs = <String>[];
      AppLog.onLog = (level, message) => logs.add(message);

      server.priceEstimate = {
        'priceState': 'sufficient',
        'showAmount': true,
        'estimatedMin': 80000,
        'estimatedMax': 120000,
        // 응답에 고객 정보가 섞여 오는 상황을 흉내 냅니다.
        'debugCustomer': {
          'phone': '010-1234-5678',
          'address': '서울특별시 강남구 테헤란로 1',
        },
        'uiCopy': {'headline': 'h', 'body': 'b', 'showAmount': true},
      };

      await PriceService().estimate(tradeId: 'plumbing.toilet_clog');
      await ApiService().post('/market/listings/l1/bid', {
        'businessId': 'biz-1',
        'bid_amount': 90000,
        'customerPhone': '010-1234-5678',
      });

      final joined = logs.join('\n');
      expect(joined, isNot(contains('1234-5678')));
      expect(joined, isNot(contains('테헤란로')));
    });
  });
}

/// 경로별로 응답을 만들어 주는 가짜 API 서버.
class FakeApiServer {
  /// 저장된 입찰. 중복 방지 검증에 씁니다.
  final List<Map<String, dynamic>> savedBids = [];

  /// 저장된 완료 금액.
  final List<Map<String, dynamic>> completedJobs = [];

  Map<String, dynamic>? priceEstimate;
  int priceStatus = 200;
  Duration priceDelay = Duration.zero;

  int bidStatus = 200;
  String? bidErrorMessage;

  int completedJobStatus = 200;

  /// 다음 한 번의 요청만 이 예외로 실패시킵니다.
  Object? failNextWith;

  http.Client get client => MockClient(_handle);

  Future<http.Response> _handle(http.Request request) async {
    final failure = failNextWith;
    if (failure != null) {
      failNextWith = null;
      throw failure;
    }

    final path = request.url.path;

    // netlify/functions/price.ts 의 ok() 는 본문을 감싸지 않고 그대로 내려줍니다.
    // 가짜 서버도 같은 모양을 지켜야 봉투 불일치를 잡아낼 수 있습니다.
    if (path.contains('/price/catalog')) {
      return _json(200, {
        'trades': [
          {
            'id': 'plumbing.toilet_clog',
            'category': '배관',
            'subcategory': '변기 막힘',
          },
        ],
      });
    }

    if (path.contains('/price/estimate')) {
      if (priceDelay > Duration.zero) {
        await Future<void>.delayed(priceDelay);
      }
      if (priceStatus != 200) {
        return _json(priceStatus, {'error': 'engine unavailable'});
      }
      return _json(200, priceEstimate ?? {});
    }

    if (path.contains('/price/completed-jobs')) {
      if (completedJobStatus != 200) {
        return _json(completedJobStatus, {'error': 'save failed'});
      }
      completedJobs.add(_body(request));
      return _json(200, {'success': true, 'completedJob': {'id': 'cj-1'}});
    }

    if (path.contains('/bid')) {
      if (bidStatus != 200) {
        return _json(bidStatus, {'message': bidErrorMessage ?? 'rejected'});
      }
      final body = _body(request);
      final bidderId = body['businessId'];
      final already = savedBids.any((b) => b['businessId'] == bidderId);
      if (already) {
        // 서버는 중복 입찰을 200 + alreadyBid 로 흡수합니다.
        return _json(200, {
          'success': true,
          'alreadyBid': true,
          'message': '이미 입찰한 일감입니다.',
        });
      }
      savedBids.add(body);
      return _json(201, {'success': true, 'bidId': 'bid-${savedBids.length}'});
    }

    return _json(404, {'message': 'not found'});
  }

  Map<String, dynamic> _body(http.Request request) {
    if (request.body.isEmpty) return {};
    final decoded = json.decode(request.body);
    return decoded is Map
        ? decoded.cast<String, dynamic>()
        : <String, dynamic>{};
  }

  http.Response _json(int status, Object body) => http.Response(
        json.encode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
}
