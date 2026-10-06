// unused import 제거됨
import 'package:flutter/foundation.dart';

class Order {
  final String? id;
  final String? customerId;
  final String title;
  final String description;
  final String address;
  final DateTime visitDate;
  final String status;
  final DateTime createdAt;
  final List<String> images;
  final double estimatedPrice;
  final String? technicianId;
  final String? selectedEstimateId;
  final String category;
  final String customerName;
  final String customerPhone;
  final String? customerEmail;
  final bool isAnonymous;
  final bool isAwarded;
  final DateTime? awardedAt;
  final String? awardedEstimateId;
  final String? sessionId;

  // 개인 오더 링크 관련 필드
  final String routingType; // 'marketplace' | 'personal_link'
  final String? personalOrderLinkId;
  final String? sourceContractorId;
  final String? assignedContractorId;
  final DateTime? assignmentLockedAt;
  final String? attributionSource;
  final String? utmSource;
  final String? utmMedium;
  final String? utmCampaign;
  final String? referrerDomain;

  // 카테고리 목록
  static const List<String> CATEGORIES = [
    '누수',
    '화장실',
    '배관',
    '난방',
    '주방',
    '리모델링',
    '기타',
  ];

  static const String STATUS_PENDING = 'pending';
  static const String STATUS_IN_PROGRESS = 'in_progress';
  static const String STATUS_COMPLETED = 'completed';
  static const String STATUS_CANCELLED = 'cancelled';
  static const String STATUS_ESTIMATING = 'estimating';

  Order({
    this.id,
    this.customerId,
    required this.title,
    required this.description,
    required this.address,
    required this.visitDate,
    required this.status,
    required this.createdAt,
    this.images = const [],
    this.estimatedPrice = 0.0,
    this.technicianId,
    this.selectedEstimateId,
    this.category = '기타',
    required this.customerName,
    required this.customerPhone,
    this.customerEmail,
    this.isAnonymous = false,
    this.isAwarded = false,
    this.awardedAt,
    this.awardedEstimateId,
    this.sessionId,
    this.routingType = 'marketplace',
    this.personalOrderLinkId,
    this.sourceContractorId,
    this.assignedContractorId,
    this.assignmentLockedAt,
    this.attributionSource,
    this.utmSource,
    this.utmMedium,
    this.utmCampaign,
    this.referrerDomain,
  });

  // equipmentType getter (하위 호환성)
  String get equipmentType => category;

  // 날짜 포맷팅 getter
  String get formattedDate {
    return '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}';
  }

  static DateTime _parseDate(dynamic value, {DateTime? fallback}) {
    if (value is DateTime) return value;
    if (value != null) {
      final parsed = DateTime.tryParse(value.toString());
      if (parsed != null) return parsed;
    }
    return fallback ?? DateTime.now();
  }

  /// 오더 찾기(marketplace_listings) 행을 신규 오더 카드용 Order 로 변환합니다.
  factory Order.fromMarketplaceListing(Map<String, dynamic> listing) {
    final region = (listing['region'] ?? '').toString();
    return Order(
      id: listing['id']?.toString(),
      title: (listing['title'] ?? '오더').toString(),
      description: (listing['description'] ?? '').toString(),
      address: region,
      visitDate: _parseDate(listing['visit_date'] ?? listing['visitDate']),
      status: STATUS_PENDING,
      createdAt: _parseDate(
        listing['createdat'] ?? listing['created_at'] ?? listing['createdAt'],
      ),
      category: (listing['category'] ?? '기타').toString(),
      customerName: '',
      customerPhone: '',
      estimatedPrice:
          (listing['budget_amount'] as num?)?.toDouble() ??
          (listing['budgetAmount'] as num?)?.toDouble() ??
          0,
      routingType: 'marketplace',
    );
  }

