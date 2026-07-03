-- ============================================================
-- 앱 강제/선택 업데이트 관리용 버전 정보 테이블
-- Supabase SQL Editor에서 실행하세요.
--
-- 앱(lib/services/version_service.dart)은 이 테이블의 id=1 행을 조회해
-- 현재 설치된 버전과 비교, 강제/선택 업데이트 여부를 판단합니다.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.app_version (
  id INT PRIMARY KEY DEFAULT 1,
  latest_version TEXT NOT NULL,
  minimum_supported_version TEXT NOT NULL,
  force_update BOOLEAN NOT NULL DEFAULT false,
  android_store_url TEXT,
  ios_store_url TEXT,
  update_message TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT app_version_singleton CHECK (id = 1)
);

COMMENT ON TABLE public.app_version IS '앱 인앱 업데이트 체크용 버전 정보 (단일 행, id=1 고정)';
COMMENT ON COLUMN public.app_version.latest_version IS '스토어에 배포된 최신 버전 (예: 1.4.2)';
COMMENT ON COLUMN public.app_version.minimum_supported_version IS '이 버전 미만이면 무조건 강제 업데이트 (예: 1.3.0)';
COMMENT ON COLUMN public.app_version.force_update IS 'true면 최신 버전이 아닌 모든 사용자에게 강제 업데이트 요구';

-- 초기 데이터 삽입 (이미 있으면 건너뜀) — 현재 배포 버전(1.0.6)에 맞춰 최초 값 세팅
-- ⚠️ ios_store_url의 id123456789 부분은 실제 App Store 앱 ID로 교체하세요.
INSERT INTO public.app_version (
  id, latest_version, minimum_supported_version, force_update,
  android_store_url, ios_store_url, update_message
) VALUES (
  1,
  '1.0.6',
  '1.0.0',
  false,
  'market://details?id=com.allsuri.app',
  'itms-apps://itunes.apple.com/app/id123456789',
  '더 안정적인 사용을 위해 최신 버전으로 업데이트해 주세요.'
)
ON CONFLICT (id) DO NOTHING;

-- RLS 활성화: 로그인 전(스플래시 단계)에도 조회해야 하므로 익명 사용자에게도 SELECT 허용
ALTER TABLE public.app_version ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS select_app_version ON public.app_version;
CREATE POLICY select_app_version ON public.app_version
FOR SELECT
TO authenticated, anon
USING (true);

-- INSERT/UPDATE/DELETE 정책은 만들지 않습니다 (기본적으로 차단됨).
-- 새 버전을 배포할 때는 Supabase 콘솔(Table Editor) 또는 서비스 롤 키로만 아래처럼 갱신하세요:
--
-- UPDATE public.app_version
-- SET latest_version = '1.1.0',
--     minimum_supported_version = '1.0.0',
--     force_update = false,
--     update_message = '새로운 기능이 추가되었습니다!',
--     updated_at = NOW()
-- WHERE id = 1;
--
-- 특정 버전 이하 사용자에게 강제 업데이트를 걸고 싶다면:
-- UPDATE public.app_version SET minimum_supported_version = '1.1.0', updated_at = NOW() WHERE id = 1;

SELECT '✅ app_version 테이블 생성 및 초기 데이터 설정 완료' AS result;
