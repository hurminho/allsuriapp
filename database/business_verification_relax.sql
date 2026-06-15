-- ============================================================
-- 사업자 활동 정책 완화 (2026-05)
--
-- 변경 사유:
--   - 국세청 진위확인 API가 신규 사업자/개업일 정합성 이슈로 false negative 다수 발생.
--   - 일단 "사업자번호가 등록되어 있으면 오더 등록·입찰·낙찰 허용" 으로 단순화.
--   - 사업자번호가 없거나 형식이 잘못된 경우만 차단.
--   - 관리자 우회(business_verify_bypass=TRUE)는 그대로 유지.
--
-- 적용 전제:
--   - database/business_verification.sql
--   - database/business_verification_bypass.sql
--   가 먼저 적용되어 있을 것.
--
-- 주의:
--   - DROP FUNCTION 은 RLS 정책이 fn_business_can_act 를 참조하고 있어 실패하므로
--     CREATE OR REPLACE 만으로 시그니처 유지하며 본문만 교체한다.
--   - SQL 언어 대신 plpgsql 로 작성하여 정의 시점에 본문이 즉시 컴파일되지 않도록 함
--     (Supabase의 search_path 강제 정책 충돌 회피).
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_business_can_act(p_uid uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ok boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = p_uid
      AND u.role = 'business'
      AND u.businessstatus::text = 'approved'
      AND (
        u.business_verify_bypass = TRUE
        OR u.businessnumber_norm IS NOT NULL
      )
  ) INTO v_ok;
  RETURN COALESCE(v_ok, FALSE);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_business_can_act(uuid)
  TO authenticated, anon, service_role;

COMMENT ON FUNCTION public.fn_business_can_act(uuid) IS
  '사업자 활동 가능 여부. 관리자 우회 또는 사업자번호 보유 시 TRUE. (2026-05 완화)';

-- ============================================================
-- 점검 쿼리는 database/business_verification_relax_check.sql 참조
-- (마이그레이션과 분리하여 실패해도 함수 갱신은 영향 없도록 함)
-- ============================================================
