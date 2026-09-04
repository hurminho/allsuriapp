import { describe, expect, it } from 'vitest'
import { normalizeBidBreakdown } from '../lib/bid_breakdown'

describe('normalizeBidBreakdown', () => {
  it('총액만 보내도 입찰이 성립하고 세부 항목 안내를 남깁니다', () => {
    const result = normalizeBidBreakdown({ bid_amount: 120000 })
    expect(result.totalAmount).toBe(120000)
    expect(result.breakdownProvided).toBe(false)
    expect(result.columns.breakdown_provided).toBe(false)
    expect(result.warnings.join()).toContain('인건비·자재비')
  })

  it('세부 항목만 보내면 총액을 합산합니다', () => {
    const result = normalizeBidBreakdown({
      visitFee: 15000,
      laborCost: 70000,
      materialCost: 30000,
      additionalCost: 5000,
    })
    expect(result.totalAmount).toBe(120000)
    expect(result.breakdownProvided).toBe(true)
    expect(result.warnings).toHaveLength(0)
  })

  it('합계와 총액이 다르면 총액을 신뢰하고 경고만 남깁니다', () => {
    const result = normalizeBidBreakdown({
      bidAmount: 200000,
      laborCost: 70000,
      materialCost: 30000,
    })
    expect(result.totalAmount).toBe(200000)
    expect(result.warnings.join()).toContain('다릅니다')
  })

  it('camelCase 와 snake_case 를 모두 받습니다', () => {
    const camel = normalizeBidBreakdown({ visitFee: 10000, laborCost: 50000 })
    const snake = normalizeBidBreakdown({ visit_fee: 10000, labor_cost: 50000 })
    expect(camel.columns.visit_fee).toBe(snake.columns.visit_fee)
    expect(camel.columns.labor_cost).toBe(snake.columns.labor_cost)
  })

  it('쉼표·원 표기를 포함한 문자열 금액을 받습니다', () => {
    const result = normalizeBidBreakdown({ bid_amount: '1,200,000원' })
    expect(result.totalAmount).toBe(1200000)
  })

  it('음수와 빈 값은 저장하지 않습니다', () => {
    const result = normalizeBidBreakdown({ visitFee: -5000, laborCost: '', materialCost: null })
    expect(result.columns.visit_fee).toBeUndefined()
    expect(result.columns.labor_cost).toBeUndefined()
    expect(result.totalAmount).toBeNull()
  })

  it('예상 작업 시간은 상식 범위를 벗어나면 버립니다', () => {
    expect(normalizeBidBreakdown({ estimatedHours: 2.5 }).columns.estimated_hours).toBe(2.5)
    expect(normalizeBidBreakdown({ estimatedHours: 0 }).columns.estimated_hours).toBeUndefined()
    expect(normalizeBidBreakdown({ estimatedHours: 999 }).columns.estimated_hours).toBeUndefined()
  })

  it('AS 기간은 개월 정수로 정규화합니다', () => {
    expect(normalizeBidBreakdown({ asPeriod: '6' }).columns.as_period_months).toBe(6)
    expect(normalizeBidBreakdown({ as_period_months: 200 }).columns.as_period_months).toBeUndefined()
  })

  it('방문 가능 시점은 한국어 표현도 받습니다', () => {
    expect(normalizeBidBreakdown({ availability: '오늘 가능' }).columns.availability).toBe('today')
    expect(normalizeBidBreakdown({ availability: '이번 주 중' }).columns.availability).toBe('this_week')
    expect(normalizeBidBreakdown({ availability: 'within_3days' }).columns.availability).toBe('within_3days')
    expect(normalizeBidBreakdown({ availability: '아무때나' }).columns.availability).toBeUndefined()
  })

  it('부가세·현장 확인 여부는 boolean 으로 정규화합니다', () => {
    expect(normalizeBidBreakdown({ vatIncluded: 'true' }).columns.vat_included).toBe(true)
    expect(normalizeBidBreakdown({ siteVisitRequired: false }).columns.site_visit_required).toBe(false)
    expect(normalizeBidBreakdown({ vatIncluded: '아마도' }).columns.vat_included).toBeUndefined()
  })

  it('빈 요청도 안전하게 처리합니다', () => {
    const result = normalizeBidBreakdown({})
    expect(result.totalAmount).toBeNull()
    expect(result.breakdownProvided).toBe(false)
    expect(Object.keys(result.columns)).toEqual(['breakdown_provided'])
  })

  it('작업 범위 태그는 최대 20개까지', () => {
    const tags = Array.from({ length: 30 }, (_, i) => `태그${i}`)
    const result = normalizeBidBreakdown({ workScopeTags: tags })
    expect((result.columns.work_scope_tags as string[]).length).toBe(20)
  })
})
