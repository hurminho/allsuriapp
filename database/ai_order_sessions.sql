-- 공사 취소 사유 컬럼 (없어도 앱은 status 만으로 취소 가능)
ALTER TABLE public.jobs
  ADD COLUMN IF NOT EXISTS cancel_reason TEXT,
  ADD COLUMN IF NOT EXISTS cancel_category TEXT;

ALTER TABLE public.marketplace_listings
  ADD COLUMN IF NOT EXISTS cancel_reason TEXT,
  ADD COLUMN IF NOT EXISTS cancel_category TEXT;

-- AI 한줄 견적 인터뷰 임시 세션. 실제 orders 를 대체하지 않는다.
CREATE TABLE IF NOT EXISTS public.ai_order_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID,
  initial_text TEXT,
  conversation_data JSONB DEFAULT '[]'::jsonb,
  analysis_data JSONB,
  status TEXT NOT NULL DEFAULT 'interviewing',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '24 hours')
);

CREATE INDEX IF NOT EXISTS idx_ai_order_sessions_status
  ON public.ai_order_sessions (status);

ALTER TABLE public.ai_order_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS service_ai_order_sessions ON public.ai_order_sessions;
CREATE POLICY service_ai_order_sessions ON public.ai_order_sessions
  FOR ALL TO service_role USING (true) WITH CHECK (true);
