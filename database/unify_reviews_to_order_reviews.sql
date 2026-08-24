-- ============================================================
-- 후기/평점 단일화: order_reviews(B2B 평점)를 유일한 원천으로 통합
--
-- 배경
--   B2B 협업 후기는 order_reviews(listing_id 기준)에, 웹 고객·관리자 평점은
--   business_reviews(order_id 기준)에 따로 쌓여 왔다. 그래서 앱이 보여주는
--   사업자 평점과 웹 화면·입찰 문자에 나가는 평점이 서로 달랐다.
--
-- 방침
--   1) order_reviews 가 두 경로를 모두 담도록 확장 (listing_id 또는 order_id)
--   2) business_reviews 데이터를 order_reviews 로 이관
--   3) business_reviews 를 같은 이름의 호환 뷰로 대체
--      → 옛 컬럼명을 읽는 코드가 남아 있어도 통합된 값을 그대로 본다
--
-- 실행: Supabase SQL Editor에서 이 파일 전체를 실행하세요.
--       여러 번 실행해도 안전합니다(멱등).
--
-- 주의: business_reviews 의 실제 컬럼명이 저장소 DDL과 다를 수 있어
--       (웹 코드가 business_id/businessid/user_id/userid 를 순차 시도함)
--       이관은 information_schema 를 보고 동적으로 수행한다.
-- ============================================================

BEGIN;

-- ── 1) order_reviews 확장 ─────────────────────────────────────

ALTER TABLE public.order_reviews
  ADD COLUMN IF NOT EXISTS order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS is_admin_review BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS comment TEXT;

-- 웹 고객 평점은 marketplace_listings 행이 없고, 작성자도 익명이다.
ALTER TABLE public.order_reviews ALTER COLUMN listing_id DROP NOT NULL;
ALTER TABLE public.order_reviews ALTER COLUMN reviewer_id DROP NOT NULL;

-- 최소 하나의 대상(협업 일감 또는 웹 오더)에는 연결되어야 한다.
ALTER TABLE public.order_reviews DROP CONSTRAINT IF EXISTS order_reviews_subject_present;
ALTER TABLE public.order_reviews
  ADD CONSTRAINT order_reviews_subject_present
  CHECK (listing_id IS NOT NULL OR order_id IS NOT NULL);

-- 기존 UNIQUE(listing_id, reviewer_id) 는 NULL 행을 막지 못하고 웹 경로에
-- 맞지도 않으므로 경로별 부분 유니크 인덱스로 분리한다.
-- uq_order_reviews_order 는 "고객이 같은 오더를 두 번 평가" 중복도 막아준다.
-- 이름이 기본 규칙과 다를 수 있어 (listing_id, reviewer_id) 조합의 유니크
-- 제약을 이름으로 찾지 않고 컬럼 구성으로 찾아 제거한다.
DO $drop_uq$
DECLARE
  v_name text;
BEGIN
  FOR v_name IN
    SELECT c.conname
      FROM pg_constraint c
     WHERE c.conrelid = 'public.order_reviews'::regclass
       AND c.contype = 'u'
       AND (
         SELECT array_agg(a.attname::text ORDER BY a.attname)
           FROM unnest(c.conkey) k
           JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k
       ) = ARRAY['listing_id', 'reviewer_id']
  LOOP
    EXECUTE format('ALTER TABLE public.order_reviews DROP CONSTRAINT %I', v_name);
    RAISE NOTICE '[통합] 기존 유니크 제약 % 제거', v_name;
  END LOOP;
END
$drop_uq$;

-- 부분 인덱스(WHERE 절)로 만들면 ON CONFLICT (order_id) 가 중재 인덱스를
-- 추론하지 못해 upsert 가 실패한다. Postgres 기본값이 NULLS DISTINCT 이므로
-- 일반 유니크 인덱스로도 order_id 가 NULL 인 B2B 후기는 얼마든지 공존한다.
DROP INDEX IF EXISTS public.uq_order_reviews_order;
CREATE UNIQUE INDEX uq_order_reviews_order
  ON public.order_reviews (order_id);

