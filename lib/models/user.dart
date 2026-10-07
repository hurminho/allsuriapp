
enum BusinessStatus {
  pending,    // 승인 대기
  approved,   // 승인됨
  rejected,   // 거절됨
}

// 한국 주요 도시 목록
class KoreanCities {
  static const List<String> cities = [
    '서울',
    '부산',
    '대구',
    '인천',
    '광주',
    '대전',
    '울산',
    '세종',
    '수원',
    '고양',
    '용인',
    '창원',
    '성남',
    '부천',
    '안산',
    '안양',
    '남양주',
    '평택',
    '시흥',
    '김포',
    '하남',
    '오산',
    '이천',
    '안성',
    '의왕',
    '양평',
    '여주',
    '과천',
    '광명',
    '군포',
    '의정부',
    '동두천',
    '구리',
    '파주',
    '양주',
    '포천',
    '연천',
    '가평',
    '천안',
    '공주',
    '보령',
    '아산',
    '서산',
    '논산',
    '계룡',
    '당진',
    '금산',
    '부여',
    '서천',
    '청양',
    '홍성',
    '예산',
    '태안',
    '청주',
    '충주',
    '제천',
    '보은',
    '옥천',
    '영동',
    '증평',
    '진천',
    '괴산',
    '음성',
    '단양',
    '전주',
    '군산',
    '익산',
    '정읍',
    '남원',
    '김제',
    '완주',
    '진안',
    '무주',
    '장수',
    '임실',
    '순창',
    '고창',
    '부안',
    '목포',
    '여수',
    '순천',
    '나주',
    '광양',
    '담양',
    '곡성',
    '구례',
    '고흥',
    '보성',
    '화순',
    '장흥',
    '강진',
    '해남',
    '영암',
    '무안',
    '함평',
    '영광',
    '장성',
    '완도',
    '진도',
    '신안',
    '포항',
    '경주',
    '김천',
    '안동',
    '구미',
    '영주',
    '영천',
    '상주',
    '문경',
    '경산',
    '군위',
    '의성',
    '청송',
    '영양',
    '영덕',
    '청도',
    '고령',
    '성주',
    '칠곡',
    '예천',
    '봉화',
    '울진',
    '울릉',
    '창원',
    '진주',
    '통영',
    '사천',
    '김해',
    '밀양',
    '거제',
    '양산',
    '의령',
    '함안',
    '창녕',
    '고성',
    '남해',
    '하동',
    '산청',
    '함양',
    '거창',
    '합천',
    '제주',
  ];
}

// 설비 카테고리 목록
class EquipmentCategories {
  static const List<String> categories = [
    '에어컨',
    '냉장고',
    '세탁기',
    '건조기',
    '가스레인지',
    '전자레인지',
    '오븐',
    '식기세척기',
    '정수기',
    '공기청정기',
    '가습기',
    '제습기',
    '청소기',
    '커피머신',
    '전기밥솥',
    '믹서기',
    '토스터기',
    '전기포트',
    '온수기',
    '보일러',
    '히터',
    '선풍기',
    '전기장판',
    '전기담요',
    '전기히터',
    '온풍기',
    '냉난방기',
    '공조기',
    '환기장치',
    '배수장치',
    '급수장치',
    '소화설비',
    '보안설비',
    'CCTV',
    '인터폰',
    '도어락',
    '자동문',
    '엘리베이터',
    '에스컬레이터',
    '컨베이어',
    '기타',
  ];
}

/// 사업자 진위확인 상태
enum BusinessVerifyStatus {
  unverified, // 아직 인증 안함
  verified,   // 국세청 진위확인 통과
  failed,     // 진위확인 실패 (불일치)
  closed,     // 휴/폐업
}

BusinessVerifyStatus parseBusinessVerifyStatus(String? raw) {
  switch (raw) {
    case 'verified':
      return BusinessVerifyStatus.verified;
    case 'failed':
      return BusinessVerifyStatus.failed;
    case 'closed':
      return BusinessVerifyStatus.closed;
    default:
      return BusinessVerifyStatus.unverified;
  }
}

String businessVerifyStatusToString(BusinessVerifyStatus s) {
  switch (s) {
    case BusinessVerifyStatus.verified:
      return 'verified';
    case BusinessVerifyStatus.failed:
      return 'failed';
    case BusinessVerifyStatus.closed:
      return 'closed';
    case BusinessVerifyStatus.unverified:
      return 'unverified';
  }
}

class User {
  final String id;
  final String email;
  final String name;
  final String role;
  final String? phoneNumber;
  final DateTime createdAt;
  final bool isAnonymous;
  final String? businessStatus;
  final String? businessName;
  final String? businessNumber;
  final String? address;
  final List<String> serviceAreas;
  final List<String> specialties;
  final String? avatarUrl;

  // 진위확인 관련
  final BusinessVerifyStatus businessVerifyStatus;
  final String? businessRepName;
  final DateTime? businessOpenDate;
  final DateTime? businessVerifiedAt;
  final DateTime? businessGraceUntil;
  final bool businessVerifyBypass;

  String get uid => id;

