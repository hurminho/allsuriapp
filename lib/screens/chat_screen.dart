import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../services/media_service.dart';
import '../services/chat_service.dart';
import '../services/auth_service.dart';
import 'business/job_management_screen.dart';
import 'business/my_order_management_screen.dart';

class ChatScreen extends StatefulWidget {
  final String chatRoomId;
  final String? chatRoomTitle;

  const ChatScreen({
    Key? key,
    required this.chatRoomId,
    this.chatRoomTitle,
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatMessage {
  final String id; // db id 또는 옵티미스틱용 임시 id
  final String text;
  final DateTime timestamp;
  final bool isFromMe;
  final String senderId;
  final String? imageUrl;
  final String? videoUrl;
  final bool isPending; // 옵티미스틱 전송 상태

  _ChatMessage({
    required this.id,
    required this.text,
    required this.timestamp,
    required this.isFromMe,
    required this.senderId,
    this.imageUrl,
    this.videoUrl,
    this.isPending = false,
  });

  _ChatMessage copyWith({bool? isPending}) => _ChatMessage(
        id: id,
        text: text,
        timestamp: timestamp,
        isFromMe: isFromMe,
        senderId: senderId,
        imageUrl: imageUrl,
        videoUrl: videoUrl,
        isPending: isPending ?? this.isPending,
      );
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final ImagePicker _picker = ImagePicker();
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<List<Map<String, dynamic>>>? _messagesSub;

  final List<_ChatMessage> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _showScrollToEnd = false;

  String? _otherUserName;
  String? _otherAvatarUrl;
  String? _otherRole; // business / customer
  String? _orderTitle;
  String? _listingId;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inputFocusNode.requestFocus();
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    // ListView가 아래쪽이 maxScrollExtent
    final atBottom = (pos.maxScrollExtent - pos.pixels) <= 80;
    if (_showScrollToEnd == atBottom) {
      setState(() => _showScrollToEnd = !atBottom);
    }
  }

  Future<void> _bootstrap() async {
    await _loadChatRoomInfo();
    await _loadMessages(initial: true);
    _subscribeRealtime();
    _markAsRead();
  }

  Future<void> _markAsRead() async {
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final chat = Provider.of<ChatService>(context, listen: false);
      final id = auth.currentUser?.id ?? '';
      if (id.isNotEmpty) {
        await chat.markChatRead(widget.chatRoomId, id);
      }
    } catch (_) {}
  }

  Future<void> _loadChatRoomInfo() async {
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final chat = Provider.of<ChatService>(context, listen: false);
      final myId = auth.currentUser?.id ?? '';
      final info = await chat.getChatRoomWithPeer(widget.chatRoomId, myId);
      if (!mounted || info == null) return;
      setState(() {
        _otherUserName = info['otherDisplayName']?.toString();
        _otherAvatarUrl = info['otherAvatarUrl']?.toString();
        _otherRole = info['otherRole']?.toString();
        _orderTitle = info['orderTitle']?.toString();
        _listingId = info['listingId']?.toString();
      });
    } catch (e) {
      debugPrint('❌ 채팅방 정보 로드 실패: $e');
    }
  }

