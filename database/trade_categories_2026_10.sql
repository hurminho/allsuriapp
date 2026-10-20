-- =============================================================================
-- 올수리 공종 목록 개편 (2026-10-20): 대분류 12개 + 세부 공종
--
-- 실행: Supabase Dashboard → SQL Editor 에 전체를 붙여 넣고 실행. 여러 번 실행해도 됩니다.
-- 목록은 앱 lib/config/trade_categories.dart · 웹 lib/trade-categories.ts 와 같습니다.
--
-- 하는 일
--   0) 바꾸기 전 값을 ops.trade_category_backup_20261020 에 백업 (처음 실행 때만)
--   1) jobs·marketplace_listings 에 세부 공종 칸(subcategory) 추가
--   2) 예전 분류를 새 대분류로 옮김
--      · 오더(jobs·marketplace_listings·orders).category → 대분류
--        이름이 바뀌는 경우 예전 값은 subcategory 에 남깁니다(비어 있을 때만). 예: 인테리어 → 기타 + 세부 '인테리어'
--      · 사업자 전문분야(users.specialties) → 대분류 (중복 제거)
--      · 개인 링크 공종(personal_order_links.supported_categories) → 대분류
--   새 목록의 이름(대분류·세부 공종)은 건드리지 않습니다.
-- =============================================================================

BEGIN;

