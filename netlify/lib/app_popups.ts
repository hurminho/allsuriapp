import { TRADE_GROUP_NAMES, groupOf } from './trade_categories'

/**
 * 앱 팝업(app_popups) 입력 검사와 대상 인원 계산.
 * DB 제약(database/app_popups_featured_2026_10.sql)과 같은 규칙입니다.
 * 앱은 allsuri_my_app_popup() 으로 자기에게 해당하는 팝업 하나만 받습니다.
 */
export type PopupAudience = 'all' | 'trades' | 'selected'
export type PopupFrequency = 'once' | 'daily' | 'always'

export type AppPopupRow = {
  title: string
  body: string
  image_url: string | null
  button_label: string | null
  button_url: string | null
  audience: PopupAudience
  target_trades: string[]
  target_user_ids: string[]
  frequency: PopupFrequency
  is_active: boolean
  start_at: string | null
  end_at: string | null
  priority: number
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

function text(v: unknown): string {
  return String(v ?? '').trim()
}

function optional(v: unknown): string | null {
  const t = text(v)
  return t ? t : null
}

function time(v: unknown, label: string): string | null {
  const t = text(v)
  if (!t) return null
  const d = new Date(t)
  if (Number.isNaN(d.getTime())) throw new Error(`${label} 날짜 형식이 올바르지 않습니다.`)
  return d.toISOString()
}

/** 관리자 페이지 입력 → DB 행. 잘못된 값이면 화면에 그대로 보여 줄 문장으로 Error 를 던집니다. */
export function parsePopupInput(input: Record<string, unknown>): AppPopupRow {
  const title = text(input.title)
  const body = text(input.body)
  if (!title || title.length > 40) throw new Error('제목은 1~40자로 입력해 주세요.')
  if (!body || body.length > 500) throw new Error('내용은 1~500자로 입력해 주세요.')

  const image_url = optional(input.imageUrl)
  if (image_url && !/^https:\/\/\S+$/.test(image_url)) throw new Error('이미지 주소는 https:// 로 시작해야 합니다.')

  const button_url = optional(input.buttonUrl)
  if (button_url && !/^https?:\/\/\S+$/.test(button_url)) throw new Error('버튼 링크는 https:// 로 시작하는 주소로 입력해 주세요.')
  let button_label = optional(input.buttonLabel)
  if (button_label && button_label.length > 20) throw new Error('버튼 글자는 20자 이하로 입력해 주세요.')
  if (button_url && !button_label) button_label = '자세히 보기'
  if (!button_url) button_label = null

  const audience = text(input.audience) as PopupAudience
  if (!['all', 'trades', 'selected'].includes(audience)) throw new Error('대상을 골라 주세요.')
  const target_trades = Array.isArray(input.targetTrades)
    ? [...new Set(input.targetTrades.map(text).filter((t) => TRADE_GROUP_NAMES.includes(t)))]
    : []
  const target_user_ids = Array.isArray(input.targetUserIds)
    ? [...new Set(input.targetUserIds.map(text).filter((id) => UUID.test(id)))]
    : []
  if (audience === 'trades' && target_trades.length === 0) throw new Error('공종을 하나 이상 골라 주세요.')
  if (audience === 'selected' && target_user_ids.length === 0) throw new Error('사업자를 한 명 이상 골라 주세요.')

  const frequency = text(input.frequency || 'once') as PopupFrequency
  if (!['once', 'daily', 'always'].includes(frequency)) throw new Error('보여 주는 빈도를 골라 주세요.')

  const start_at = time(input.startAt, '시작')
  const end_at = time(input.endAt, '종료')
  if (start_at && end_at && end_at <= start_at) throw new Error('종료 일시는 시작 일시보다 뒤여야 합니다.')

  const priority = Number.isFinite(Number(input.priority)) ? Math.trunc(Number(input.priority)) : 0

  return {
    title,
    body,
    image_url,
    button_label,
    button_url,
    audience,
    target_trades: audience === 'trades' ? target_trades : [],
    target_user_ids: audience === 'selected' ? target_user_ids : [],
    frequency,
    is_active: input.isActive !== false,
    start_at,
    end_at,
    priority,
  }
}

export type PopupTargetUser = { id: string; specialties: string[] | null }

/** 팝업을 받을 사람 수 (allsuri_my_app_popup 의 대상 조건과 같음) */
export function countPopupTargets(
  row: Pick<AppPopupRow, 'audience' | 'target_trades' | 'target_user_ids'>,
  users: PopupTargetUser[],
): number {
  if (row.audience === 'all') return users.length
  if (row.audience === 'selected') {
    const ids = new Set(row.target_user_ids)
    return users.filter((u) => ids.has(u.id)).length
  }
  const trades = new Set(row.target_trades)
  return users.filter((u) => (u.specialties ?? []).some((s) => trades.has(groupOf(s)))).length
}
