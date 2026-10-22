-- =============================================================================
-- 앱 팝업 + 우수 업체 연락처 표시 (2026-10-22)
--
-- 실행: Supabase Dashboard → SQL Editor 에 전체를 붙여 넣고 실행. 여러 번 실행해도 됩니다.
-- 새 앱(1.0.19)·관리자 페이지보다 먼저 실행해야 합니다. 실행 전 버전 앱에는 영향이 없습니다.
--
-- 하는 일
--   1) 이번 달 우수 업체: 업체마다 표시 이름·표시 전화번호·웹사이트를 따로 정할 수 있게 칸 추가
--      · 웹사이트가 있으면 전화번호 대신 웹사이트 링크를 보여 줍니다(표시 전화번호를 넣으면 같이 보임)
--      · 표시 전화번호가 있으면 회원 전화번호 대신 그 번호를 보여 줍니다
--   2) 앱 팝업 app_popups: 앱을 열면 대상자에게 뜨는 안내 창 (관리자 페이지에서 등록)
--      · 대상: 전체 / 공종(대분류)별 사업자 / 직접 고른 사업자
--      · 빈도: 한 번만 / 하루 한 번 / 열 때마다 (사용자가 '다시 보지 않기'를 누르면 그만 뜸)
--   3) 팝업 노출·클릭 기록 app_popup_views (관리자 통계용)
--   4) 앱이 부르는 함수: allsuri_my_app_popup(), allsuri_app_popup_event()
-- =============================================================================

BEGIN;

-- 1) 우수 업체 표시 정보 ----------------------------------------------------------
ALTER TABLE public.web_featured_businesses
  ADD COLUMN IF NOT EXISTS display_name text,
  ADD COLUMN IF NOT EXISTS contact_phone text,
  ADD COLUMN IF NOT EXISTS website_url text;

COMMENT ON COLUMN public.web_featured_businesses.display_name IS '웹에 보여 줄 업체 이름 (비우면 회원 상호명)';
COMMENT ON COLUMN public.web_featured_businesses.contact_phone IS '웹에 보여 줄 전화번호 (비우면 회원 전화번호, 웹사이트가 있으면 이 번호만)';
COMMENT ON COLUMN public.web_featured_businesses.website_url IS '웹사이트 링크 (있으면 회원 전화번호 대신 표시)';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'web_featured_businesses_website_url_check') THEN
    ALTER TABLE public.web_featured_businesses
      ADD CONSTRAINT web_featured_businesses_website_url_check
      CHECK (website_url IS NULL OR website_url ~ '^https?://');
  END IF;
END $$;


-- 2) 앱 팝업 --------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_popups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL CHECK (char_length(btrim(title)) BETWEEN 1 AND 40),
  body text NOT NULL CHECK (char_length(btrim(body)) BETWEEN 1 AND 500),
  image_url text CHECK (image_url IS NULL OR image_url ~ '^https://'),
  button_label text CHECK (button_label IS NULL OR char_length(button_label) <= 20),
  button_url text CHECK (button_url IS NULL OR button_url ~ '^https?://'),
  audience text NOT NULL DEFAULT 'all' CHECK (audience IN ('all', 'trades', 'selected')),
  target_trades text[] NOT NULL DEFAULT '{}',      -- audience = 'trades': 공종 대분류 이름
  target_user_ids uuid[] NOT NULL DEFAULT '{}',    -- audience = 'selected': 사업자 id
  frequency text NOT NULL DEFAULT 'once' CHECK (frequency IN ('once', 'daily', 'always')),
  is_active boolean NOT NULL DEFAULT true,
  start_at timestamptz,                            -- null = 바로
  end_at timestamptz,                              -- null = 끄기 전까지
  priority integer NOT NULL DEFAULT 0,             -- 여러 개가 해당되면 큰 것부터 하나만
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS app_popups_active_idx ON public.app_popups (is_active, priority DESC, created_at DESC);
ALTER TABLE public.app_popups ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.app_popups FROM anon, authenticated;

COMMENT ON TABLE public.app_popups IS '앱을 열 때 대상자에게 뜨는 안내 창 (관리자 페이지에서 등록, 앱은 allsuri_my_app_popup 으로만 읽음)';


