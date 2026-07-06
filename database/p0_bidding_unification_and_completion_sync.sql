-- ============================================================
-- P0: 웹 오더 입찰 데이터 단일화(order_bids) + 완료 상태 동기화 스키마 보강
-- Supabase SQL Editor에서 실행하세요.
-- ============================================================

-- 1. orders: 낙찰된 입찰(order_bids.id) 참조 컬럼 추가
--    기존 awardedEstimateId는 레거시로 유지하되, 이제부터는 order_bids를 단일 소스로 사용
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS awarded_bid_id UUID REFERENCES public.order_bids(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.orders.awarded_bid_id IS '낙찰된 입찰 (order_bids.id). estimates 대신 order_bids를 단일 소스로 사용';

-- 2. orders.status CHECK 제약: 'bidding' / 'awaiting_confirmation' 상태 허용
--    (기존 제약이 있으면 완화하여 재생성, 없으면 새로 추가)
DO $$
DECLARE
  v_conname text;
BEGIN
  SELECT c.conname INTO v_conname
  FROM pg_constraint c
  WHERE c.conrelid = 'public.orders'::regclass
    AND c.contype = 'c'
    AND pg_get_constraintdef(c.oid) ILIKE '%status%'
  LIMIT 1;

  IF v_conname IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.orders DROP CONSTRAINT %I', v_conname);
    RAISE NOTICE '기존 orders status 제약조건 % 제거됨', v_conname;
  END IF;
END $$;

-- 기존 데이터를 깨지 않도록 NOT VALID로 추가 (신규/변경되는 행부터 적용)
ALTER TABLE public.orders
  ADD CONSTRAINT orders_status_check
  CHECK (status IN ('pending', 'bidding', 'in_progress', 'awaiting_confirmation', 'completed', 'cancelled'))
  NOT VALID;

-- 3. order_bids: 웹 오더 입찰 목록 조회 성능을 위한 인덱스
CREATE INDEX IF NOT EXISTS idx_order_bids_listing_status ON public.order_bids(listing_id, status);

-- 4. business_reviews: 사업자별 평점 집계 성능을 위한 인덱스
CREATE INDEX IF NOT EXISTS idx_business_reviews_business_id ON public.business_reviews(business_id);

-- 5. marketplace_listings: web_order_id로 역참조 조회 성능을 위한 인덱스
--    (컬럼이 없다면 아래 라인은 오류 없이 무시되도록 존재 여부 체크)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'marketplace_listings' AND column_name = 'web_order_id'
  ) THEN
    CREATE INDEX IF NOT EXISTS idx_marketplace_listings_web_order_id ON public.marketplace_listings(web_order_id);
  END IF;
END $$;

SELECT '✅ P0 입찰 단일화 + 완료 동기화 스키마 보강 완료' AS result;
