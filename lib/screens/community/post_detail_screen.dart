import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/community_service.dart';
import '../../services/auth_service.dart';
import '../../models/community_post.dart';
import '../../models/community_comment.dart';

class PostDetailScreen extends StatefulWidget {
  final String postId;
  const PostDetailScreen({super.key, required this.postId});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  CommunityPost? _post;
  List<CommunityComment> _comments = [];
  bool _loading = false;
  final TextEditingController _commentCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final svc = Provider.of<CommunityService>(context, listen: false);
      final post = await svc.getPost(widget.postId);
      final comments = await svc.getComments(widget.postId);
      setState(() {
        _post = post;
        _comments = comments;
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('게시글')),
      body: _loading && _post == null
          ? const Center(child: CupertinoActivityIndicator())
          : SafeArea(
              child: DefaultTextStyle(
                style: const TextStyle(fontFamily: 'Arial', fontSize: 15, color: CupertinoColors.black),
                child: Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        // index 0 = 게시글 헤더, 이후 = 댓글, 마지막 = 하단 여백
                        itemCount: _comments.length + 2,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_post != null) _buildPost(_post!),
                                const SizedBox(height: 16),
                                const Divider(height: 1),
                                const SizedBox(height: 12),
                                Text('댓글 ${_comments.length}', style: const TextStyle(fontFamily: 'Arial', fontSize: 11, color: CupertinoColors.black, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 8),
                              ],
                            );
                          }
                          if (index == _comments.length + 1) {
                            return const SizedBox(height: 80);
                          }
                          return _buildComment(_comments[index - 1]);
                        },
                      ),
                    ),
                    _buildCommentInput()
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildPost(CommunityPost post) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(post.title, style: const TextStyle(fontFamily: 'Arial', fontSize: 15, color: CupertinoColors.black, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(_formatTime(post.createdAt), style: const TextStyle(fontFamily: 'Arial', fontSize: 15, color: CupertinoColors.black)),
        const SizedBox(height: 12),
        Text(post.content, style: const TextStyle(fontFamily: 'Arial', fontSize: 15, color: CupertinoColors.black)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            ...post.tags.map((t) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGrey6,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('#$t', style: const TextStyle(fontFamily: 'Arial', fontSize: 15, color: CupertinoColors.black)),
                )),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              onPressed: () async {
                final svc = Provider.of<CommunityService>(context, listen: false);
                await svc.upvotePost(post.id);
                await _refresh();
              },
              child: Row(children: const [Icon(CupertinoIcons.hand_thumbsup), SizedBox(width: 6), Text('추천', style: TextStyle(fontFamily: 'Arial', fontSize: 15, color: CupertinoColors.black))]),
            ),
            Text(' ${post.upvotes}', style: const TextStyle(fontFamily: 'Arial', fontSize: 15, color: CupertinoColors.black)),
          ],
        )
      ],
    );
  }

  Widget _buildComment(CommunityComment c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: CupertinoColors.systemGrey5,
            backgroundImage: c.authorProfileImageUrl != null 
                ? NetworkImage(c.authorProfileImageUrl!) 
                : null,
            child: c.authorProfileImageUrl == null 
                ? const Icon(Icons.person, size: 14, color: CupertinoColors.systemGrey) 
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      c.authorName ?? '알 수 없는 사업자', 
                      style: const TextStyle(fontFamily: 'Arial', fontSize: 13, fontWeight: FontWeight.w600, color: CupertinoColors.black),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatTime(c.createdAt), 
                      style: const TextStyle(fontFamily: 'Arial', fontSize: 12, color: CupertinoColors.systemGrey),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(c.content, style: const TextStyle(fontFamily: 'Arial', fontSize: 15, color: CupertinoColors.black)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentInput() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: CupertinoColors.systemBackground,
          border: Border(top: BorderSide(color: CupertinoColors.separator.resolveFrom(context))),
        ),
        child: Row(
          children: [
            Expanded(
              child: CupertinoTextField(
                controller: _commentCtrl,
                placeholder: '댓글을 입력하세요',
                style: const TextStyle(fontFamily: 'Arial', fontSize: 15, color: CupertinoColors.black),
              ),
            ),
            const SizedBox(width: 8),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              onPressed: () async {
                final text = _commentCtrl.text.trim();
                if (text.isEmpty) return;
                final auth = Provider.of<AuthService>(context, listen: false);
                final svc = Provider.of<CommunityService>(context, listen: false);
                final userId = auth.currentUser?.id ?? '';
                await svc.addComment(postId: widget.postId, authorId: userId, content: text);
                _commentCtrl.clear();
                await _refresh();
              },
              child: const Text('등록', style: TextStyle(fontFamily: 'Arial', fontSize: 15, color: CupertinoColors.black)),
            )
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inHours < 1) return '${diff.inMinutes}분 전';
    if (diff.inDays < 1) return '${diff.inHours}시간 전';
    return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
  }
}
