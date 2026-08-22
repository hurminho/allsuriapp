/**
 * 웹 고객 LMS 문구 설정.
 *
 * Solapi 콘솔의 알림톡 템플릿이 아닙니다. 일반 문자는 여기서 상태(이벤트)별로
 * 본문과 #{변수}를 바꿉니다. 배포 없이 바꾸려면 Netlify 환경변수로 덮어씁니다.
 *
 *   SOLAPI_SMS_TPL_BID_RECEIVED
 *   SOLAPI_SMS_TPL_AWARDED
 *   SOLAPI_SMS_TPL_WORK_DONE
 *
 * 사용 가능한 변수 (템플릿마다 채워지는 값이 다름):
 *   #{오더명} #{상호} #{견적가} #{평점} #{연락처} #{링크}
 */

export type SmsTemplateId = 'bid_received' | 'awarded' | 'work_done'

/** 오더 status → 문자 템플릿 */
export const SMS_TEMPLATE_BY_STATUS: Record<string, SmsTemplateId> = {
  bidding: 'bid_received',
  in_progress: 'awarded',
  awaiting_confirmation: 'work_done',
}

export const SMS_TEMPLATES: Record<SmsTemplateId, string> = {
  bid_received: [
    '[올수리] 새 견적이 도착했습니다.',
    '',
    '요청: #{오더명}',
    '상호: #{상호}',
    '견적가: #{견적가}',
    '평점: #{평점}',
    '',
    '아래 링크에서 견적을 비교·확인할 수 있습니다.',
    '#{링크}',
  ].join('\n'),

  awarded: [
    '[올수리] 사업자가 선정되었습니다.',
    '',
    '요청: #{오더명}',
    '상호: #{상호}',
    '연락처: #{연락처}',
    '',
    '공사 진행 안내는 아래 링크에서 확인하세요.',
    '#{링크}',
  ].join('\n'),

  work_done: [
    '[올수리] 공사가 완료되었습니다.',
    '',
    '요청: #{오더명}',
    '',
    '웹에서 완료를 확인하신 뒤, 사업자 평점을 남겨 주세요.',
    '#{링크}',
  ].join('\n'),
}

export const SMS_TEMPLATE_ENV_KEYS: Record<SmsTemplateId, string> = {
  bid_received: 'SOLAPI_SMS_TPL_BID_RECEIVED',
  awarded: 'SOLAPI_SMS_TPL_AWARDED',
  work_done: 'SOLAPI_SMS_TPL_WORK_DONE',
}
