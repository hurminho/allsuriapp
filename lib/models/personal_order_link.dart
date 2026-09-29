/// 개인 오더 링크 모델
/// 사업자가 발행하는 개인 영업 페이지 링크
class PersonalOrderLink {
  final String id;
  final String contractorId;
  final String slug;
  final String slugNormalized;
  final PersonalOrderLinkStatus status;
  final bool acceptsDirectOrders;
  
  // 프로필 정보
  final String? displayName;
  final String? headline;
  final String? introduction;
  final List<String> supportedCategories;
  final List<String> serviceRegions;
  final String? profileImageUrl;
  final String? coverImageUrl;
  
  // 검증 상태
  final VerificationStatus verificationStatus;
  
  // 타임스탬프
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? revokedAt;
  final DateTime? lastSharedAt;

  PersonalOrderLink({
    required this.id,
    required this.contractorId,
    required this.slug,
    required this.slugNormalized,
    required this.status,
    this.acceptsDirectOrders = true,
    this.displayName,
    this.headline,
    this.introduction,
    this.supportedCategories = const [],
    this.serviceRegions = const [],
    this.profileImageUrl,
    this.coverImageUrl,
    this.verificationStatus = VerificationStatus.pending,
    required this.createdAt,
    required this.updatedAt,
    this.revokedAt,
    this.lastSharedAt,
  });

  /// 링크가 활성 상태이고 오더를 받을 수 있는지 확인
  bool get canAcceptOrders {
    return status == PersonalOrderLinkStatus.active && acceptsDirectOrders;
  }

  /// 공개 페이지 URL 생성 (환경 변수 기반)
  String getPublicUrl(String baseUrl) {
    return '$baseUrl/allsuri/$slug';
  }