DROP INDEX IF EXISTS public.uq_order_reviews_listing_reviewer;
CREATE UNIQUE INDEX uq_order_reviews_listing_reviewer
  ON public.order_reviews (listing_id, reviewer_id);

-- ── 2) business_reviews → order_reviews 이관 ──────────────────

DO $migrate$
DECLARE
  v_business_col  text;
  v_order_col     text;
  v_comment_col   text;
  v_reviewer_col  text;
  v_admin_col     text;
  v_created_col   text;

  v_business_expr text;
  v_order_expr    text;
  v_comment_expr  text;
  v_reviewer_expr text;
  v_admin_expr    text;
  v_created_expr  text;

  v_sql           text;
  v_moved         bigint;
BEGIN
  -- 이미 뷰로 교체된 상태(재실행)라면 이관할 것이 없다.
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
     WHERE table_schema = 'public'
       AND table_name = 'business_reviews'
       AND table_type = 'BASE TABLE'
  ) THEN
    RAISE NOTICE '[통합] business_reviews 기본 테이블이 없습니다 — 이관 건너뜀';
    RETURN;
  END IF;

  -- 사업자 ID 컬럼 (필수)
  SELECT column_name INTO v_business_col
    FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'business_reviews'
     AND column_name IN ('business_id', 'businessid', 'user_id', 'userid')
   ORDER BY array_position(
     ARRAY['business_id', 'businessid', 'user_id', 'userid'], column_name)
   LIMIT 1;

  IF v_business_col IS NULL THEN
    RAISE EXCEPTION '[통합] business_reviews 에서 사업자 ID 컬럼을 찾지 못했습니다';
  END IF;

  -- 오더 ID 컬럼 (필수) — 이 값이 없으면 중복 판정 기준이 없어 이관하지 않는다.
  SELECT column_name INTO v_order_col
    FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'business_reviews'
     AND column_name IN ('order_id', 'orderid')
   ORDER BY array_position(ARRAY['order_id', 'orderid'], column_name)
   LIMIT 1;

  IF v_order_col IS NULL THEN
    RAISE EXCEPTION '[통합] business_reviews 에서 오더 ID 컬럼을 찾지 못했습니다';
  END IF;

  -- 나머지는 있으면 쓰고 없으면 NULL/기본값으로 채운다.
  SELECT column_name INTO v_comment_col
    FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'business_reviews'
     AND column_name IN ('comment', 'content')
   ORDER BY array_position(ARRAY['comment', 'content'], column_name)
   LIMIT 1;

  SELECT column_name INTO v_reviewer_col
    FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'business_reviews'
     AND column_name IN ('reviewer_id', 'customer_id')
   ORDER BY array_position(ARRAY['reviewer_id', 'customer_id'], column_name)
   LIMIT 1;

  SELECT column_name INTO v_admin_col
    FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'business_reviews'
     AND column_name = 'is_admin_review';

  SELECT column_name INTO v_created_col
    FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'business_reviews'
     AND column_name IN ('created_at', 'createdat')
   ORDER BY array_position(ARRAY['created_at', 'createdat'], column_name)
   LIMIT 1;

  RAISE NOTICE '[통합] 감지된 컬럼: business=%, order=%, comment=%, reviewer=%, admin=%, created=%',
    v_business_col, v_order_col, v_comment_col, v_reviewer_col, v_admin_col, v_created_col;

  -- 없는 컬럼은 대체 리터럴로 채운다. 있는 컬럼은 반드시 별칭(b.)을 붙여
  -- 하위 쿼리와 이름이 겹쳐도 엉뚱한 테이블을 참조하지 않게 한다.
  v_business_expr := 'b.' || quote_ident(v_business_col);
  v_order_expr    := 'b.' || quote_ident(v_order_col);
  v_comment_expr  := CASE WHEN v_comment_col  IS NULL THEN 'NULL::text'
                          ELSE 'b.' || quote_ident(v_comment_col) END;
  v_reviewer_expr := CASE WHEN v_reviewer_col IS NULL THEN 'NULL::uuid'
                          ELSE 'b.' || quote_ident(v_reviewer_col) END;
  v_admin_expr    := CASE WHEN v_admin_col    IS NULL THEN 'FALSE'
                          ELSE 'COALESCE(b.' || quote_ident(v_admin_col) || ', FALSE)' END;
  v_created_expr  := CASE WHEN v_created_col  IS NULL THEN 'NOW()'
                          ELSE 'COALESCE(b.' || quote_ident(v_created_col) || ', NOW())' END;

  -- 오더 ID가 비어 있는 행은 어느 오더에 대한 평점인지 알 수 없어 제외한다.
  -- 남은 행은 legacy 테이블에 그대로 보존되므로 나중에 확인할 수 있다.
  v_sql := format($fmt$
    INSERT INTO public.order_reviews
      (listing_id, job_id, order_id, reviewer_id, reviewee_id,
       rating, tags, comment, is_admin_review, created_at, updated_at)
    SELECT
      NULL, NULL, %1$s, %2$s, %3$s,
      b.rating::int, '{}'::text[], %4$s, %5$s, %6$s, %6$s
    FROM public.business_reviews b
    WHERE %1$s IS NOT NULL
      AND %3$s IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.order_reviews r WHERE r.order_id = %1$s
      )
    ON CONFLICT DO NOTHING
  $fmt$,
    v_order_expr, v_reviewer_expr, v_business_expr,
    v_comment_expr, v_admin_expr, v_created_expr
  );

  EXECUTE v_sql;
  GET DIAGNOSTICS v_moved = ROW_COUNT;
  RAISE NOTICE '[통합] business_reviews → order_reviews 이관 %건', v_moved;