-- 값(대분류·세부 공종·예전 값) → 대분류. 모르는 값은 '기타'. (앱·웹의 groupOf 와 같은 표)
CREATE OR REPLACE FUNCTION public.allsuri_trade_group(p text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT coalesce((SELECT t.grp FROM (VALUES
    ('하수구·막힘', '하수구·막힘'),
    ('하수구·배수구 막힘', '하수구·막힘'),
    ('변기 막힘', '하수구·막힘'),
    ('싱크대 막힘', '하수구·막힘'),
    ('세면대·욕조 막힘', '하수구·막힘'),
    ('고압세척(배관 청소)', '하수구·막힘'),
    ('배관 내시경 점검', '하수구·막힘'),
    ('오수·배수 펌프', '하수구·막힘'),
    ('누수·방수', '누수·방수'),
    ('누수 탐지', '누수·방수'),
    ('누수 보수', '누수·방수'),
    ('욕실 방수', '누수·방수'),
    ('옥상·외벽 방수', '누수·방수'),
    ('베란다·발코니 방수', '누수·방수'),
    ('실리콘·코킹', '누수·방수'),
    ('지하·승강기 피트 물빼기', '누수·방수'),
    ('수도·급수', '수도·급수'),
    ('수전·샤워기 교체', '수도·급수'),
    ('세면대·양변기 설치·교체', '수도·급수'),
    ('수도 배관 수리·교체', '수도·급수'),
    ('동파·계량기', '수도·급수'),
    ('급수펌프·물탱크', '수도·급수'),
    ('정수기·연수기 설치', '수도·급수'),
    ('보일러·난방', '보일러·난방'),
    ('보일러 수리', '보일러·난방'),
    ('보일러 교체', '보일러·난방'),
    ('난방 배관 청소', '보일러·난방'),
    ('분배기 교체', '보일러·난방'),
    ('온수기 설치·수리', '보일러·난방'),
    ('바닥 난방', '보일러·난방'),
    ('에어컨·공조', '에어컨·공조'),
    ('에어컨 설치·이전', '에어컨·공조'),
    ('에어컨 수리·가스 충전', '에어컨·공조'),
    ('시스템 에어컨', '에어컨·공조'),
    ('환기·전열교환기', '에어컨·공조'),
    ('덕트·배기', '에어컨·공조'),
    ('전기', '전기'),
    ('콘센트·스위치', '전기'),
    ('조명 교체·설치', '전기'),
    ('차단기·누전', '전기'),
    ('배선·증설', '전기'),
    ('인터폰·도어락', '전기'),
    ('주방·욕실 설비', '주방·욕실 설비'),
    ('싱크대 교체', '주방·욕실 설비'),
    ('주방 후드', '주방·욕실 설비'),
    ('욕실 부분 공사', '주방·욕실 설비'),
    ('타일·줄눈 보수', '주방·욕실 설비'),
    ('입주·이사 청소', '입주·이사 청소'),
    ('입주 청소', '입주·이사 청소'),
    ('이사 청소', '입주·이사 청소'),
    ('거주 중 청소', '입주·이사 청소'),
    ('준공·공사 후 청소', '입주·이사 청소'),
    ('상가·건물 청소', '상가·건물 청소'),
    ('사무실·상가 청소', '상가·건물 청소'),
    ('계단·건물 정기 청소', '상가·건물 청소'),
    ('유리창·외벽 청소', '상가·건물 청소'),
    ('바닥 왁스·광택', '상가·건물 청소'),
    ('가전·설비 청소', '가전·설비 청소'),
    ('에어컨 분해 세척', '가전·설비 청소'),
    ('세탁기 분해 세척', '가전·설비 청소'),
    ('주방 후드 청소', '가전·설비 청소'),
    ('보일러·난방 배관 청소', '가전·설비 청소'),
    ('위생·특수 청소', '위생·특수 청소'),
    ('욕실 곰팡이 제거', '위생·특수 청소'),
    ('줄눈 시공', '위생·특수 청소'),
    ('소독·방역·해충', '위생·특수 청소'),
    ('저수조·정화조 청소', '위생·특수 청소'),
    ('매트리스·소파 클리닝', '위생·특수 청소'),
    ('특수 청소', '위생·특수 청소'),
    ('기타', '기타'),
    ('수도', '수도·급수'),
    ('배관', '수도·급수'),
    ('급수장치', '수도·급수'),
    ('정수기', '수도·급수'),
    ('난방', '보일러·난방'),
    ('온수기', '보일러·난방'),
    ('보일러', '보일러·난방'),
    ('히터', '보일러·난방'),
    ('전기히터', '보일러·난방'),
    ('온풍기', '보일러·난방'),
    ('전기장판', '보일러·난방'),
    ('전기담요', '보일러·난방'),
    ('에어컨', '에어컨·공조'),
    ('냉난방기', '에어컨·공조'),
    ('공조기', '에어컨·공조'),
    ('환기장치', '에어컨·공조'),
    ('누수', '누수·방수'),
    ('방수', '누수·방수'),
    ('화장실', '주방·욕실 설비'),
    ('주방', '주방·욕실 설비'),
    ('가스레인지', '주방·욕실 설비'),
    ('식기세척기', '주방·욕실 설비'),
    ('배수장치', '하수구·막힘'),
    ('도어락', '전기'),
    ('인터폰', '전기'),
    ('CCTV', '전기'),
    ('보안설비', '전기'),
    ('자동문', '전기'),
    ('일반', '기타'),
    ('인테리어', '기타'),
    ('리모델링', '기타'),
    ('청소', '기타')
  ) AS t(val, grp) WHERE t.val = btrim(coalesce(p, '')) LIMIT 1), '기타')
$$;

-- 새 목록의 세부 공종인지 (전문분야에 세부 공종이 들어 있으면 그대로 둡니다)
CREATE OR REPLACE FUNCTION public.allsuri_is_trade_item(p text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT btrim(coalesce(p, '')) = ANY (ARRAY['하수구·배수구 막힘', '변기 막힘', '싱크대 막힘', '세면대·욕조 막힘', '고압세척(배관 청소)', '배관 내시경 점검', '오수·배수 펌프', '누수 탐지', '누수 보수', '욕실 방수', '옥상·외벽 방수', '베란다·발코니 방수', '실리콘·코킹', '지하·승강기 피트 물빼기', '수전·샤워기 교체', '세면대·양변기 설치·교체', '수도 배관 수리·교체', '동파·계량기', '급수펌프·물탱크', '정수기·연수기 설치', '보일러 수리', '보일러 교체', '난방 배관 청소', '분배기 교체', '온수기 설치·수리', '바닥 난방', '에어컨 설치·이전', '에어컨 수리·가스 충전', '시스템 에어컨', '환기·전열교환기', '덕트·배기', '콘센트·스위치', '조명 교체·설치', '차단기·누전', '배선·증설', '인터폰·도어락', '싱크대 교체', '주방 후드', '욕실 부분 공사', '타일·줄눈 보수', '입주 청소', '이사 청소', '거주 중 청소', '준공·공사 후 청소', '사무실·상가 청소', '계단·건물 정기 청소', '유리창·외벽 청소', '바닥 왁스·광택', '에어컨 분해 세척', '세탁기 분해 세척', '주방 후드 청소', '보일러·난방 배관 청소', '욕실 곰팡이 제거', '줄눈 시공', '소독·방역·해충', '저수조·정화조 청소', '매트리스·소파 클리닝', '특수 청소'])
$$;


-- 0) 백업 ----------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS ops;
REVOKE ALL ON SCHEMA ops FROM PUBLIC;
REVOKE ALL ON SCHEMA ops FROM anon, authenticated;

DO $$
BEGIN
  IF to_regclass('ops.trade_category_backup_20261020') IS NULL THEN
    CREATE TABLE ops.trade_category_backup_20261020 AS
      SELECT 'jobs'::text AS tbl, id::text AS row_id, category AS old_value, NULL::text[] AS old_array FROM public.jobs
      UNION ALL SELECT 'marketplace_listings', id::text, category, NULL FROM public.marketplace_listings
      UNION ALL SELECT 'orders', id::text, category, NULL FROM public.orders
      UNION ALL SELECT 'users.specialties', id::text, NULL, specialties FROM public.users WHERE cardinality(specialties) > 0
      UNION ALL SELECT 'personal_order_links', id::text, NULL, supported_categories FROM public.personal_order_links
                WHERE cardinality(supported_categories) > 0;
  END IF;
END $$;


-- 1) 세부 공종 칸 ----------------------------------------------------------------
ALTER TABLE public.jobs ADD COLUMN IF NOT EXISTS subcategory text;
ALTER TABLE public.marketplace_listings ADD COLUMN IF NOT EXISTS subcategory text;


