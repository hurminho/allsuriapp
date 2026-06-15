-- ============================================================
-- business_verification_relax.sql 적용 결과 진단 / 점검
-- ============================================================
-- 1) public.users 가 안 보인다는 에러가 났다면 먼저 이 진단부터 실행.
-- 2) 사용자가 한 줄씩 따로 실행해도 됨 (앞 쿼리 실패가 뒤에 영향 주지 않음).
-- ============================================================

-- 진단 1: 접속 정보
SELECT current_database() AS db,
       current_user      AS role,
       current_schema()  AS current_schema;

-- 진단 2: search_path
SHOW search_path;

-- 진단 3: 'user' 가 이름에 들어간 모든 테이블/뷰
SELECT table_schema, table_name, table_type
FROM information_schema.tables
WHERE table_name ILIKE '%user%'
ORDER BY table_schema, table_name;

-- 진단 4: public.users 가 실제로 있는지 (pg_class 기준)
SELECT n.nspname AS schema, c.relname AS name, c.relkind AS kind
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relname = 'users'
ORDER BY n.nspname;

-- 진단 5: fn_business_can_act 가 잘 만들어졌는지
SELECT pg_get_functiondef(p.oid)
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'fn_business_can_act';

-- ============================================================
-- 진단 1~4에서 public.users 가 보이면 → 아래 점검 쿼리 실행
-- ============================================================
SELECT id, name, businessname,
       businessnumber_norm IS NOT NULL AS has_b_no,
       business_verify_bypass,
       business_verify_status,
       public.fn_business_can_act(id)  AS can_act
FROM public.users
WHERE role = 'business'
ORDER BY can_act DESC NULLS LAST, businessname NULLS LAST
LIMIT 30;

-- 326-24-01663 (진고 JINGO / 이경남) 특정 점검
SELECT id, name, businessname, businessnumber, businessnumber_norm,
       business_verify_status,
       business_verify_bypass,
       public.fn_business_can_act(id) AS can_act
FROM public.users
WHERE REPLACE(REPLACE(COALESCE(businessnumber, ''), '-', ''), ' ', '') = '3262401663';
