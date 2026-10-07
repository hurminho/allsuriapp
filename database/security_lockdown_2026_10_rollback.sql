-- =============================================================================
-- 올수리 DB 보안 잠금 되돌리기 (security_lockdown_2026_10.sql 적용 전 상태로)
--
-- 앱이 잠금 때문에 멈췄을 때만 실행합니다. ops.*_20261007 백업을 읽어 복원합니다.
-- 위험 함수(전체 삭제·입찰 RPC)의 실행 권한은 되돌리지 않습니다 — 앱·웹이 직접 부르지 않고,
-- 다시 열면 누구나 임의 사용자를 지울 수 있게 됩니다.
-- =============================================================================

BEGIN;

-- 1) 권한 상승 차단 트리거 제거 (수수료 보호는 commission_guard_2026_10.sql 의 되돌리기 참고)
DROP TRIGGER IF EXISTS allsuri_guard_user_privileges ON public.users;
DROP FUNCTION IF EXISTS public.allsuri_guard_user_privileges();

-- 2) 새 정책 제거 후 예전 정책 복원
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

  FOR r IN
    SELECT * FROM ops.policy_backup_20261007
    WHERE tablename IN ('users', 'orders', 'notifications', 'chat_rooms', 'chat_messages', 'admins')
  LOOP
    EXECUTE format(
      'CREATE POLICY %I ON public.%I AS %s FOR %s TO %s%s%s',
      r.policyname, r.tablename, r.permissive, r.cmd,
      array_to_string(ARRAY(SELECT quote_ident(x) FROM unnest(r.roles) AS x), ', '),
      CASE WHEN r.qual IS NOT NULL THEN ' USING (' || r.qual || ')' ELSE '' END,
      CASE WHEN r.with_check IS NOT NULL THEN ' WITH CHECK (' || r.with_check || ')' ELSE '' END
    );
  END LOOP;
END $$;

-- 3) RLS 켜짐/꺼짐 복원
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT * FROM ops.rls_backup_20261007
    WHERE tablename IN ('users', 'orders', 'notifications', 'chat_rooms', 'chat_messages',
                        'admins', 'ai_order_sessions', 'business_verifications',
                        'users_id_map', 'personal_order_link_audit_logs')
  LOOP
    EXECUTE format('ALTER TABLE public.%I %s ROW LEVEL SECURITY',
                   r.tablename, CASE WHEN r.relrowsecurity THEN 'ENABLE' ELSE 'DISABLE' END);
  END LOOP;
END $$;

-- 4) anon·authenticated 테이블 권한 복원
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM ops.grant_backup_20261007 LOOP
    IF to_regclass('public.' || r.table_name) IS NOT NULL THEN
      EXECUTE format('GRANT %s ON public.%I TO %I', r.privilege_type, r.table_name, r.grantee);
    END IF;
  END LOOP;
END $$;

ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon;

COMMIT;