-- 2) 예전 값 옮기기 ----------------------------------------------------------------
UPDATE public.jobs
SET subcategory = CASE WHEN subcategory IS NULL AND category IS NOT NULL
                            AND public.allsuri_trade_group(category) <> btrim(category)
                       THEN btrim(category) ELSE subcategory END,
    category = public.allsuri_trade_group(category)
WHERE category IS DISTINCT FROM public.allsuri_trade_group(category);

UPDATE public.marketplace_listings
SET subcategory = CASE WHEN subcategory IS NULL AND category IS NOT NULL
                            AND public.allsuri_trade_group(category) <> btrim(category)
                       THEN btrim(category) ELSE subcategory END,
    category = public.allsuri_trade_group(category)
WHERE category IS DISTINCT FROM public.allsuri_trade_group(category);

UPDATE public.orders
SET subcategory = CASE WHEN subcategory IS NULL AND category IS NOT NULL
                            AND public.allsuri_trade_group(category) <> btrim(category)
                       THEN btrim(category) ELSE subcategory END,
    category = public.allsuri_trade_group(category)
WHERE category IS DISTINCT FROM public.allsuri_trade_group(category);

-- 전문분야: 세부 공종은 그대로, 나머지는 대분류로 (중복 제거, 순서 유지)
UPDATE public.users u
SET specialties = sub.next
FROM (
  SELECT id, array_agg(v ORDER BY first_pos) AS next
  FROM (
    SELECT id, v, min(pos) AS first_pos
    FROM (
      SELECT u2.id, x.pos,
             CASE WHEN public.allsuri_is_trade_item(x.val) THEN btrim(x.val)
                  ELSE public.allsuri_trade_group(x.val) END AS v
      FROM public.users u2, unnest(u2.specialties) WITH ORDINALITY AS x(val, pos)
      WHERE cardinality(u2.specialties) > 0
    ) mapped
    GROUP BY id, v
  ) dedup
  GROUP BY id
) sub
WHERE u.id = sub.id AND u.specialties IS DISTINCT FROM sub.next;

-- 개인 링크 공종: 대분류로 (중복 제거, 순서 유지)
UPDATE public.personal_order_links l
SET supported_categories = sub.next
FROM (
  SELECT id, array_agg(v ORDER BY first_pos) AS next
  FROM (
    SELECT l2.id, public.allsuri_trade_group(x.val) AS v, min(x.pos) AS first_pos
    FROM public.personal_order_links l2, unnest(l2.supported_categories) WITH ORDINALITY AS x(val, pos)
    WHERE cardinality(l2.supported_categories) > 0
    GROUP BY l2.id, public.allsuri_trade_group(x.val)
  ) dedup
  GROUP BY id
) sub
WHERE l.id = sub.id AND l.supported_categories IS DISTINCT FROM sub.next;

COMMIT;

-- 확인 (선택): 아래 결과에 예전 이름(수도·일반·배수장치 등)이 없으면 정상입니다.
-- SELECT category, count(*) FROM public.marketplace_listings GROUP BY 1 ORDER BY 2 DESC;
-- SELECT v, count(*) FROM public.users, unnest(specialties) v WHERE role = 'business' GROUP BY 1 ORDER BY 2 DESC;
--
-- 되돌리기 (필요할 때만): 백업에서 예전 값을 다시 넣습니다.
-- UPDATE public.jobs t SET category = b.old_value FROM ops.trade_category_backup_20261020 b WHERE b.tbl = 'jobs' AND b.row_id = t.id::text;
-- UPDATE public.marketplace_listings t SET category = b.old_value FROM ops.trade_category_backup_20261020 b WHERE b.tbl = 'marketplace_listings' AND b.row_id = t.id::text;
-- UPDATE public.orders t SET category = b.old_value FROM ops.trade_category_backup_20261020 b WHERE b.tbl = 'orders' AND b.row_id = t.id::text;
-- UPDATE public.users t SET specialties = b.old_array FROM ops.trade_category_backup_20261020 b WHERE b.tbl = 'users.specialties' AND b.row_id = t.id::text;
-- UPDATE public.personal_order_links t SET supported_categories = b.old_array FROM ops.trade_category_backup_20261020 b WHERE b.tbl = 'personal_order_links' AND b.row_id = t.id::text;
