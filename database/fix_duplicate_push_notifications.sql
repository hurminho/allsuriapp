-- ============================================================
-- 푸시 알림 중복 발송 방지 (idempotency 가드)
--
-- 배경: notifications INSERT → Supabase Database Webhook →
--       notifications-send-push.ts 가 FCM 발송을 담당하는 구조인데,
--       webhook 응답 지연/재시도(retry) 또는 대시보드에 중복 webhook이
--       설정된 경우 같은 notifications row에 대해 FCM이 2번 발송될 수 있다.
--
-- 해결: notifications 테이블에 push_sent_at 컬럼을 추가하고,
--       webhook 핸들러가 "push_sent_at IS NULL" 조건으로 원자적으로
--       claim(UPDATE ... WHERE push_sent_at IS NULL RETURNING)한 뒤에만
--       FCM을 발송하도록 한다. 이미 처리된 row라면 즉시 스킵.
--
-- Supabase SQL Editor에서 실행하세요.
-- ============================================================

ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS push_sent_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_notifications_push_sent_at
  ON public.notifications(push_sent_at)
  WHERE push_sent_at IS NULL;

SELECT '✅ notifications.push_sent_at 컬럼 및 인덱스 추가 완료' AS result;
