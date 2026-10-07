-- =============================================================================
-- 올수리 DB 보안 잠금 (2026-10-07)
--
-- 실행: Supabase Dashboard → SQL Editor 에 전체를 붙여 넣고 실행합니다.
--       한 트랜잭션이라 중간에 실패하면 아무것도 바뀌지 않습니다. 여러 번 실행해도 됩니다.
-- 되돌리기: database/security_lockdown_2026_10_rollback.sql
--
-- 하는 일
--   0) 현재 정책·RLS 상태·권한을 ops 스키마에 백업 (처음 실행할 때 한 번만 저장)
--   1) 위험 함수 잠금: 전체 삭제(delete_business_user·delete_user_cascade)와
--      입찰·낙찰 RPC(claim_listing·select_bidder·create_order_bid·withdraw_bid)는 서버(service_role)만.
--      → 예전에는 anon 키만으로 누구나 임의 사용자를 통째로 지울 수 있었습니다.
--   2) 로그인 안 한 사용자(anon): 공개 콘텐츠 테이블만 읽기. 나머지는 모두 차단.
--   3) 로그인 사용자(authenticated):
--        users          본인 + 사업자 프로필 + 관리자
--        orders         본인 주문(고객) / 배정·연결된 사업자 / 관리자
--        notifications  본인 알림 (다른 사용자에게 보내는 INSERT 는 허용 — 앱 알림 경로)
--        chat_rooms     참여자만
--        chat_messages  해당 방 참여자만, 보낼 때는 본인 이름으로만
--        admins 등 서버 전용 테이블은 차단
--   4) users 권한 상승 차단 트리거: is_admin·admin 역할·사업자 인증 결과는 본인이 바꿀 수 없음
--   5) 공사 금액·수수료 보호: 수수료율 10%(allsuri_commission_rate) 고정,
--      jobs.awarded_amount·commission_* 는 서버·관리자만 바꿈
--
-- 서버 경로(Netlify Functions·웹 API·카카오 로그인)는 service_role 이라 영향이 없습니다.
-- 이후 새 공개 테이블을 만들면 anon 에 필요한 권한을 직접 GRANT 해야 합니다(기본 권한을 막아 둠).
-- =============================================================================

BEGIN;

-- 0) 백업 ---------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS ops;
REVOKE ALL ON SCHEMA ops FROM PUBLIC;
REVOKE ALL ON SCHEMA ops FROM anon, authenticated;

CREATE TABLE IF NOT EXISTS ops.policy_backup_20261007 AS
  SELECT now() AS backed_up_at, p.*
  FROM pg_policies p
  WHERE p.schemaname = 'public';

CREATE TABLE IF NOT EXISTS ops.rls_backup_20261007 AS
  SELECT c.relname::text AS tablename, c.relrowsecurity, c.relforcerowsecurity
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p');

CREATE TABLE IF NOT EXISTS ops.grant_backup_20261007 AS
  SELECT table_name::text, grantee::text, privilege_type::text
  FROM information_schema.role_table_grants
  WHERE table_schema = 'public' AND grantee IN ('anon', 'authenticated');


-- 1) 위험 함수 잠금 --------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN ('delete_business_user', 'delete_user_cascade',
                        'claim_listing', 'select_bidder', 'create_order_bid', 'withdraw_bid')
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', r.sig);
  END LOOP;

  -- 카운트 증가 함수는 앱(로그인 사용자)이 부릅니다. 로그인 안 한 호출만 막습니다.
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN ('increment_user_estimates_created_count', 'increment_user_jobs_accepted_count',
                        'increment_user_projects_awarded_count', 'increment_post_comments',
                        'increment_post_upvotes')
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', r.sig);
  END LOOP;
END $$;


-- 2) anon: 공개 콘텐츠만 ------------------------------------------------------------
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;

DO $$
DECLARE t text;
BEGIN
  -- 로그인 전 앱 화면·웹 공개 페이지가 읽는 테이블
  FOREACH t IN ARRAY ARRAY['web_settings', 'web_ads', 'ads', 'announcements', 'app_version',
                           'community_posts', 'community_comments',
                           'personal_order_links', 'reserved_slugs']
  LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE format('GRANT SELECT ON public.%I TO anon', t);
    END IF;
  END LOOP;
  -- 개인 오더 링크 방문 통계(개인정보 없음)
  IF to_regclass('public.personal_order_link_events') IS NOT NULL THEN
    GRANT INSERT ON public.personal_order_link_events TO anon;
  END IF;
END $$;

-- 앞으로 만드는 테이블도 anon 에 자동으로 열리지 않게 합니다.
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM anon;


-- 3) 로그인 사용자 범위 제한 ----------------------------------------------------------

-- 관리자 판별 (users 정책 안에서 써도 재귀가 생기지 않도록 SECURITY DEFINER)
CREATE OR REPLACE FUNCTION public.allsuri_is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND (u.is_admin IS TRUE OR u.role = 'admin')
  );
