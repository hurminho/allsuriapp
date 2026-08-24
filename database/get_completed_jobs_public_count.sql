-- 플랫폼 전체 "완료된 공사" 수 (홈 화면 통계용)
-- jobs RLS는 인증 사용자에게 본인 관련 행만 보이므로, 집계는 SECURITY DEFINER RPC로만 허용합니다.
-- Supabase SQL Editor에서 실행 후 GRANT 확인.

CREATE OR REPLACE FUNCTION public.get_completed_jobs_public_count()
RETURNS bigint
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT count(*)::bigint
  FROM public.jobs
  WHERE status IN ('completed', 'awaiting_confirmation');
$$;

REVOKE ALL ON FUNCTION public.get_completed_jobs_public_count() FROM public;
GRANT EXECUTE ON FUNCTION public.get_completed_jobs_public_count() TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_open_listings_public_count()
RETURNS bigint
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT count(*)::bigint
  FROM public.marketplace_listings
  WHERE status IN ('open', 'created');
$$;

REVOKE ALL ON FUNCTION public.get_open_listings_public_count() FROM public;
GRANT EXECUTE ON FUNCTION public.get_open_listings_public_count() TO anon, authenticated;

COMMENT ON FUNCTION public.get_completed_jobs_public_count() IS '올수리 홈 배너용: 완료·완료확인대기 공사 총 건수 (RLS 우회 집계)';
COMMENT ON FUNCTION public.get_open_listings_public_count() IS '올수리 홈 배너용: 공개 중인 일감 수 (RLS 우회 집계)';
