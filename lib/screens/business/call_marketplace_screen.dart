import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:allsuriapp/services/marketplace_service.dart';
import 'package:allsuriapp/screens/business/estimate_management_screen.dart';
import 'package:allsuriapp/widgets/interactive_card.dart';
import 'package:allsuriapp/widgets/shimmer_widgets.dart';
import 'package:allsuriapp/services/chat_service.dart';
import 'package:provider/provider.dart';
import 'package:allsuriapp/models/estimate.dart';
import 'package:allsuriapp/services/estimate_service.dart';
import 'package:allsuriapp/screens/chat_screen.dart';
import 'package:allsuriapp/services/notification_service.dart';

class CallMarketplaceScreen extends StatefulWidget {
  final bool showSuccessMessage;
  final String? createdByUserId;
  
  const CallMarketplaceScreen({
    Key? key,
    this.showSuccessMessage = false,
    this.createdByUserId,
  }) : super(key: key);

  @override
  State<CallMarketplaceScreen> createState() => _CallMarketplaceScreenState();
}

class _CallMarketplaceScreenState extends State<CallMarketplaceScreen> {
  final MarketplaceService _market = MarketplaceService();
  late Future<List<Map<String, dynamic>>> _future;
  String _status = 'all';
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    print('CallMarketplaceScreen initState 시작');
    
    // 사용자 인증 상태 확인
    final currentUser = Supabase.instance.client.auth.currentUser;
    print('CallMarketplaceScreen: 현재 사용자 - ${currentUser?.id ?? "null (로그인 안됨)"}');
    
    if (currentUser == null) {
      print('⚠️ [CallMarketplaceScreen] 사용자가 로그인되어 있지 않습니다!');
    }
    
    _future = _market.listListings(status: _status, throwOnError: true, postedBy: widget.createdByUserId);
    print('CallMarketplaceScreen: _future 설정됨');
    
