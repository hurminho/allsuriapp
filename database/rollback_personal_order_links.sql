-- ============================================
-- 개인 오더 링크 기능 롤백 스크립트
-- ============================================

-- 트리거 삭제
DROP TRIGGER IF EXISTS log_personal_order_link_changes ON public.personal_order_links;
DROP TRIGGER IF EXISTS update_personal_order_links_updated_at ON public.personal_order_links;

-- 함수 삭제
DROP FUNCTION IF EXISTS log_personal_link_changes();
DROP FUNCTION IF EXISTS update_updated_at_column();
DROP FUNCTION IF EXISTS normalize_slug(TEXT);
DROP FUNCTION IF EXISTS is_slug_available(TEXT, UUID);

-- 테이블 삭제 (역순)
DROP TABLE IF EXISTS public.personal_order_link_audit_logs CASCADE;
DROP TABLE IF EXISTS public.personal_order_link_events CASCADE;
DROP TABLE IF EXISTS public.reserved_slugs CASCADE;

-- orders 테이블에서 개인 링크 관련 컬럼 제거
ALTER TABLE public.orders DROP COLUMN IF EXISTS routing_type;
ALTER TABLE public.orders DROP COLUMN IF EXISTS personal_order_link_id;
ALTER TABLE public.orders DROP COLUMN IF EXISTS source_contractor_id;
ALTER TABLE public.orders DROP COLUMN IF EXISTS assigned_contractor_id;
ALTER TABLE public.orders DROP COLUMN IF EXISTS assignment_locked_at;
ALTER TABLE public.orders DROP COLUMN IF EXISTS attribution_source;
ALTER TABLE public.orders DROP COLUMN IF EXISTS utm_source;
ALTER TABLE public.orders DROP COLUMN IF EXISTS utm_medium;
ALTER TABLE public.orders DROP COLUMN IF EXISTS utm_campaign;
ALTER TABLE public.orders DROP COLUMN IF EXISTS referrer_domain;

-- personal_order_links 테이블 삭제
DROP TABLE IF EXISTS public.personal_order_links CASCADE;

SELECT '✅ 개인 오더 링크 스키마 롤백 완료' AS status;
