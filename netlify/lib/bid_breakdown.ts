// 입찰 세부 원가 정규화. 순수 함수라 단위 테스트로 검증합니다.
//
// 사업자에게 긴 설문을 받지 않고, 견적을 쓰는 행위 자체가 구조화된 가격 데이터를
// 남기도록 하는 게 목적입니다. 그래서 세부 항목은 전부 선택 입력이고,
// 총액만 넣어도 입찰은 그대로 성립합니다(breakdown_provided=false).

export const BID_AVAILABILITIES = [
  'today',
  'tomorrow',
  'within_3days',
  'this_week',
  'scheduled',
] as const
export type BidAvailability = (typeof BID_AVAILABILITIES)[number]

export type NormalizedBid = {
  /** order_bids 에 그대로 넣을 수 있는 컬럼 맵 (undefined 키는 제외됨) */
  columns: Record<string, unknown>
  totalAmount: number | null
  breakdownProvided: boolean
  /** 사업자에게 돌려줄 안내. 입찰을 막지는 않습니다. */
  warnings: string[]
}

function pick(raw: Record<string, any>, ...keys: string[]): unknown {
  for (const key of keys) {
    if (raw[key] !== undefined && raw[key] !== null && raw[key] !== '') return raw[key]
  }
  return undefined
}

function money(value: unknown): number | null {
  if (value === undefined || value === null || value === '') return null
  const n = Number(String(value).replace(/[,\s원]/g, ''))
  if (!Number.isFinite(n) || n < 0) return null
  return Math.round(n)
}

function hours(value: unknown): number | null {
  if (value === undefined || value === null || value === '') return null
  const n = Number(value)
  if (!Number.isFinite(n) || n <= 0 || n > 240) return null
  return Math.round(n * 10) / 10
}

function months(value: unknown): number | null {
  if (value === undefined || value === null || value === '') return null
  const n = Number(value)
  if (!Number.isFinite(n) || n < 0 || n > 120) return null
  return Math.round(n)
}

function bool(value: unknown): boolean | null {
  if (value === true || value === 'true' || value === 1 || value === '1') return true
  if (value === false || value === 'false' || value === 0 || value === '0') return false
  return null
}

function availability(value: unknown): BidAvailability | null {
  const s = String(value ?? '').trim()
  if (!s) return null
  if ((BID_AVAILABILITIES as readonly string[]).includes(s)) return s as BidAvailability
  if (/오늘/.test(s)) return 'today'
  if (/내일/.test(s)) return 'tomorrow'
  if (/3일|삼일/.test(s)) return 'within_3days'
  if (/이번\s*주/.test(s)) return 'this_week'
  if (/협의|일정/.test(s)) return 'scheduled'
  return null
}

/** 총액과 세부 항목이 어긋나도 입찰을 거부하지 않습니다. 경고만 남기고 총액을 신뢰합니다. */
export function normalizeBidBreakdown(raw: Record<string, any>): NormalizedBid {
  const visitFee = money(pick(raw, 'visitFee', 'visit_fee'))
  const laborCost = money(pick(raw, 'laborCost', 'labor_cost'))
  const materialCost = money(pick(raw, 'materialCost', 'material_cost'))
  const additionalCost = money(pick(raw, 'additionalCost', 'additional_cost'))
  const explicitTotal = money(pick(raw, 'bidAmount', 'bid_amount', 'totalBidAmount', 'total_bid_amount'))

  const parts = [visitFee, laborCost, materialCost, additionalCost]
  const providedParts = parts.filter((p): p is number => p != null)
  const partsSum = providedParts.reduce((sum, n) => sum + n, 0)
  // 인건비 또는 자재비가 있으면 "세부 항목을 낸 입찰"로 봅니다.
  const breakdownProvided = laborCost != null || materialCost != null

  const warnings: string[] = []
  let totalAmount = explicitTotal

  if (totalAmount == null && providedParts.length > 0 && partsSum > 0) {
    totalAmount = partsSum
  } else if (
    totalAmount != null &&
    breakdownProvided &&
    providedParts.length >= 2 &&
    Math.abs(partsSum - totalAmount) > 1000
  ) {
    warnings.push(
      `세부 항목 합계(${partsSum.toLocaleString()}원)와 총 견적가(${totalAmount.toLocaleString()}원)가 다릅니다. 총 견적가로 저장했습니다.`,
    )
  }

  if (totalAmount != null && !breakdownProvided) {
    warnings.push('인건비·자재비를 나눠 적으면 고객이 금액을 더 신뢰하고, 지역 시장 리포트도 열립니다.')
  }

  const columns: Record<string, unknown> = {}
  const set = (key: string, value: unknown) => {
    if (value !== null && value !== undefined) columns[key] = value
  }
  set('visit_fee', visitFee)
  set('labor_cost', laborCost)
  set('material_cost', materialCost)
  set('additional_cost', additionalCost)
  set('additional_note', (() => {
    const note = pick(raw, 'additionalNote', 'additional_note')
    return note ? String(note).slice(0, 500) : null
  })())
  set('vat_included', bool(pick(raw, 'vatIncluded', 'vat_included')))
  set('estimated_hours', hours(pick(raw, 'estimatedHours', 'estimated_hours')))
  set('as_period_months', months(pick(raw, 'asPeriodMonths', 'as_period_months', 'asPeriod')))
  set('availability', availability(pick(raw, 'availability')))
  set('site_visit_required', bool(pick(raw, 'siteVisitRequired', 'site_visit_required')))
  const tags = pick(raw, 'workScopeTags', 'work_scope_tags')
  if (Array.isArray(tags) && tags.length) {
    set('work_scope_tags', tags.map((t) => String(t)).filter(Boolean).slice(0, 20))
  }
  columns.breakdown_provided = breakdownProvided

  return { columns, totalAmount, breakdownProvided, warnings }
}
