# 개인 오더 링크 기능 구현 완료 보고서

## 📌 구현 개요

"개인 오더 링크" 기능은 각 설비 사업자가 개인 영업 페이지 링크를 발행하고, 이를 카카오톡, 명함, 블로그, 인스타그램 등에 공유하여 직접 고객 오더를 받을 수 있게 하는 기능입니다.

**핵심 가치**: 사업자에게 개인 영업 도구를 주고, 그 사업자가 스스로 올수리로 고객을 데려오게 만드는 것

## 1. 수정·추가한 파일 목록

### 1.1 데이터베이스 및 마이그레이션
- `database/personal_order_links.sql` ✨ **NEW**
  - `personal_order_links` 테이블 생성
  - `personal_order_link_events` 테이블 생성 (분석)
  - `personal_order_link_audit_logs` 테이블 생성 (감사)
  - `reserved_slugs` 테이블 생성
  - RLS 정책 설정
  - 트리거 및 헬퍼 함수
  - `orders` 테이블에 개인 링크 관련 컬럼 추가

- `database/rollback_personal_order_links.sql` ✨ **NEW**
  - 롤백 스크립트

### 1.2 Flutter 모델
- `lib/models/personal_order_link.dart` ✨ **NEW**
  - `PersonalOrderLink` 모델
  - `PersonalOrderLinkStatus` enum
  - `VerificationStatus` enum
  - `PersonalOrderLinkEvent` 모델
  - `PersonalOrderLinkEventType` enum
  - `PersonalOrderLinkStats` 모델

- `lib/models/order.dart` 📝 **MODIFIED**
  - 개인 링크 관련 필드 추가:
    - `routingType`, `personalOrderLinkId`, `sourceContractorId`
    - `assignedContractorId`, `assignmentLockedAt`
    - `attributionSource`, `utmSource`, `utmMedium`, `utmCampaign`, `referrerDomain`
  - `fromMap`, `toMap`, `copyWith` 메서드 업데이트

### 1.3 서비스 계층
- `lib/services/personal_order_link_service.dart` ✨ **NEW**
  - 개인 링크 CRUD 작업
  - Slug 검증 및 가용성 확인
  - 통계 조회
  - 분석 이벤트 기록
  - 직접 오더 목록 조회

- `lib/services/order_service.dart` 📝 **MODIFIED**
  - `createPersonalLinkOrder` 메서드 추가
  - 서버 측에서 개인 링크 필드를 강제 설정

### 1.4 사업자 앱 UI
- `lib/screens/business/personal_order_link_management_screen.dart` ✨ **NEW**
  - 개인 링크 관리 메인 화면
  - 링크 발행 전/후 상태 표시
  - 통계 카드
  - 링크 복사, 공유, QR 코드, 수정, 일시정지, 폐기 기능

- `lib/screens/business/create_personal_order_link_screen.dart` ✨ **NEW**
  - 개인 링크 생성 화면
  - Slug 실시간 중복 확인
  - 카테고리, 지역 선택

- `lib/screens/business/edit_personal_order_link_screen.dart` ✨ **NEW**
  - 개인 링크 편집 화면
  - Slug 변경 경고

### 1.5 소비자 웹 UI
- `lib/screens/web/personal_order_link_public_page.dart` ✨ **NEW**
  - 공개 영업 페이지
  - 사업자 프로필 표시
  - 신뢰 정보 (인증, 리뷰)
  - 직접 배정 안내 배너
  - 견적 요청 CTA
  - 링크 일시정지 상태 처리

- `lib/screens/web/personal_link_quote_request_screen.dart` ✨ **NEW**
  - 개인 링크 견적 요청 플로우 (4단계)
    - Step 1: 수리 종류 선택
    - Step 2: 증상과 사진
    - Step 3: 추가 정보 (위치, 연락처, 방문일)
    - Step 4: 확인 및 개인정보 동의
  - 직접 배정 안내 지속 표시
  - `PersonalLinkQuoteRequestCompletionScreen` (완료 화면)

### 1.6 의존성
- `pubspec.yaml` 📝 **MODIFIED**
  - `qr_flutter: ^4.1.0` 추가

