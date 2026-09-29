-- ============================================
-- 개인 오더 링크 기능을 위한 DB 스키마
-- ============================================

-- 1. 개인 오더 링크 테이블
CREATE TABLE IF NOT EXISTS public.personal_order_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contractor_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- 링크 slug (URL 경로에 사용)
    slug TEXT NOT NULL,
    slug_normalized TEXT NOT NULL UNIQUE, -- 소문자 정규화 버전
    
    -- 링크 상태
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'paused', 'revoked', 'suspended')),
    accepts_direct_orders BOOLEAN NOT NULL DEFAULT true,
    
    -- 사업자 프로필 정보
    display_name TEXT,
    headline TEXT, -- 한 줄 소개
    introduction TEXT, -- 상세 소개
    supported_categories TEXT[], -- 지원 카테고리 목록
    service_regions TEXT[], -- 활동 지역 목록
    profile_image_url TEXT,
    cover_image_url TEXT,
    
    -- 검증 상태
    verification_status TEXT DEFAULT 'pending' CHECK (verification_status IN ('pending', 'verified', 'rejected')),
    
    -- 타임스탬프
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at TIMESTAMPTZ,
    last_shared_at TIMESTAMPTZ,
    
    -- 제약조건
    CONSTRAINT valid_slug CHECK (
        slug_normalized ~ '^[a-z0-9_-]+$' AND
        LENGTH(slug_normalized) >= 3 AND
        LENGTH(slug_normalized) <= 50
    )
);

-- 인덱스
CREATE INDEX IF NOT EXISTS idx_personal_order_links_contractor ON public.personal_order_links(contractor_id);
CREATE INDEX IF NOT EXISTS idx_personal_order_links_slug ON public.personal_order_links(slug_normalized);
CREATE INDEX IF NOT EXISTS idx_personal_order_links_status ON public.personal_order_links(status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_personal_order_links_active_contractor 
    ON public.personal_order_links(contractor_id) 
    WHERE status = 'active';

-- 2. orders 테이블에 개인 링크 관련 필드 추가
ALTER TABLE public.orders 
ADD COLUMN IF NOT EXISTS routing_type TEXT DEFAULT 'marketplace' 
    CHECK (routing_type IN ('marketplace', 'personal_link'));

ALTER TABLE public.orders 
ADD COLUMN IF NOT EXISTS personal_order_link_id UUID 
    REFERENCES public.personal_order_links(id) ON DELETE SET NULL;

ALTER TABLE public.orders 
ADD COLUMN IF NOT EXISTS source_contractor_id UUID 
    REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.orders 
ADD COLUMN IF NOT EXISTS assigned_contractor_id UUID 
    REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.orders 
ADD COLUMN IF NOT EXISTS assignment_locked_at TIMESTAMPTZ;

ALTER TABLE public.orders 
ADD COLUMN IF NOT EXISTS attribution_source TEXT;

ALTER TABLE public.orders 
ADD COLUMN IF NOT EXISTS utm_source TEXT;

ALTER TABLE public.orders 
ADD COLUMN IF NOT EXISTS utm_medium TEXT;

ALTER TABLE public.orders 
ADD COLUMN IF NOT EXISTS utm_campaign TEXT;

ALTER TABLE public.orders 
ADD COLUMN IF NOT EXISTS referrer_domain TEXT;

-- 개인 링크 요청 인덱스
CREATE INDEX IF NOT EXISTS idx_orders_routing_type ON public.orders(routing_type);
CREATE INDEX IF NOT EXISTS idx_orders_personal_link ON public.orders(personal_order_link_id);
CREATE INDEX IF NOT EXISTS idx_orders_assigned_contractor ON public.orders(assigned_contractor_id);

-- 3. 개인 링크 분석 이벤트 테이블
CREATE TABLE IF NOT EXISTS public.personal_order_link_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    personal_order_link_id UUID NOT NULL REFERENCES public.personal_order_links(id) ON DELETE CASCADE,
    
    -- 이벤트 타입
    event_type TEXT NOT NULL CHECK (event_type IN (
        'page_view',
        'quote_start',
        'category_selected',
        'photo_added',
        'quote_submitted',
        'contractor_viewed',
        'contractor_replied',
        'order_completed'
    )),
    
    -- 익명 세션 추적 (개인정보 제외)
    anonymous_session_id TEXT,
    
    -- 유입 경로 분석
    utm_source TEXT,
    utm_medium TEXT,
    utm_campaign TEXT,
    referrer_domain TEXT,
    
    -- 타임스탬프
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 분석 이벤트 인덱스
CREATE INDEX IF NOT EXISTS idx_personal_link_events_link ON public.personal_order_link_events(personal_order_link_id);
CREATE INDEX IF NOT EXISTS idx_personal_link_events_type ON public.personal_order_link_events(event_type);
CREATE INDEX IF NOT EXISTS idx_personal_link_events_created ON public.personal_order_link_events(created_at DESC);

-- 4. 링크 slug 감사 로그 테이블
CREATE TABLE IF NOT EXISTS public.personal_order_link_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    personal_order_link_id UUID NOT NULL REFERENCES public.personal_order_links(id) ON DELETE CASCADE,
    
    action TEXT NOT NULL CHECK (action IN ('created', 'slug_changed', 'paused', 'resumed', 'revoked')),
    old_slug TEXT,
    new_slug TEXT,
    reason TEXT,
    performed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_personal_link_audit_link ON public.personal_order_link_audit_logs(personal_order_link_id);

-- 5. 예약된 slug 목록
CREATE TABLE IF NOT EXISTS public.reserved_slugs (
    slug TEXT PRIMARY KEY,
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 기본 예약어 삽입
INSERT INTO public.reserved_slugs (slug, reason) VALUES
('admin', 'System reserved'),
('api', 'System reserved'),
('app', 'System reserved'),
('auth', 'System reserved'),
('login', 'System reserved'),
('logout', 'System reserved'),
('signup', 'System reserved'),
('register', 'System reserved'),
('dashboard', 'System reserved'),
('profile', 'System reserved'),
('settings', 'System reserved'),
('help', 'System reserved'),
('support', 'System reserved'),
('about', 'System reserved'),
('terms', 'System reserved'),
('privacy', 'System reserved'),
('contact', 'System reserved'),
('allsuri', 'Brand reserved'),
('root', 'System reserved'),
('public', 'System reserved'),
('private', 'System reserved'),
('static', 'System reserved'),
('assets', 'System reserved'),
('images', 'System reserved'),
('css', 'System reserved'),
('js', 'System reserved'),
('javascript', 'System reserved')
ON CONFLICT (slug) DO NOTHING;

-- 6. RLS 정책 설정

-- personal_order_links 정책
ALTER TABLE public.personal_order_links ENABLE ROW LEVEL SECURITY;

-- 사업자는 자신의 링크만 조회/수정 가능
CREATE POLICY select_own_personal_links ON public.personal_order_links
    FOR SELECT
    USING (auth.uid() = contractor_id OR auth.role() = 'anon');

CREATE POLICY insert_own_personal_links ON public.personal_order_links
    FOR INSERT
    WITH CHECK (auth.uid() = contractor_id);

CREATE POLICY update_own_personal_links ON public.personal_order_links
    FOR UPDATE
    USING (auth.uid() = contractor_id);

-- 공개 페이지는 익명 사용자도 조회 가능 (slug 기반)
CREATE POLICY select_public_active_links ON public.personal_order_links
    FOR SELECT
    TO anon
    USING (status = 'active');

-- personal_order_link_events 정책
ALTER TABLE public.personal_order_link_events ENABLE ROW LEVEL SECURITY;

-- 링크 소유자만 자신의 분석 이벤트 조회 가능
CREATE POLICY select_own_link_events ON public.personal_order_link_events
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.personal_order_links
            WHERE id = personal_order_link_events.personal_order_link_id
            AND contractor_id = auth.uid()
        )
    );

