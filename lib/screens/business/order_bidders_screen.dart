import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:allsuriapp/services/api_service.dart';
import 'package:allsuriapp/services/auth_service.dart';
import 'package:allsuriapp/services/chat_service.dart';
import 'package:allsuriapp/widgets/loading_indicator.dart';
import 'package:allsuriapp/services/business_verify_service.dart';
import 'package:allsuriapp/widgets/business/business_app_shell.dart';
import 'package:allsuriapp/widgets/business/business_empty_state.dart';
import 'package:allsuriapp/widgets/business/business_primary_button.dart';
import 'package:allsuriapp/widgets/business/business_section_header.dart';
import 'package:allsuriapp/widgets/business/business_status_chip.dart';
import 'package:allsuriapp/widgets/business/business_tokens.dart';
import '../chat_screen.dart';

class OrderBiddersScreen extends StatefulWidget {
  final String listingId;
  final String orderTitle;

  const OrderBiddersScreen({
    Key? key,
    required this.listingId,
    required this.orderTitle,
  }) : super(key: key);

  @override
  State<OrderBiddersScreen> createState() => _OrderBiddersScreenState();
}

class _OrderBiddersScreenState extends State<OrderBiddersScreen> {
  List<Map<String, dynamic>> _bidders = [];
  bool _loading = true;
  String? _error;
  String? _selectedBidderId;
  String? _selectedBidderName;

  // bidderId -> {average, count}. _loadBidders 에서 일괄 채움.
  final Map<String, Map<String, dynamic>> _ratingsByBidder = {};

  // 사업자 평점 평균 가져오기 (단건 - 프로필 다이얼로그용)
  Future<Map<String, dynamic>> _getBidderRating(String bidderId) async {
    try {
      final reviews = await Supabase.instance.client
          .from('order_reviews')
          .select('rating')
          .eq('reviewee_id', bidderId);

      if (reviews.isEmpty) {
        return {'average': 0.0, 'count': 0};
      }

      final ratings = reviews.map((r) => (r['rating'] ?? 0) as int).toList();
      final average = ratings.reduce((a, b) => a + b) / ratings.length;

      return {'average': average, 'count': ratings.length};
    } catch (e) {
      debugPrint('⚠️ 평점 조회 실패: $e');
      return {'average': 0.0, 'count': 0};
    }
  }

  /// 모든 입찰자의 평점을 단일 쿼리로 조회해 _ratingsByBidder 에 채운다.
  /// (입찰자마다 FutureBuilder로 쿼리하던 N+1 제거)
  Future<void> _loadRatingsFor(List<String> bidderIds) async {
    _ratingsByBidder.clear();
    if (bidderIds.isEmpty) return;
    try {
      final reviews = await Supabase.instance.client
          .from('order_reviews')
          .select('rating, reviewee_id')
          .inFilter('reviewee_id', bidderIds);

      final sums = <String, int>{};
      final counts = <String, int>{};
      for (final r in reviews) {
        final id = r['reviewee_id']?.toString();
        if (id == null) continue;
        final rating = (r['rating'] ?? 0) as int;
        sums[id] = (sums[id] ?? 0) + rating;
        counts[id] = (counts[id] ?? 0) + 1;
      }
      for (final id in bidderIds) {
        final cnt = counts[id] ?? 0;
        _ratingsByBidder[id] = {
          'average': cnt > 0 ? (sums[id]! / cnt) : 0.0,
          'count': cnt,
        };
      }
    } catch (e) {
      debugPrint('⚠️ 평점 일괄 조회 실패: $e');
    }
  }

