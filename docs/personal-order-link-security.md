# 개인 오더 링크 보안 및 권한 검증

## 1. 핵심 보안 원칙

### 1.1 직접 배정의 신뢰성
- **서버 측 검증**: 개인 링크 오더의 `routing_type`, `assigned_contractor_id` 등은 서버(OrderService)에서만 설정
- **클라이언트 신뢰 금지**: URL 파라미터나 폼 데이터에서 contractor ID를 직접 받지 않음
- **Slug 기반 조회**: 공개 페이지는 slug로 링크를 조회하고, 서버가 반환한 contractor_id만 사용

### 1.2 개인정보 보호
- **PII 마스킹**: 로그에 고객 연락처, 주소, 사진 URL을 기록하지 않음 (`AppLog` 사용)
- **분석 이벤트 분리**: `PersonalOrderLinkEvent`에는 절대 PII를 저장하지 않음
- **RLS 정책**: DB 레벨에서 권한 검증 (`personal_order_links`, `personal_order_link_events` RLS 활성화)

### 1.3 링크 악용 방지
- **Slug 정규화**: 소문자, 숫자, 하이픈, 언더스코어만 허용
- **예약어 차단**: `reserved_slugs` 테이블로 시스템 예약어 관리
- **중복 검증**: slug는 전역 unique (`slug_normalized` unique index)
- **Rate Limiting**: 공개 API는 rate limit 필요 (TODO: 구현 필요)

## 2. RLS 정책 요약

### 2.1 personal_order_links
- **SELECT (사업자)**: 자신의 링크만 조회 가능 (`contractor_id = auth.uid()`)
- **SELECT (익명)**: 활성 상태 링크만 조회 가능 (`status = 'active'`)
- **INSERT**: 자신의 contractor_id로만 생성 가능
- **UPDATE**: 자신의 링크만 수정 가능

### 2.2 personal_order_link_events
- **SELECT**: 링크 소유자만 자신의 분석 이벤트 조회 가능
- **INSERT**: 익명 사용자도 이벤트 삽입 가능 (분석용)

### 2.3 orders
- **개인 링크 오더 필터링**: `routing_type = 'personal_link'`인 오더는 `assigned_contractor_id`가 일치하는 사업자만 조회 가능
- **일반 마켓 차단**: 개인 링크 오더는 일반 마켓플레이스 목록에 노출되지 않음

## 3. 구현된 보안 기능

### 3.1 Slug 검증
```dart
// PersonalOrderLinkService._normalizeSlug
String _normalizeSlug(String slug) {
  return slug.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9_-]'), '');
}

// PersonalOrderLinkService._isValidSlug
bool _isValidSlug(String slug) {
  if (slug.length < 3 || slug.length > 50) return false;
  return RegExp(r'^[a-z0-9_-]+$').hasMatch(slug);
}
```

### 3.2 서버 측 직접 배정 강제
```dart
// OrderService.createPersonalLinkOrder
Future<Order> createPersonalLinkOrder({
  required Order order,
  required String personalOrderLinkId,
  required String contractorId,
  // ...
}) async {
  final personalLinkOrder = order.copyWith(
    routingType: 'personal_link',
    personalOrderLinkId: personalOrderLinkId,
    sourceContractorId: contractorId,
    assignedContractorId: contractorId,  // 서버에서 강제 설정
    assignmentLockedAt: DateTime.now(),
    attributionSource: 'personal_link',
  );
  // ...
}
```

### 3.3 PII 마스킹
- `AppLog.debug` 사용: 민감 정보는 로그에 기록하지 않음
- 분석 이벤트: `PersonalOrderLinkEvent`에는 익명 세션 ID, UTM 파라미터만 기록

### 3.4 감사 로그
- **Slug 변경**: `personal_order_link_audit_logs`에 자동 기록 (트리거 사용)
- **상태 변경**: active ↔ paused, revoked 전환 시 자동 기록

## 4. 남은 보안 작업

### 4.1 Rate Limiting
- [ ] 공개 slug 조회 API에 rate limit 적용
- [ ] 견적 요청 제출 API에 rate limit 적용
- [ ] 동일 IP/세션에서 반복 제출 방지

### 4.2 파일 업로드 검증
- [ ] 이미지 업로드 시 파일 형식 검증
- [ ] 파일 크기 제한 (예: 5MB)
- [ ] 악성 파일 스캔 (optional)

### 4.3 CSRF/XSS 방어
- [ ] Supabase RLS로 기본 방어되지만, 추가 검증 고려
- [ ] 폼 제출 시 idempotency key 사용 (중복 제출 방지)

### 4.4 운영 모니터링
- [ ] 개인 링크 오더의 일반 마켓 노출 여부 감사 쿼리
- [ ] 비정상적인 링크 생성 패턴 감지
- [ ] 링크 폐기/정지 로그 모니터링

## 5. 보안 체크리스트

### 배포 전 확인
- [x] DB에 RLS 정책 적용됨
- [x] 예약어 테이블에 기본 예약어 삽입됨
- [x] 개인 링크 오더 생성 시 서버에서 contractor_id 설정
- [x] 클라이언트가 routing_type, assigned_contractor_id를 직접 설정할 수 없음
- [x] 로그에 PII 마스킹됨
- [ ] Rate limiting 구현 (Netlify Functions 또는 Supabase Edge Functions)
- [ ] 파일 업로드 검증 구현
- [ ] 운영 모니터링 대시보드 설정

### 정기 감사
- [ ] 개인 링크 오더가 일반 마켓에 노출되지 않는지 확인
- [ ] 링크 소유자가 변경되지 않는지 확인 (contractor_id immutable)
- [ ] 분석 이벤트에 PII가 저장되지 않는지 확인
- [ ] Slug 변경 로그 검토

## 6. 긴급 대응 절차

### 개인정보 유출 발견 시
1. 해당 링크 즉시 정지 (`status = 'suspended'`)
2. 유출된 데이터 범위 확인
3. 관련 로그 백업 및 분석
4. 고객 및 사업자 통보
5. 재발 방지 조치 적용

### 악성 링크 발견 시
1. 링크 즉시 폐기 (`status = 'revoked'`)
2. 해당 사업자 계정 정지 (`verification_status = 'rejected'`)
3. 관련 오더 검토
4. 필요 시 법적 조치

### 시스템 침해 시도 발견 시
1. 의심스러운 IP 차단
2. Rate limit 강화
3. 로그 분석 및 침해 경로 확인
4. 필요 시 서비스 일시 중단

## 7. 참고 자료

- Supabase RLS 문서: https://supabase.com/docs/guides/auth/row-level-security
- OWASP Top 10: https://owasp.org/www-project-top-ten/
- 개인정보보호법: https://www.privacy.go.kr/
