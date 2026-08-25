-- 공사 취소 사유. 앱은 컬럼이 없으면 status 만 갱신하므로 없어도 동작한다.
ALTER TABLE public.jobs
  ADD COLUMN IF NOT EXISTS cancel_reason TEXT,
  ADD COLUMN IF NOT EXISTS cancel_category TEXT;

ALTER TABLE public.marketplace_listings
  ADD COLUMN IF NOT EXISTS cancel_reason TEXT,
  ADD COLUMN IF NOT EXISTS cancel_category TEXT;