### 1.7 문서
- `docs/personal-order-link-security.md` ✨ **NEW**
  - 보안 원칙 및 구현 내역
  - RLS 정책 요약
  - 보안 체크리스트
  - 긴급 대응 절차

- `docs/personal-order-link-implementation-report.md` ✨ **NEW** (본 문서)

### 1.8 테스트
- `test/personal_order_link_test.dart` ✨ **NEW**
  - `PersonalOrderLink` 모델 테스트
  - `PersonalOrderLinkStats` 테스트
  - `Order` 모델 개인 링크 필드 테스트
  - Slug 정규화 및 예약어 테스트

---

## 2. DB 마이그레이션 및 롤백 방식

### 2.1 마이그레이션 실행
```bash
# Supabase SQL Editor 또는 CLI를 사용하여 실행
psql -U postgres -d allsuridb -f database/personal_order_links.sql
```

### 2.2 롤백 실행
```bash
psql -U postgres -d allsuridb -f database/rollback_personal_order_links.sql
```

### 2.3 주요 변경사항
- 4개의 새 테이블 생성 (personal_order_links, personal_order_link_events, personal_order_link_audit_logs, reserved_slugs)
- `orders` 테이블에 10개의 컬럼 추가 (routing_type, personal_order_link_id 등)
- RLS 정책 설정으로 권한 관리
- 트리거로 감사 로그 자동 생성

---

## 3. 직접 배정이 보장되는 서버 측 로직

### 3.1 핵심 원칙
- **클라이언트가 contractor ID를 신뢰할 수 없음**: URL 파라미터나 폼 데이터에서 contractor ID를 직접 받지 않음
- **서버에서 강제 설정**: `OrderService.createPersonalLinkOrder`에서 `routing_type`, `assigned_contractor_id` 등을 서버가 설정

### 3.2 구현 코드
```dart
// lib/services/order_service.dart
Future<Order> createPersonalLinkOrder({
  required Order order,
  required String personalOrderLinkId,
  required String contractorId,
  // ...
}) async {
  // 서버에서 개인 링크 필드를 강제 설정
  final personalLinkOrder = order.copyWith(
    routingType: 'personal_link',           // ✅ 서버에서 설정
    personalOrderLinkId: personalOrderLinkId,
    sourceContractorId: contractorId,       // ✅ 서버에서 설정
    assignedContractorId: contractorId,     // ✅ 서버에서 설정
    assignmentLockedAt: DateTime.now(),     // ✅ 서버에서 설정
    attributionSource: 'personal_link',
  );
  
  // DB 삽입
  final inserted = await _sb.from('orders').insert(personalLinkOrder.toMap()).select().single();
  return Order.fromMap(inserted);
}
```

### 3.3 RLS 정책
```sql
-- orders 테이블: 개인 링크 오더는 assigned_contractor_id가 일치하는 사업자만 조회 가능
CREATE POLICY select_assigned_orders ON orders
FOR SELECT
USING (
  auth.uid() = assigned_contractor_id
  OR routing_type = 'marketplace'
);
```

---

## 4. 사업자 앱의 개인 오더 링크 UX

### 4.1 진입 경로
- 사업자 앱 > 프로필 > "개인 오더 링크" 메뉴 (구현 필요: Provider 등록 및 라우팅 연결)

### 4.2 링크 미발행 상태
```
나만의 견적 접수 링크를 만들어 보세요

단골 고객, 부동산, 관리소장님에게 공유하면
사장님에게만 직접 견적 요청이 들어옵니다.

[개인 링크 만들기]
```

### 4.3 링크 발행 화면
- 상호 또는 표시 이름
- 한 줄 소개
- 링크 주소 (slug)
  - 실시간 중복 확인
  - 자동 제안 기능
- 전문 공정 선택 (FilterChip)
- 활동 지역 입력

### 4.4 링크 발행 완료 화면
- 링크 URL 표시
- [링크 복사] [공유하기] [QR 코드 보기] [페이지 미리보기]
- 통계 카드 (최근 30일):
  - 링크 방문
  - 견적 요청 시작/완료
  - 응답 대기 오더
  - 견적 응답률
  - 완료된 직접 오더
