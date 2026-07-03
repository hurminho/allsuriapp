-- ============================================================
-- 입찰자 선택 시 jobs.assigned_business_id 동기화 보완
-- order_bids.job_id 가 NULL 이어도 listing.jobid 로 jobs 업데이트
-- Supabase SQL Editor에서 실행하세요.
-- ============================================================

CREATE OR REPLACE FUNCTION public.handle_bidder_selection()
RETURNS TRIGGER AS $$
DECLARE
  v_listing_job_id UUID;
BEGIN
  IF NEW.status = 'selected' AND OLD.status IS DISTINCT FROM 'selected' THEN
    UPDATE public.marketplace_listings
    SET selected_bidder_id = NEW.bidder_id,
        status = 'assigned',
        claimed_by = NEW.bidder_id,
        claimed_at = NOW(),
        updatedat = NOW()
    WHERE id = NEW.listing_id;

    UPDATE public.order_bids
    SET status = 'rejected',
        updated_at = NOW()
    WHERE listing_id = NEW.listing_id
      AND id != NEW.id
      AND status = 'pending';

    -- jobs: order_bids.job_id 또는 listing.jobid 로 동기화
    IF NEW.job_id IS NOT NULL THEN
      UPDATE public.jobs
      SET assigned_business_id = NEW.bidder_id,
          status = 'in_progress',
          updated_at = NOW()
      WHERE id = NEW.job_id;
    ELSE
      SELECT jobid INTO v_listing_job_id
      FROM public.marketplace_listings
      WHERE id = NEW.listing_id;

      IF v_listing_job_id IS NOT NULL THEN
        UPDATE public.jobs
        SET assigned_business_id = NEW.bidder_id,
            status = 'in_progress',
            updated_at = NOW()
        WHERE id = v_listing_job_id;
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_handle_bidder_selection ON public.order_bids;

CREATE TRIGGER trigger_handle_bidder_selection
  AFTER UPDATE ON public.order_bids
  FOR EACH ROW
  WHEN (NEW.status = 'selected')
  EXECUTE FUNCTION public.handle_bidder_selection();

-- 기존 데이터 백필: listing은 assigned인데 jobs.assigned_business_id 가 비어 있는 경우
UPDATE public.jobs j
SET assigned_business_id = ml.selected_bidder_id,
    status = CASE
      WHEN j.status IN ('created', 'open', 'assigned') THEN 'in_progress'
      ELSE j.status
    END,
    updated_at = NOW()
FROM public.marketplace_listings ml
WHERE ml.jobid = j.id
  AND ml.selected_bidder_id IS NOT NULL
  AND ml.status IN ('assigned', 'in_progress', 'awaiting_confirmation', 'completed')
  AND (j.assigned_business_id IS NULL OR j.assigned_business_id <> ml.selected_bidder_id);

SELECT '✅ 입찰자 선택 → jobs 동기화 트리거 업데이트 및 기존 데이터 백필 완료' AS result;