-- 익명 사용자는 이벤트 삽입만 가능 (읽기 불가)
CREATE POLICY insert_link_events ON public.personal_order_link_events
    FOR INSERT
    WITH CHECK (true);

-- personal_order_link_audit_logs 정책
ALTER TABLE public.personal_order_link_audit_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY select_own_audit_logs ON public.personal_order_link_audit_logs
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.personal_order_links
            WHERE id = personal_order_link_audit_logs.personal_order_link_id
            AND contractor_id = auth.uid()
        )
    );

-- 7. 트리거: updated_at 자동 갱신
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_personal_order_links_updated_at
    BEFORE UPDATE ON public.personal_order_links
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- 8. 트리거: slug 변경 시 감사 로그 자동 생성
CREATE OR REPLACE FUNCTION log_personal_link_changes()
RETURNS TRIGGER AS $$
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

CREATE TRIGGER log_personal_order_link_changes
    AFTER INSERT OR UPDATE ON public.personal_order_links
    FOR EACH ROW
    EXECUTE FUNCTION log_personal_link_changes();

-- 9. 헬퍼 함수: slug 정규화
CREATE OR REPLACE FUNCTION normalize_slug(input_slug TEXT)
RETURNS TEXT AS $$
BEGIN
    RETURN LOWER(TRIM(REGEXP_REPLACE(input_slug, '[^a-zA-Z0-9_-]', '', 'g')));
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- 10. 헬퍼 함수: slug 가용성 확인
CREATE OR REPLACE FUNCTION is_slug_available(check_slug TEXT, exclude_link_id UUID DEFAULT NULL)
RETURNS BOOLEAN AS $$
DECLARE
    normalized TEXT;
    is_reserved BOOLEAN;
    is_taken BOOLEAN;
BEGIN
    normalized := normalize_slug(check_slug);
    
    -- 예약어 확인
    SELECT EXISTS(SELECT 1 FROM public.reserved_slugs WHERE slug = normalized) INTO is_reserved;
    IF is_reserved THEN
        RETURN FALSE;
    END IF;
    
    -- 이미 사용 중인지 확인
    SELECT EXISTS(
        SELECT 1 FROM public.personal_order_links 
        WHERE slug_normalized = normalized 
        AND (exclude_link_id IS NULL OR id != exclude_link_id)
    ) INTO is_taken;
    
    RETURN NOT is_taken;
END;
$$ LANGUAGE plpgsql;

-- 완료 메시지
SELECT '✅ 개인 오더 링크 스키마 생성 완료' AS status;
