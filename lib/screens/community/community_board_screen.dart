import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/community_service.dart';
import '../../models/community_post.dart';
import 'create_post_screen.dart';
import 'post_detail_screen.dart';
import '../../services/auth_service.dart';

class CommunityBoardScreen extends StatefulWidget {
  const CommunityBoardScreen({super.key});

  @override
  State<CommunityBoardScreen> createState() => _CommunityBoardScreenState();
}

class _CommunityBoardScreenState extends State<CommunityBoardScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<CommunityPost> _posts = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    debugPrint('[CommunityBoardScreen] _refresh 시작');
    try {
      final svc = Provider.of<CommunityService>(context, listen: false);
      final rows = await svc.getPosts(query: _searchController.text.trim());
      debugPrint('[CommunityBoardScreen] getPosts 결과 - ${rows.length}개 항목');
      setState(() => _posts = rows);
      debugPrint('[CommunityBoardScreen] _posts 업데이트 완료: ${_posts.length}개 항목');
    } finally {
      setState(() => _loading = false);
      debugPrint('[CommunityBoardScreen] _refresh 완료');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: const Text(
          '커뮤니티',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refresh,
            tooltip: '새로고침',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: '검색어를 입력하세요',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onSubmitted: (_) => _refresh(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 80,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _refresh,
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      backgroundColor: const Color(0xFF0B2545),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('검색', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _refresh,
                    child: _posts.isEmpty
                        ? ListView(
                            children: [
                              const SizedBox(height: 100),
                              Center(
                                child: Column(
                                  children: [
                                    Container(
                                      width: 100,
                                      height: 100,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFE5E9F2),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.forum_outlined,
                                        size: 50,
                                        color: Color(0xFF0B2545),
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    const Text(
                                      '게시글이 없습니다',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '첫 게시글을 작성해보세요',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            itemCount: _posts.length,
                            itemBuilder: (_, idx) {
                              debugPrint('[CommunityBoardScreen] 게시글 빌드 중: ${idx+1}/${_posts.length} - ${_posts[idx].title}');
                              try {
                                final tile = _buildModernPostTile(_posts[idx]);
                                debugPrint('[CommunityBoardScreen] 게시글 타일 생성 성공: ${idx+1}');
                                return tile;
                              } catch (e) {
                                debugPrint('[CommunityBoardScreen] 게시글 타일 생성 실패: ${idx+1} - $e');
                                return Container(
                                  height: 100,
                                  color: Colors.red[100],
                                  child: Center(child: Text('게시글 로드 오류: $e')),
                                );
                              }
                            },
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                          ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CreatePostScreen()),
                    );
                    if (!mounted) return;
                    await _refresh();
                  },
                  icon: const Icon(Icons.edit_rounded, size: 20),
                  label: const Text('새 글 작성', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0B2545),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernPostTile(CommunityPost post) {
    final currentUserId = Provider.of<AuthService>(context, listen: false).currentUser?.id;
    final isAuthor = currentUserId == post.authorId;
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PostDetailScreen(postId: post.id)),
            );
            if (!mounted) return;
            await _refresh();
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Author profile section with delete button
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.grey[200],
                      backgroundImage: post.authorProfileImageUrl != null
                          ? NetworkImage(post.authorProfileImageUrl!)
                          : null,
                      child: post.authorProfileImageUrl == null
                          ? Icon(Icons.person, color: Colors.grey[600], size: 20)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        post.authorName ?? '알 수 없는 사업자',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isAuthor)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                              title: const Text('글 삭제'),
                              content: const Text('이 글을 삭제하시겠습니까?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dialogContext),
                                  child: const Text('취소'),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    Navigator.pop(dialogContext);
                                    await _deletePost(post.id);
                                  },
                                  child: const Text('삭제', style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          );
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                  ],
                ),
                const SizedBox(height: 12), // Spacing between author and tags/title
                // Tags
                if (post.tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: post.tags.take(3).map((t) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B2545).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '#$t',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF0B2545),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )).toList(),
                    ),
                  ),
                // Title
                Text(
                  post.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0B2545),
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                // Content preview
                Text(
                  post.content.length > 100 ? '${post.content.substring(0, 100)}…' : post.content,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                // Stats row
                Row(
                  children: [
                    Icon(Icons.access_time_outlined, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Flexible( // Flexible 추가
                      child: Text(
                        _formatTime(post.createdAt),
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        maxLines: 1, // 추가
                        overflow: TextOverflow.ellipsis, // 추가
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(Icons.thumb_up_outlined, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Flexible( // Flexible 추가
                      child: Text(
                        post.upvotes.toString(),
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        maxLines: 1, // 추가
                        overflow: TextOverflow.ellipsis, // 추가
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(Icons.comment_outlined, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Flexible( // Flexible 추가 (기존 Expanded를 Flexible로 변경)
                      child: Text(
                        post.commentsCount.toString(),
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inHours < 1) return '${diff.inMinutes}분 전';
    if (diff.inDays < 1) return '${diff.inHours}시간 전';
    return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
  }

  Future<void> _deletePost(String postId) async {
    final svc = Provider.of<CommunityService>(context, listen: false);
    try {
      await svc.deletePost(postId);
      debugPrint('[CommunityBoardScreen] 게시글 삭제 성공: $postId');
      if (!mounted) return;
      await _refresh();
    } catch (e) {
      debugPrint('[CommunityBoardScreen] 게시글 삭제 실패: $postId - $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('게시글 삭제 실패: $e')),
      );
    }
  }
}