END
$migrate$;

-- ── 3) business_reviews 를 호환 뷰로 대체 ─────────────────────
-- 아직 옛 컬럼명으로 읽는 코드(웹 프로필, 목록, 입찰 문자 등)가 남아 있어도
-- 통합된 평점을 그대로 보게 한다. 원본 테이블은 legacy 로 보존한다.

DO $swap$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
     WHERE table_schema = 'public'
       AND table_name = 'business_reviews'
       AND table_type = 'BASE TABLE'
  ) THEN
    ALTER TABLE public.business_reviews RENAME TO business_reviews_legacy;
    RAISE NOTICE '[통합] business_reviews → business_reviews_legacy 로 보존';
  END IF;
END
$swap$;

CREATE OR REPLACE VIEW public.business_reviews
WITH (security_invoker = true) AS
SELECT
  r.id,
  r.reviewee_id                             AS business_id,
  r.order_id,
  r.listing_id,
  r.reviewer_id,
  r.rating,
  r.comment,
  r.comment                                 AS content,
  COALESCE(u.businessname, u.name)          AS reviewer_name,
  r.is_admin_review,
  r.created_at,
  r.updated_at
FROM public.order_reviews r
LEFT JOIN public.users u ON u.id = r.reviewer_id;

GRANT SELECT ON public.business_reviews TO anon, authenticated, service_role;

-- ── 4) 평점 집계 트리거 보완 ──────────────────────────────────
-- 기존 트리거는 INSERT/UPDATE 만 처리하고 NEW 만 참조해서, 삭제 시 통계가
-- 남아 있고 reviewee_id 가 바뀌면 이전 대상이 갱신되지 않았다.

CREATE OR REPLACE FUNCTION public.update_user_review_stats()
RETURNS TRIGGER AS $$
DECLARE
  v_targets uuid[] := '{}';
  v_target  uuid;
