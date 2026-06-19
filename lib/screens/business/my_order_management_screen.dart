import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart'; // 추가
import '../../services/marketplace_service.dart'; // 추가
import '../../services/kakao_share_service.dart';
import '../../widgets/loading_indicator.dart';
import '../business/order_bidders_screen.dart';
import '../business/order_review_screen.dart';
import '../business/order_process_screen.dart';
import '../../services/api_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../chat_screen.dart'; // 추가

/// 내 오더 관리 화면
/// - 내가 생성한 오더만 표시
/// - "진행 중" 필터에 걸린 공사들 (assigned 상태)
/// - 입찰자 선택, 리뷰 작성 등 오더 소유자 기능
class MyOrderManagementScreen extends StatefulWidget {
  final String? highlightedOrderId; // 포커싱할 오더 ID
  final String? initialFilter; // 초기 필터 ('all', 'pending', 'in_progress', 'completed')
  
  const MyOrderManagementScreen({
    Key? key, 
    this.highlightedOrderId,
    this.initialFilter,
  }) : super(key: key);

  @override
  State<MyOrderManagementScreen> createState() => _MyOrderManagementScreenState();
}

class _MyOrderManagementScreenState extends State<MyOrderManagementScreen> {
  List<Map<String, dynamic>> _myOrders = [];
  bool _isLoading = false;
  late String _filter; // all, pending, in_progress, completed
  RealtimeChannel? _channel;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    
    // 초기 필터 설정
    _filter = widget.initialFilter ?? 'all';
    