  factory Order.fromMap(Map<String, dynamic> map) {
    return Order(
      id: map['id'],
      customerId: map['customerid'] ?? map['customerId'], // 둘 다 시도
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      address: map['address'] ?? '',
      visitDate: (map['visitDate'] ?? map['visitdate']) != null  // 둘 다 시도
          ? ((map['visitDate'] ?? map['visitdate']) is DateTime 
              ? (map['visitDate'] ?? map['visitdate']) 
              : DateTime.parse((map['visitDate'] ?? map['visitdate']).toString()))
          : DateTime.now(),
      status: map['status'] ?? STATUS_PENDING,
      createdAt: (map['createdAt'] ?? map['createdat']) != null  // 둘 다 시도
          ? ((map['createdAt'] ?? map['createdat']) is DateTime 
              ? (map['createdAt'] ?? map['createdat']) 
              : DateTime.parse((map['createdAt'] ?? map['createdat']).toString()))
          : DateTime.now(),
      images: List<String>.from(map['images'] ?? []),
      estimatedPrice: (map['estimatedPrice'] ?? map['estimatedprice'] ?? 0.0).toDouble(), // 둘 다 시도
      technicianId: map['technicianId'] ?? map['technicianid'], // 둘 다 시도
      selectedEstimateId: map['selectedEstimateId'] ?? map['selectedestimateid'], // 둘 다 시도
      category: map['category'] ?? '기타',
      customerName: map['customerName'] ?? map['customername'] ?? '', // 둘 다 시도
      customerPhone: map['customerPhone'] ?? map['customerphone'] ?? '', // 둘 다 시도
      customerEmail: map['customerEmail'],
      isAnonymous: map['isAnonymous'] ?? false,
      isAwarded: map['isAwarded'] ?? false,
      awardedAt: map['awardedAt'] != null 
          ? (map['awardedAt'] is DateTime 
              ? map['awardedAt'] 
              : DateTime.parse(map['awardedAt'].toString()))
          : null,
      awardedEstimateId: map['awardedEstimateId'],
      sessionId: map['sessionId'],
      routingType: map['routing_type'] ?? map['routingType'] ?? 'marketplace',
      personalOrderLinkId: map['personal_order_link_id'] ?? map['personalOrderLinkId'],
      sourceContractorId: map['source_contractor_id'] ?? map['sourceContractorId'],
      assignedContractorId: map['assigned_contractor_id'] ?? map['assignedContractorId'],
      assignmentLockedAt: map['assignment_locked_at'] != null || map['assignmentLockedAt'] != null
          ? (map['assignment_locked_at'] != null 
              ? (map['assignment_locked_at'] is DateTime 
                  ? map['assignment_locked_at'] 
                  : DateTime.parse(map['assignment_locked_at'].toString()))
              : (map['assignmentLockedAt'] is DateTime 
                  ? map['assignmentLockedAt'] 
                  : DateTime.parse(map['assignmentLockedAt'].toString())))
          : null,
      attributionSource: map['attribution_source'] ?? map['attributionSource'],
      utmSource: map['utm_source'] ?? map['utmSource'],
      utmMedium: map['utm_medium'] ?? map['utmMedium'],
      utmCampaign: map['utm_campaign'] ?? map['utmCampaign'],
      referrerDomain: map['referrer_domain'] ?? map['referrerDomain'],
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      if (id != null && id!.isNotEmpty) 'id': id,
      'customerId': customerId,
      'title': title,
      'description': description,
      'address': address,
      'visitDate': visitDate.toIso8601String(),
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'images': images,
      'estimatedPrice': estimatedPrice,
      'technicianId': technicianId,
      'selectedEstimateId': selectedEstimateId,
      'category': category,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'customerEmail': customerEmail,
      'isAnonymous': isAnonymous,
      'isAwarded': isAwarded,
      'awardedAt': awardedAt?.toIso8601String(),
      'awardedEstimateId': awardedEstimateId,
      if (sessionId != null) 'sessionId': sessionId,
      'routing_type': routingType,
      if (personalOrderLinkId != null) 'personal_order_link_id': personalOrderLinkId,
      if (sourceContractorId != null) 'source_contractor_id': sourceContractorId,
      if (assignedContractorId != null) 'assigned_contractor_id': assignedContractorId,
      if (assignmentLockedAt != null) 'assignment_locked_at': assignmentLockedAt!.toIso8601String(),
      if (attributionSource != null) 'attribution_source': attributionSource,
      if (utmSource != null) 'utm_source': utmSource,
      if (utmMedium != null) 'utm_medium': utmMedium,
      if (utmCampaign != null) 'utm_campaign': utmCampaign,
      if (referrerDomain != null) 'referrer_domain': referrerDomain,
    };
    return map;
  }

  Order copyWith({
    String? id,
    String? customerId,
    String? title,
    String? description,
    String? address,
    DateTime? visitDate,
    String? status,
    DateTime? createdAt,
    List<String>? images,
    double? estimatedPrice,
    String? technicianId,
    String? selectedEstimateId,
    String? category,
    String? customerName,
    String? customerPhone,
    String? customerEmail,
    bool? isAnonymous,
    bool? isAwarded,
    DateTime? awardedAt,
    String? awardedEstimateId,
    String? sessionId,
    String? routingType,
    String? personalOrderLinkId,
    String? sourceContractorId,
    String? assignedContractorId,
    DateTime? assignmentLockedAt,
    String? attributionSource,
    String? utmSource,
    String? utmMedium,
    String? utmCampaign,
    String? referrerDomain,
  }) {
    return Order(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      title: title ?? this.title,
      description: description ?? this.description,
      address: address ?? this.address,
      visitDate: visitDate ?? this.visitDate,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      images: images ?? this.images,
      estimatedPrice: estimatedPrice ?? this.estimatedPrice,
      technicianId: technicianId ?? this.technicianId,
      selectedEstimateId: selectedEstimateId ?? this.selectedEstimateId,
      category: category ?? this.category,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      customerEmail: customerEmail ?? this.customerEmail,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      isAwarded: isAwarded ?? this.isAwarded,
      awardedAt: awardedAt ?? this.awardedAt,
      awardedEstimateId: awardedEstimateId ?? this.awardedEstimateId,
      sessionId: sessionId ?? this.sessionId,
      routingType: routingType ?? this.routingType,
      personalOrderLinkId: personalOrderLinkId ?? this.personalOrderLinkId,
      sourceContractorId: sourceContractorId ?? this.sourceContractorId,
      assignedContractorId: assignedContractorId ?? this.assignedContractorId,
      assignmentLockedAt: assignmentLockedAt ?? this.assignmentLockedAt,
      attributionSource: attributionSource ?? this.attributionSource,
      utmSource: utmSource ?? this.utmSource,
      utmMedium: utmMedium ?? this.utmMedium,
      utmCampaign: utmCampaign ?? this.utmCampaign,
      referrerDomain: referrerDomain ?? this.referrerDomain,
    );
  }
}
