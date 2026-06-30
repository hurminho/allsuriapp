-- ============================================================
-- 자동 완료 처리 비활성화
-- Supabase SQL Editor에서 실행하세요.
-- (등록되지 않은 cron job은 건너뜁니다 — 에러 없음)
-- ============================================================

-- pg_cron 스케줄 제거 (존재하는 job만)
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT jobid, jobname
    FROM cron.job
    WHERE jobname IN ('auto-complete-jobs-5days', 'daily-auto-complete-jobs')
  LOOP
    PERFORM cron.unschedule(r.jobid);
    RAISE NOTICE 'Unscheduled cron job: % (jobid=%)', r.jobname, r.jobid;
  END LOOP;
END $$;

-- 자동완료 함수 제거
DROP FUNCTION IF EXISTS public.auto_complete_jobs_after_5days();
DROP FUNCTION IF EXISTS public.auto_complete_old_assigned_jobs();

-- 등록된 cron job 확인 (0 rows = 정상)
SELECT jobid, jobname, schedule, command, active
FROM cron.job
WHERE jobname IN ('auto-complete-jobs-5days', 'daily-auto-complete-jobs');

SELECT '✅ 자동 완료 처리(cron + 함수)가 비활성화되었습니다.' AS result;