    _channel = Supabase.instance.client
        .channel('public:marketplace_listings')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'marketplace_listings',
          callback: (payload) {
            print('CallMarketplaceScreen Realtime 이벤트: $payload');
            if (!mounted) return;
            
            // 새로운 INSERT 이벤트 감지
            if (payload.eventType == 'INSERT') {
              final newListing = payload.newRecord;
              final title = newListing['title'] ?? 'Call 공사';
              final region = newListing['region'] ?? '지역 미정';
              
              print('🔔 새로운 Call 공사 감지: $title in $region');
              
              // 로컬 알림 표시
              try {
                NotificationService().showNewJobNotification(
                  title: '새로운 Call 공사!',
                  body: '$title - $region',
                  jobId: newListing['id']?.toString() ?? 'unknown',
                );
              } catch (e) {
                print('알림 표시 실패: $e');
              }
            }
            
            _reload();
          },
        )
        .subscribe();
    print('CallMarketplaceScreen: Realtime 구독 완료');
    
    // Call 공사 등록 성공 후 이동한 경우 성공 메시지 표시
    if (widget.showSuccessMessage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Call에 성공적으로 등록되었습니다!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
      });
    }

    // 화면 진입 직후 한번 더 새로고침하여 데이터 보장
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _reload();
      }
    });
  }

  Future<void> _reload() async {
    print('CallMarketplaceScreen _reload 시작: status=$_status');
    setState(() {
      _future = _market.listListings(status: _status, postedBy: widget.createdByUserId);
    });
    print('CallMarketplaceScreen _reload 완료');
  }

  @override
  void dispose() {
    if (_channel != null) {
      Supabase.instance.client.removeChannel(_channel!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Call 공사 현황', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _reload,
            tooltip: '새로고침',
          ),
        ],
      ),
      body: Column(
        children: [
          // 필터 제거: 항상 오픈(또는 withdrawn) 항목만 표시
          Expanded(
            child: RefreshIndicator(
              onRefresh: _reload,
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _future,
                builder: (context, snapshot) {
                  print('CallMarketplaceScreen FutureBuilder: connectionState=${snapshot.connectionState}, hasError=${snapshot.hasError}, data=${snapshot.data?.length ?? 0}');
                  
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    print('CallMarketplaceScreen: 로딩 중...');
                    return const ShimmerList(itemCount: 6, itemHeight: 110);
                  }
                  if (snapshot.hasError) {
                    print('CallMarketplaceScreen: 에러 발생 - ${snapshot.error}');
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 120),
                        Center(child: Text('불러오기 실패: ')),
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text('${snapshot.error}'),
                        ),
                      ],
                    );
                  }
                  final items = snapshot.data ?? [];
                  final visibleItems = items.where((row) {
                    final s = (row['status'] ?? '').toString();
                    return s == 'open' || s == 'withdrawn' || s == 'created'; // 'created' 상태 추가
                  }).toList();
                  print('CallMarketplaceScreen: 데이터 로드 완료 - ${visibleItems.length}개 항목(오픈/철회/생성됨만)');
                  if (visibleItems.isEmpty) {
                    print('CallMarketplaceScreen: 빈 목록 표시');
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 100),
                        Center(
                          child: Column(
                            children: [
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  color: Colors.orange[50],
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.work_outline_rounded,
                                  size: 50,
                                  color: Colors.orange[300],
                                ),
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                '현재 진행 중인 Call이 없습니다',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '아래로 당겨서 새로고침해보세요',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }
                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: visibleItems.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    padding: const EdgeInsets.all(16),
                    itemBuilder: (context, index) {
                      try {
                        final e = visibleItems[index];
                      final String id = (e['id'] ?? '').toString();
                      final String title = (e['title'] ?? e['description'] ?? '-') as String;
                      final String description = (e['description'] ?? '-') as String;
                      final String region = (e['region'] ?? '-') as String;
                      final String category = (e['category'] ?? '-') as String;
                      final String status = (e['status'] ?? '-') as String;
                      final createdAt = (e['createdat'] ?? e['createdAt']);
                      final budget = e['budget_amount'] ?? e['budgetAmount'];
                      final String? postedBy = (e['posted_by'] ?? e['postedBy'])?.toString();
                      final String jobId = (e['jobid'] ?? e['jobId'] ?? '').toString();
                      final String createdText = createdAt != null
                          ? (DateTime.tryParse(createdAt.toString())?.toLocal().toString().split('.').first ?? '-')
                          : '-';
                      final estimateAmount = e['estimate_amount'] ?? e['estimateAmount'];
                      final mediaUrls = e['media_urls'] is List ? List<String>.from(e['media_urls']) : <String>[];

                      // 상태 라벨은 이 화면에서 불필요 (항상 오픈/철회만 표시)

                      return GestureDetector(
                        onTap: () => _showCallDetail(e),
                        child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header row
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF3E0),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      category,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFFF57C00),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE8F5E9),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.location_on_outlined, size: 12, color: Colors.green[700]),
                                        const SizedBox(width: 4),
                                        Text(
                                          region,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.green[700],
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // Title
                              Text(
                                title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 17,
                                  height: 1.3,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              // Images thumbnail
                              if (mediaUrls.isNotEmpty) ...[
                                SizedBox(
                                  height: 80,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: mediaUrls.length > 3 ? 3 : mediaUrls.length,
                                    itemBuilder: (context, idx) {
                                      return Container(
                                        width: 80,
                                        margin: const EdgeInsets.only(right: 8),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(8),
                                          image: DecorationImage(
                                            image: CachedNetworkImageProvider(
                                              mediaUrls[idx],
                                              maxWidth: 240,
                                              maxHeight: 240,
                                            ),
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],

                              // Description
                              Text(
                                description,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[700],
                                  height: 1.4,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 12),
                              // Info row
                              Row(
                                children: [
                                  if (estimateAmount != null)
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE3F2FD),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.payments_outlined, size: 16, color: Color(0xFF1976D2)),
                                            const SizedBox(width: 6),
                                            Flexible(
                                              child: Text(
                                                '${estimateAmount is num ? estimateAmount.toInt().toString() : estimateAmount.toString()}원',
                                                style: const TextStyle(
                                                  color: Color(0xFF1976D2),
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  const SizedBox(width: 8),
                                  if (e['jobs'] != null && e['jobs'] is Map && (e['jobs']['commission_rate'] != null))
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.purple[50],
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.percent_rounded, size: 14, color: Colors.purple[700]),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${(e['jobs']['commission_rate']).toString()}%',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.purple[700],
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // Footer
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Icon(Icons.access_time_outlined, size: 14, color: Colors.grey[500]),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            createdText,
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 12,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Call 잡기 버튼
                                  SizedBox(
                                    height: 36,
                                    width: 100,
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFF57C00),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        elevation: 0,
                                      ),
                                      onPressed: (status == 'open' || status == 'withdrawn')
                                          ? () async {
                                              final ok = await _market.claimListing(id);
                                              if (!mounted) return;
                                              if (ok) {
                                                final me = Supabase.instance.client.auth.currentUser?.id;
                                                if (postedBy != null && postedBy.isNotEmpty && me != null && me.isNotEmpty) {
                                                  try {
                                                    await ChatService().createChatRoom('call_$id', postedBy, me);
                                                  } catch (_) {}
                                                }
                                                String estimateId = '';
                                                if (me != null && me.isNotEmpty && jobId.isNotEmpty) {
                                                  try {
                                                    final estimateSvc = context.read<EstimateService>();
                                                    estimateId = await estimateSvc.createEstimate(
                                                      Estimate(
                                                        id: '',
                                                        orderId: jobId,
                                                        customerId: '',
                                                        customerName: '고객',
                                                        businessId: me,
                                                        businessName: '사업자',
                                                        businessPhone: '',
                                                        equipmentType: '기타',
                                                        amount: (budget is num) ? budget.toDouble() : 0.0,
                                                        description: (e['description']?.toString() ?? title),
                                                        estimatedDays: 0,
                                                        createdAt: DateTime.now(),
                                                        visitDate: DateTime.now(),
                                                        status: Estimate.STATUS_COMPLETED,
                                                      ),
                                                    );
                                                  } catch (_) {}
                                                }
                                                // 채팅방 UUID 확보 후 채팅으로 이동
                                                String chatRoomId = '';
                                                if (postedBy != null && postedBy.isNotEmpty && me != null && me.isNotEmpty) {
                                                  try {
                                                    chatRoomId = await ChatService().createChatRoom('call_$id', postedBy, me, estimateId: estimateId);
                                                  } catch (_) {}
                                                }
                                                if (chatRoomId.isNotEmpty) {
                                                  // 채팅으로 먼저 이동
                                                  if (!mounted) return;
                                                  Navigator.pushReplacement(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) => ChatScreen(chatRoomId: chatRoomId, chatRoomTitle: '원 사업자와 채팅'),
                                                    ),
                                                  );
                                                } else {
                                                  // 기존 흐름 유지
                                                  Navigator.pushReplacement(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) => const EstimateManagementScreen(initialStatus: Estimate.STATUS_COMPLETED),
                                                  ),
                                                  );
                                                }
                                              } else {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(content: Text('이미 다른 사업자가 가져갔습니다')),
                                                );
                                              }
                                            }
                                          : null,
                                      icon: const Icon(Icons.touch_app_rounded, size: 16),
                                      label: const Text('잡기', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                      } catch (e, stackTrace) {
                        print('CallMarketplaceScreen 카드 렌더링 에러: $e');
                        print('StackTrace: $stackTrace');
                        return Container(
                          height: 100,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: Text('카드 렌더링 오류: $e'),
                          ),
                        );
                      }
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _claimListing(String id) async {
    try {
      print('🔍 [_claimListing] 공사 잡기 시작: $id');
      
      // 사용자 로그인 확인 (AuthService 사용)
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUserId = authService.currentUser?.id;
      print('   현재 사용자 (AuthService): ${currentUserId ?? "null"}');
      print('   현재 사용자 (Supabase): ${Supabase.instance.client.auth.currentUser?.id ?? "null"}');
      
      if (currentUserId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('로그인이 필요합니다'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
      
      print('   → marketplace_service에서 공사 잡기 요청 중...');
      final ok = await _market.claimListing(id);
      
      if (!mounted) return;
      
      if (ok) {
        print('   ✅ 공사 잡기 성공!');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('공사를 성공적으로 잡았습니다!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
        
        // 목록 새로고침
        await _reload();
      } else {
        print('   ❌ 공사 잡기 실패 (이미 다른 사업자가 잡았거나 오류)');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('이미 다른 사업자가 가져갔거나 오류가 발생했습니다'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e, stackTrace) {
      print('❌ [_claimListing] 에러 발생: $e');
      print('   StackTrace: $stackTrace');
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('공사 잡기 실패: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _deleteJob(String jobId) async {
    try {
      print('🔍 [_deleteJob] 공사 삭제 시작: $jobId');
      
      // jobs 테이블에서 삭제 (marketplace_listings는 ON DELETE CASCADE로 자동 삭제)
      final response = await Supabase.instance.client
          .from('jobs')
          .delete()
          .eq('id', jobId);
      
      print('✅ [_deleteJob] 공사 삭제 완료');
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('공사가 삭제되었습니다.'), backgroundColor: Colors.green),
      );
      
      // 상세 화면 닫기 및 리스트 새로고침
      Navigator.pop(context);
      _reload();
      
    } catch (e) {
      print('❌ [_deleteJob] 삭제 실패: $e');
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('공사 삭제 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showCallDetail(Map<String, dynamic> data) {
    final String title = (data['title'] ?? data['description'] ?? '-') as String;
    final String description = (data['description'] ?? '-') as String;
    final String region = (data['region'] ?? '-') as String;
    final String category = (data['category'] ?? '-') as String;
    final estimateAmount = data['estimate_amount'] ?? data['estimateAmount'];
    final mediaUrls = data['media_urls'] is List ? List<String>.from(data['media_urls']) : <String>[];
    final budget = data['budget_amount'] ?? data['budgetAmount'];
    final createdAt = data['createdat'] ?? data['createdAt'];
    final String jobId = (data['jobid'] ?? data['id'] ?? '').toString();
    final String postedBy = (data['posted_by'] ?? '').toString();
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isOwner = currentUserId == postedBy;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            elevation: 0,
            backgroundColor: Colors.white,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.share_outlined, color: Colors.black),
                onPressed: () {},
              ),
              if (isOwner)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('공사 삭제'),
                        content: const Text('이 공사를 삭제하시겠습니까? 삭제된 데이터는 복구될 수 없습니다.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('취소'),
                          ),
                          TextButton(
                            onPressed: () async {
                              Navigator.pop(dialogContext);
                              await _deleteJob(jobId);
                            },
                            child: const Text('삭제', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
          body: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.only(bottom: 80),
                children: [
                  // 이미지 갤러리
                  if (mediaUrls.isNotEmpty)
                    SizedBox(
                      height: 350,
                      child: Stack(
                        children: [
                          PageView.builder(
                            itemCount: mediaUrls.length,
                            itemBuilder: (context, index) {
                              return Container(
                                color: Colors.grey[200],
                                child: Image.network(
                                  mediaUrls[index],
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => Container(
                                    color: Colors.grey[300],
                                    child: const Icon(Icons.image_not_supported_outlined),
                                  ),
                                ),
                              );
                            },
                          ),
                          // 이미지 개수 표시
                          Positioned(
                            bottom: 16,
                            right: 16,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '1 / ${mediaUrls.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      height: 350,
                      color: Colors.grey[200],
                      child: const Icon(Icons.image_not_supported_outlined, size: 80),
                    ),
                  
                  // 콘텐츠 섹션
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 카테고리 & 지역
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF3E0),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                category,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFFF57C00),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.location_on_outlined, size: 14, color: Colors.green[700]),
                                  const SizedBox(width: 4),
                                  Text(
                                    region,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.green[700],
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        
                        // 제목
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 12),
                        
                        // 예산
                        if (budget != null)
                          Text(
                            '예상 예산: ${budget is num ? '${(budget as num).toInt().toString()}원' : budget.toString()}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFF57C00),
                            ),
                          ),
                        
                        const SizedBox(height: 12),
                        
                        // 올린 시간
                        Row(
                          children: [
                            Icon(Icons.access_time_outlined, size: 14, color: Colors.grey[500]),
                            const SizedBox(width: 6),
                            Text(
                              createdAt != null
                                  ? (DateTime.tryParse(createdAt.toString())?.toLocal().toString().split('.').first ?? '-')
                                  : '-',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // 구분선
                        Divider(color: Colors.grey[300], thickness: 1),
                        
                        const SizedBox(height: 24),
                        
                        // 상세 설명
                        const Text(
                          '공사 정보',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[200]!, width: 1),
                          ),
                          child: Text(
                            description,
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.grey[800],
                              height: 1.6,
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ],
              ),
              
              // 하단 "잡기" 버튼
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(16),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          await _claimListing(data['id'].toString());
                        },
                        icon: const Icon(Icons.touch_app_rounded, size: 20),
                        label: const Text(
                          '공사 잡기',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF57C00),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


