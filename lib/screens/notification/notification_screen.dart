import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/user.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../business/job_management_screen.dart';
import '../business/my_order_management_screen.dart';
import '../business/order_marketplace_screen.dart';
import '../business/order_bidders_screen.dart';
import '../community/post_detail_screen.dart';
import '../chat_screen.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({Key? key}) : super(key: key);

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final NotificationService _notificationService = NotificationService();
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final user = authService.currentUser;
      
      print('🔍 [NotificationScreen] 알림 로드 시작');
      print('   AuthService currentUser: ${user?.id ?? "null"}');
      
      if (user != null) {
        print('   사용자 ID로 알림 조회: ${user.id}');
        final notifications = await _notificationService.getNotifications(user.id);
        print('✅ [NotificationScreen] ${notifications.length}개 알림 조회 완료');
        
        if (notifications.isNotEmpty) {
          print('   첫 번째 알림: ${notifications.first}');
        }
        
        setState(() {
          _notifications = notifications;
          _isLoading = false;
        });
      } else {
        print('❌ [NotificationScreen] AuthService에 사용자 없음');
        setState(() {
          _error = '사용자 정보를 찾을 수 없습니다.';
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ [NotificationScreen] 알림 로드 실패: $e');
      setState(() {
        _error = '알림을 불러오는 중 오류가 발생했습니다: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _markAsRead(Map<String, dynamic> notification) async {
    // 1. 읽음 처리
    if (notification['isread'] != true) {
      await _notificationService.markAsRead(notification['id']);
      setState(() {
        final index = _notifications.indexWhere((n) => n['id'] == notification['id']);
        if (index != -1) {
          _notifications[index]['isread'] = true;
        }
      });
    }
    
    // 2. 알림 타입에 따라 페이지 이동
    final type = notification['type'] as String?;
    
    if (type == 'bid_pending') {
      // 입찰 확인 - 오더 마켓플레이스로 이동
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const OrderMarketplaceScreen(),
        ),
      );
    } else if (type == 'new_bid') {
      // 🎯 새로운 입찰 - 내 오더 관리 (해당 오더 포커싱)
      final orderId = notification['orderid']?.toString() ?? notification['jobid']?.toString() ?? '';
      if (orderId.isNotEmpty && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MyOrderManagementScreen(highlightedOrderId: orderId),
          ),
        );
      } else if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const MyOrderManagementScreen(),
          ),
        );
      }
    } else if (type == 'chat_message') {
      // 💬 채팅 메시지 - 채팅 화면
      final chatRoomId = notification['chatroom_id']?.toString() ?? notification['chatroomid']?.toString() ?? '';
      if (chatRoomId.isNotEmpty && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(chatRoomId: chatRoomId),
          ),
        );
      }
    } else if (type == 'bid_selected') {
      // 🏆 낙찰 - 내 공사 관리 (해당 공사 포커싱)
      final jobIdValue = notification['jobid']?.toString() ?? '';
      if (jobIdValue.isNotEmpty && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => JobManagementScreen(highlightedJobId: jobIdValue),
          ),
        );
      } else if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const JobManagementScreen(),
          ),
        );
      }
    } else if (type == 'order_completed' || type == 'review_request') {
      // 📝 공사 완료 / 후기 작성 요청 - 내 오더 관리 (해당 오더 포커싱)
      final orderId = notification['listingid']?.toString() ??
          notification['orderid']?.toString() ??
          notification['jobid']?.toString() ??
          '';
      if (orderId.isNotEmpty && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MyOrderManagementScreen(
              highlightedOrderId: orderId,
              initialFilter: 'completed',
            ),
          ),
        );
      } else if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const MyOrderManagementScreen(initialFilter: 'completed'),
          ),
        );
      }
    } else if (type == 'review_received') {
      // ⭐ 리뷰 받음 - 내 공사 관리 > 완료된 공사 (해당 공사 포커싱)
      final jobIdValue = notification['jobid']?.toString() ?? '';
      if (jobIdValue.isNotEmpty && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => JobManagementScreen(
              highlightedJobId: jobIdValue,
              initialFilter: 'completed',
            ),
          ),
        );
      } else if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const JobManagementScreen(initialFilter: 'completed'),
          ),
        );
      }
    }
  }

  Future<void> _markAllAsRead() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    
    if (user != null) {
      await _notificationService.markAllAsRead(user.id);
      setState(() {
        _notifications = _notifications.map((n) => {...n, 'isread': true}).toList();
      });
    }
  }

  Future<void> _deleteAllNotifications() async {
    if (_notifications.isEmpty) return;

    // 확인 다이얼로그
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Row(
          children: [
            Icon(Icons.delete_sweep, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Text('모든 알림 삭제'),
          ],
        ),
        content: Text('${_notifications.length}개의 알림을 모두 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('모두 삭제'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // 삭제 중 로딩 표시
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      int successCount = 0;
      final notificationsCopy = List<Map<String, dynamic>>.from(_notifications);
      
      for (final notification in notificationsCopy) {
        final notificationId = notification['id']?.toString();
        if (notificationId != null) {
          final success = await _notificationService.deleteNotification(notificationId);
          if (success) successCount++;
        }
      }

      if (!mounted) return;
      Navigator.pop(context); // 로딩 다이얼로그 닫기

      setState(() {
        _notifications.clear();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text('$successCount개의 알림이 삭제되었습니다'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  String _formatTimeAgo(dynamic dateTimeValue) {
    DateTime dateTime;
    
    // String인 경우 파싱, 이미 DateTime인 경우 그대로 사용
    if (dateTimeValue is String) {
      try {
        dateTime = DateTime.parse(dateTimeValue);
      } catch (e) {
        return '시간 정보 없음';
      }
    } else if (dateTimeValue is DateTime) {
      dateTime = dateTimeValue;
    } else {
      return '시간 정보 없음';
    }
    
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}일 전';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}시간 전';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}분 전';
    } else {
      return '방금 전';
    }
  }

  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'comment':
        return Icons.comment;
      case 'new_order':
        return Icons.campaign;
      case 'new_bid':
        return Icons.gavel;
      case 'bid_pending':
        return Icons.schedule;
      case 'bid_selected':
        return Icons.check_circle;
      case 'bid_rejected':
        return Icons.cancel;
      case 'estimate':
        return Icons.assignment;
      case 'estimate_selected':
        return Icons.emoji_events;
      case 'estimate_transferred':
        return Icons.swap_horiz;
      case 'order_completed':
        return Icons.done_all;
      case 'review_request':
        return Icons.rate_review;
      case 'review_received':
        return Icons.star;
      case 'order_status':
        return Icons.update;
      default:
        return Icons.notifications;
    }
  }

  Color _getNotificationColor(String type) {
    switch (type) {
      case 'comment':
        return Colors.purple;
      case 'new_order':
        return Colors.deepOrange;
      case 'new_bid':
        return Colors.orange;
      case 'bid_pending':
        return Colors.blue;
      case 'bid_selected':
        return Colors.green;
      case 'bid_rejected':
        return Colors.grey;
      case 'estimate':
        return Colors.blue;
      case 'estimate_selected':
        return Colors.green;
      case 'estimate_transferred':
        return Colors.teal;
      case 'order_completed':
        return Colors.green;
      case 'review_request':
        return Colors.amber;
      case 'review_received':
        return Colors.amber;
      case 'order_status':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '알림',
          style: TextStyle(
            color: Color(0xFF1E3A8A),
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1E3A8A)),
        actions: [
          if (_notifications.any((n) => n['isread'] != true))
            IconButton(
              icon: const Icon(Icons.done_all),
              onPressed: _markAllAsRead,
              tooltip: '모두 읽음 처리',
            ),
          if (_notifications.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'delete_all') {
                  _deleteAllNotifications();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'delete_all',
                  child: Row(
                    children: [
                      Icon(Icons.delete_sweep, color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Text('모두 삭제', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: const TextStyle(fontSize: 16, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadNotifications,
                        child: const Text('다시 시도'),
                      ),
                    ],
                  ),
                )
              : _notifications.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text(
                            '알림이 없습니다.',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadNotifications,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _notifications.length,
                        itemBuilder: (context, index) {
                          final notification = _notifications[index];
                          return _buildDismissibleNotificationItem(notification);
                        },
                      ),
                    ),
    );
  }

  Widget _buildDismissibleNotificationItem(Map<String, dynamic> notification) {
    final notificationId = notification['id']?.toString() ?? '';
    
    return Dismissible(
      key: Key(notificationId),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_outline, color: Colors.white, size: 28),
            SizedBox(height: 4),
            Text(
              '삭제',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        // 스와이프만으로 삭제 확인 다이얼로그 표시
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.delete_outline, color: Colors.red, size: 28),
                SizedBox(width: 12),
                Text('알림 삭제'),
              ],
            ),
            content: const Text('이 알림을 삭제하시겠습니까?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('삭제'),
              ),
            ],
          ),
        );
        
        if (confirm == true) {
          final success = await _notificationService.deleteNotification(notificationId);
          
          if (success) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.white),
                      SizedBox(width: 8),
                      Text('알림이 삭제되었습니다'),
                    ],
                  ),
                  backgroundColor: Colors.green,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            }
            return true;
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.white),
                      SizedBox(width: 8),
                      Text('알림 삭제에 실패했습니다'),
                    ],
                  ),
                  backgroundColor: Colors.red,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            }
            return false;
          }
        }
        
        return false;
      },
      child: _buildNotificationItem(notification),
    );
  }

  Widget _buildNotificationItem(Map<String, dynamic> notification) {
    // null 안전성을 위한 기본값 설정
    final title = notification['title']?.toString() ?? '제목 없음';
    final message = notification['body']?.toString() ?? notification['message']?.toString() ?? '내용 없음';
    final type = notification['type']?.toString() ?? 'unknown';
    final isRead = notification['isread'] == true;
    final jobTitle = notification['jobtitle']?.toString();
    final region = notification['region']?.toString();
    final createdAt = notification['createdat'];
    final jobId = notification['jobid']?.toString();
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isRead ? Colors.white : Colors.blue[50],
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getNotificationColor(type).withOpacity(0.1),
          child: Icon(
            _getNotificationIcon(type),
            color: _getNotificationColor(type),
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            if ((jobTitle?.isNotEmpty ?? false) || (region?.isNotEmpty ?? false)) ...[
              const SizedBox(height: 4),
              Text(
                '${jobTitle ?? ''}${(jobTitle?.isNotEmpty ?? false) && (region?.isNotEmpty ?? false) ? ' · ' : ''}${region ?? ''}',
                style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              _formatTimeAgo(createdAt),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  await _markAsRead(notification);
                  if (!mounted) return;
                  
                  // 알림 타입에 따라 다른 화면으로 이동
                  if (type == 'comment') {
                    // 댓글 알림 → 게시글 상세 화면
                    final postId = notification['postid']?.toString() ?? '';
                    if (postId.isNotEmpty) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PostDetailScreen(postId: postId),
                        ),
                      );
                    }
                  } else if (type == 'new_order') {
                    // 새로운 오더 → 오더 마켓플레이스로 이동
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const OrderMarketplaceScreen(),
                      ),
                    );
                  } else if (type == 'new_bid') {
                    // 🎯 새로운 입찰 → 내 오더 관리 (해당 오더 포커싱)
                    final orderId = notification['orderid']?.toString() ?? notification['jobid']?.toString() ?? '';
                    print('🔔 [new_bid] 내 오더 관리로 이동: orderId=$orderId');
                    
                    if (orderId.isNotEmpty) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MyOrderManagementScreen(highlightedOrderId: orderId),
                        ),
                      );
                    } else {
                      // orderId가 없으면 기본 화면
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MyOrderManagementScreen(),
                        ),
                      );
                    }
                  } else if (type == 'chat_message') {
                    // 💬 채팅 메시지 → 채팅 화면
                    final chatRoomId = notification['chatroom_id']?.toString() ?? notification['chatroomid']?.toString() ?? '';
                    print('🔔 [chat_message] 채팅 화면으로 이동: chatRoomId=$chatRoomId');
                    
                    if (chatRoomId.isNotEmpty) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(chatRoomId: chatRoomId),
                        ),
                      );
                    }
                  } else if (type == 'bid_selected') {
                    // 🏆 낙찰 → 내 공사 관리 (해당 공사 포커싱)
                    final jobIdValue = notification['jobid']?.toString() ?? '';
                    print('🔔 [bid_selected] 내 공사 관리로 이동: jobId=$jobIdValue');
                    
                    if (jobIdValue.isNotEmpty) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => JobManagementScreen(highlightedJobId: jobIdValue),
                        ),
                      );
                    } else {
                      // jobId가 없으면 기본 화면
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const JobManagementScreen()),
                      );
                    }
                  } else if (type == 'bid_rejected') {
                    // 입찰 거절됨 → 오더 마켓
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OrderMarketplaceScreen()),
                    );
                  } else if (type == 'order_completed' || type == 'review_request') {
                    // 📝 공사 완료 / 후기 작성 요청 → 내 오더 관리 (해당 오더 포커싱)
                    final orderId = notification['listingid']?.toString() ??
                        notification['orderid']?.toString() ??
                        notification['jobid']?.toString() ??
                        '';
                    print('🔔 [$type] 내 오더 관리로 이동 (완료 필터): orderId=$orderId');
                    
                    if (orderId.isNotEmpty) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MyOrderManagementScreen(
                            highlightedOrderId: orderId,
                            initialFilter: 'completed',
                          ),
                        ),
                      );
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MyOrderManagementScreen(initialFilter: 'completed'),
                        ),
                      );
                    }
                  } else if (type == 'review_received') {
                    // ⭐ 리뷰 받음 → 내 공사 관리 > 완료된 공사 (해당 공사 포커싱)
                    final jobIdValue = notification['jobid']?.toString() ?? '';
                    print('🔔 [review_received] 내 공사 관리로 이동 (완료됨 필터): jobId=$jobIdValue');
                    
                    if (jobIdValue.isNotEmpty) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => JobManagementScreen(
                            highlightedJobId: jobIdValue,
                            initialFilter: 'completed',
                          ),
                        ),
                      );
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const JobManagementScreen(initialFilter: 'completed'),
                        ),
                      );
                    }
                  } else if ((type == 'call_assigned' || type == 'call_update') && (jobId?.isNotEmpty ?? false)) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OrderMarketplaceScreen()),
                    );
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const JobManagementScreen()),
                    );
                  }
                },
                child: const Text('자세히 보기'),
              ),
            )
          ],
        ),
        trailing: isRead
            ? null
            : Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                ),
              ),
        onTap: () => _markAsRead(notification),
      ),
    );
  }
} 