  /// 사업자번호 보유 여부 (정규화된 10자리 기준).
  bool get hasBusinessNumber {
    final n = (businessNumber ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    return n.length == 10;
  }

  /// 사업자 활동(오더 생성/입찰/낙찰 등) 가능 여부.
  ///
  /// 2026-05 정책 완화:
  /// - 관리자 우회(bypass=TRUE)는 그대로 통과
  /// - 그 외에는 **사업자번호 보유 여부**만 본다.
  ///   진위확인 실패/미완료 상태여도, 10자리 사업자번호가 있으면 통과.
  ///   (국세청 API false negative 대응)
  /// - 사업자번호가 없으면 차단.
  bool get canActAsBusiness {
    if (businessVerifyBypass) return true;
    return hasBusinessNumber;
  }

  /// 인증되지는 않았지만 유예 기간 중인지 (bypass는 별개로 취급)
  bool get isInGracePeriod {
    if (businessVerifyBypass) return false;
    if (businessVerifyStatus == BusinessVerifyStatus.verified) return false;
    final until = businessGraceUntil;
    return until != null && until.isAfter(DateTime.now());
  }

  /// 유예 만료까지 남은 시간 (없거나 만료면 null)
  Duration? get graceRemaining {
    final until = businessGraceUntil;
    if (until == null) return null;
    final diff = until.difference(DateTime.now());
    return diff.isNegative ? null : diff;
  }

  User({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.phoneNumber,
    required this.createdAt,
    this.isAnonymous = false,
    this.businessStatus,
    this.businessName,
    this.businessNumber,
    this.address,
    this.serviceAreas = const [],
    this.specialties = const [],
    this.avatarUrl,
    this.businessVerifyStatus = BusinessVerifyStatus.unverified,
    this.businessRepName,
    this.businessOpenDate,
    this.businessVerifiedAt,
    this.businessGraceUntil,
    this.businessVerifyBypass = false,
  });

  factory User.fromMap(Map<String, dynamic> map) {
    DateTime? _parseDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is String && v.isNotEmpty) {
        try {
          return DateTime.parse(v);
        } catch (_) {
          return null;
        }
      }
      return null;
    }

    return User(
      id: map['id'] ?? '',
      email: map['email'] ?? '',
      name: map['name'] ?? '',
      role: map['role'] ?? 'customer',
      phoneNumber: map['phonenumber'] ?? map['phoneNumber'],
      createdAt: DateTime.parse(map['createdat'] ?? map['createdAt'] ?? DateTime.now().toIso8601String()),
      isAnonymous: map['isanonymous'] ?? map['isAnonymous'] ?? false,
      businessStatus: map['businessstatus'] ?? map['businessStatus'],
      businessName: map['businessname'] ?? map['businessName'],
      businessNumber: map['businessnumber'] ?? map['businessNumber'],
      address: map['address'],
      serviceAreas: List<String>.from(map['serviceareas'] ?? map['serviceAreas'] ?? const []),
      specialties: List<String>.from(map['specialties'] ?? const []),
      avatarUrl: map['avatar_url'] ?? map['avatarUrl'],
      businessVerifyStatus: parseBusinessVerifyStatus(
        (map['business_verify_status'] ?? map['businessVerifyStatus']) as String?,
      ),
      businessRepName: map['business_repname'] ?? map['businessRepName'],
      businessOpenDate: _parseDate(map['business_open_date'] ?? map['businessOpenDate']),
      businessVerifiedAt: _parseDate(map['business_verified_at'] ?? map['businessVerifiedAt']),
      businessGraceUntil: _parseDate(map['business_grace_until'] ?? map['businessGraceUntil']),
      businessVerifyBypass:
          (map['business_verify_bypass'] ?? map['businessVerifyBypass'] ?? false) as bool,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'role': role,
      'phoneNumber': phoneNumber,
      'createdAt': createdAt.toIso8601String(),
      'isAnonymous': isAnonymous,
      'businessStatus': businessStatus,
      'businessName': businessName,
      'businessNumber': businessNumber,
      'address': address,
      'serviceAreas': serviceAreas,
      'specialties': specialties,
      'avatar_url': avatarUrl,
    };
  }

  User copyWith({
    String? id,
    String? email,
    String? name,
    String? role,
    String? phoneNumber,
    DateTime? createdAt,
    bool? isAnonymous,
    String? businessStatus,
    String? businessName,
    String? businessNumber,
    String? address,
    List<String>? serviceAreas,
    List<String>? specialties,
    String? avatarUrl,
    BusinessVerifyStatus? businessVerifyStatus,
    String? businessRepName,
    DateTime? businessOpenDate,
    DateTime? businessVerifiedAt,
    DateTime? businessGraceUntil,
    bool? businessVerifyBypass,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      role: role ?? this.role,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      createdAt: createdAt ?? this.createdAt,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      businessStatus: businessStatus ?? this.businessStatus,
      businessName: businessName ?? this.businessName,
      businessNumber: businessNumber ?? this.businessNumber,
      address: address ?? this.address,
      serviceAreas: serviceAreas ?? this.serviceAreas,
      specialties: specialties ?? this.specialties,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      businessVerifyStatus: businessVerifyStatus ?? this.businessVerifyStatus,
      businessRepName: businessRepName ?? this.businessRepName,
      businessOpenDate: businessOpenDate ?? this.businessOpenDate,
      businessVerifiedAt: businessVerifiedAt ?? this.businessVerifiedAt,
      businessGraceUntil: businessGraceUntil ?? this.businessGraceUntil,
      businessVerifyBypass: businessVerifyBypass ?? this.businessVerifyBypass,
    );
  }
}
