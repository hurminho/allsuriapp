-- =============================================================================
-- 올수리 공사 금액·수수료 보호 (2026-10-07)
--
-- 먼저 security_lockdown_2026_10.sql 을 실행한 뒤 실행합니다(allsuri_is_admin 함수를 씁니다).
-- 실행: Supabase Dashboard → SQL Editor 에 전체를 붙여 넣고 실행. 여러 번 실행해도 됩니다.
--
-- 수수료 = jobs.awarded_amount(낙찰된 입찰가) × jobs.commission_rate.
--   · 사업자 간 오더: 수수료율은 오더를 올린 사업자(원청)가 정합니다. 기본값 10%.
--   · 고객 웹 오더: 플랫폼 수수료 10% (서버가 낙찰 때 넣습니다).
--   · 공사 금액은 서버(낙찰·가져가기 API)가 낙찰된 입찰가로 저장합니다.
--
-- 하는 일
--   1) commission_rate 기본값 10% (allsuri_default_commission_rate 한 곳에서 정함)
--   2) 로그인 사용자(앱)가 공사 금액·수수료를 바꾸는 것을 막습니다. 오류 대신 기존 값을 유지합니다.
--      - 등록할 때: 금액은 비워 두고(낙찰 때 서버가 저장), 수수료율은 원청이 입력한 값(0~100)
--      - 수정할 때: 공사 금액·수수료 금액은 그대로. 수수료율은 아직 아무에게도 넘어가지 않은
--        공사에서만 바꿀 수 있습니다(낙찰·가져가기 뒤에는 고정).
--      예전 앱 버전이 낙찰 직후 예산 금액으로 덮어쓰던 동작도 이 규칙으로 막힙니다.
--   서버(service_role)·관리자·SQL Editor 는 제한하지 않습니다.
-- =============================================================================

BEGIN;

-- 1) 사업자 간 오더 수수료율 기본값 ----------------------------------------------------
-- (앱 lib/config/commission.dart 의 kDefaultB2BCommissionRatePercent 와 같은 값)
CREATE OR REPLACE FUNCTION public.allsuri_default_commission_rate()
RETURNS numeric
LANGUAGE sql
STABLE
AS $$ SELECT 10::numeric $$;

GRANT EXECUTE ON FUNCTION public.allsuri_default_commission_rate() TO anon, authenticated, service_role;
ALTER TABLE public.jobs ALTER COLUMN commission_rate SET DEFAULT public.allsuri_default_commission_rate();

-- 이전 초안에서 쓰던 이름 정리 (있을 때만)
DROP FUNCTION IF EXISTS public.allsuri_commission_rate();


-- 2) 공사 금액·수수료 보호 ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.allsuri_guard_job_commission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  req_role text := coalesce(nullif(current_setting('request.jwt.claims', true), '')::json ->> 'role', '');
BEGIN
  -- 서버(service_role)·SQL Editor(JWT 없음)는 제한하지 않습니다.
  IF req_role NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;
  IF public.allsuri_is_admin() THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    -- 공사 금액은 낙찰 때 서버가 저장합니다.
    NEW.awarded_amount := NULL;
    NEW.commission_amount := NULL;
    NEW.commission_rate := coalesce(NEW.commission_rate, public.allsuri_default_commission_rate());
    IF NEW.commission_rate < 0 OR NEW.commission_rate > 100 THEN
      RAISE EXCEPTION '수수료율은 0~100 사이여야 합니다' USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
  END IF;

  NEW.awarded_amount := OLD.awarded_amount;
  NEW.commission_amount := OLD.commission_amount;
  -- 수수료율은 아직 아무에게도 넘어가지 않은 공사에서만 바꿀 수 있습니다.
  IF OLD.assigned_business_id IS NOT NULL
     OR OLD.awarded_amount IS NOT NULL
     OR NEW.commission_rate IS NULL
     OR NEW.commission_rate < 0
     OR NEW.commission_rate > 100
  THEN
    NEW.commission_rate := OLD.commission_rate;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS allsuri_guard_job_commission ON public.jobs;
CREATE TRIGGER allsuri_guard_job_commission
  BEFORE INSERT OR UPDATE ON public.jobs
  FOR EACH ROW EXECUTE FUNCTION public.allsuri_guard_job_commission();

COMMIT;

-- 적용 확인 (선택): 둘 다 1행이면 정상입니다.
-- SELECT tgname FROM pg_trigger WHERE tgname = 'allsuri_guard_job_commission';
-- SELECT column_default FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'jobs' AND column_name = 'commission_rate';

-- 되돌리기 (필요할 때만, 아래 주석을 풀어 실행)
-- BEGIN;
-- DROP TRIGGER IF EXISTS allsuri_guard_job_commission ON public.jobs;
-- DROP FUNCTION IF EXISTS public.allsuri_guard_job_commission();
-- ALTER TABLE public.jobs ALTER COLUMN commission_rate SET DEFAULT 5;
-- DROP FUNCTION IF EXISTS public.allsuri_default_commission_rate();
-- COMMIT;
