import 'package:flutter/foundation.dart';

class Estimate {
  final String id;
  final String orderId;
  final String customerId;
  final String customerName;
  final String businessId;
  final String businessName;
  final String businessPhone;
  final String equipmentType;
  final double amount;
  final String description;
  final int estimatedDays;
  final DateTime createdAt;
  final DateTime visitDate;
  final String status;
  final String? transferredBy;
  final DateTime? transferredAt;
  final String? transferReason;
  final DateTime? awardedAt;
  final List<String>? mediaUrls;

  static const String STATUS_PENDING = 'pending';
  static const String STATUS_APPROVED = 'approved';
  static const String STATUS_REJECTED = 'rejected';
  static const String STATUS_COMPLETED = 'completed';
  static const String STATUS_TRANSFERRED = 'transferred';
  static const String STATUS_ACCEPTED = 'accepted';
  static const String STATUS_AWARDED = 'awarded';

  // 하위 호환성을 위한 getter들
  double get price => amount;
  String get technicianId => businessId;
  String get technicianName => businessName;
  bool get isTransferEstimate =>
      status == STATUS_TRANSFERRED || (transferredBy != null && transferredBy!.isNotEmpty);

  Estimate({
    required this.id,
    required this.orderId,
    required this.customerId,
    required this.customerName,
    required this.businessId,
    required this.businessName,
    required this.businessPhone,
    required this.equipmentType,
    required this.amount,
    required this.description,
    required this.estimatedDays,
    required this.createdAt,
    required this.visitDate,
    required this.status,
    this.transferredBy,
    this.transferredAt,
    this.transferReason,
    this.awardedAt,
    this.mediaUrls,
  });

  // 빈 견적 생성자
  factory Estimate.empty() {
    return Estimate(
      id: '',
      orderId: '',
      customerId: '',
      customerName: '',
      businessId: '',
      businessName: '',
      businessPhone: '',
      equipmentType: '',
      amount: 0.0,
      description: '',
      estimatedDays: 0,
      createdAt: DateTime.now(),
      visitDate: DateTime.now(),
      status: STATUS_PENDING,
      mediaUrls: [],
    );
  }

  Estimate copyWith({
    String? id,
    String? orderId,
    String? customerId,
    String? customerName,
    String? businessId,
    String? businessName,
    String? businessPhone,
    String? equipmentType,
    double? amount,
    String? description,
    int? estimatedDays,
    DateTime? createdAt,
    DateTime? visitDate,
    String? status,
    String? transferredBy,
    DateTime? transferredAt,
    String? transferReason,
    DateTime? awardedAt,
    List<String>? mediaUrls,
  }) {
    return Estimate(
      id: id ?? this.id,
      orderId: orderId ?? this.orderId,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      businessId: businessId ?? this.businessId,
      businessName: businessName ?? this.businessName,
      businessPhone: businessPhone ?? this.businessPhone,
      equipmentType: equipmentType ?? this.equipmentType,
      amount: amount ?? this.amount,
      description: description ?? this.description,
      estimatedDays: estimatedDays ?? this.estimatedDays,
      createdAt: createdAt ?? this.createdAt,
      visitDate: visitDate ?? this.visitDate,
      status: status ?? this.status,
      transferredBy: transferredBy ?? this.transferredBy,
      transferredAt: transferredAt ?? this.transferredAt,
      transferReason: transferReason ?? this.transferReason,
      awardedAt: awardedAt ?? this.awardedAt,
      mediaUrls: mediaUrls ?? this.mediaUrls,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'orderId': orderId,
      'customerId': customerId,
      'customerName': customerName,
      'businessId': businessId,
      'businessName': businessName,
      'businessPhone': businessPhone,
      'equipmentType': equipmentType,
      'amount': amount,
      'description': description,
      'estimatedDays': estimatedDays,
      'createdAt': createdAt.toIso8601String(),
      'visitDate': visitDate.toIso8601String(),
      'status': status,
      'transferredBy': transferredBy,
      'transferredAt': transferredAt?.toIso8601String(),
      'transferReason': transferReason,
      'awardedAt': awardedAt?.toIso8601String(),
      'mediaUrls': mediaUrls,
    };
  }

  factory Estimate.fromMap(Map<String, dynamic> map) {
    String _strOf(dynamic v, {String fallback = ''}) => v == null ? fallback : v.toString();
    num _numOf(dynamic v, {num fallback = 0}) => v is num ? v : (v == null ? fallback : num.tryParse(v.toString()) ?? fallback);
    DateTime _dtOf(dynamic v, {DateTime? fallback}) {
      if (v == null) return fallback ?? DateTime.now();
      final s = v.toString();
      return DateTime.tryParse(s) ?? (fallback ?? DateTime.now());
    }

    final id = _strOf(map['id']);
    final orderId = _strOf(map['orderId'] ?? map['orderid']);
    final customerId = _strOf(map['customerId'] ?? map['customerid']);
    final customerName = _strOf(map['customerName'] ?? map['customername'], fallback: '고객');
    final businessId = _strOf(map['businessId'] ?? map['businessid']);
    final businessName = _strOf(map['businessName'] ?? map['businessname'], fallback: '사업자');
    final businessPhone = _strOf(map['businessPhone'] ?? map['businessphone']);
    final equipmentType = _strOf(map['equipmentType'] ?? map['equipmenttype'], fallback: '기타');
    final amount = _numOf(map['amount']).toDouble();
    final description = _strOf(map['description']);
    final estimatedDays = _numOf(map['estimatedDays'] ?? map['estimateddays']).toInt();
    final createdAt = _dtOf(map['createdAt'] ?? map['createdat']);
    final visitDate = _dtOf(map['visitDate'] ?? map['visitdate']);
    final status = _strOf(map['status'], fallback: STATUS_PENDING);
    final transferredBy = map['transferredBy'] ?? map['transferredby'];
    final transferredAt = (map['transferredAt'] ?? map['transferredat']) != null
        ? _dtOf(map['transferredAt'] ?? map['transferredat'])
        : null;
    final transferReason = map['transferReason'] ?? map['transferreason'];
    final awardedAt = (map['awardedAt'] ?? map['awardedat']) != null
        ? _dtOf(map['awardedAt'] ?? map['awardedat'])
        : null;
    final mediaUrls = List<String>.from(map['mediaUrls'] ?? []);

    return Estimate(
      id: id,
      orderId: orderId,
      customerId: customerId,
      customerName: customerName,
      businessId: businessId,
      businessName: businessName,
      businessPhone: businessPhone,
      equipmentType: equipmentType,
      amount: amount,
      description: description,
      estimatedDays: estimatedDays,
      createdAt: createdAt,
      visitDate: visitDate,
      status: status,
      transferredBy: transferredBy?.toString(),
      transferredAt: transferredAt,
      transferReason: transferReason?.toString(),
      awardedAt: awardedAt,
      mediaUrls: mediaUrls,
    );
  }
}