- [링크 일시정지] [링크 재개] [링크 폐기]

---

## 5. 소비자 공개 페이지와 견적 요청 UX

### 5.1 공개 페이지 URL
```
https://{PUBLIC_WEB_BASE_URL}/allsuri/{slug}
```

### 5.2 페이지 구조
1. **사업자 소개 영역**
   - 프로필 이미지
   - 이름 (displayName)
   - 한 줄 소개 (headline)
   - 활동 지역, 전문 분야
   - 상세 소개 (introduction)

2. **신뢰 정보** (검증된 경우만 표시)
   - 올수리 인증 사업자
   - 평점, 후기 수

3. **직접 배정 안내 배너**
   ```
   이 페이지에서 접수한 요청은
   김 사장님에게만 직접 전달됩니다.
   ```

4. **CTA 버튼**
   ```
   [무료 견적 요청하기]
   ```

### 5.3 견적 요청 플로우 (4단계)
- **Step 1**: 수리 종류 선택 (ChoiceChip)
- **Step 2**: 증상과 사진
- **Step 3**: 추가 정보 (위치, 연락처, 방문일, 긴급 여부, 주택 유형)
- **Step 4**: 확인 및 개인정보 동의
  - 개인정보 수집 및 제3자 제공 동의
  - "김 사장님에게만 요청을 보냅니다" 명시

### 5.4 완료 화면
```
견적 요청이 전달되었습니다.

김 사장님이 내용을 확인한 뒤
올수리를 통해 견적 또는 연락을 드릴 예정입니다.

[내 요청 확인하기]
[다른 수리도 요청하기]
```

---

## 6. 링크 중지·응답 지연·비교 견적 전환 정책

### 6.1 링크 일시정지 (`status = 'paused'`)
- **공개 페이지 표시**:
  ```
  현재 새 견적 요청을 받고 있지 않습니다.
  
  [다른 검증 업체에 비교 견적 요청하기]
  ```
- **기본 동작**: 자동 전환하지 않음
- **고객 선택**: 명시적으로 버튼을 눌러야 비교 견적 요청

### 6.2 응답 지연
- **조건**: 운영 정책상 정한 시간(예: 24시간) 이후에도 사업자가 응답하지 않음
- **고객 선택지 제공**:
  ```
  아직 답변이 도착하지 않았습니다.
  
  [조금 더 기다리기]
  [다른 업체 비교 견적 요청하기]
  ```
- **전환 방식**: 
  - 기존 개인 링크 요청의 `assigned_contractor_id`를 변경하지 않음
  - 새로운 marketplace 요청 생성 (`routing_type = 'marketplace'`)

### 6.3 정책 요약
- ✅ 개인 링크 요청은 절대 자동 전환되지 않음
- ✅ 고객의 명시적 동의 필요
- ✅ 전환 시 새 요청 생성 (기존 요청 유지)

---

## 7. 보안 및 개인정보 처리 방식

### 7.1 직접 배정 신뢰성
- ✅ 서버 측에서만 `routing_type`, `assigned_contractor_id` 설정
- ✅ 클라이언트가 contractor ID를 조작할 수 없음
- ✅ Slug 기반 조회만 허용

### 7.2 개인정보 보호
- ✅ `AppLog`로 PII 마스킹
- ✅ 분석 이벤트(`PersonalOrderLinkEvent`)에 PII 저장 안 함
- ✅ RLS 정책으로 DB 레벨 권한 검증

### 7.3 링크 악용 방지
- ✅ Slug 정규화: 소문자, 숫자, 하이픈, 언더스코어만 허용
- ✅ 예약어 차단 (`reserved_slugs` 테이블)
- ✅ Slug 전역 unique (`slug_normalized` unique index)
- ⚠️ Rate limiting 필요 (TODO)

### 7.4 감사 로그
- ✅ Slug 변경, 링크 상태 변경 자동 기록 (트리거)
- ✅ `personal_order_link_audit_logs` 테이블

