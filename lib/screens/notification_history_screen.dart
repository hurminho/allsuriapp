import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/notification.dart';
import '../services/notification_service.dart';
import '../services/auth_service.dart';
import '../widgets/loading_indicator.dart';
import '../config/app_constants.dart';

/// 알림 히스토리 화면
/// 
/// 사용자가 받은 모든 알림을 시간순으로 표시합니다.
/// 각 알림에는 "바로가기" 버튼이 있어 해당 화면으로 이동할 수 있습니다.
class NotificationHistoryScreen extends StatefulWidget {
  const NotificationHistoryScreen({Key? key}) : super(key: key);

  @override
  State<NotificationHistoryScreen> createState() => _NotificationHistoryScreenState();
}

class _NotificationHistoryScreenState extends State<NotificationHistoryScreen> {
  List<NotificationModel> _notifications = [];
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    
    try {
      final authService = context.read<AuthService>();
      final userId = authService.currentUser?.id;
      
      if (userId == null) {
        setState(() => _isLoading = false);
        return;
      }
      
      final notificationService = NotificationService();
      final data = await notificationService.getNotifications(userId);
      
      setState(() {
        _notifications = data.map((e) => NotificationModel.fromMap(e)).toList();
        _isLoading = false;
      });
    } catch (e) {
      print('❌ [NotificationHistory] 알림 로드 실패: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _markAsRead(NotificationModel notification) async {
    if (notification.isRead) return;
    
    try {
      final notificationService = NotificationService();
      await notificationService.markAsRead(notification.id);
      
      setState(() {
        final index = _notifications.indexWhere((n) => n.id == notification.id);
        if (index != -1) {
          _notifications[index] = notification.copyWith(isRead: true);
        }
      });
    } catch (e) {
      print('❌ [NotificationHistory] 읽음 표시 실패: $e');
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      final authService = context.read<AuthService>();
      final userId = authService.currentUser?.id;
      
      if (userId == null) return;
      
      final notificationService = NotificationService();
      await notificationService.markAllAsRead(userId);
      
      setState(() {
        _notifications = _notifications.map((n) => n.copyWith(isRead: true)).toList();
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('모든 알림을 읽음으로 표시했습니다')),
        );
      }
    } catch (e) {
      print('❌ [NotificationHistory] 모두 읽음 표시 실패: $e');
    }
  }

  void _handleNotificationTap(NotificationModel notification) {
    _markAsRead(notification);
    
    // 알림 타입에 따라 적절한 화면으로 이동
    switch (notification.type) {
      case 'new_order':
        Navigator.pushNamed(context, '/order_marketplace');
        break;
      case 'job_completed':
        if (notification.listingId != null && notification.jobId != null) {
          // 리뷰 화면으로 이동
          // TODO: 리뷰 화면 구현 후 추가
        }
        break;
      case 'chat_start':
      case 'chat_message':
        if (notification.chatRoomId != null) {
          // 채팅 화면으로 이동
          // TODO: 채팅 화면 네비게이션 추가
        }
        break;
      case 'new_bid':
        if (notification.listingId != null) {
          // 입찰자 목록 화면으로 이동
          // TODO: 입찰자 목록 화면 네비게이션 추가
        }
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifications.where((n) => !n.isRead).length;
    
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('알림', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (unreadCount > 0)
            TextButton(
              onPressed: _markAllAsRead,
              child: Text(
                '모두 읽음',
                style: TextStyle(
                  color: AppConstants.primaryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadNotifications,
            tooltip: '새로고침',
          ),
        ],
      ),
      body: _isLoading
          ? const LoadingIndicator(
              message: '알림을 불러오는 중...',
              subtitle: '잠시만 기다려주세요',
            )
          : _notifications.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadNotifications,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _notifications.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final notification = _notifications[index];
                      return _buildNotificationCard(notification);
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 80,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            '알림이 없습니다',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '새로운 알림이 오면 여기에 표시됩니다',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(NotificationModel notification) {
    final isUnread = !notification.isRead;
    
    return Container(
      decoration: BoxDecoration(
        color: isUnread ? AppConstants.primaryColor.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isUnread ? AppConstants.primaryColor.withOpacity(0.3) : Colors.grey[200]!,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _handleNotificationTap(notification),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 아이콘
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _getIconColor(notification.type).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _getIcon(notification.type),
                    color: _getIconColor(notification.type),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                
                // 내용
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              notification.title,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: isUnread ? FontWeight.w700 : FontWeight.w600,
                                color: Colors.grey[900],
                              ),
                            ),
                          ),
                          if (isUnread)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: AppConstants.primaryColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        notification.message,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatTime(notification.createdAt),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppConstants.primaryColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              '바로가기',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getIcon(String type) {
    switch (type) {
      case 'new_order':
        return Icons.add_business_rounded;
      case 'job_completed':
        return Icons.check_circle_rounded;
      case 'chat_start':
      case 'chat_message':
        return Icons.chat_bubble_rounded;
      case 'new_bid':
        return Icons.gavel_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _getIconColor(String type) {
    switch (type) {
      case 'new_order':
        return const Color(0xFF2196F3); // 파란색
      case 'job_completed':
        return const Color(0xFF4CAF50); // 초록색
      case 'chat_start':
      case 'chat_message':
        return const Color(0xFFFF9800); // 주황색
      case 'new_bid':
        return AppConstants.primaryColor; // 보라색
      default:
        return Colors.grey;
    }
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inMinutes < 1) {
      return '방금 전';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}분 전';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}시간 전';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}일 전';
    } else {
      return DateFormat('MM월 dd일').format(dateTime);
    }
  }
}