  factory PersonalOrderLink.fromMap(Map<String, dynamic> map) {
    return PersonalOrderLink(
      id: map['id'] ?? '',
      contractorId: map['contractor_id'] ?? '',
      slug: map['slug'] ?? '',
      slugNormalized: map['slug_normalized'] ?? '',
      status: _parseStatus(map['status']),
      acceptsDirectOrders: map['accepts_direct_orders'] ?? true,
      displayName: map['display_name'],
      headline: map['headline'],
      introduction: map['introduction'],
      supportedCategories: List<String>.from(map['supported_categories'] ?? []),
      serviceRegions: List<String>.from(map['service_regions'] ?? []),
      profileImageUrl: map['profile_image_url'],
      coverImageUrl: map['cover_image_url'],
      verificationStatus: _parseVerificationStatus(map['verification_status']),
      createdAt: _parseDateTime(map['created_at']) ?? DateTime.now(),
      updatedAt: _parseDateTime(map['updated_at']) ?? DateTime.now(),
      revokedAt: _parseDateTime(map['revoked_at']),
      lastSharedAt: _parseDateTime(map['last_shared_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'contractor_id': contractorId,
      'slug': slug,
      'slug_normalized': slugNormalized,
      'status': status.value,
      'accepts_direct_orders': acceptsDirectOrders,
      'display_name': displayName,
      'headline': headline,
      'introduction': introduction,
      'supported_categories': supportedCategories,
      'service_regions': serviceRegions,
      'profile_image_url': profileImageUrl,
      'cover_image_url': coverImageUrl,
      'verification_status': verificationStatus.value,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      if (revokedAt != null) 'revoked_at': revokedAt!.toIso8601String(),
      if (lastSharedAt != null) 'last_shared_at': lastSharedAt!.toIso8601String(),
    };
  }

  PersonalOrderLink copyWith({
    String? id,
    String? contractorId,
    String? slug,
    String? slugNormalized,
    PersonalOrderLinkStatus? status,
    bool? acceptsDirectOrders,
    String? displayName,
    String? headline,
    String? introduction,
    List<String>? supportedCategories,
    List<String>? serviceRegions,
    String? profileImageUrl,
    String? coverImageUrl,
    VerificationStatus? verificationStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? revokedAt,
    DateTime? lastSharedAt,
  }) {
    return PersonalOrderLink(
      id: id ?? this.id,
      contractorId: contractorId ?? this.contractorId,
      slug: slug ?? this.slug,
      slugNormalized: slugNormalized ?? this.slugNormalized,
      status: status ?? this.status,
      acceptsDirectOrders: acceptsDirectOrders ?? this.acceptsDirectOrders,
      displayName: displayName ?? this.displayName,
      headline: headline ?? this.headline,
      introduction: introduction ?? this.introduction,
      supportedCategories: supportedCategories ?? this.supportedCategories,
      serviceRegions: serviceRegions ?? this.serviceRegions,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      revokedAt: revokedAt ?? this.revokedAt,
      lastSharedAt: lastSharedAt ?? this.lastSharedAt,
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    try {
      return DateTime.parse(value.toString());
    } catch (e) {
      return null;
    }
  }

  static PersonalOrderLinkStatus _parseStatus(dynamic value) {
    final str = value?.toString() ?? 'active';
    switch (str) {
      case 'active':
        return PersonalOrderLinkStatus.active;
      case 'paused':
        return PersonalOrderLinkStatus.paused;
      case 'revoked':
        return PersonalOrderLinkStatus.revoked;
      case 'suspended':
        return PersonalOrderLinkStatus.suspended;
      default:
        return PersonalOrderLinkStatus.active;
    }
  }

  static VerificationStatus _parseVerificationStatus(dynamic value) {
    final str = value?.toString() ?? 'pending';
    switch (str) {
      case 'verified':
        return VerificationStatus.verified;
      case 'rejected':
        return VerificationStatus.rejected;
      case 'pending':
      default:
        return VerificationStatus.pending;
    }
  }
}

/// 개인 오더 링크 상태
enum PersonalOrderLinkStatus {
  active('active', '활성'),
  paused('paused', '일시정지'),
  revoked('revoked', '폐기'),
  suspended('suspended', '정지');

  final String value;
  final String displayName;
  const PersonalOrderLinkStatus(this.value, this.displayName);
}

/// 검증 상태
enum VerificationStatus {
  pending('pending', '검증 대기'),
  verified('verified', '검증 완료'),
  rejected('rejected', '검증 거부');

  final String value;
  final String displayName;
  const VerificationStatus(this.value, this.displayName);
}

/// 개인 오더 링크 분석 이벤트
class PersonalOrderLinkEvent {
  final String id;
  final String personalOrderLinkId;
  final PersonalOrderLinkEventType eventType;
  final String? anonymousSessionId;
  final String? utmSource;
  final String? utmMedium;
  final String? utmCampaign;
  final String? referrerDomain;
  final DateTime createdAt;

  PersonalOrderLinkEvent({
    required this.id,
    required this.personalOrderLinkId,
    required this.eventType,
    this.anonymousSessionId,
    this.utmSource,
    this.utmMedium,
    this.utmCampaign,
    this.referrerDomain,
    required this.createdAt,
  });

  factory PersonalOrderLinkEvent.fromMap(Map<String, dynamic> map) {
    return PersonalOrderLinkEvent(
      id: map['id'] ?? '',
      personalOrderLinkId: map['personal_order_link_id'] ?? '',
      eventType: _parseEventType(map['event_type']),
      anonymousSessionId: map['anonymous_session_id'],
      utmSource: map['utm_source'],
      utmMedium: map['utm_medium'],
      utmCampaign: map['utm_campaign'],
      referrerDomain: map['referrer_domain'],
      createdAt: DateTime.parse(map['created_at'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'personal_order_link_id': personalOrderLinkId,
      'event_type': eventType.value,
      'anonymous_session_id': anonymousSessionId,
      'utm_source': utmSource,
      'utm_medium': utmMedium,
      'utm_campaign': utmCampaign,
      'referrer_domain': referrerDomain,
      'created_at': createdAt.toIso8601String(),
    };
  }

  static PersonalOrderLinkEventType _parseEventType(dynamic value) {
    final str = value?.toString() ?? 'page_view';
    switch (str) {
      case 'page_view':
        return PersonalOrderLinkEventType.pageView;
      case 'quote_start':
        return PersonalOrderLinkEventType.quoteStart;
      case 'category_selected':
        return PersonalOrderLinkEventType.categorySelected;
      case 'photo_added':
        return PersonalOrderLinkEventType.photoAdded;
      case 'quote_submitted':
        return PersonalOrderLinkEventType.quoteSubmitted;
      case 'contractor_viewed':
        return PersonalOrderLinkEventType.contractorViewed;
      case 'contractor_replied':
        return PersonalOrderLinkEventType.contractorReplied;
      case 'order_completed':
        return PersonalOrderLinkEventType.orderCompleted;
      default:
        return PersonalOrderLinkEventType.pageView;
    }
  }
}

/// 개인 오더 링크 이벤트 타입
enum PersonalOrderLinkEventType {
  pageView('page_view', '페이지 방문'),
  quoteStart('quote_start', '견적 요청 시작'),
  categorySelected('category_selected', '카테고리 선택'),
  photoAdded('photo_added', '사진 추가'),
  quoteSubmitted('quote_submitted', '견적 요청 제출'),
  contractorViewed('contractor_viewed', '사업자 확인'),
  contractorReplied('contractor_replied', '사업자 응답'),
  orderCompleted('order_completed', '오더 완료');

  final String value;
  final String displayName;
  const PersonalOrderLinkEventType(this.value, this.displayName);
}

/// 개인 오더 링크 통계
class PersonalOrderLinkStats {
  final int pageViews;
  final int quoteStarts;
  final int quoteSubmissions;
  final int pendingOrders;
  final double responseRate;
  final Duration? averageFirstResponseTime;
  final int completedOrders;

  PersonalOrderLinkStats({
    this.pageViews = 0,
    this.quoteStarts = 0,
    this.quoteSubmissions = 0,
    this.pendingOrders = 0,
    this.responseRate = 0.0,
    this.averageFirstResponseTime,
    this.completedOrders = 0,
  });

  /// 견적 요청 시작 → 제출 전환율
  double get startToSubmissionRate {
    if (quoteStarts == 0) return 0.0;
    return (quoteSubmissions / quoteStarts) * 100;
  }

  /// 페이지 방문 → 견적 요청 시작 전환율
  double get viewToStartRate {
    if (pageViews == 0) return 0.0;
    return (quoteStarts / pageViews) * 100;
  }
}