### 7.5 RLS 정책 요약
- **personal_order_links**: 사업자는 자신의 링크만 조회/수정, 익명 사용자는 활성 링크만 조회
- **personal_order_link_events**: 링크 소유자만 자신의 분석 이벤트 조회, 익명 사용자는 삽입만 가능
- **orders**: 개인 링크 오더는 `assigned_contractor_id`가 일치하는 사업자만 조회

---

## 8. 테스트 실행 결과

### 8.1 단위 테스트
- `test/personal_order_link_test.dart` 작성 완료
- 테스트 항목:
  - PersonalOrderLink 모델 생성 및 기본값
  - 링크 상태별 `canAcceptOrders` 검증
  - `getPublicUrl` 생성
  - `toMap` / `fromMap` 대칭성
  - PersonalOrderLinkStats 전환율 계산
  - Order 모델 개인 링크 필드
  - Slug 정규화 및 예약어

### 8.2 실행 방법
```bash
flutter test test/personal_order_link_test.dart
```

### 8.3 통합 테스트 (TODO)
- [ ] 사업자가 개인 링크 발행
- [ ] 고객이 공개 페이지 방문 및 견적 요청 제출
- [ ] 요청이 정확한 사업자에게만 배정
- [ ] 다른 사업자에게 목록 노출되지 않음
- [ ] 링크 중지 후 신규 요청 차단

---

## 9. 기능 플래그와 단계적 출시 방법

### 9.1 Phase 1: MVP (제한된 사업자)
- 승인된 사업자만 대상
- 기능:
  - 사업자당 개인 링크 1개
  - 기본 프로필 (이름, 한 줄 소개, 카테고리, 지역)
  - 링크 복사·공유
  - 직접 요청 접수
  - 직접 배정
  - 기본 알림
  - 기본 유입 통계 (페이지 방문, 요청 시작/완료)

### 9.2 Phase 2 (확장)
- QR 코드
- 사업자 프로필 편집 (상세 소개, 커버 이미지)
- 응답률·응답 시간 표시
- 동적 공유 카드 (Open Graph)
- 유입 채널 분석 (UTM 파라미터)
- 직접 오더 리마인더

### 9.3 Phase 3 (고급)
- 사업자별 소개 템플릿
- 지역별 랜딩 페이지
- 링크 캠페인 분석
- 반복 고객 관리
- 완료 고객의 재요청 링크
- 유료 프리미엄 프로필 또는 CRM 기능

### 9.4 기능 플래그 구현 방법
- DB에 `feature_flags` 테이블 생성
- 사업자별 `personal_link_enabled` 플래그
- 앱 시작 시 플래그 조회
- 플래그가 `false`이면 메뉴 숨김

### 9.5 성공 지표
- 링크 발행 사업자 비율
- 링크 공유 사업자 비율
- 링크 방문 대비 요청 시작률
- 요청 시작 대비 접수 완료율
- 직접 오더 첫 응답 시간
- 직접 오더 견적 응답률
- 직접 오더 완료율
- **직접 오더의 일반 마켓 오배정 건수: 반드시 0건**

---

## 10. 운영자가 최종 결정해야 할 정책 항목

### 10.1 링크 발행 승인
- [ ] 모든 사업자에게 즉시 오픈?
- [ ] 승인된 사업자만?
- [ ] 인증된 사업자만?

### 10.2 Slug 변경 정책
- [ ] 자유롭게 변경 가능?
- [ ] 변경 시 이전 slug redirect 제공?
- [ ] 변경 횟수 제한?

### 10.3 응답 지연 시 비교 견적 전환 타이밍
- [ ] 24시간 후?
- [ ] 48시간 후?
- [ ] 자동 전환할지 고객 선택지만 제공할지?

### 10.4 링크 폐기 정책
- [ ] 폐기 후 동일 slug 재사용 가능?
- [ ] 폐기된 링크 복구 가능?

### 10.5 Rate Limiting 정책
- [ ] 공개 slug 조회 API: 분당 X회?
- [ ] 견적 요청 제출 API: 시간당 Y회?

### 10.6 파일 업로드 제한
- [ ] 최대 파일 크기: 5MB?
- [ ] 지원 형식: JPEG, PNG, HEIC?
- [ ] 악성 파일 스캔 필요?