BEGIN
  -- INSERT 트리거에서 OLD 를, DELETE 트리거에서 NEW 를 건드리면
  -- "record is not assigned yet" 오류가 나므로 TG_OP 로 나눠서 모은다.
  IF TG_OP <> 'DELETE' AND NEW.reviewee_id IS NOT NULL THEN
    v_targets := array_append(v_targets, NEW.reviewee_id);
  END IF;
  IF TG_OP <> 'INSERT' AND OLD.reviewee_id IS NOT NULL
     AND NOT (OLD.reviewee_id = ANY (v_targets)) THEN
    v_targets := array_append(v_targets, OLD.reviewee_id);
  END IF;

  FOREACH v_target IN ARRAY v_targets LOOP
    UPDATE public.users u
       SET review_count = s.cnt,
           review_average = s.avg_rating,
           review_tags = s.tags
      FROM (
        SELECT
          COUNT(*)::int AS cnt,
          COALESCE(ROUND(AVG(rating)::numeric, 2), 0.00) AS avg_rating,
          COALESCE((
            SELECT jsonb_object_agg(tag, c)
              FROM (
                SELECT unnest(tags) AS tag, COUNT(*) AS c
                  FROM public.order_reviews
                 WHERE reviewee_id = v_target
                 GROUP BY 1
              ) t
          ), '{}'::jsonb) AS tags
        FROM public.order_reviews
       WHERE reviewee_id = v_target
      ) s
     WHERE u.id = v_target;
  END LOOP;

  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_update_review_stats ON public.order_reviews;
CREATE TRIGGER trigger_update_review_stats
AFTER INSERT OR UPDATE OR DELETE ON public.order_reviews
FOR EACH ROW EXECUTE FUNCTION public.update_user_review_stats();

-- 이관된 웹 평점이 users.review_* 에 반영되도록 전체 재계산.
-- 후기가 하나도 없는 사업자도 0 으로 정리되도록 users 전체를 기준으로 돈다.
-- review_tags 는 B2C 후기가 tags 를 채우지 않아 기존 값이 그대로 유효하다.
UPDATE public.users u
   SET review_count = s.cnt,
       review_average = s.avg_rating
  FROM (
    SELECT u2.id,
           COUNT(r.id)::int AS cnt,
           COALESCE(ROUND(AVG(r.rating)::numeric, 2), 0.00) AS avg_rating
      FROM public.users u2
      LEFT JOIN public.order_reviews r ON r.reviewee_id = u2.id
     GROUP BY u2.id
  ) s
 WHERE u.id = s.id
   AND (u.review_count IS DISTINCT FROM s.cnt
        OR u.review_average IS DISTINCT FROM s.avg_rating);

COMMIT;

-- PostgREST(Netlify 함수·앱이 쓰는 REST 계층)가 새 컬럼과 뷰를 인식하도록
-- 스키마 캐시를 갱신한다.
NOTIFY pgrst, 'reload schema';

-- ── 확인용 쿼리 ───────────────────────────────────────────────
-- 통합 결과: 경로별 건수
--   SELECT
--     CASE WHEN listing_id IS NOT NULL THEN 'B2B(협업)' ELSE 'B2C(웹오더)' END AS 경로,
--     COUNT(*) AS 건수, ROUND(AVG(rating)::numeric, 2) AS 평균
--   FROM public.order_reviews GROUP BY 1;
--
-- 원본과 이관분 건수 비교 (legacy 의 오더 ID 컬럼명은 실행 로그의
-- '[통합] 감지된 컬럼' NOTICE 에 찍힌 이름을 사용하세요)
--   SELECT
--     (SELECT COUNT(*) FROM public.business_reviews_legacy) AS 원본,
--     (SELECT COUNT(*) FROM public.order_reviews WHERE order_id IS NOT NULL) AS 이관분;
--
-- 호환 뷰가 정상 동작하는지
--   SELECT business_id, rating, comment, reviewer_name FROM public.business_reviews LIMIT 5;

-- ── 롤백 ──────────────────────────────────────────────────────
--   DROP VIEW IF EXISTS public.business_reviews;
--   ALTER TABLE public.business_reviews_legacy RENAME TO business_reviews;
--   DELETE FROM public.order_reviews WHERE order_id IS NOT NULL AND listing_id IS NULL;
--   NOTIFY pgrst, 'reload schema';
--   (코드도 함께 되돌려야 합니다 — 아래 '코드 배포 순서' 참고)
--
-- ── 코드 배포 순서 (중요) ─────────────────────────────────────
--   이 SQL을 먼저 실행한 뒤에 앱/함수를 배포하세요.
--   평점 저장 코드가 order_reviews.order_id 에 upsert 하도록 바뀌었으므로,
--   SQL 적용 전에 배포하면 그 사이 들어온 평점이 저장되지 않습니다.