-- 3) 노출·클릭 기록 (서버·관리자 전용) ------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_popup_views (
  popup_id uuid NOT NULL REFERENCES public.app_popups(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  first_seen_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  seen_count integer NOT NULL DEFAULT 1,
  clicked_at timestamptz,          -- 버튼을 처음 누른 때
  hidden_at timestamptz,           -- '다시 보지 않기'를 누른 때
  PRIMARY KEY (popup_id, user_id)
);
ALTER TABLE public.app_popup_views ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.app_popup_views FROM anon, authenticated;


-- 4) 앱이 부르는 함수 --------------------------------------------------------------
-- 지금 로그인한 사용자에게 띄울 팝업 하나 (없으면 빈 결과)
CREATE OR REPLACE FUNCTION public.allsuri_my_app_popup()
RETURNS TABLE (
  id uuid, title text, body text, image_url text,
  button_label text, button_url text, frequency text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.id, p.title, p.body, p.image_url, p.button_label, p.button_url, p.frequency
  FROM public.app_popups p
  JOIN public.users u ON u.id = auth.uid()
  LEFT JOIN public.app_popup_views v ON v.popup_id = p.id AND v.user_id = u.id
  WHERE p.is_active
    AND (p.start_at IS NULL OR p.start_at <= now())
    AND (p.end_at IS NULL OR p.end_at > now())
    AND (
      p.audience = 'all'
      OR (p.audience = 'selected' AND u.id = ANY (p.target_user_ids))
      OR (p.audience = 'trades' AND EXISTS (
            SELECT 1 FROM unnest(coalesce(u.specialties, '{}'::text[])) s
            WHERE public.allsuri_trade_group(s) = ANY (p.target_trades)))
    )
    AND v.hidden_at IS NULL
    AND (
      v.popup_id IS NULL
      OR p.frequency = 'always'
      OR (p.frequency = 'daily'
          AND (v.last_seen_at AT TIME ZONE 'Asia/Seoul')::date < (now() AT TIME ZONE 'Asia/Seoul')::date)
    )
  ORDER BY p.priority DESC, p.created_at DESC
  LIMIT 1;
$$;

-- 팝업을 봤다(seen) / 버튼을 눌렀다(click) / 다시 보지 않기(hide)
CREATE OR REPLACE FUNCTION public.allsuri_app_popup_event(p_popup_id uuid, p_event text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
BEGIN
  IF uid IS NULL THEN
    RETURN;
  END IF;
  IF p_event NOT IN ('seen', 'click', 'hide') THEN
    RAISE EXCEPTION 'unknown popup event: %', p_event;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.app_popups WHERE id = p_popup_id) THEN
    RETURN;
  END IF;

  INSERT INTO public.app_popup_views AS v (popup_id, user_id, clicked_at, hidden_at)
  VALUES (
    p_popup_id, uid,
    CASE WHEN p_event = 'click' THEN now() END,
    CASE WHEN p_event = 'hide' THEN now() END
  )
  ON CONFLICT (popup_id, user_id) DO UPDATE SET
    last_seen_at = CASE WHEN p_event = 'seen' THEN now() ELSE v.last_seen_at END,
    seen_count = v.seen_count + CASE WHEN p_event = 'seen' THEN 1 ELSE 0 END,
    clicked_at = CASE WHEN p_event = 'click' THEN coalesce(v.clicked_at, now()) ELSE v.clicked_at END,
    hidden_at = CASE WHEN p_event = 'hide' THEN coalesce(v.hidden_at, now()) ELSE v.hidden_at END;
END;
$$;

REVOKE ALL ON FUNCTION public.allsuri_my_app_popup() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.allsuri_app_popup_event(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.allsuri_my_app_popup() TO authenticated;
GRANT EXECUTE ON FUNCTION public.allsuri_app_popup_event(uuid, text) TO authenticated;

COMMIT;

-- 확인 (결과 3줄이 모두 true 면 정상)
SELECT 'featured columns' AS item,
       count(*) = 3 AS ok
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'web_featured_businesses'
  AND column_name IN ('display_name', 'contact_phone', 'website_url')
UNION ALL
SELECT 'popup tables', count(*) = 2
FROM information_schema.tables
WHERE table_schema = 'public' AND table_name IN ('app_popups', 'app_popup_views')
UNION ALL
SELECT 'popup functions', count(*) = 2
FROM pg_proc
WHERE pronamespace = 'public'::regnamespace
  AND proname IN ('allsuri_my_app_popup', 'allsuri_app_popup_event');
