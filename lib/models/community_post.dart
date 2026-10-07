
class CommunityPost {
  final String id;
  final String authorId;
  final String? authorName;
  final String? authorProfileImageUrl;
  final String title;
  final String content;
  final List<String> tags;
  final int upvotes;
  final int commentsCount;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const CommunityPost({
    required this.id,
    required this.authorId,
    this.authorName,
    this.authorProfileImageUrl,
    required this.title,
    required this.content,
    required this.tags,
    required this.upvotes,
    required this.commentsCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CommunityPost.fromMap(Map<String, dynamic> map) {
    final id = (map['id'] ?? '').toString();
    final authorId = (map['authorid'] ?? map['authorId'] ?? '').toString();
    final authorName = (map['author_name'] ?? map['authorName'] ?? map['users_name'] ?? map['users_businessname'])?.toString();
    final authorProfileImageUrl = (map['author_profile_image_url'] ?? map['authorProfileImageUrl'] ?? map['users_avatar_url'])?.toString();
    final title = (map['title'] ?? '').toString();
    final content = (map['content'] ?? map['body'] ?? '').toString();
    final rawTags = map['tags'];
    final tags = rawTags is List
        ? rawTags.map((e) => e.toString()).toList()
        : (rawTags is String && rawTags.isNotEmpty)
            ? rawTags.split(',').map((e) => e.trim()).toList()
            : <String>[];
    final upvotes = int.tryParse((map['upvotes'] ?? map['likes'] ?? 0).toString()) ?? 0;
    final commentsCount = int.tryParse((map['commentscount'] ?? map['commentsCount'] ?? 0).toString()) ?? 0;
    final created = map['createdat'] ?? map['createdAt'] ?? map['created_at'];
    final updated = map['updatedat'] ?? map['updatedAt'] ?? map['updated_at'];

    return CommunityPost(
      id: id,
      authorId: authorId,
      authorName: authorName,
      authorProfileImageUrl: authorProfileImageUrl,
      title: title,
      content: content,
      tags: tags,
      upvotes: upvotes,
      commentsCount: commentsCount,
      createdAt: DateTime.tryParse(created?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(updated?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'authorid': authorId,
      if (authorName != null) 'author_name': authorName,
      if (authorProfileImageUrl != null) 'author_profile_image_url': authorProfileImageUrl,
      'title': title,
      'content': content,
      'tags': tags,
      'upvotes': upvotes,
      'commentscount': commentsCount,
      'createdat': createdAt.toIso8601String(),
      if (updatedAt != null) 'updatedat': updatedAt!.toIso8601String(),
    };
  }
}