    // 🔒 사업자 승인 상태 확인
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkBusinessApproval();
    });
    
    _loadMyOrders();
    _subscribeToOrderBids();
  }
  
  /// 🔒 사업자 승인 상태 확인
  void _checkBusinessApproval() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    
    if (user == null) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('로그인이 필요합니다.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    if (user.role != 'business') {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('사업자 계정만 접근 가능합니다.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    if (user.businessStatus != 'approved') {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('사업자 승인이 필요합니다. 관리자 승인 후 이용 가능합니다.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }
  }
  
  @override
  void dispose() {
    _channel?.unsubscribe();
    _scrollController.dispose();
    super.dispose();
  }
  
  /// 내 오더에 대한 입찰 및 상태 변경 실시간 구독
  void _subscribeToOrderBids() {
    final currentUserId = context.read<AuthService>().currentUser?.id;
    if (currentUserId == null) {
      print('❌ [MyOrderManagement] 현재 사용자 ID가 없어 실시간 구독 불가');
      return;
    }
    
    print('🔔 [MyOrderManagement] 입찰 및 상태 실시간 알림 구독 시작');
    print('   currentUserId: $currentUserId');
    
    _channel = Supabase.instance.client
        .channel('my_order_realtime_$currentUserId')
        // 새 입찰 감지
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'order_bids',
          callback: (payload) {
            print('🔔 [MyOrderManagement] 새 입찰 감지!');
            print('   Payload: $payload');
            
            // 새 입찰이 들어온 경우 목록 새로고침
            _loadMyOrders();
            
            // 사용자에게 알림 표시
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('새로운 입찰이 들어왔습니다!'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 3),
                ),
              );
            }
          },
        )
        // marketplace_listings 상태 변경 감지 (공사 완료, 확인 대기 등)
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'marketplace_listings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'posted_by',
            value: currentUserId,
          ),
          callback: (payload) {
            print('🔔 [MyOrderManagement] 내 오더 상태 변경 감지!');
            print('   Old: ${payload.oldRecord}');
            print('   New: ${payload.newRecord}');
            
            final oldStatus = payload.oldRecord?['status'];
            final newStatus = payload.newRecord?['status'];
            
            if (oldStatus != newStatus) {
              print('   상태 변경: $oldStatus → $newStatus');
              
              // 상태가 변경된 경우 목록 새로고침
              _loadMyOrders();
              
              // 사용자에게 알림 표시
              if (mounted && newStatus == 'awaiting_confirmation') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('공사가 완료되었습니다! 확인 후 리뷰를 작성해주세요.'),
                    backgroundColor: Colors.orange,
                    duration: Duration(seconds: 4),
                  ),
                );
              }
            }
          },
        )
        .subscribe((status, error) {
          if (error != null) {
            print('❌ [MyOrderManagement] 실시간 구독 에러: $error');
          } else {
            print('✅ [MyOrderManagement] 실시간 구독 상태: $status');
          }
        });
  }

  Future<void> _loadMyOrders() async {
    setState(() => _isLoading = true);

    try {
      final authService = context.read<AuthService>();
      final currentUserId = authService.currentUser?.id;

      if (currentUserId == null) {
        print('❌ [MyOrderManagement] 현재 사용자 ID가 없음');
        return;
      }

      print('🔍 [MyOrderManagement] 내가 생성한 오더 로드 시작');
      print('   현재 사용자 ID: $currentUserId');

      final api = ApiService();
      final response = await api.get('/market/listings?status=all&postedBy=$currentUserId');

      if (response['success'] != true) {
        throw Exception(response['error'] ?? 'API 호출 실패');
      }

      final data = List<Map<String, dynamic>>.from(response['data'] ?? []);

      print('🔍 [MyOrderManagement] 조회된 오더: ${data.length}개');
      if (data.isNotEmpty) {
        print('   첫 번째 오더: ${data[0]['id']} - ${data[0]['title']}');
        print('   posted_by: ${data[0]['posted_by']}');
      }

      setState(() {
        _myOrders = data;
      });
      
      // 데이터가 0개일 때는 알림만 표시
      if (data.isEmpty && mounted) {
        print('ℹ️ [MyOrderManagement] 생성한 오더가 없습니다');
      }
    } catch (e, stackTrace) {
      print('❌ [MyOrderManagement] 오더 로드 실패: $e');
      print('   StackTrace: $stackTrace');
      
      // 502 에러이거나 데이터 없음이 아닌 경우에만 에러 메시지 표시
      final errorMsg = e.toString();
      final is502Error = errorMsg.contains('502') || errorMsg.contains('Bad Gateway');
      
      if (mounted && !is502Error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오더 로드 실패: $e'), backgroundColor: Colors.red),
        );
      } else if (is502Error) {
        // 502 에러는 로그만 출력하고 사용자에게는 표시하지 않음
        print('ℹ️ [MyOrderManagement] 서버 일시적 오류 (502), 조용히 처리');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        
        // 🎯 포커싱: highlightedOrderId가 있으면 해당 오더로 스크롤
        if (widget.highlightedOrderId != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToHighlightedOrder();
          });
        }
      }
    }
  }

  void _scrollToHighlightedOrder() {
    if (widget.highlightedOrderId == null || !mounted) return;

    // 약간의 지연을 두어 ListView가 완전히 빌드된 후 스크롤
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted || !_scrollController.hasClients) return;
      
      final index = _filteredOrders.indexWhere((order) => order['id']?.toString() == widget.highlightedOrderId);

      print('🔍 [_scrollToHighlightedOrder] 찾는 중...');
      print('   highlightedOrderId: ${widget.highlightedOrderId}');
      print('   _filteredOrders 개수: ${_filteredOrders.length}');
      print('   현재 필터: $_filter');
      print('   찾은 index: $index');

      if (index != -1) {
        // 대략적인 아이템 높이 (카드 높이 + spacing)
        const double itemHeight = 250.0;
        final double offset = index * itemHeight;
        final double maxScroll = _scrollController.position.maxScrollExtent;
        
        // 스크롤 범위를 초과하지 않도록 제한
        final double targetOffset = offset > maxScroll ? maxScroll : offset;
        
        _scrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOutCubic,
        );
        
        print('✅ [MyOrderManagement] ${widget.highlightedOrderId} 오더로 스크롤 (index: $index, offset: $targetOffset)');
      } else {
        print('⚠️ [MyOrderManagement] highlightedOrderId를 찾을 수 없음');
        if (_filteredOrders.isNotEmpty) {
          print('   첫 번째 오더 ID: ${_filteredOrders.first['id']}');
        }
      }
    });
  }

  List<Map<String, dynamic>> get _filteredOrders {
    if (_filter == 'all') return _myOrders;
    
    return _myOrders.where((order) {
      final status = order['status']?.toString() ?? '';
      
      switch (_filter) {
        case 'pending':
          // 입찰 대기중 (created, open)
          return status == 'created' || status == 'open';
        case 'in_progress':
          // 진행 중 (assigned)
          return status == 'assigned';
        case 'completed':
          // 완료됨 (completed, awaiting_confirmation)
          return status == 'completed' || status == 'awaiting_confirmation';
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final me = context.read<AuthService>().currentUser?.id ?? '';
    
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          '내 오더 관리',
          style: TextStyle(
            color: Color(0xFF1E3A8A),
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Color(0xFF1E3A8A)),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF1E3A8A)),
            onPressed: _loadMyOrders,
            tooltip: '새로고침',
          ),
        ],
      ),
      body: _isLoading
          ? const LoadingIndicator(
              message: '내 오더를 불러오는 중...',
              subtitle: '잠시만 기다려주세요',
            )
          : Column(
              children: [
                _buildFilterChips(),
                Expanded(
                  child: _filteredOrders.isEmpty
                      ? _buildEmptyState()
                      : ListView.separated(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          itemCount: _filteredOrders.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final order = _filteredOrders[index];
                            final isHighlighted = widget.highlightedOrderId != null && order['id']?.toString() == widget.highlightedOrderId;
                            return _buildOrderCard(order, me, isHighlighted);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildFilterChips() {
    final pendingCount = _myOrders.where((o) {
      final s = o['status']?.toString() ?? '';
      return s == 'created' || s == 'open';
    }).length;
    
    final inProgressCount = _myOrders.where((o) => o['status'] == 'assigned').length;
    
    final completedCount = _myOrders.where((o) {
      final s = o['status']?.toString() ?? '';
      return s == 'completed' || s == 'awaiting_confirmation';
    }).length;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '필터',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildChip('전체', 'all', Icons.dashboard_outlined, _myOrders.length),
                const SizedBox(width: 10),
                _buildChip('입찰 대기', 'pending', Icons.schedule, pendingCount),
                const SizedBox(width: 10),
                _buildChip('진행 중', 'in_progress', Icons.construction_outlined, inProgressCount),
                const SizedBox(width: 10),
                _buildChip('완료', 'completed', Icons.check_circle_outline, completedCount),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String label, String value, IconData icon, int count) {
    final isSelected = _filter == value;
    final color = const Color(0xFFF57C00); // Orange for orders
    
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey[300]!,
            width: 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Colors.white : color,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? Colors.white : Colors.grey[700],
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white.withOpacity(0.3) : color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : color,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.orange[50],
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.handyman_outlined,
              size: 50,
              color: Colors.orange[700],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '생성한 오더가 없습니다',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '공사 등록 시 "오더로 올리기"를 선택해보세요',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order, String me, [bool isHighlighted = false]) {
    final String title = order['title']?.toString() ?? '제목 없음';
    final String description = order['description']?.toString() ?? '';
    final String status = order['status']?.toString() ?? '';
    final int bidCount = order['bid_count'] is int 
        ? order['bid_count'] as int 
        : int.tryParse(order['bid_count']?.toString() ?? '0') ?? 0;
    final String listingId = order['id']?.toString() ?? '';
    final String jobId = order['jobid']?.toString() ?? ''; // 추가
    final budget = order['budget_amount'];
    final selectedBidderId = order['selected_bidder_id']?.toString();
    final completedBy = order['completed_by']?.toString();
    final claimedBy = order['claimed_by']?.toString();

    print('📋 [_buildOrderCard] 오더: $title');
    print('   status: $status');
    print('   jobId: $jobId');
    print('   completedBy: $completedBy');
    print('   selectedBidderId: $selectedBidderId');
    print('   claimedBy: $claimedBy');
    print('   bidCount: $bidCount');

    // 상태 배지
    final badge = _getBadgeForStatus(status, bidCount, selectedBidderId, completedBy);

    // 삭제 가능 여부 (낙찰 전 상태 + 생성자)
    final bool canDelete = (status == 'created' || status == 'open') && selectedBidderId == null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 800),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: isHighlighted 
            ? Border.all(color: const Color(0xFF1E3A8A), width: 3)
            : Border.all(color: Colors.grey[200]!, width: 1),
        boxShadow: isHighlighted ? [
          BoxShadow(
            color: const Color(0xFF1E3A8A).withOpacity(0.3),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ] : [
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
            // Header
            Row(
              children: [
                // Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: badge.color,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(badge.icon, size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        badge.label,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // 카카오 공유 버튼 (낙찰 전 오더에 한해 노출)
                if (listingId.isNotEmpty && selectedBidderId == null)
                  IconButton(
                    onPressed: () => _shareOrder(order),
                    icon: const Icon(Icons.share_outlined, color: Color(0xFF1E3A8A), size: 22),
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    tooltip: '오더 공유',
                  ),
                if (listingId.isNotEmpty && selectedBidderId == null)
                  const SizedBox(width: 8),
                // 프로세스 보기 버튼
                if (listingId.isNotEmpty)
                  IconButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OrderProcessScreen(
                          listingId: listingId,
                          orderTitle: title,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.timeline_rounded, color: Color(0xFF1E3A8A), size: 22),
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    tooltip: '프로세스 보기',
                  ),
                const SizedBox(width: 8),
                // 삭제 버튼 (추가)
                if (canDelete)
                  IconButton(
                    onPressed: () => _deleteOrder(listingId, jobId, title),
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    tooltip: '오더 삭제',
                  ),
                const SizedBox(width: 8),
                // Budget
                if (budget != null)
                  Text(
                    '₩${budget.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E3A8A),
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
                fontSize: 16,
                color: Color(0xFF1E3A8A),
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            // Description
            if (description.isNotEmpty)
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
            
            // 버튼 로직: 완료 상태에 따라 다른 버튼 표시
            // 1. 완료된 오더 (completed): 상세보기 + 작성한 후기 보기
            if (status == 'completed') ...[
              const SizedBox(height: 12),
              Stack(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _showCompletedOrderDetail(order),
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: const Text(
                        '공사 상세 및 후기 보기',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF64748B),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                  if (listingId.isNotEmpty)
                    Positioned(
                      top: 0,
                      bottom: 0,
                      right: 0,
                      child: Center(
                        child: InkWell(
                          onTap: () async {
                            // 채팅방 이동 로직
                            try {
                              final chatService = ChatService();
                              final authService = Provider.of<AuthService>(context, listen: false);
                              final currentUserId = authService.currentUser?.id;
                              
                              if (currentUserId == null) return;
                              
                              // 상대방 ID 확인 (낙찰된 사업자)
                              final targetUserId = completedBy ?? selectedBidderId ?? claimedBy;
                              
                              if (targetUserId == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('대화할 상대방 정보를 찾을 수 없습니다.')),
                                );
                                return;
                              }
                              
                              // 채팅방 생성/조회
                              final chatRoomId = await chatService.ensureChatRoom(
                                customerId: currentUserId, // 나 (오더 소유자)
                                businessId: targetUserId, // 낙찰받은 사업자
                                listingId: listingId,
                                title: title,
                              );
                              
                              // 채팅 화면으로 이동
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatScreen(
                                    chatRoomId: chatRoomId,
                                    chatRoomTitle: title,
                                  ),
                                ),
                              );
                            } catch (e) {
                              print('❌ 채팅방 이동 실패: $e');
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('채팅방을 열 수 없습니다.')),
                              );
                            }
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.chat_bubble_outline, color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ]
            // 2. 완료 확인 대기 (awaiting_confirmation): 후기 작성
            else if (status == 'awaiting_confirmation') ...[
              const SizedBox(height: 12),
              Stack(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        if (completedBy == null && selectedBidderId == null && claimedBy == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('낙찰된 사업자 정보를 찾을 수 없습니다.'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        _openReviewScreen(order);
                      },
                      icon: const Icon(Icons.star_outline, size: 18),
                      label: const Text(
                        '후기 작성하기',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF59E0B),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                  if (listingId.isNotEmpty)
                    Positioned(
                      top: 0,
                      bottom: 0,
                      right: 0,
                      child: Center(
                        child: InkWell(
                          onTap: () async {
                            // 채팅방 이동 로직
                            try {
                              final chatService = ChatService();
                              final authService = Provider.of<AuthService>(context, listen: false);
                              final currentUserId = authService.currentUser?.id;
                              
                              if (currentUserId == null) return;
                              
                              // 상대방 ID 확인 (낙찰된 사업자)
                              final targetUserId = completedBy ?? selectedBidderId ?? claimedBy;
                              
                              if (targetUserId == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('대화할 상대방 정보를 찾을 수 없습니다.')),
                                );
                                return;
                              }
                              
                              // 채팅방 생성/조회
                              final chatRoomId = await chatService.ensureChatRoom(
                                customerId: currentUserId, // 나 (오더 소유자)
                                businessId: targetUserId, // 낙찰받은 사업자
                                listingId: listingId,
                                title: title,
                              );
                              
                              // 채팅 화면으로 이동
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatScreen(
                                    chatRoomId: chatRoomId,
                                    chatRoomTitle: title,
                                  ),
                                ),
                              );
                            } catch (e) {
                              print('❌ 채팅방 이동 실패: $e');
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('채팅방을 열 수 없습니다.')),
                              );
                            }
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.chat_bubble_outline, color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ]
            // 3. 입찰자 보기 버튼 (진행 중 상태 포함)
            else if (bidCount > 0) ...[
              const SizedBox(height: 12),
              Stack(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _openBidderList(listingId, title),
                      icon: const Icon(Icons.people_outline, size: 18),
                      label: Text(
                        '입찰자 보기 ($bidCount명)', 
                        style: const TextStyle(fontWeight: FontWeight.w600)
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A8A),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                  if (status == 'assigned' || status == 'in_progress')
                    Positioned(
                      top: 0,
                      bottom: 0,
                      right: 0,
                      child: Center(
                        child: InkWell(
                          onTap: () async {
                            // 채팅방 이동 로직 (낙찰자와의 채팅)
                            try {
                              final chatService = ChatService();
                              final authService = Provider.of<AuthService>(context, listen: false);
                              final currentUserId = authService.currentUser?.id;
                              
                              if (currentUserId == null) return;
                              
                              // 상대방 ID 확인 (낙찰된 사업자)
                              final targetUserId = completedBy ?? selectedBidderId ?? claimedBy;
                              
                              if (targetUserId == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('대화할 상대방 정보를 찾을 수 없습니다.')),
                                );
                                return;
                              }
                              
                              // 채팅방 생성/조회
                              final chatRoomId = await chatService.ensureChatRoom(
                                customerId: currentUserId, // 나 (오더 소유자)
                                businessId: targetUserId, // 낙찰받은 사업자
                                listingId: listingId,
                                title: title,
                              );
                              
                              // 채팅 화면으로 이동
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatScreen(
                                    chatRoomId: chatRoomId,
                                    chatRoomTitle: title,
                                  ),
                                ),
                              );
                            } catch (e) {
                              print('❌ 채팅방 이동 실패: $e');
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('채팅방을 열 수 없습니다.')),
                              );
                            }
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.chat_bubble_outline, color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  _OrderBadge _getBadgeForStatus(String status, int bidCount, String? selectedBidderId, String? completedBy) {
    switch (status) {
      case 'created':
      case 'open':
        if (bidCount > 0) {
          return _OrderBadge('입찰 $bidCount건', Colors.blue, Icons.people);
        }
        return _OrderBadge('입찰 대기', Colors.orange, Icons.schedule);
      case 'assigned':
        return _OrderBadge('진행 중', Colors.green, Icons.construction);
      case 'awaiting_confirmation':
        return _OrderBadge('완료 확인 대기', Colors.purple, Icons.hourglass_empty);
      case 'completed':
        return _OrderBadge('완료', Colors.grey, Icons.check_circle);
      default:
        return _OrderBadge(status, Colors.grey, Icons.info_outline);
    }
  }

  void _openBidderList(String listingId, String orderTitle) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderBiddersScreen(
          listingId: listingId,
          orderTitle: orderTitle,
        ),
      ),
    ).then((_) => _loadMyOrders());
  }

  /// 오더 카카오톡 공유 (오더 등록자가 직접 공유)
  /// - listingId 가 있고 낙찰 전인 오더에서만 노출되며,
  ///   카카오 미설치/공유 실패 시 시스템 공유로 폴백한다.
  Future<void> _shareOrder(Map<String, dynamic> order) async {
    final String title = order['title']?.toString() ?? '제목 없음';
    final String description = order['description']?.toString() ?? '';
    final String listingId = order['id']?.toString() ?? '';
    final String jobId = order['jobid']?.toString() ?? '';
    final String category =
        (order['category'] ?? order['equipmentType'] ?? order['equipment_type'] ?? '')
            .toString();
    final String region =
        (order['region'] ?? order['address'] ?? order['location'] ?? '').toString();

    final budgetRaw = order['budget_amount'] ??
        order['estimate_amount'] ??
        order['budgetAmount'] ??
        order['estimateAmount'];
    final double? budgetAmount =
        budgetRaw is num ? budgetRaw.toDouble() : double.tryParse(budgetRaw?.toString() ?? '');

    final commRaw = order['commission_rate'] ?? order['commissionRate'];
    final double? commissionRate =
        commRaw is num ? commRaw.toDouble() : double.tryParse(commRaw?.toString() ?? '');

    String? imageUrl;
    final mediaCandidates = order['media_urls'] ??
        order['mediaUrls'] ??
        order['images'] ??
        order['imageurls'];
    if (mediaCandidates is List && mediaCandidates.isNotEmpty) {
      imageUrl = mediaCandidates.first?.toString();
    }

    try {
      final kakaoService = KakaoShareService();
      final ok = await kakaoService.shareOrder(
        orderId: listingId.isNotEmpty ? listingId : jobId,
        title: title,
        region: region,
        category: category,
        budgetAmount: budgetAmount,
        commissionRate: commissionRate,
        imageUrl: imageUrl,
        description: description,
      );
      if (ok) return;
    } catch (e) {
      print('⚠️ [_shareOrder] 카카오 공유 실패, 시스템 공유로 폴백: $e');
    }

    final shareText =
        '[$category] $title${region.isNotEmpty ? '\n📍 지역: $region' : ''}'
        '${description.isNotEmpty ? '\n\n$description' : ''}\n\n올수리 앱에서 입찰하세요!';
    await Share.share(shareText, subject: title);
  }

  /// 오더 삭제 처리
  Future<void> _deleteOrder(String listingId, String jobId, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('오더 삭제'),
        content: Text('[$title] 오더를 정말 삭제하시겠습니까?\n삭제된 오더는 복구할 수 없으며 모든 입찰 내역도 함께 삭제됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      final marketplaceService = MarketplaceService();
      final success = await marketplaceService.deleteListing(listingId, jobId);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('오더가 삭제되었습니다.'), backgroundColor: Colors.green),
          );
          _loadMyOrders(); // 목록 새로고침
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('오더 삭제에 실패했습니다.'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      print('❌ [MyOrderManagement] 오더 삭제 에러: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('에러 발생: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openReviewScreen(Map<String, dynamic> order) async {
    final listingId = order['id']?.toString();
    final completedBy = order['completed_by']?.toString();
    final selectedBidderId = order['selected_bidder_id']?.toString();
    final claimedBy = order['claimed_by']?.toString();
    final title = order['title']?.toString() ?? '오더';
    final jobId = order['jobid']?.toString();
    
    // 리뷰 대상자 ID: completedBy > selectedBidderId > claimedBy 순서로 확인
    final revieweeId = completedBy ?? selectedBidderId ?? claimedBy;
    
    print('🔍 [_openReviewScreen] 리뷰 화면 열기');
    print('   listingId: $listingId');
    print('   jobId: $jobId');
    print('   completedBy: $completedBy');
    print('   selectedBidderId: $selectedBidderId');
    print('   claimedBy: $claimedBy');
    print('   최종 revieweeId: $revieweeId');
    
    // jobId는 선택사항 (없어도 리뷰 작성 가능)
    if (listingId == null || revieweeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('리뷰 작성 정보가 부족합니다.\n오더가 완료되지 않았을 수 있습니다.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    
    // Get reviewee name from users table
    String revieweeName = '사업자';
    try {
      final userResponse = await Supabase.instance.client
          .from('users')
          .select('businessname, name')
          .eq('id', revieweeId)
          .single();
      
      revieweeName = userResponse['businessname']?.toString() ?? 
                     userResponse['name']?.toString() ?? '사업자';
    } catch (e) {
      print('⚠️ [MyOrderManagement] 사업자 이름 조회 실패: $e');
    }
    
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderReviewScreen(
          listingId: listingId,
          jobId: jobId,
          revieweeId: revieweeId,
          revieweeName: revieweeName,
          orderTitle: title,
        ),
      ),
    );
    
    // 리뷰 작성 후 새로고침
    _loadMyOrders();
  }

  Future<void> _showCompletedOrderDetail(Map<String, dynamic> order) async {
    final listingId = order['id']?.toString();
    final title = order['title']?.toString() ?? '오더';
    final description = order['description']?.toString() ?? '';
    final budget = order['budget_amount'];
    final me = context.read<AuthService>().currentUser?.id ?? '';
    
    if (listingId == null) return;
    
    // 내가 작성한 리뷰 가져오기
    Map<String, dynamic>? myReview;
    try {
      final reviewData = await Supabase.instance.client
          .from('order_reviews')
          .select('rating, tags, comment, created_at, reviewee_id')
          .eq('listing_id', listingId)
          .eq('reviewer_id', me)
          .maybeSingle();
      myReview = reviewData;
    } catch (e) {
      print('⚠️ 리뷰 조회 실패: $e');
    }
    
    if (!mounted) return;
    
    // 상세보기 다이얼로그
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 28),
            const SizedBox(width: 12),
            const Expanded(child: Text('완료된 공사', style: TextStyle(fontSize: 18))),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 공사 제목
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              
              // 공사 설명
              if (description.isNotEmpty) ...[
                Text(description, style: TextStyle(fontSize: 14, color: Colors.grey[700])),
                const SizedBox(height: 12),
              ],
              
              // 예산
              if (budget != null) ...[
                Row(
                  children: [
                    const Icon(Icons.payments_outlined, size: 16),
                    const SizedBox(width: 4),
                    Text('예산: ₩${budget.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              
              const Divider(),
              const SizedBox(height: 12),
              
              // 내가 작성한 후기
              if (myReview != null) ...[
                const Text('내가 작성한 후기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ...List.generate(5, (i) => Icon(
                      i < (myReview!['rating'] ?? 0) ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 20,
                    )),
                    const SizedBox(width: 8),
                    Text('${myReview['rating'] ?? 0}.0', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                if (myReview['tags'] != null && (myReview['tags'] as List).isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: (myReview['tags'] as List).map((tag) => Chip(
                      label: Text(tag.toString(), style: const TextStyle(fontSize: 11)),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    )).toList(),
                  ),
                  const SizedBox(height: 8),
                ],
                if (myReview['comment'] != null && myReview['comment'].toString().isNotEmpty) ...[
                  Text(myReview['comment'].toString(), 
                    style: TextStyle(fontSize: 14, color: Colors.grey[700])),
                ],
                const SizedBox(height: 8),
                Text('작성일: ${myReview['created_at']?.toString().substring(0, 10) ?? ''}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              ] else ...[
                const Text('작성된 후기가 없습니다.', style: TextStyle(color: Colors.grey)),
              ],
            ],
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
}

class _OrderBadge {
  final String label;
  final Color color;
  final IconData icon;
  
  const _OrderBadge(this.label, this.color, this.icon);
}

