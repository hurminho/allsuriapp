-- =============================================================================
-- 올수리 광고성 정보 수신 동의 (2026-10-13)
--
-- 실행: Supabase Dashboard → SQL Editor 에 전체를 붙여 넣고 실행. 여러 번 실행해도 됩니다.
-- 앱(새 버전)과 웹 동의 페이지(allsuri.app/consent)보다 먼저 실행해야 합니다.
--
-- 정보통신망법 제50조에 맞춘 것
--   · 동의는 선택이고 기본값은 '안 받음'
--   · 야간(21시~다음 날 8시) 전송은 따로 동의
--   · 동의·철회를 처리하면 수신자에게 처리 결과(보내는 곳, 일자, 내용)를 알림 → 앱 알림으로 자동 발송
--   · 동의·철회 이력을 남김 (2년마다 수신 동의 여부 확인할 때 근거)
--
-- 하는 일
--   1) users 에 동의 상태 칸 추가
--   2) 동의 이력 테이블 marketing_consent_logs (서버 전용)
--   3) 동의 일자는 DB 가 기록 (앱이 보낸 날짜는 무시), 바뀔 때마다 이력 + 처리 결과 알림
--   4) 웹 동의 페이지용: 전화번호 인증번호 테이블 phone_otps(서버 전용), 전화번호로 회원 찾기 함수
-- =============================================================================

BEGIN;

-- 1) 동의 상태 ------------------------------------------------------------------
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS marketing_consent boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS marketing_night_consent boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS marketing_consent_at timestamptz,
  ADD COLUMN IF NOT EXISTS marketing_withdrawn_at timestamptz,
  ADD COLUMN IF NOT EXISTS marketing_consent_channel text,
  ADD COLUMN IF NOT EXISTS marketing_consent_asked_at timestamptz;

COMMENT ON COLUMN public.users.marketing_consent IS '광고성 정보(문자·앱 푸시) 수신 동의';
COMMENT ON COLUMN public.users.marketing_night_consent IS '야간(21~08시) 광고성 정보 수신 동의';
COMMENT ON COLUMN public.users.marketing_consent_at IS '마지막으로 동의한 일시 (DB 가 기록)';
COMMENT ON COLUMN public.users.marketing_withdrawn_at IS '마지막으로 철회한 일시 (DB 가 기록)';
COMMENT ON COLUMN public.users.marketing_consent_channel IS '마지막 변경 경로: app, web 등';
COMMENT ON COLUMN public.users.marketing_consent_asked_at IS '앱에서 동의 여부를 물어본 일시 (다시 묻지 않기 위함)';


-- 2) 동의 이력 (서버·관리자 전용) -----------------------------------------------------
CREATE TABLE IF NOT EXISTS public.marketing_consent_logs (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL,
  consent boolean NOT NULL,
  night_consent boolean NOT NULL DEFAULT false,
  channel text,
  actor text NOT NULL,            -- self(본인 앱), server(웹 인증 페이지 등), sql(SQL Editor)
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS marketing_consent_logs_user_idx ON public.marketing_consent_logs (user_id, created_at DESC);
ALTER TABLE public.marketing_consent_logs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.marketing_consent_logs FROM anon, authenticated;


-- 3) 동의 일자 기록·이력·처리 결과 알림 -------------------------------------------------
-- 일자는 여기서만 정합니다. 앱이 marketing_consent_at 등을 보내도 이전 값으로 되돌립니다.
CREATE OR REPLACE FUNCTION public.allsuri_marketing_consent_stamp()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    NEW.marketing_consent_at := OLD.marketing_consent_at;
    NEW.marketing_withdrawn_at := OLD.marketing_withdrawn_at;
  END IF;

  IF NOT NEW.marketing_consent THEN
    NEW.marketing_night_consent := false;
  END IF;

  IF NEW.marketing_consent AND (TG_OP = 'INSERT' OR NOT OLD.marketing_consent) THEN
    NEW.marketing_consent_at := now();
  ELSIF TG_OP = 'UPDATE' AND OLD.marketing_consent AND NOT NEW.marketing_consent THEN
    NEW.marketing_withdrawn_at := now();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS allsuri_marketing_consent_stamp ON public.users;
CREATE TRIGGER allsuri_marketing_consent_stamp
  BEFORE INSERT OR UPDATE OF marketing_consent, marketing_night_consent, marketing_consent_at, marketing_withdrawn_at
  ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.allsuri_marketing_consent_stamp();

