import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:allsuriapp/widgets/loading_indicator.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../../theme/business_theme.dart';
import '../chat_screen.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _chatRooms = [];

  @override
  void initState() {
    super.initState();
    _loadChatRooms();
  }

  Future<void> _loadChatRooms() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final chatService = Provider.of<ChatService>(context, listen: false);
      final userId = auth.currentUser?.id ?? '';
      if (userId.isEmpty) {
        if (mounted) setState(() => _chatRooms = []);
      } else {
        final chatRooms = await chatService.getChatRooms(userId);
        if (mounted) setState(() => _chatRooms = chatRooms);
      }
    } catch (e) {
      debugPrint('채팅방 로드 오류: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, child) {
        final user = authService.currentUser;
        if (user == null) {
        return Scaffold(
          backgroundColor: BusinessTheme.background,
          appBar: AppBar(title: const Text('채팅')),
          body: SafeArea(child: _buildLoginGuide(context)),
        );
        }
        return Scaffold(
          backgroundColor: BusinessTheme.background,
          appBar: AppBar(
            title: const Text('채팅'),
            actions: [
              IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _loadChatRooms),
            ],
          ),
          body: SafeArea(child: _buildChatList(context)),
        );
      },
    );
  }

  Widget _buildLoginGuide(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(CupertinoIcons.chat_bubble_2, size: 80, color: CupertinoColors.systemGrey),
          const SizedBox(height: 24),
          const Text(
            '채팅을 사용하려면\n로그인하세요',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, color: CupertinoColors.systemGrey, height: 1.5),
          ),
          const SizedBox(height: 32),
          CupertinoButton.filled(
            onPressed: () => Navigator.pop(context),
            child: const Text('로그인', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildChatList(BuildContext context) {
    if (_isLoading) {
      return const Center(child: LoadingIndicator(message: '채팅방을 불러오는 중...'));
    }
    if (_chatRooms.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(CupertinoIcons.chat_bubble_2, size: 64, color: CupertinoColors.systemGrey),
            SizedBox(height: 16),
            Text('아직 채팅방이 없습니다', style: TextStyle(fontSize: 18, color: CupertinoColors.systemGrey)),
            SizedBox(height: 8),
            Text('견적 요청을 하면 업체와 채팅할 수 있습니다',
                style: TextStyle(fontSize: 14, color: CupertinoColors.systemGrey2)),
          ],
        ),
      );
    }

    return CupertinoScrollbar(
      child: CustomScrollView(
        slivers: [
          CupertinoSliverRefreshControl(onRefresh: _loadChatRooms),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final chatRoom = _chatRooms[index];
                return _buildChatItem(context, chatRoom);
              },
              childCount: _chatRooms.length,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatItem(BuildContext context, Map<String, dynamic> chatRoom) {
    final displayName = (chatRoom['displayName']?.toString().isNotEmpty ?? false)
        ? chatRoom['displayName'].toString()
        : '채팅';
    final avatarUrl = chatRoom['otherAvatarUrl']?.toString();
    final isBusiness = chatRoom['otherRole']?.toString() == 'business';
    final orderTitle = chatRoom['orderTitle']?.toString();
    final lastMessage = chatRoom['lastMessage']?.toString() ?? '';
    final unread = (chatRoom['unreadCount'] ?? 0) as int;
    final lastAt = _parseTimestamp(
      chatRoom['lastMessageAt'] ??
          chatRoom['createdat'] ??
          chatRoom['created_at'] ??
          chatRoom['createdAt'],
    );

    return Material(
      color: CupertinoColors.systemBackground,
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            CupertinoPageRoute(
              builder: (context) => ChatScreen(chatRoomId: chatRoom['id']),
            ),
          );
          _loadChatRooms();
        },
        onLongPress: () => _confirmDelete(context, chatRoom['id']),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE), width: 0.6)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ListAvatar(name: displayName, avatarUrl: avatarUrl, isBusiness: isBusiness),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: isBusiness ? const Color(0xFFE3F2FD) : const Color(0xFFF1F8E9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isBusiness ? '사업자' : '의뢰인',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: isBusiness ? const Color(0xFF1565C0) : const Color(0xFF558B2F),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (orderTitle != null && orderTitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '📋 $orderTitle',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF1E88E5), fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      lastMessage.isNotEmpty ? lastMessage : '대화를 시작해 보세요',
                      style: const TextStyle(fontSize: 13, color: Colors.black54),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatTimestamp(lastAt),
                    style: const TextStyle(fontSize: 11, color: Colors.black45),
                  ),
                  const SizedBox(height: 6),
                  if (unread > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF3B30),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        unread > 99 ? '99+' : '$unread',
                        style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, dynamic roomId) async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('채팅방 삭제'),
        content: const Text('메시지 포함 채팅방을 삭제하시겠습니까?'),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final userId = Provider.of<AuthService>(context, listen: false).currentUser?.id ?? '';
      final svc = Provider.of<ChatService>(context, listen: false);
      try {
        await svc.deleteMessages(roomId.toString());
        await svc.softDeleteChatRoom(roomId.toString(), userId);
        await _loadChatRooms();
      } catch (_) {}
    }
  }

  DateTime _parseTimestamp(dynamic value) {
    if (value is DateTime) return value.toLocal();
    if (value is String) return (DateTime.tryParse(value) ?? DateTime.now()).toLocal();
    return DateTime.now();
  }

  /// 카카오톡 스타일 시간 포맷:
  /// - 오늘: HH:mm
  /// - 어제: 어제
  /// - 그 외 같은 해: M월 d일
  /// - 그 외: yy.MM.dd
  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final t = timestamp.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(t.year, t.month, t.day);
    final diffDays = today.difference(that).inDays;
    if (diffDays == 0) {
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    if (diffDays == 1) return '어제';
    if (t.year == now.year) return '${t.month}월 ${t.day}일';
    return '${t.year.toString().substring(2)}.${t.month.toString().padLeft(2, '0')}.${t.day.toString().padLeft(2, '0')}';
  }
}

class _ListAvatar extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final bool isBusiness;

  const _ListAvatar({required this.name, this.avatarUrl, required this.isBusiness});

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name.characters.first : '?';
    final bg = isBusiness ? const Color(0xFFE3F2FD) : const Color(0xFFFFF3E0);
    final fg = isBusiness ? const Color(0xFF1565C0) : const Color(0xFF6D4C00);
    Widget fallback() => Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(
            initial,
            style: TextStyle(color: fg, fontSize: 19, fontWeight: FontWeight.w700),
          ),
        );
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: avatarUrl!,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          memCacheWidth: 144,
          memCacheHeight: 144,
          errorWidget: (_, __, ___) => fallback(),
          placeholder: (context, url) => fallback(),
        ),
      );
    }
    return fallback();
  }
}