$$;
REVOKE ALL ON FUNCTION public.allsuri_is_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.allsuri_is_admin() TO authenticated, service_role;

-- 기존 정책을 지우고 새로 만듭니다(지운 정책은 0)의 백업에 있습니다).
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT policyname, tablename FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN ('users', 'orders', 'notifications', 'chat_rooms', 'chat_messages', 'admins')
  LOOP
    EXECUTE format('DROP POLICY %I ON public.%I', r.policyname, r.tablename);
  END LOOP;
END $$;

-- users
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
CREATE POLICY allsuri_users_select ON public.users FOR SELECT TO authenticated
  USING (id = auth.uid() OR role = 'business' OR public.allsuri_is_admin());
CREATE POLICY allsuri_users_insert ON public.users FOR INSERT TO authenticated
  WITH CHECK (id = auth.uid());
CREATE POLICY allsuri_users_update ON public.users FOR UPDATE TO authenticated
  USING (id = auth.uid() OR public.allsuri_is_admin())
  WITH CHECK (id = auth.uid() OR public.allsuri_is_admin());
CREATE POLICY allsuri_users_delete ON public.users FOR DELETE TO authenticated
  USING (public.allsuri_is_admin());

-- orders (웹 고객 주문: 연락처·주소가 있습니다)
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY allsuri_orders_select ON public.orders FOR SELECT TO authenticated
  USING ("customerId" = auth.uid()
         OR assigned_contractor_id = auth.uid()
         OR source_contractor_id = auth.uid()
         OR public.allsuri_is_admin());
CREATE POLICY allsuri_orders_insert ON public.orders FOR INSERT TO authenticated
  WITH CHECK (true);
CREATE POLICY allsuri_orders_update ON public.orders FOR UPDATE TO authenticated
  USING ("customerId" = auth.uid() OR assigned_contractor_id = auth.uid() OR public.allsuri_is_admin())
  WITH CHECK ("customerId" = auth.uid() OR assigned_contractor_id = auth.uid() OR public.allsuri_is_admin());
CREATE POLICY allsuri_orders_delete ON public.orders FOR DELETE TO authenticated
  USING ("customerId" = auth.uid() OR public.allsuri_is_admin());

-- notifications
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY allsuri_notifications_select ON public.notifications FOR SELECT TO authenticated
  USING (userid = auth.uid() OR public.allsuri_is_admin());
CREATE POLICY allsuri_notifications_insert ON public.notifications FOR INSERT TO authenticated
  WITH CHECK (true);
CREATE POLICY allsuri_notifications_update ON public.notifications FOR UPDATE TO authenticated
  USING (userid = auth.uid() OR public.allsuri_is_admin())
  WITH CHECK (userid = auth.uid() OR public.allsuri_is_admin());
CREATE POLICY allsuri_notifications_delete ON public.notifications FOR DELETE TO authenticated
  USING (userid = auth.uid() OR public.allsuri_is_admin());

-- chat_rooms
ALTER TABLE public.chat_rooms ENABLE ROW LEVEL SECURITY;
CREATE POLICY allsuri_chat_rooms_select ON public.chat_rooms FOR SELECT TO authenticated
  USING (auth.uid() IN (participant_a, participant_b, customerid, businessid) OR public.allsuri_is_admin());
CREATE POLICY allsuri_chat_rooms_insert ON public.chat_rooms FOR INSERT TO authenticated
  WITH CHECK (auth.uid() IN (participant_a, participant_b, customerid, businessid));
CREATE POLICY allsuri_chat_rooms_update ON public.chat_rooms FOR UPDATE TO authenticated
  USING (auth.uid() IN (participant_a, participant_b, customerid, businessid) OR public.allsuri_is_admin())
  WITH CHECK (auth.uid() IN (participant_a, participant_b, customerid, businessid) OR public.allsuri_is_admin());
CREATE POLICY allsuri_chat_rooms_delete ON public.chat_rooms FOR DELETE TO authenticated
  USING (auth.uid() IN (participant_a, participant_b, customerid, businessid) OR public.allsuri_is_admin());

-- chat_messages (room_id 는 text 입니다)
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY allsuri_chat_messages_select ON public.chat_messages FOR SELECT TO authenticated
  USING (
    public.allsuri_is_admin()
    OR EXISTS (
      SELECT 1 FROM public.chat_rooms r
      WHERE r.id::text = chat_messages.room_id
        AND auth.uid() IN (r.participant_a, r.participant_b, r.customerid, r.businessid)
    )
  );
CREATE POLICY allsuri_chat_messages_insert ON public.chat_messages FOR INSERT TO authenticated
  WITH CHECK (
    sender_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.chat_rooms r
      WHERE r.id::text = chat_messages.room_id
        AND auth.uid() IN (r.participant_a, r.participant_b, r.customerid, r.businessid)
    )
  );