  Future<void> _navigateToOrder() async {
    if (_listingId == null) return;
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final myId = auth.currentUser?.id ?? '';
      final listing = await Supabase.instance.client
          .from('marketplace_listings')
          .select('posted_by, status, jobid')
          .eq('id', _listingId!)
          .single();
      final postedBy = listing['posted_by'];
      final jobId = listing['jobid'];
      if (!mounted) return;
      if (postedBy == myId) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MyOrderManagementScreen(highlightedOrderId: _listingId),
          ),
        );
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => JobManagementScreen(highlightedJobId: jobId),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('오더 정보를 불러올 수 없습니다.')),
        );
      }
    }
  }

  _ChatMessage _rowToMessage(Map<String, dynamic> r, String myId) {
    final created = r['createdat'] ?? r['createdAt'] ?? r['created_at'];
    final senderId = r['sender_id']?.toString() ??
        r['senderid']?.toString() ??
        r['senderId']?.toString() ??
        '';
    return _ChatMessage(
      id: (r['id'] ?? '').toString(),
      text: (r['content'] ?? r['text'] ?? '').toString(),
      timestamp: DateTime.tryParse(created?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      isFromMe: senderId == myId,
      senderId: senderId,
      imageUrl: r['image_url']?.toString(),
      videoUrl: r['video_url']?.toString(),
    );
  }

  Future<void> _loadMessages({bool initial = false}) async {
    if (initial) {
      setState(() => _isLoading = true);
    }
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final myId = auth.currentUser?.id ?? '';
      final rows = await Supabase.instance.client
          .from('chat_messages')
          .select()
          .eq('room_id', widget.chatRoomId)
          .order('createdat', ascending: true);
      final list = rows.map<_ChatMessage>((r) => _rowToMessage(Map<String, dynamic>.from(r), myId)).toList();
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(list);
      });
      _jumpToBottom();
    } catch (e) {
      debugPrint('❌ 메시지 로드 실패: $e');
    } finally {
      if (mounted && initial) setState(() => _isLoading = false);
    }
  }

  /// 실시간 수신: 전체 교체 대신 id 기준 병합 → 깜빡임 제거
  void _subscribeRealtime() {
    try {
      final client = Supabase.instance.client;
      _messagesSub = client
          .from('chat_messages')
          .stream(primaryKey: ['id'])
          .eq('room_id', widget.chatRoomId)
          .order('createdat', ascending: true)
          .listen((rows) {
        if (!mounted) return;
        final auth = Provider.of<AuthService>(context, listen: false);
        final myId = auth.currentUser?.id ?? '';
        _mergeRows(rows, myId);
      });
    } catch (e) {
      debugPrint('❌ 실시간 구독 실패: $e');
    }
  }

  void _mergeRows(List<Map<String, dynamic>> rows, String myId) {
    bool atBottom = true;
    if (_scrollController.hasClients) {
      final pos = _scrollController.position;
      atBottom = (pos.maxScrollExtent - pos.pixels) <= 80;
    }

    // 기존 id 인덱스
    final indexById = {for (var i = 0; i < _messages.length; i++) _messages[i].id: i};
    bool changed = false;
    for (final raw in rows) {
      final m = _rowToMessage(Map<String, dynamic>.from(raw), myId);
      final idx = indexById[m.id];
      if (idx == null) {
        // 옵티미스틱(temp_) 항목 중 같은 본문/시간 비슷한 것이 있으면 교체
        final tmpIdx = _messages.indexWhere((x) =>
            x.isPending && x.isFromMe && x.text == m.text && (x.imageUrl ?? '') == (m.imageUrl ?? '') && (x.videoUrl ?? '') == (m.videoUrl ?? ''));
        if (tmpIdx >= 0) {
          _messages[tmpIdx] = m;
        } else {
          _messages.add(m);
        }
        changed = true;
      } else if (_messages[idx].isPending) {
        _messages[idx] = m;
        changed = true;
      }
    }
    if (!changed) return;
    // 시간순 정렬 보장
    _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    setState(() {});
    if (atBottom) _animateToBottom();
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  void _animateToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    final auth = Provider.of<AuthService>(context, listen: false);
    final chat = Provider.of<ChatService>(context, listen: false);
    final myId = auth.currentUser?.id ?? '';
    if (myId.isEmpty) return;

    // 옵티미스틱 추가
    final tempId = 'temp_${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = _ChatMessage(
      id: tempId,
      text: text,
      timestamp: DateTime.now(),
      isFromMe: true,
      senderId: myId,
      isPending: true,
    );
    setState(() {
      _messages.add(optimistic);
      _isSending = true;
    });
    _messageController.clear();
    _animateToBottom();

    try {
      await chat.sendMessage(widget.chatRoomId, text, myId);
      // realtime stream이 곧 _mergeRows 로 교체하므로 별도 작업 불필요
    } catch (e) {
      if (!mounted) return;
      // 실패 시 옵티미스틱 제거
      setState(() {
        _messages.removeWhere((m) => m.id == tempId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('메시지 전송 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFFB2C7DA), // 카카오톡 채팅 배경 톤
      appBar: _buildAppBar(),
      body: Column(
        children: [
          if (_orderTitle != null && _orderTitle!.isNotEmpty) _buildOrderBanner(),
          Expanded(
            child: Stack(
              children: [
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _messages.isEmpty
                        ? const Center(
                            child: Text(
                              '아직 메시지가 없습니다.\n첫 인사를 건네 보세요.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.black54),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final msg = _messages[index];
                              final showDate = _shouldShowDateHeader(index);
                              final groupingInfo = _groupingInfo(index);
                              return Column(
                                children: [
                                  if (showDate) _buildDateHeader(msg.timestamp),
                                  _buildBubble(msg, groupingInfo),
                                ],
                              );
                            },
                          ),
                if (_showScrollToEnd)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: FloatingActionButton(
                      mini: true,
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      onPressed: _animateToBottom,
                      child: const Icon(Icons.keyboard_arrow_down),
                    ),
                  ),
              ],
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black87,
      elevation: 0.5,
      leadingWidth: 40,
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.pop(context),
      ),
      title: InkWell(
        onTap: _listingId != null ? _navigateToOrder : null,
        child: Row(
          children: [
            _PeerAvatar(
              name: _otherUserName ?? widget.chatRoomTitle ?? '?',
              avatarUrl: _otherAvatarUrl,
              size: 36,
              isBusiness: _otherRole == 'business',
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _otherUserName ?? widget.chatRoomTitle ?? '채팅',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  if (_otherRole != null)
                    Text(
                      _otherRole == 'business' ? '사업자' : '의뢰인',
                      style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.normal),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) async {
            final svc = Provider.of<ChatService>(context, listen: false);
            if (value == 'clear') {
              await svc.deleteMessages(widget.chatRoomId);
              await _loadMessages(initial: true);
            } else if (value == 'delete') {
              final me = Provider.of<AuthService>(context, listen: false).currentUser?.id ?? '';
              await svc.softDeleteChatRoom(widget.chatRoomId, me);
              if (mounted) Navigator.pop(context);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'clear', child: Text('메시지 비우기')),
            const PopupMenuItem(value: 'delete', child: Text('채팅방 삭제')),
          ],
        ),
      ],
    );
  }

  Widget _buildOrderBanner() {
    return InkWell(
      onTap: _listingId != null ? _navigateToOrder : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: const Color(0xFFFFF6D8),
        child: Row(
          children: [
            const Icon(Icons.receipt_long, size: 16, color: Color(0xFF8B6F00)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _orderTitle ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Color(0xFF6B5300), fontWeight: FontWeight.w600),
              ),
            ),
            if (_listingId != null) const Icon(Icons.arrow_forward_ios, size: 11, color: Color(0xFF8B6F00)),
          ],
        ),
      ),
    );
  }

  /// 같은 발신자의 연속 메시지 그룹화 정보
  ({bool showAvatar, bool showName, bool showTime}) _groupingInfo(int index) {
    final cur = _messages[index];
    final prev = index > 0 ? _messages[index - 1] : null;
    final next = index < _messages.length - 1 ? _messages[index + 1] : null;

    final samePrev = prev != null &&
        prev.senderId == cur.senderId &&
        prev.timestamp.year == cur.timestamp.year &&
        prev.timestamp.month == cur.timestamp.month &&
        prev.timestamp.day == cur.timestamp.day;
    final sameNext = next != null &&
        next.senderId == cur.senderId &&
        next.timestamp.year == cur.timestamp.year &&
        next.timestamp.month == cur.timestamp.month &&
        next.timestamp.day == cur.timestamp.day &&
        // 1분 이내면 시간 표시 합치기
        next.timestamp.difference(cur.timestamp).inMinutes == 0;

    return (
      showAvatar: !samePrev,
      showName: !samePrev,
      showTime: !sameNext,
    );
  }

  Widget _buildBubble(_ChatMessage m, ({bool showAvatar, bool showName, bool showTime}) g) {
    final isMe = m.isFromMe;
    final bg = isMe ? const Color(0xFFFFEB33) : Colors.white;
    final fg = Colors.black87;
    final radius = BorderRadius.only(
      topLeft: Radius.circular(isMe ? 14 : (g.showAvatar ? 4 : 14)),
      topRight: Radius.circular(isMe ? (g.showAvatar ? 4 : 14) : 14),
      bottomLeft: const Radius.circular(14),
      bottomRight: const Radius.circular(14),
    );

    final timeText = '${m.timestamp.hour.toString().padLeft(2, '0')}:${m.timestamp.minute.toString().padLeft(2, '0')}';
    final hasMedia = (m.imageUrl != null && m.imageUrl!.isNotEmpty) || (m.videoUrl != null && m.videoUrl!.isNotEmpty);

    final bubble = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
      child: Container(
        padding: hasMedia ? const EdgeInsets.all(4) : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: bg, borderRadius: radius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (m.imageUrl != null && m.imageUrl!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: GestureDetector(
                  onTap: () => _showImageFullScreen(m.imageUrl!),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240, maxHeight: 280),
                    child: CachedNetworkImage(
                      imageUrl: m.imageUrl!,
                      fit: BoxFit.cover,
                      memCacheWidth: 720,
                    ),
                  ),
                ),
              ),
            if (m.videoUrl != null && m.videoUrl!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: VideoPlayerWidget(videoUrl: m.videoUrl!),
              ),
            if (m.text.isNotEmpty && m.text != '[이미지]' && m.text != '[동영상]')
              Padding(
                padding: hasMedia ? const EdgeInsets.fromLTRB(8, 6, 8, 4) : EdgeInsets.zero,
                child: Text(m.text, style: TextStyle(color: fg, fontSize: 14.5, height: 1.35)),
              ),
          ],
        ),
      ),
    );

    final timeWidget = g.showTime
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (m.isPending)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.4, color: Colors.black45),
                    ),
                  ),
                Text(timeText, style: const TextStyle(fontSize: 10.5, color: Colors.black54)),
              ],
            ),
          )
        : const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(bottom: g.showTime ? 6 : 1, left: 0, right: 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) ...[
            SizedBox(
              width: 36,
              child: g.showAvatar
                  ? _PeerAvatar(
                      name: _otherUserName ?? '?',
                      avatarUrl: _otherAvatarUrl,
                      size: 36,
                      isBusiness: _otherRole == 'business',
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (g.showName)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 2),
                      child: Text(
                        _otherUserName ?? '상대방',
                        style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w600),
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(child: bubble),
                      timeWidget,
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            timeWidget,
            Flexible(child: bubble),
          ],
        ],
      ),
    );
  }

  void _showImageFullScreen(String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
            ),
            Positioned(
              top: 30,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: const BoxDecoration(
        color: Color(0xFFF7F7F7),
        border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              onPressed: _isSending ? null : _pickAndSendImage,
              icon: const Icon(Icons.photo_outlined, color: Colors.black54),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              tooltip: '이미지',
            ),
            IconButton(
              onPressed: _isSending ? null : _pickAndSendVideo,
              icon: const Icon(Icons.videocam_outlined, color: Colors.black54),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              tooltip: '동영상',
            ),
            const SizedBox(width: 4),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 38, maxHeight: 120),
                child: TextField(
                  controller: _messageController,
                  focusNode: _inputFocusNode,
                  decoration: InputDecoration(
                    hintText: '메시지 입력',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(color: Color(0xFFFFCC00)),
                    ),
                  ),
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                  enabled: !_isSending,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Material(
              color: const Color(0xFFFFEB33),
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _isSending ? null : _sendMessage,
                child: const SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(Icons.send, color: Colors.black87, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndSendImage() async {
    try {
      final x = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (x == null) return;
      setState(() => _isSending = true);
      final file = File(x.path);
      final media = MediaService();
      final myId = Provider.of<AuthService>(context, listen: false).currentUser?.id ?? '';
      final url = await media.uploadMessageImage(roomId: widget.chatRoomId, userId: myId, file: file);
      if (url == null) throw Exception('이미지 업로드 실패');

      await Supabase.instance.client.from('chat_messages').insert({
        'room_id': widget.chatRoomId,
        'sender_id': myId,
        'content': '[이미지]',
        'image_url': url,
        'createdat': DateTime.now().toIso8601String(),
      });
      // 실시간 stream이 받아서 _mergeRows 처리
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이미지 전송 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _pickAndSendVideo() async {
    try {
      final media = MediaService();
      final videoFile = await media.pickVideoFromGallery();
      if (videoFile == null) return;
      setState(() => _isSending = true);
      final myId = Provider.of<AuthService>(context, listen: false).currentUser?.id ?? '';
      final url = await media.uploadMessageVideo(roomId: widget.chatRoomId, userId: myId, file: videoFile);
      if (url == null) throw Exception('동영상 업로드 실패');

      await Supabase.instance.client.from('chat_messages').insert({
        'room_id': widget.chatRoomId,
        'sender_id': myId,
        'content': '[동영상]',
        'video_url': url,
        'createdat': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('동영상 전송 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  bool _shouldShowDateHeader(int index) {
    if (index == 0) return true;
    return !_isSameDay(_messages[index].timestamp, _messages[index - 1].timestamp);
  }

  Widget _buildDateHeader(DateTime date) {
    final label = '${date.year}년 ${date.month}월 ${date.day}일';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label, style: const TextStyle(fontSize: 11, color: Colors.white)),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _messagesSub?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _messageController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }
}

/// 상대방/사용자 아바타 — avatar_url 우선, 없으면 머리글자
class _PeerAvatar extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final double size;
  final bool isBusiness;

  const _PeerAvatar({
    required this.name,
    this.avatarUrl,
    this.size = 36,
    this.isBusiness = false,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name.characters.first : '?';
    final bg = isBusiness ? const Color(0xFFE3F2FD) : const Color(0xFFFFF3E0);
    final fg = isBusiness ? const Color(0xFF1565C0) : const Color(0xFF6D4C00);

    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          avatarUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildInitial(initial, bg, fg),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return _buildInitial(initial, bg, fg);
          },
        ),
      );
    }
    return _buildInitial(initial, bg, fg);
  }

  Widget _buildInitial(String initial, Color bg, Color fg) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(color: fg, fontSize: size * 0.42, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// 동영상 플레이어 위젯
class VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;

  const VideoPlayerWidget({Key? key, required this.videoUrl}) : super(key: key);

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      await _controller.initialize();
      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  void dispose() {
    if (_isInitialized) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        width: 240,
        height: 200,
        color: Colors.grey[300],
        alignment: Alignment.center,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 40, color: Colors.grey),
            SizedBox(height: 6),
            Text('동영상을 불러올 수 없습니다', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      );
    }
    if (!_isInitialized) {
      return Container(
        width: 240,
        height: 200,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      );
    }
    return GestureDetector(
      onTap: () => setState(() => _controller.value.isPlaying ? _controller.pause() : _controller.play()),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 240, maxHeight: 280),
        child: Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(aspectRatio: _controller.value.aspectRatio, child: VideoPlayer(_controller)),
            if (!_controller.value.isPlaying)
              Container(
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
                padding: const EdgeInsets.all(10),
                child: const Icon(Icons.play_arrow, color: Colors.white, size: 36),
              ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: VideoProgressIndicator(
                _controller,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: Colors.amber,
                  backgroundColor: Colors.black26,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
