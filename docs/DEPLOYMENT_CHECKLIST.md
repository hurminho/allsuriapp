# 오더 입찰 시스템 배포 체크리스트

## 📋 **배포 전 준비사항**

### 1. Supabase SQL 실행 (순서대로)

#### ✅ **Step 1: 입찰 시스템 테이블 및 RPC**
```bash
# Supabase SQL Editor에서 실행
database/order_bids_system.sql
```

**생성되는 것:**
- `order_bids` 테이블
- `create_order_bid()` RPC
- `select_bidder()` RPC
- `withdraw_bid()` RPC
- Triggers 및 RLS 정책

#### ✅ **Step 2: claim_listing RPC 수정**
```bash
# Supabase SQL Editor에서 실행
database/fix_claim_listing_for_created_status.sql
```

**변경사항:**
- `created` 상태도 claim 가능
- `status = 'assigned'` 사용 (not 'in_progress')

#### ✅ **Step 3: FCM 토큰 컬럼 추가**
```bash
# Supabase SQL Editor에서 실행
database/add_fcm_token_to_users.sql
```

### 2. 푸시 알림 경로

Supabase Edge Function은 쓰지 않습니다. 푸시는 `notifications` INSERT → Database Webhook →
Netlify `send-push-webhook`(FCM v1) 한 경로로 나갑니다(`database/setup_push_webhook.sql`).
Webhook 헤더의 `Authorization: Bearer <PUSH_WEBHOOK_SECRET>` 값은 Netlify 환경변수 `PUSH_WEBHOOK_SECRET`과 같아야 합니다.

### 3. Netlify 환경 변수 설정

**Netlify Dashboard → Site settings → Environment variables:**

| Key | Value | 설명 |
|-----|-------|------|
| `SUPABASE_JWT_SECRET` | Supabase JWT Secret | Supabase Dashboard → Settings → API |
| `SUPABASE_URL` | https://xxx.supabase.co | Supabase 프로젝트 URL |
| `SUPABASE_SERVICE_ROLE_KEY` | eyJxxx... | Service Role Key |
| `JWT_SECRET` | your-secret-key | 백엔드 JWT 시크릿 |

### 4. Git Push

```bash
git add -A
git commit -m "feat: Complete competitive bidding system with push notifications

- Implement OrderBiddersScreen for viewing bidders
- Add FCM token management and push notifications
- Update notification routing based on type
- Add bid count badges on order cards
- Integrate Supabase Edge Function for FCM"

git push origin main
```

### 5. Netlify 자동 배포 대기 (2-3분)

---

## 🧪 **테스트 시나리오**

### **시나리오 1: 입찰 생성**

1. **사업자 B 로그인**
2. **오더 마켓 진입**
3. **사업자 A의 오더 클릭 → "오더 잡기" 버튼 클릭**
4. **확인사항:**
   - ✅ "입찰이 완료되었습니다! 승인을 기다리고 있어요~" 메시지
   - ✅ 사업자 A의 알림 목록에 "새로운 입찰" 알림
   - ✅ 사업자 A의 기기에 푸시 알림
   - ✅ `order_bids` 테이블에 레코드 생성

### **시나리오 2: 입찰자 목록 보기**

1. **사업자 A 로그인**
2. **알림 목록에서 "새로운 입찰" 클릭**
3. **확인사항:**
   - ✅ 입찰자 목록 화면 표시
   - ✅ 사업자 B의 프로필, 평점, 메시지 표시
   - ✅ "이 사업자 선택하기" 버튼 표시

### **시나리오 3: 사업자 선택**

1. **사업자 A가 사업자 B 선택**
2. **확인사항:**
   - ✅ 사업자 B의 알림 목록에 "오더 선택됨" 알림
   - ✅ 사업자 B의 기기에 푸시 알림
   - ✅ 다른 입찰자들에게 "이관되었습니다" 알림
   - ✅ 채팅방 자동 생성
   - ✅ `marketplace_listings.status = 'assigned'`
   - ✅ `jobs.assigned_business_id` 업데이트

### **시나리오 4: Realtime 업데이트**

1. **기기 A: 오더 목록 보기 (사업자 C)**
2. **기기 B: 입찰 (사업자 B)**
3. **확인사항:**
   - ✅ 기기 A: 오더 카드에 "입찰 1" 배지 표시 (실시간)
4. **기기 C: 입찰자 선택 (사업자 A)**
5. **확인사항:**
   - ✅ 기기 A, B: 오더가 리스트에서 사라짐 (실시간)

---

## 🐛 **트러블슈팅**

### **FCM 토큰이 저장되지 않음**

**확인:**
```sql
SELECT id, businessname, fcm_token FROM users WHERE fcm_token IS NOT NULL;
```

**해결:**
- Firebase 프로젝트 설정 확인
- `google-services.json` (Android) / `GoogleService-Info.plist` (iOS) 파일 확인
- 앱 재설치

### **푸시 알림이 오지 않음**

**확인:**
1. Supabase Edge Function 로그 확인
2. FCM Server Key 확인
3. 기기 알림 권한 확인

**해결:**
```dart
// 권한 재요청
await NotificationService().initializeFCM(userId);
```

### **입찰자 목록이 비어있음**

**확인:**
```sql
SELECT * FROM order_bids WHERE listing_id = 'xxx';
```

**해결:**
- RPC 함수 실행 확인
- RLS 정책 확인

### **Netlify Function 404 에러**

**확인:**
- Netlify Dashboard → Functions → market 함수 존재 확인
- 배포 로그 확인

**해결:**
- `netlify.toml` 확인
- Git push 후 재배포

---

## 📊 **데이터베이스 모니터링**

### **입찰 현황 조회**
```sql
SELECT 
  ml.title,
  ml.bid_count,
  COUNT(ob.id) as actual_bids,
  ml.status
FROM marketplace_listings ml
LEFT JOIN order_bids ob ON ml.id = ob.listing_id
WHERE ml.status IN ('open', 'created')
GROUP BY ml.id, ml.title, ml.bid_count, ml.status
ORDER BY ml.createdat DESC;
```

### **알림 전송 현황**
```sql
SELECT 
  type,
  COUNT(*) as count,
  COUNT(CASE WHEN isread = true THEN 1 END) as read_count
FROM notifications
WHERE createdat > NOW() - INTERVAL '7 days'
GROUP BY type;
```

### **FCM 토큰 현황**
```sql
SELECT 
  role,
  COUNT(*) as total_users,
  COUNT(fcm_token) as users_with_fcm
FROM users
GROUP BY role;
```

---

## 🎯 **성공 지표**

- ✅ **입찰 생성 성공률**: > 95%
- ✅ **알림 전송 성공률**: > 90%
- ✅ **푸시 알림 수신률**: > 85%
- ✅ **Realtime 업데이트 지연**: < 2초
- ✅ **사업자 선택 성공률**: > 98%

---

## 📝 **다음 개선 사항**

1. **입찰 메시지 커스터마이징**
   - 사업자가 입찰 시 자유롭게 메시지 작성

2. **입찰 취소 기능**
   - 사업자가 자신의 입찰 취소 가능

3. **입찰 기한 설정**
   - 오더 소유자가 입찰 마감 시간 설정

4. **자동 선택 기능**
   - 평점/완료 건수 기반 자동 추천

5. **입찰 통계**
   - 사업자별 입찰 성공률, 평균 응답 시간 등