  // 사업자 프로필 및 후기 보기
  Future<void> _showBidderProfile(String bidderId, String bidderName,
      {String personName = ''}) async {
    // 후기 목록 가져오기
    List<Map<String, dynamic>> reviews = [];
    try {
      reviews = await Supabase.instance.client
          .from('order_reviews')
          .select('rating, tags, comment, created_at, reviewer_id')
          .eq('reviewee_id', bidderId)
          .order('created_at', ascending: false);
    } catch (e) {
      print('⚠️ 후기 조회 실패: $e');
    }

    final rating = await _getBidderRating(bidderId);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.storefront, color: Colors.blue, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bidderName,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold)),
                  if (personName.isNotEmpty && personName != bidderName)
                    Text('대표자: $personName',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.normal)),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 평점 요약
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.star, color: Colors.amber[700], size: 32),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '평균 ${rating['average'].toStringAsFixed(1)}',
                            style: const TextStyle(
                                fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${rating['count']}개의 후기',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 후기 목록
                if (reviews.isEmpty) ...[
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('아직 작성된 후기가 없습니다.',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  ),
                ] else ...[
                  const Text('받은 후기',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  ...reviews
                      .map((review) => Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    ...List.generate(
                                        5,
                                        (i) => Icon(
                                              i < (review['rating'] ?? 0)
                                                  ? Icons.star
                                                  : Icons.star_border,
                                              color: Colors.amber[700],
                                              size: 16,
                                            )),
                                    const SizedBox(width: 8),
                                    Text('${review['rating']}.0',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                if (review['tags'] != null &&
                                    (review['tags'] as List).isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: (review['tags'] as List)
                                        .take(3)
                                        .map((tag) => Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.blue[50],
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(tag.toString(),
                                                  style: const TextStyle(
                                                      fontSize: 11)),
                                            ))
                                        .toList(),
                                  ),
                                ],
                                if (review['comment'] != null &&
                                    review['comment']
                                        .toString()
                                        .isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    review['comment'].toString(),
                                    style: TextStyle(
                                        fontSize: 13, color: Colors.grey[700]),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                const SizedBox(height: 6),
                                Text(
                                  review['created_at']
                                          ?.toString()
                                          .substring(0, 10) ??
                                      '',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey[500]),
                                ),
                              ],
                            ),
                          ))
                      .toList(),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadBidders();
  }

  Future<void> _loadBidders() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = ApiService();
      final response =
          await api.get('/market/listings/${widget.listingId}/bids');

      if (response['success'] == true && response['data'] is List) {
        final bidders = List<Map<String, dynamic>>.from(response['data']);

        // 입찰자 평점을 단일 쿼리로 일괄 로드 (N+1 제거)
        final bidderIds = bidders
            .map((b) => b['bidder_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();
        await _loadRatingsFor(bidderIds);

        if (!mounted) return;
        setState(() {
          _bidders = bidders;
          _loading = false;
        });
      } else {
        throw Exception('데이터 형식이 올바르지 않습니다');
      }
    } catch (e) {
      debugPrint('❌ [OrderBiddersScreen] 로드 오류: $e');
      if (!mounted) return;
      setState(() {
        _error = '지원 사업자 목록을 불러오지 못했습니다';
        _loading = false;
      });
    }
  }

  Future<void> _selectBidder(String bidderId, String bidderName) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: BusinessTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: BusinessTokens.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text('협업 사업자 배정', style: BusinessTokens.title),
              const SizedBox(height: 8),
              Text(
                '$bidderName 사업자에게 이 일감을 배정하시겠습니까?',
                style: BusinessTokens.body,
              ),
              const SizedBox(height: 8),
              const Text(
                '배정하면 다른 지원은 미선정 처리되며 채팅방이 생성됩니다.',
                style: BusinessTokens.caption,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: BusinessPrimaryButton(
                      label: '취소',
                      secondary: true,
                      onPressed: () => Navigator.pop(sheetContext, false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: BusinessPrimaryButton(
                      label: '배정 확정',
                      icon: Icons.check_rounded,
                      onPressed: () => Navigator.pop(sheetContext, true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    // ⭐ 낙찰 사전 가드: 사업자번호 등록 여부만 점검
    final bidderEligible =
        await BusinessVerifyService.isUserEligibleAsBusiness(bidderId);
    if (!mounted) return;
    if (!bidderEligible) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.orange),
              SizedBox(width: 10),
              Text('협업 배정을 진행할 수 없습니다'),
            ],
          ),
          content: Text(
            '$bidderName님의 사업자 정보가 아직 준비되지 않았습니다.\n\n'
            '다른 사업자를 선택하시거나 잠시 후 다시 시도해 주세요.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      return;
    }

    // 로딩 표시
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      print('🔍 [OrderBiddersScreen] 입찰자 선택 시작');

      // 현재 사용자 ID 확인
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUserId = authService.currentUser?.id;

      if (currentUserId == null || currentUserId.isEmpty) {
        throw Exception('사용자 정보를 찾을 수 없습니다. 다시 로그인해주세요.');
      }

      final api = ApiService();
      final response =
          await api.post('/market/listings/${widget.listingId}/select-bidder', {
        'bidderId': bidderId,
        'ownerId': currentUserId,
      });

      // 서버(RPC)가 BIDDER_NOT_VERIFIED 등으로 차단한 경우의 표준 에러 처리.
      // error에는 'HTTP 500: ...' 같은 일반 문구만 담기므로 message/data까지 함께 봅니다.
      if (response['success'] != true) {
        final data = response['data'];
        final errStr = [
          response['error'],
          response['message'],
          data is Map ? data['message'] : null,
          data is Map ? data['code'] : null,
          data is Map ? data['error'] : null,
        ].where((v) => v != null).join(' ');
        if (errStr.contains('BIDDER_NOT_VERIFIED') ||
            errStr.contains('진위확인이 완료되지 않아')) {
          if (!mounted) return;
          Navigator.of(context, rootNavigator: true).pop(); // 로딩 닫기
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('협업 배정을 진행할 수 없습니다'),
              content: Text(
                '$bidderName님의 사업자 정보가 아직 준비되지 않았습니다.\n'
                '잠시 후 다시 시도하거나 다른 사업자를 선택해 주세요.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('확인'),
                ),
              ],
            ),
          );
          return;
        }
      }

      print('✅ [OrderBiddersScreen] API 응답: $response');

      if (response['success'] == true) {
        // 🔧 awarded_amount 업데이트 (오더 예산을 공사 금액으로 저장)
        try {
          print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
          print('💰 [OrderBiddersScreen] awarded_amount 업데이트 시작');

          // 1. marketplace_listings의 budget_amount와 jobid 조회
          //    (select-bidder 응답에는 jobId가 없어서 예전에는 이 블록이 항상 스킵됐음)
          final listingData = await Supabase.instance.client
              .from('marketplace_listings')
              .select('budget_amount, jobid')
              .eq('id', widget.listingId)
              .single();

          final budgetAmount = listingData['budget_amount'];
          final jobId = listingData['jobid']?.toString();
          print('   오더 예산 금액: $budgetAmount');

          // 2. jobs 테이블의 awarded_amount 업데이트
          if (budgetAmount != null && jobId != null && jobId.isNotEmpty) {
            print('   Job ID: $jobId');

            final updated = await Supabase.instance.client
                .from('jobs')
                .update({'awarded_amount': budgetAmount})
                .eq('id', jobId)
                .select();

            print(
                '✅ [OrderBiddersScreen] awarded_amount 업데이트 ${updated.length}행: $budgetAmount원');
          } else {
            print('⚠️ [OrderBiddersScreen] budgetAmount 또는 jobId가 없음');
          }
          print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        } catch (amountErr) {
          print(
              '❌ [OrderBiddersScreen] awarded_amount 업데이트 실패 (무시됨): $amountErr');
          print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        }

        // 채팅방 생성 및 이동
        if (!mounted) return;

        // 로딩 닫기
        Navigator.pop(context);

        // 성공 메시지
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$bidderName 사업자에게 배정되었습니다. 채팅방으로 이동합니다.')),
        );

        // 낙찰 알림은 서버(handleSelectBidder)에서 DB INSERT → webhook으로 처리
        // 중복 방지를 위해 Flutter 측 직접 발송 제거

        // 2️⃣ 채팅방 생성/이동
        try {
          // ChatService를 통해 채팅방 생성/조회
          print('🔍 [OrderBiddersScreen] 채팅방 생성 시도');
          print('   Owner ID: $currentUserId');
          print('   Bidder ID: $bidderId');
          print('   Listing ID: ${widget.listingId}');

          final chatService = ChatService();
          final chatRoomId = await chatService.ensureChatRoom(
            customerId: currentUserId,
            businessId: bidderId,
            listingId: widget.listingId, // 오더 마켓플레이스 ID 전달
            title: widget.orderTitle, // 오더 제목 저장
          );

          print('✅ [OrderBiddersScreen] 채팅방 생성 성공: $chatRoomId');

          // 3️⃣ 자동 환영 메시지 발송
          try {
            print('📤 [OrderBiddersScreen] 자동 환영 메시지 발송 중...');
            final welcomeMessage = '안녕하세요. [${widget.orderTitle}] 공사로 연락 드립니다.';
            await chatService.sendMessage(
              chatRoomId,
              welcomeMessage,
              currentUserId,
            );
            print('✅ [OrderBiddersScreen] 자동 환영 메시지 발송 완료: $welcomeMessage');
          } catch (msgErr) {
            print('⚠️ [OrderBiddersScreen] 자동 메시지 발송 실패 (무시됨): $msgErr');
            // 메시지 실패해도 채팅방은 열림
          }

          // 채팅방으로 이동
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(
                  chatRoomId: chatRoomId,
                  chatRoomTitle: bidderName,
                ),
              ),
            );
          }
        } catch (chatErr) {
          print('❌ [OrderBiddersScreen] 채팅방 생성 실패: $chatErr');
          print('   에러 타입: ${chatErr.runtimeType}');
          print('   에러 상세: ${chatErr.toString()}');

          // 채팅방 생성 실패해도 낙찰은 성공했으므로 메시지 표시
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    Text('협업 배정은 완료되었으나 채팅방 생성에 실패했습니다: ${chatErr.toString()}'),
                duration: const Duration(seconds: 5),
              ),
            );
            Navigator.pop(context); // 입찰자 목록 화면 닫기
          }
        }
      } else {
        throw Exception(response['message'] ?? '협업 사업자 배정 실패');
      }
    } catch (e) {
      print('❌ [OrderBiddersScreen] 선택 오류: $e');
      print('   에러 타입: ${e.runtimeType}');
      print('   에러 상세: ${e.toString()}');

      if (mounted) {
        Navigator.pop(context); // 로딩 닫기
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('오류가 발생했습니다: ${e.toString()}'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPendingBidders = _bidders.any(
      (bid) => bid['status']?.toString() == 'pending',
    );
    return BusinessAppShell(
      title: '협업 지원 사업자',
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: BusinessTokens.surface,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: BusinessSectionHeader(
              title: widget.orderTitle,
              subtitle: _loading
                  ? '지원 사업자를 불러오는 중입니다'
                  : '지원 ${_bidders.length}건 · 사업자를 비교해 배정하세요',
            ),
          ),
          const Divider(height: 1, color: BusinessTokens.border),
          Expanded(child: _buildBiddersBody()),
          if (!_loading && _error == null && hasPendingBidders)
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: const BoxDecoration(
                  color: BusinessTokens.surface,
                  border: Border(
                    top: BorderSide(color: BusinessTokens.border),
                  ),
                ),
                child: BusinessPrimaryButton(
                  label: '선택한 사업자 배정',
                  icon: Icons.assignment_turned_in_outlined,
                  onPressed: _selectedBidderId == null
                      ? null
                      : () => _selectBidder(
                            _selectedBidderId!,
                            _selectedBidderName!,
                          ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBiddersBody() {
    if (_loading) {
      return const Center(
        child: LoadingIndicator(message: '지원 사업자 정보를 불러오고 있습니다...'),
      );
    }
    if (_error != null) {
      return BusinessEmptyState(
        icon: Icons.error_outline_rounded,
        title: _error!,
        actionLabel: '다시 시도',
        onAction: _loadBidders,
      );
    }
    if (_bidders.isEmpty) {
      return const BusinessEmptyState(
        icon: Icons.groups_outlined,
        title: '아직 지원한 사업자가 없습니다',
        subtitle: '지원이 접수되면 사업자 정보와 제안 조건을 비교할 수 있습니다.',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadBidders,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _bidders.length,
        itemBuilder: (context, index) {
          final bid = _bidders[index];
          final bidder = bid['bidder'] as Map<String, dynamic>?;
          final bidderId = bid['bidder_id']?.toString() ?? '';
          final status = bid['status']?.toString() ?? 'pending';
          final rawBizName = bidder?['businessname']?.toString() ?? '';
          final bidderName = rawBizName.isNotEmpty ? rawBizName : '상호명 없음';
          final personName = bidder?['name']?.toString() ?? '';
          final message = bid['message']?.toString() ?? '';
          final verificationStatus = (bidder?['business_verify_status'] ??
                      bidder?['businessVerifyStatus'])
                  ?.toString() ??
              '';
          final businessNumber = (bidder?['businessnumber'] ??
                      bidder?['businessregistrationnumber'])
                  ?.toString() ??
              '';
          final bidAmount = bid['bid_amount'];
          final estimatedDays = bid['estimated_days'];
          final double? bidAmountValue = bidAmount is num
              ? bidAmount.toDouble()
              : double.tryParse(bidAmount?.toString() ?? '');
          final int? estimatedDaysValue = estimatedDays is num
              ? estimatedDays.toInt()
              : int.tryParse(estimatedDays?.toString() ?? '');

          return _buildBidderCard(
            bidderId: bidderId,
            bidderName: bidderName,
            personName: personName,
            message: message,
            status: status,
            verificationStatus: verificationStatus,
            hasBusinessRegistration: businessNumber.isNotEmpty,
            bidAmount: bidAmountValue,
            estimatedDays: estimatedDaysValue,
            isChosen: _selectedBidderId == bidderId,
          );
        },
      ),
    );
  }

  Widget _buildBidderCard({
    required String bidderId,
    required String bidderName,
    String personName = '',
    required String message,
    required String status,
    required String verificationStatus,
    required bool hasBusinessRegistration,
    double? bidAmount,
    int? estimatedDays,
    required bool isChosen,
  }) {
    final isPending = status == 'pending';
    final isSelected = status == 'selected';
    final isRejected = status == 'rejected';
    final isVerified = verificationStatus == 'verified';
    final rating = _ratingsByBidder[bidderId];
    final average = rating?['average'] as double? ?? 0.0;
    final ratingCount = rating?['count'] as int? ?? 0;
    final showPersonName = personName.isNotEmpty && personName != bidderName;
    final highlighted = isChosen || isSelected;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BusinessTokens.card(
        borderColor: highlighted ? BusinessTokens.blue : BusinessTokens.border,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(BusinessTokens.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isPending
              ? () {
                  setState(() {
                    _selectedBidderId = bidderId;
                    _selectedBidderName = bidderName;
                  });
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: BusinessTokens.blueLight,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.storefront_outlined,
                        color: BusinessTokens.blue,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            bidderName,
                            style: BusinessTokens.sectionTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (showPersonName)
                            Text(
                              '대표자 $personName',
                              style: BusinessTokens.caption,
                            ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              BusinessStatusChip(
                                label: isVerified
                                    ? '사업자 인증'
                                    : hasBusinessRegistration
                                        ? '사업자 정보 등록'
                                        : verificationStatus.isEmpty
                                            ? '인증 정보 없음'
                                            : '인증 미완료',
                                tone: isVerified
                                    ? BusinessStatusTone.success
                                    : BusinessStatusTone.neutral,
                                icon: isVerified
                                    ? Icons.verified_outlined
                                    : Icons.info_outline_rounded,
                              ),
                              if (ratingCount > 0)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.star_rounded,
                                      size: 16,
                                      color: BusinessTokens.warning,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      '${average.toStringAsFixed(1)} ($ratingCount)',
                                      style: BusinessTokens.caption.copyWith(
                                        color: BusinessTokens.text,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (highlighted)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(
                          Icons.check_circle_rounded,
                          size: 22,
                          color: BusinessTokens.blue,
                        ),
                      ),
                  ],
                ),
                if ((bidAmount != null && bidAmount > 0) ||
                    (estimatedDays != null && estimatedDays > 0)) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BusinessTokens.card(
                      color: BusinessTokens.canvas,
                      radius: BusinessTokens.controlRadius,
                    ),
                    child: Row(
                      children: [
                        if (bidAmount != null && bidAmount > 0) ...[
                          const Icon(
                            Icons.payments_outlined,
                            size: 17,
                            color: BusinessTokens.blue,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${_formatAmount(bidAmount)}원',
                              style: const TextStyle(
                                color: BusinessTokens.text,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                        if (estimatedDays != null && estimatedDays > 0) ...[
                          const Icon(
                            Icons.calendar_today_outlined,
                            size: 15,
                            color: BusinessTokens.mutedText,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '$estimatedDays일',
                            style: BusinessTokens.caption.copyWith(
                              color: BusinessTokens.text,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                if (message.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('제안 메시지', style: BusinessTokens.caption),
                  const SizedBox(height: 4),
                  Text(message, style: BusinessTokens.body),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    _bidStatusChip(
                      isSelected: isSelected,
                      isRejected: isRejected,
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => _showBidderProfile(
                        bidderId,
                        bidderName,
                        personName: personName,
                      ),
                      child: const Text('사업자 정보'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bidStatusChip({
    required bool isSelected,
    required bool isRejected,
  }) {
    if (isSelected) {
      return const BusinessStatusChip(
        label: '배정 완료',
        tone: BusinessStatusTone.success,
        icon: Icons.check_rounded,
      );
    }
    if (isRejected) {
      return const BusinessStatusChip(
        label: '미선정',
        tone: BusinessStatusTone.neutral,
      );
    }
    return const BusinessStatusChip(
      label: '지원 검토',
      tone: BusinessStatusTone.info,
    );
  }

  String _formatAmount(double amount) {
    return amount.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (match) => '${match[1]},',
        );
  }
}
