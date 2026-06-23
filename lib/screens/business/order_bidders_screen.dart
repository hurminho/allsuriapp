import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:allsuriapp/services/api_service.dart';
import 'package:allsuriapp/services/auth_service.dart';
import 'package:allsuriapp/services/chat_service.dart';
import 'package:allsuriapp/widgets/loading_indicator.dart';
import 'package:allsuriapp/services/business_verify_service.dart';
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
  Future<void> _showBidderProfile(String bidderId, String bidderName, {String personName = ''}) async {
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
                  Text(bidderName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  if (personName.isNotEmpty && personName != bidderName)
                    Text('대표자: $personName', style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.normal)),
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
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${rating['count']}개의 후기',
                            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
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
                      child: Text('아직 작성된 후기가 없습니다.', style: TextStyle(color: Colors.grey)),
                    ),
                  ),
                ] else ...[
                  const Text('받은 후기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  ...reviews.map((review) => Container(
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
                            ...List.generate(5, (i) => Icon(
                              i < (review['rating'] ?? 0) ? Icons.star : Icons.star_border,
                              color: Colors.amber[700],
                              size: 16,
                            )),
                            const SizedBox(width: 8),
                            Text('${review['rating']}.0', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        if (review['tags'] != null && (review['tags'] as List).isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: (review['tags'] as List).take(3).map((tag) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(tag.toString(), style: const TextStyle(fontSize: 11)),
                            )).toList(),
                          ),
                        ],
                        if (review['comment'] != null && review['comment'].toString().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(review['comment'].toString(), 
                            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          review['created_at']?.toString().substring(0, 10) ?? '',
                          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  )).toList(),
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
      final response = await api.get('/market/listings/${widget.listingId}/bids');

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
        _error = '입찰자 목록을 불러오는데 실패했습니다';
        _loading = false;
      });
    }
  }

  Future<void> _selectBidder(String bidderId, String bidderName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('입찰자 선택'),
        content: Text('$bidderName님을 선택하시겠습니까?\n선택하면 다른 입찰은 거절되며 채팅방이 생성됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('선택하기'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // ⭐ 낙찰 사전 가드: 사업자번호 등록 여부만 점검
    final bidderEligible = await BusinessVerifyService.isUserEligibleAsBusiness(bidderId);
    if (!mounted) return;
    if (!bidderEligible) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.orange),
              SizedBox(width: 10),
              Text('낙찰을 진행할 수 없습니다'),
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
      final response = await api.post('/market/listings/${widget.listingId}/select-bidder', {
        'bidderId': bidderId,
        'ownerId': currentUserId,
      });

      // 서버(RPC)가 BIDDER_NOT_VERIFIED 등으로 차단한 경우의 표준 에러 처리
      if (response['success'] != true) {
        final errStr = (response['error'] ?? response['message'] ?? '').toString();
        if (errStr.contains('BIDDER_NOT_VERIFIED') ||
            errStr.contains('진위확인이 완료되지 않아')) {
          if (!mounted) return;
          Navigator.of(context, rootNavigator: true).pop(); // 로딩 닫기
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('낙찰을 진행할 수 없습니다'),
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
          
          // 1. marketplace_listings의 budget_amount 조회
          final listingData = await Supabase.instance.client
              .from('marketplace_listings')
              .select('budget_amount')
              .eq('id', widget.listingId)
              .single();
          
          final budgetAmount = listingData['budget_amount'];
          print('   오더 예산 금액: $budgetAmount');
          
          // 2. jobs 테이블의 awarded_amount 업데이트
          if (budgetAmount != null && response['data']?['jobId'] != null) {
            final jobId = response['data']['jobId'];
            print('   Job ID: $jobId');
            
            await Supabase.instance.client
                .from('jobs')
                .update({'awarded_amount': budgetAmount})
                .eq('id', jobId);
            
            print('✅ [OrderBiddersScreen] awarded_amount 업데이트 완료: $budgetAmount원');
          } else {
            print('⚠️ [OrderBiddersScreen] budgetAmount 또는 jobId가 없음');
          }
          print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        } catch (amountErr) {
          print('❌ [OrderBiddersScreen] awarded_amount 업데이트 실패 (무시됨): $amountErr');
          print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        }
        
        // 채팅방 생성 및 이동
        if (!mounted) return;
        
        // 로딩 닫기
        Navigator.pop(context); 
        
        // 성공 메시지
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$bidderName님이 선택되었습니다. 채팅방으로 이동합니다.')),
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
                content: Text('낙찰은 완료되었으나 채팅방 생성에 실패했습니다: ${chatErr.toString()}'),
                duration: const Duration(seconds: 5),
              ),
            );
            Navigator.pop(context); // 입찰자 목록 화면 닫기
          }
        }
      } else {
        throw Exception(response['message'] ?? '입찰자 선택 실패');
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('입찰자 목록'),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: LoadingIndicator(message: '입찰자 정보를 불러오고 있습니다...'))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(_error!),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadBidders,
                        child: const Text('다시 시도'),
                      ),
                    ],
                  ),
                )
              : _bidders.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people_outline, size: 48, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('아직 입찰자가 없습니다'),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadBidders,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _bidders.length,
                        itemBuilder: (context, index) {
                          final bid = _bidders[index];
                          final bidder = bid['bidder'] as Map<String, dynamic>?;
                          final status = bid['status']?.toString() ?? 'pending';
                          
                          // 상호명(businessname) 우선 표시, 없으면 '상호명 미입력'
                          final rawBizName = bidder?['businessname']?.toString() ?? '';
                          final bidderName = rawBizName.isNotEmpty ? rawBizName : '상호명 없음';
                          // 대표자 개인 이름 (상호명과 다를 때만 표시)
                          final personName = bidder?['name']?.toString() ?? '';
                          final avatarUrl = bidder?['avatar_url']?.toString();
                          final estimatesCount = bidder?['estimates_created_count'] ?? 0;
                          final jobsCount = bidder?['jobs_accepted_count'] ?? 0;
                          final message = bid['message']?.toString() ?? '';
                          final createdAt = bid['created_at']?.toString() ?? '';
                          
                          // 활동 지역과 전문 분야 가져오기
                          final serviceAreas = bidder?['serviceareas'] ?? bidder?['serviceAreas'] ?? bidder?['service_areas'];
                          List<String> serviceAreasList = [];
                          if (serviceAreas is List) {
                            serviceAreasList = serviceAreas.map((e) => e.toString()).toList();
                          } else if (serviceAreas is String && serviceAreas.isNotEmpty) {
                            serviceAreasList = [serviceAreas];
                          }
                          
                          final specialties = bidder?['specialties'];
                          List<String> specialtiesList = [];
                          if (specialties is List) {
                            specialtiesList = specialties.map((e) => e.toString()).toList();
                          } else if (specialties is String && specialties.isNotEmpty) {
                            specialtiesList = [specialties];
                          }

                          // 추가 정보 (region 컬럼이 users 테이블에 없어 address로 폴백)
                          final region = (bidder?['address']
                              ?? bidder?['region'])?.toString() ?? '';
                          final category = bidder?['category']?.toString() ?? '';
                          final description = (bidder?['bio']
                              ?? bidder?['description'])?.toString() ?? '';
                          final businessNum = (bidder?['businessnumber']
                              ?? bidder?['businessregistrationnumber'])?.toString() ?? '';
                          final bidAmount = bid['bid_amount'];
                          final estimatedDays = bid['estimated_days'];
                          final double? bidAmountVal = bidAmount != null
                              ? (bidAmount as num).toDouble() : null;
                          final int? estimatedDaysVal = estimatedDays != null
                              ? (estimatedDays as num).toInt() : null;

                          return _buildBidderCard(
                            bidderId: bid['bidder_id']?.toString() ?? '',
                            bidderName: bidderName,
                            personName: personName,
                            avatarUrl: avatarUrl,
                            jobsCount: jobsCount is int ? jobsCount : int.tryParse(jobsCount.toString()) ?? 0,
                            message: message,
                            createdAt: createdAt,
                            status: status,
                            serviceAreas: serviceAreasList,
                            specialties: specialtiesList,
                            region: region,
                            category: category,
                            description: description,
                            businessNum: businessNum,
                            bidAmount: bidAmountVal,
                            estimatedDays: estimatedDaysVal,
                          );
                        },
                      ),
                    ),
    );
  }

  Widget _buildBidderCard({
    required String bidderId,
    required String bidderName,
    String personName = '',
    String? avatarUrl,
    required int jobsCount,
    required String message,
    required String createdAt,
    required String status,
    List<String> serviceAreas = const [],
    List<String> specialties = const [],
    String region = '',
    String category = '',
    String description = '',
    String businessNum = '',
    double? bidAmount,
    int? estimatedDays,
  }) {
    // 상호명과 대표자명이 다를 때만 대표자명 표시
    final showPersonName = personName.isNotEmpty && personName != bidderName;
    final isPending = status == 'pending';
    final isSelected = status == 'selected';
    final isRejected = status == 'rejected';
    final hasBusinessReg = businessNum.isNotEmpty && businessNum != '등록번호 없음';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: isSelected ? 4 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected ? const Color(0xFF10B981) : isRejected ? Colors.grey[300]! : Colors.transparent,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── 견적가 배너 (있을 때만) ─────────────────────────
            if (bidAmount != null && bidAmount > 0)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.attach_money_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      '견적가  ₩${bidAmount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    if (estimatedDays != null && estimatedDays > 0) ...[
                      const Spacer(),
                      const Icon(Icons.calendar_today_outlined, color: Colors.white70, size: 14),
                      const SizedBox(width: 4),
                      Text('$estimatedDays일', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ],
                ),
              ),

            // ── 프로필 헤더 ────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => _showBidderProfile(bidderId, bidderName, personName: personName),
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: Colors.blue[100],
                        backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                            ? NetworkImage(avatarUrl) : null,
                        child: avatarUrl == null || avatarUrl.isEmpty
                            ? Icon(Icons.person, size: 34, color: Colors.blue[700]) : null,
                      ),
                      if (hasBusinessReg)
                        Positioned(
                          right: 0, bottom: 0,
                          child: Container(
                            width: 18, height: 18,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981), shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.verified, color: Colors.white, size: 12),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _showBidderProfile(bidderId, bidderName, personName: personName),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 상호명 (주표시)
                                  Text(bidderName,
                                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  // 대표자명 (상호명과 다를 때만)
                                  if (showPersonName)
                                    Text('대표자: $personName',
                                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                    ),
                                ],
                              ),
                            ),
                            if (hasBusinessReg)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green[50],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.green),
                                ),
                                child: const Text('사업자등록',
                                  style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // 평점 (사전 로드된 _ratingsByBidder 사용)
                        Builder(
                          builder: (context) {
                            final rating = _ratingsByBidder[bidderId];
                            final avg = rating?['average'] as double? ?? 0.0;
                            final cnt = rating?['count'] as int? ?? 0;
                            return Row(children: [
                              ...List.generate(5, (i) => Icon(
                                i < avg.round() ? Icons.star : Icons.star_border,
                                size: 14, color: Colors.amber[700],
                              )),
                              const SizedBox(width: 4),
                              Text(cnt > 0 ? '${avg.toStringAsFixed(1)} ($cnt건)' : '후기 없음',
                                style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                            ]);
                          },
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.work_outline, size: 13, color: Colors.grey[500]),
                            const SizedBox(width: 3),
                            Text('완료 $jobsCount건', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                            if (category.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Icon(Icons.category_outlined, size: 13, color: Colors.grey[500]),
                              const SizedBox(width: 3),
                              Text(category, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── 지역 / 카테고리 정보 ─────────────────────────────
            if (region.isNotEmpty || serviceAreas.isNotEmpty || specialties.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (region.isNotEmpty)
                      _infoRow(Icons.location_on_outlined, '활동 지역', region, Colors.blue),
                    if (region.isNotEmpty && serviceAreas.isNotEmpty) const SizedBox(height: 4),
                    if (serviceAreas.isNotEmpty)
                      _infoRow(Icons.map_outlined, '서비스 지역',
                        serviceAreas.take(3).join(', ') + (serviceAreas.length > 3 ? ' 외 ${serviceAreas.length-3}곳' : ''),
                        Colors.blue),
                    if (specialties.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _infoRow(Icons.build_outlined, '전문 분야',
                        specialties.take(2).join(', ') + (specialties.length > 2 ? ' 외 ${specialties.length-2}개' : ''),
                        Colors.orange),
                    ],
                  ],
                ),
              ),

            // ── 사업자 소개 ──────────────────────────────────────
            if (description.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('사업자 소개', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[600])),
                    const SizedBox(height: 4),
                    Text(description, style: TextStyle(fontSize: 13, color: Colors.grey[800]), maxLines: 3, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],

            // ── 입찰 메시지 ──────────────────────────────────────
            if (message.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.indigo[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.indigo.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('입찰 메시지', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo[600])),
                    const SizedBox(height: 4),
                    Text(message, style: TextStyle(fontSize: 13, color: Colors.grey[800])),
                  ],
                ),
              ),
            ],

            // ── 입찰 시각 ────────────────────────────────────────
            Row(
              children: [
                Icon(Icons.access_time, size: 13, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text(_formatTime(createdAt), style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _showBidderProfile(bidderId, bidderName, personName: personName),
                  icon: Icon(Icons.reviews_outlined, size: 14, color: Colors.blue[700]),
                  label: Text('후기 보기', style: TextStyle(fontSize: 12, color: Colors.blue[700])),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero),
                ),
              ],
            ),

            // ── 상태 배지 / 선택 버튼 ────────────────────────────
            if (isSelected) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 18),
                    SizedBox(width: 6),
                    Text('낙찰 확정', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 15)),
                  ],
                ),
              ),
            ] else if (isRejected) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey[400]!),
                ),
                child: const Center(child: Text('미선택', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
              ),
            ] else if (isPending) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _selectBidder(bidderId, bidderName),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A8A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.check_circle_outline, size: 20),
                  label: const Text('이 사업자 낙찰하기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, MaterialColor color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: color[700]),
        const SizedBox(width: 4),
        Text('$label: ', style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
        Expanded(child: Text(value, style: TextStyle(fontSize: 12, color: Colors.grey[800]), overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  String _formatTime(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inMinutes < 1) {
        return '방금 전';
      } else if (diff.inHours < 1) {
        return '${diff.inMinutes}분 전';
      } else if (diff.inDays < 1) {
        return '${diff.inHours}시간 전';
      } else if (diff.inDays < 7) {
        return '${diff.inDays}일 전';
      } else {
        return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      return dateStr;
    }
  }
}