CREATE OR REPLACE FUNCTION public.allsuri_marketing_consent_changed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  req_role text := coalesce(nullif(current_setting('request.jwt.claims', true), '')::json ->> 'role', '');
  v_actor text := CASE req_role WHEN 'authenticated' THEN 'self' WHEN 'service_role' THEN 'server' ELSE 'sql' END;
  v_when text := to_char(now() AT TIME ZONE 'Asia/Seoul', 'YYYY-MM-DD HH24:MI');
  v_body text;
BEGIN
  IF NEW.marketing_consent IS NOT DISTINCT FROM OLD.marketing_consent
     AND NEW.marketing_night_consent IS NOT DISTINCT FROM OLD.marketing_night_consent THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.marketing_consent_logs (user_id, consent, night_consent, channel, actor)
  VALUES (NEW.id, NEW.marketing_consent, NEW.marketing_night_consent, NEW.marketing_consent_channel, v_actor);

  -- 처리 결과 안내 (정보통신망법 제50조 제7항). 광고가 아닌 안내라 동의 없이 보냅니다.
  v_body := CASE
    WHEN NEW.marketing_consent THEN
      format('올수리 광고성 정보 수신에 동의하셨습니다.%s처리 일시: %s%s야간(21~08시) 수신: %s%s동의는 앱 [내 정보 > 소식·혜택 받기] 또는 allsuri.app/consent 에서 언제든 철회할 수 있습니다.',
             E'\n', v_when, E'\n', CASE WHEN NEW.marketing_night_consent THEN '동의' ELSE '동의 안 함' END, E'\n')
    ELSE
      format('올수리 광고성 정보 수신 동의를 철회하셨습니다.%s처리 일시: %s%s앞으로 광고성 문자·푸시를 보내지 않습니다.',
             E'\n', v_when, E'\n')
  END;

  INSERT INTO public.notifications (userid, title, body, type, isread, createdat)
  VALUES (NEW.id, '광고성 정보 수신 동의 처리 결과', v_body, 'marketing_consent', false, now());

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS allsuri_marketing_consent_changed ON public.users;
CREATE TRIGGER allsuri_marketing_consent_changed
  AFTER UPDATE OF marketing_consent, marketing_night_consent ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.allsuri_marketing_consent_changed();


-- 4) 웹 동의 페이지: 전화번호 인증 ---------------------------------------------------
CREATE TABLE IF NOT EXISTS public.phone_otps (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_hash text NOT NULL,       -- 번호 원문은 저장하지 않습니다
  code_hash text NOT NULL,
  purpose text NOT NULL DEFAULT 'marketing_consent',
  ip text,
  attempts integer NOT NULL DEFAULT 0,
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS phone_otps_phone_idx ON public.phone_otps (phone_hash, created_at DESC);
CREATE INDEX IF NOT EXISTS phone_otps_ip_idx ON public.phone_otps (ip, created_at DESC);
ALTER TABLE public.phone_otps ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.phone_otps FROM anon, authenticated;

-- 전화번호(숫자만)로 회원 찾기. users 의 번호는 하이픈 유무·칸(phonenumber/phoneNumber)이 섞여 있습니다.
CREATE OR REPLACE FUNCTION public.allsuri_users_by_phone(p_digits text)
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT u.id
  FROM public.users u
  WHERE length(regexp_replace(coalesce(p_digits, ''), '[^0-9]', '', 'g')) BETWEEN 10 AND 11
    AND (regexp_replace(coalesce(u.phonenumber, ''), '[^0-9]', '', 'g') = regexp_replace(p_digits, '[^0-9]', '', 'g')
      OR regexp_replace(coalesce(u."phoneNumber", ''), '[^0-9]', '', 'g') = regexp_replace(p_digits, '[^0-9]', '', 'g'));
$$;
REVOKE ALL ON FUNCTION public.allsuri_users_by_phone(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.allsuri_users_by_phone(text) TO service_role;

COMMIT;

-- 동의한 사람 목록 (보낼 때 쓰는 쿼리, 참고용)
-- SELECT u.id, coalesce(nullif(u.businessname, ''), u.name) AS 이름,
--        coalesce(nullif(u.phonenumber, ''), u."phoneNumber") AS 연락처,
--        u.marketing_night_consent AS 야간동의,
--        to_char(u.marketing_consent_at AT TIME ZONE 'Asia/Seoul', 'YYYY-MM-DD HH24:MI') AS 동의일시
-- FROM public.users u
-- WHERE u.marketing_consent
-- ORDER BY u.marketing_consent_at DESC;
