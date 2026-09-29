-- ============================================
-- 감사 로그 RLS 정책 수정
-- personal_order_link_audit_logs INSERT 권한 추가
-- ============================================

-- 방법 1: 트리거 함수를 SECURITY DEFINER로 변경 (RLS 우회)
CREATE OR REPLACE FUNCTION log_personal_link_changes()
RETURNS TRIGGER 
SECURITY DEFINER  -- 이 함수는 소유자 권한으로 실행 (RLS 우회)
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.personal_order_link_audit_logs (
            personal_order_link_id,
            action,
            new_slug,
            performed_by
        ) VALUES (
            NEW.id,
            'created',
            NEW.slug,
            NEW.contractor_id
        );
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.slug != NEW.slug THEN
            INSERT INTO public.personal_order_link_audit_logs (
                personal_order_link_id,
                action,
                old_slug,
                new_slug,
                performed_by
            ) VALUES (
                NEW.id,
                'slug_changed',
                OLD.slug,
                NEW.slug,
                NEW.contractor_id
            );
        END IF;
        
        IF OLD.status = 'active' AND NEW.status = 'paused' THEN
            INSERT INTO public.personal_order_link_audit_logs (
                personal_order_link_id,
                action,
                performed_by
            ) VALUES (
                NEW.id,
                'paused',
                NEW.contractor_id
            );
        ELSIF OLD.status = 'paused' AND NEW.status = 'active' THEN
            INSERT INTO public.personal_order_link_audit_logs (
                personal_order_link_id,
                action,
                performed_by
            ) VALUES (
                NEW.id,
                'resumed',
                NEW.contractor_id
            );
        ELSIF NEW.status = 'revoked' AND OLD.status != 'revoked' THEN
            INSERT INTO public.personal_order_link_audit_logs (
                personal_order_link_id,
                action,
                performed_by
            ) VALUES (
                NEW.id,
                'revoked',
                NEW.contractor_id
            );
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 완료 메시지
SELECT '✅ 감사 로그 트리거 함수 수정 완료 (SECURITY DEFINER)' AS status;
