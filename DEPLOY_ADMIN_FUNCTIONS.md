# 관리자 기능 배포 가이드

관리자 페이지에서 "관리자 지정" 및 "사용자 삭제" 기능이 작동하도록 설정하는 방법입니다.

## 🔧 1단계: Supabase SQL 함수 실행

### 1.1 Supabase Dashboard 접속
1. [Supabase Dashboard](https://supabase.com/dashboard) 로그인
2. 프로젝트 선택
3. 왼쪽 메뉴에서 **SQL Editor** 클릭

### 1.2 SQL 함수 실행
`database/delete_business_user_function.sql` 파일의 전체 내용을 복사하여 SQL Editor에 붙여넣고 **Run** 버튼 클릭

### 1.3 함수 확인
다음 쿼리로 함수가 생성되었는지 확인:
```sql
SELECT routine_name 
FROM information_schema.routines 
WHERE routine_name IN ('delete_user_cascade', 'delete_business_user');
```

결과로 두 함수가 모두 표시되어야 합니다.

---

## 🚀 2단계: Netlify에 배포

### 2.1 변경사항 커밋 및 푸시
```bash
cd /Users/hurmin-ho/Documents/dev/allsuriapp
git add .
git commit -m "Add admin toggle and cascade delete functions"
git push origin main
```

### 2.2 Netlify 자동 배포 확인
1. [Netlify Dashboard](https://app.netlify.com/) 접속
2. 프로젝트 선택
3. **Deploys** 탭에서 배포 상태 확인
4. 배포 완료될 때까지 대기 (보통 1-2분)

### 2.3 배포 완료 확인
배포가 완료되면 다음 URL로 확인:
- Production: https://api.allsuri.app/admin.html
- Preview: (PR 번호에 따라 다름)

---

## ✅ 3단계: 기능 테스트

### 3.1 관리자 지정 기능
1. 관리자 페이지(https://api.allsuri.app/admin.html) 접속
2. "사용자 관리" 섹션으로 이동
3. 테스트 사용자의 "상세 보기" 클릭
4. 모달 하단의 **"관리자 지정"** 버튼 클릭
5. 확인 메시지가 표시되고 사용자가 관리자로 변경되어야 함
6. 목록에서 "관리자" 배지 확인

### 3.2 사용자 삭제 기능
1. 삭제할 테스트 사용자 선택
2. "상세 보기" → **"삭제"** 버튼 클릭
3. 확인 메시지에서 삭제될 데이터 확인
4. "확인" 클릭
5. 삭제 완료 후 통계가 표시되어야 함:
   ```
   사용자가 삭제되었습니다.
   
   삭제된 데이터:
   - 견적: X개
   - 입찰: X개
   - 오더: X개
   - 작업: X개
   - 채팅방: X개
   - 알림: X개
   ```

---

## 🔍 문제 해결

### 여전히 404 에러 발생
- **원인**: Netlify 배포가 완료되지 않음
- **해결**: 
  1. Netlify Dashboard에서 배포 상태 확인
  2. 배포 로그에서 에러 확인
  3. 필요 시 수동 재배포: `Trigger deploy` → `Deploy site`

### Supabase 함수 호출 실패
- **원인**: SQL 함수가 생성되지 않음
- **해결**:
  1. Supabase SQL Editor에서 함수 확인 쿼리 실행
  2. 함수가 없으면 SQL 파일 다시 실행
  3. GRANT 권한이 제대로 실행되었는지 확인

### "permission denied" 오류
- **원인**: 함수 실행 권한 부족
- **해결**: SQL 파일의 GRANT 문 다시 실행

---

## 📋 변경된 파일 목록

### Netlify Functions
- ✅ `netlify/functions/admin.ts`
  - 추가: `PATCH /users/:userId/admin` (관리자 권한 토글)
  - 수정: `DELETE /users/:id` (CASCADE 삭제 RPC 호출)

### Frontend
- ✅ `backend/public/admin.js`
  - 관리자 컬럼 표시
  - 관리자 권한 토글 함수
  - 삭제 통계 표시

### Database
- ✅ `database/delete_business_user_function.sql`
  - `delete_user_cascade()` 함수
  - `delete_business_user()` 별칭 함수

---

## ⚠️ 주의사항

1. **백업**: 중요한 데이터가 있는 경우 삭제 전 백업 권장
2. **테스트**: Production에서 바로 사용하지 말고 테스트 계정으로 먼저 테스트
3. **복구 불가**: CASCADE 삭제는 영구적이며 복구 불가능
4. **관리자 권한**: 관리자 지정은 developer 권한을 가진 사용자만 가능

---

## 📞 지원

문제가 계속되면:
1. 브라우저 콘솔 로그 확인
2. Netlify 배포 로그 확인
3. Supabase Logs 확인