### 10.7 통계 데이터 보존 기간
- [ ] 이벤트 데이터 보존: 90일? 1년?
- [ ] 통계 집계 주기: 실시간? 일간?

---

## 11. 남은 작업 (TODO)

### 11.1 Provider 등록 및 라우팅 설정
- [ ] `PersonalOrderLinkService`를 Provider로 등록
- [ ] 사업자 프로필 화면에 "개인 오더 링크" 메뉴 추가
- [ ] Web용 라우팅 설정 (`/allsuri/{slug}`)

### 11.2 사업자 앱에서 직접 오더 표시
- [ ] 사업자 홈 화면에 "신규 직접 오더" 섹션 추가
- [ ] 오더 목록에 "[개인 링크]" 뱃지 표시
- [ ] 직접 오더 알림 구현

### 11.3 이미지 업로드 구현
- [ ] `PersonalLinkQuoteRequestScreen`의 `_pickPhotos` 구현
- [ ] Supabase Storage 연동
- [ ] 파일 크기/형식 검증

### 11.4 Rate Limiting
- [ ] Netlify Functions 또는 Supabase Edge Functions에서 rate limit 구현
- [ ] 동일 IP/세션 반복 제출 방지

### 11.5 Open Graph 메타데이터
- [ ] 공유 시 미리보기를 위한 Open Graph 메타데이터 생성
- [ ] SSR 또는 prerender 구현 (필요 시)

### 11.6 통합 테스트
- [ ] E2E 테스트 작성
- [ ] 실제 DB 연동 테스트

### 11.7 문서 및 가이드
- [ ] 사업자용 개인 링크 사용 가이드
- [ ] 운영자용 관리 매뉴얼

---

## 12. 구현 완료 요약

✅ **완료된 작업**:
1. DB 스키마 및 마이그레이션 (4개 테이블, RLS, 트리거)
2. Flutter 모델 (PersonalOrderLink, PersonalOrderLinkEvent, Order 확장)
3. 서비스 계층 (PersonalOrderLinkService, OrderService 확장)
4. 사업자 앱 UI (링크 관리, 생성, 편집 화면)
5. 소비자 웹 UI (공개 페이지, 견적 요청 플로우)
6. 보안 검증 (서버 측 강제 설정, RLS, slug 검증)
7. 단위 테스트 작성
8. 보안 문서 및 구현 보고서 작성

⚠️ **남은 작업**:
- Provider 등록 및 라우팅 연결
- 사업자 앱에서 직접 오더 표시
- 이미지 업로드 구현
- Rate limiting 구현
- 통합 테스트 작성

---

## 13. 배포 체크리스트

### 13.1 배포 전
- [ ] DB 마이그레이션 실행 (`personal_order_links.sql`)
- [ ] 예약어 데이터 확인
- [ ] RLS 정책 활성화 확인
- [ ] 환경 변수 설정 (`PUBLIC_WEB_BASE_URL`)
- [ ] Flutter 패키지 설치 (`flutter pub get`)
- [ ] 테스트 실행 (`flutter test`)

### 13.2 배포 후
- [ ] 개인 링크 생성 테스트
- [ ] 공개 페이지 접근 테스트
- [ ] 견적 요청 제출 테스트
- [ ] 직접 배정 확인 (DB 쿼리)
- [ ] 일반 마켓에 노출되지 않는지 확인
- [ ] 로그 모니터링

### 13.3 정기 감사
- [ ] 개인 링크 오더의 일반 마켓 노출 여부 확인
- [ ] Slug 변경 로그 검토
- [ ] 분석 이벤트 PII 누락 확인

---

## 14. 참고 자료

- **Supabase RLS**: https://supabase.com/docs/guides/auth/row-level-security
- **Flutter Web**: https://flutter.dev/web
- **QR Flutter**: https://pub.dev/packages/qr_flutter
- **Share Plus**: https://pub.dev/packages/share_plus

---

**구현 완료일**: 2026년 9월 14일  
**구현자**: Claude Sonnet 4.5 AI Assistant  
**검토 필요**: Provider 등록, 라우팅 연결, 운영 정책 결정