CREATE POLICY allsuri_chat_messages_delete ON public.chat_messages FOR DELETE TO authenticated
  USING (
    public.allsuri_is_admin()
    OR EXISTS (
      SELECT 1 FROM public.chat_rooms r
      WHERE r.id::text = chat_messages.room_id
        AND auth.uid() IN (r.participant_a, r.participant_b, r.customerid, r.businessid)
    )
  );

-- 서버 전용 테이블 (앱·웹 브라우저가 쓰지 않음)
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['admins', 'ai_order_sessions', 'business_verifications',
                           'users_id_map', 'personal_order_link_audit_logs']
  LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE format('REVOKE ALL ON public.%I FROM anon, authenticated', t);
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    END IF;
  END LOOP;
END $$;


-- 4) users 권한 상승 차단 --------------------------------------------------------------
-- 사업자 승인(businessstatus)은 앱이 프로필 저장 때 자동 승인하는 설계라 막지 않습니다.
CREATE OR REPLACE FUNCTION public.allsuri_guard_user_privileges()
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
    IF coalesce(NEW.is_admin, false) OR NEW.role = 'admin' THEN
      RAISE EXCEPTION '관리자 권한은 직접 설정할 수 없습니다' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.is_admin IS DISTINCT FROM OLD.is_admin
     OR (NEW.role = 'admin' AND OLD.role IS DISTINCT FROM 'admin')
     OR NEW.business_verify_status IS DISTINCT FROM OLD.business_verify_status
     OR NEW.business_verify_bypass IS DISTINCT FROM OLD.business_verify_bypass
     OR NEW.business_verified_at IS DISTINCT FROM OLD.business_verified_at
  THEN
    RAISE EXCEPTION '관리자·사업자 인증 정보는 직접 바꿀 수 없습니다' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS allsuri_guard_user_privileges ON public.users;
CREATE TRIGGER allsuri_guard_user_privileges
  BEFORE INSERT OR UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.allsuri_guard_user_privileges();


-- 5) 공사 금액·수수료 보호 -----------------------------------------------------------
-- 수수료 = awarded_amount(낙찰된 입찰가) × commission_rate. 금액은 서버(낙찰 API)가 저장합니다.
-- 앱 사용자가 직접 바꾸면 수수료가 틀어지므로(예: 0원으로 수정), 로그인 사용자의 변경은
-- 오류 없이 기존 값으로 되돌립니다. 예전 앱 버전이 낙찰 직후 예산 금액으로 덮어쓰던 동작도 막힙니다.

-- 플랫폼 수수료율(%)은 이 함수 한 곳에서 정합니다. 바꿀 때는 이 함수만 다시 만들면 됩니다.
-- (앱 lib/config/commission.dart, 서버 netlify/lib/commission.ts, 웹 lib/commission.ts 와 같은 값)
CREATE OR REPLACE FUNCTION public.allsuri_commission_rate()
RETURNS numeric
LANGUAGE sql
STABLE
AS $$ SELECT 10::numeric $$;

GRANT EXECUTE ON FUNCTION public.allsuri_commission_rate() TO anon, authenticated, service_role;
ALTER TABLE public.jobs ALTER COLUMN commission_rate SET DEFAULT public.allsuri_commission_rate();

-- 아직 아무에게도 넘어가지 않은(등록만 된) 공사는 새 수수료율을 적용합니다. 진행·완료된 공사는 그대로 둡니다.
UPDATE public.jobs
SET commission_rate = public.allsuri_commission_rate()
WHERE status = 'created'
  AND assigned_business_id IS NULL
  AND commission_rate IS DISTINCT FROM public.allsuri_commission_rate();
CREATE OR REPLACE FUNCTION public.allsuri_guard_job_commission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  req_role text := coalesce(nullif(current_setting('request.jwt.claims', true), '')::json ->> 'role', '');
BEGIN
  IF req_role NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;
  IF public.allsuri_is_admin() THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    -- 앱이 공사를 올릴 때는 금액이 정해지지 않습니다(낙찰 때 서버가 저장).
    -- 수수료율은 플랫폼 정책이라 앱이 보낸 값 대신 고정 비율을 씁니다.
    NEW.awarded_amount := NULL;
    NEW.commission_amount := NULL;
    NEW.commission_rate := public.allsuri_commission_rate();
    RETURN NEW;
  END IF;

  NEW.awarded_amount := OLD.awarded_amount;
  NEW.commission_rate := OLD.commission_rate;
  NEW.commission_amount := OLD.commission_amount;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS allsuri_guard_job_commission ON public.jobs;
CREATE TRIGGER allsuri_guard_job_commission
  BEFORE INSERT OR UPDATE ON public.jobs
  FOR EACH ROW EXECUTE FUNCTION public.allsuri_guard_job_commission();

COMMIT;

-- 적용 확인 (선택): 아래 결과에 allsuri_* 정책 19개가 보이면 정상입니다.
-- SELECT tablename, policyname, cmd FROM pg_policies
-- WHERE schemaname = 'public' AND policyname LIKE 'allsuri_%' ORDER BY tablename, policyname;
