class BusinessReview {
  final String id;
  final String businessId;
  final String? customerId;
  final String orderId;
  final String? estimateId;
  
  // 리뷰 내용
  final int rating; // 1-5점
  final String? title;
  final String? content;
  
  // 메타데이터
  final bool isVerified;
  final bool isAnonymous;
  final DateTime createdAt;
  final DateTime updatedAt;

  BusinessReview({
    required this.id,
    required this.businessId,
    this.customerId,
    required this.orderId,
    this.estimateId,
    required this.rating,
    this.title,
    this.content,
    this.isVerified = false,
    this.isAnonymous = false,
    required this.createdAt,
    required this.updatedAt,
  });

  /// order_reviews(reviewee_id/comment)와 호환 뷰(business_id/content) 양쪽
  /// 컬럼명을 모두 받는다.
  factory BusinessReview.fromMap(Map<String, dynamic> map) {
    return BusinessReview(
      id: map['id'] ?? '',
      businessId: map['reviewee_id'] ?? map['business_id'] ?? '',
      customerId: map['reviewer_id'] ?? map['customer_id'],
      orderId: map['order_id'] ?? '',
      estimateId: map['estimate_id'],
      rating: (map['rating'] as num?)?.round() ?? 0,
      title: map['title'],
      content: map['comment'] ?? map['content'],
      isVerified: map['is_verified'] ?? false,
      isAnonymous: map['is_anonymous'] ?? false,
      createdAt: DateTime.parse(map['created_at'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(map['updated_at'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'business_id': businessId,
      'customer_id': customerId,
      'order_id': orderId,
      'estimate_id': estimateId,
      'rating': rating,
      'title': title,
      'content': content,
      'is_verified': isVerified,
      'is_anonymous': isAnonymous,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  BusinessReview copyWith({
    String? id,
    String? businessId,
    String? customerId,
    String? orderId,
    String? estimateId,
    int? rating,
    String? title,
    String? content,
    bool? isVerified,
    bool? isAnonymous,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BusinessReview(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      customerId: customerId ?? this.customerId,
      orderId: orderId ?? this.orderId,
      estimateId: estimateId ?? this.estimateId,
      rating: rating ?? this.rating,
      title: title ?? this.title,
      content: content ?? this.content,
      isVerified: isVerified ?? this.isVerified,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'BusinessReview(id: $id, businessId: $businessId, rating: $rating, title: $title)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BusinessReview && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
