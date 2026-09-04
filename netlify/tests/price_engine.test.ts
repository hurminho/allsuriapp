import { describe, expect, it } from 'vitest'
import { DEFAULT_SETTINGS, DEFAULT_TRADES } from '../lib/price_catalog'
import { baselineToSamples, computePrice, type PriceSample } from '../lib/price_engine'

const NOW = new Date('2026-09-01T00:00:00.000Z')
const toiletClog = DEFAULT_TRADES.find((t) => t.id === 'plumbing.toilet_clog')!

function daysAgo(days: number): string {
  return new Date(NOW.getTime() - days * 86400000).toISOString()
}

function completed(value: number, days = 30, extra: Partial<PriceSample> = {}): PriceSample {
  return {
    source: 'completed_job',
    value,
    occurredAt: daysAgo(days),
    regionLevel1: '서울',
    regionLevel2: '강남구',
    propertyType: 'apartment',
    workScopeTags: ['관통 작업'],
    ...extra,
  }
}

function bid(value: number, days = 30, hasBreakdown = true): PriceSample {
  return {
    source: 'contractor_bid',
    value,
    occurredAt: daysAgo(days),
    workScopeTags: ['관통 작업'],
    hasBreakdown,
  }
}

const run = (samples: PriceSample[], request = {}) =>
  computePrice({ trade: toiletClog, request, samples, settings: DEFAULT_SETTINGS, now: NOW })

describe('데이터 부족 처리', () => {
  it('공정을 확정하지 못하면 금액을 만들지 않습니다', () => {
    const result = computePrice({
      trade: null,
      request: {},
      samples: [completed(80000)],
      settings: DEFAULT_SETTINGS,
      now: NOW,
    })
    expect(result.priceState).toBe('insufficient')
    expect(result.estimatedMin).toBeNull()
    expect(result.estimatedMax).toBeNull()
    expect(result.insufficientReason).toBe('unknown_trade')
  })

  it('표본이 없으면 insufficient', () => {
    const result = run([])
    expect(result.priceState).toBe('insufficient')
    expect(result.insufficientReason).toBe('no_samples')
    expect(result.estimatedTypical).toBeNull()
  })

  it('표본이 임계값 미달이면 숫자를 내지 않습니다', () => {
    const result = run([completed(80000), completed(90000)])
    expect(result.priceState).toBe('insufficient')
    expect(result.insufficientReason).toBe('below_threshold')
    expect(result.estimatedMin).toBeNull()
  })

  it('sanity 범위 밖 표본만 있으면 insufficient', () => {
    const result = run([completed(500), completed(700), completed(900), completed(1100)])
    expect(result.priceState).toBe('insufficient')
    expect(result.droppedOutlierCount).toBe(4)
  })

  it('오래된 표본(최대 기간 초과)은 가중치 0 이라 쓰이지 않습니다', () => {
    const result = run([completed(80000, 900), completed(85000, 900), completed(90000, 900)])
    expect(result.priceState).toBe('insufficient')
  })
})

describe('preliminary 상태', () => {
  it('표본 3건이면 참고 범위를 넓게 잡습니다', () => {
    const result = run([completed(80000), completed(90000), completed(100000)])
    expect(result.priceState).toBe('preliminary')
    expect(result.estimatedMin).toBeLessThan(result.estimatedTypical as number)
    expect(result.estimatedMax).toBeGreaterThan(result.estimatedTypical as number)
    expect(result.confidenceLevel).not.toBe('high')
    expect(result.disclaimer).toContain('참고 금액')
  })

  it('기준표만 있으면 3개 표본으로 펼쳐 참고 범위가 됩니다', () => {
    const samples = baselineToSamples({
      min_amount: 65000,
      typical_amount: 95000,
      max_amount: 165000,
      updated_at: daysAgo(10),
    })
    const result = run(samples)
    expect(result.priceState).toBe('preliminary')
    expect(result.confidenceLevel).toBe('low')
    expect(result.basis[0].source).toBe('baseline')
    expect(result.completedJobCount).toBe(0)
  })
})

describe('sufficient 상태', () => {
  const many = Array.from({ length: 10 }, (_, i) => completed(75000 + i * 3000, 20 + i))

  it('완료 거래가 임계값을 넘으면 sufficient', () => {
    const result = run(many, { regionLevel1: '서울', regionLevel2: '강남구' })
    expect(result.priceState).toBe('sufficient')
    expect(result.completedJobCount).toBe(10)
    expect(result.estimatedMin).toBeGreaterThan(0)
    expect(result.estimatedMax).toBeGreaterThan(result.estimatedMin as number)
    expect(result.disclaimer).toContain('최근 유사 완료 사례')
  })

  it('천원 단위로 반올림합니다', () => {
    const result = run(many)
    for (const value of [result.estimatedMin, result.estimatedTypical, result.estimatedMax]) {
      expect((value as number) % 1000).toBe(0)
    }
  })

  it('근거에 출처별 표본 수와 가중치 비중이 담깁니다', () => {
    const result = run([...many, bid(120000), bid(130000)])
    const sources = result.basis.map((b) => b.source)
    expect(sources).toContain('completed_job')
    expect(sources).toContain('contractor_bid')
    const total = result.basis.reduce((sum, b) => sum + b.weightShare, 0)
    expect(total).toBeGreaterThan(0.98)
    expect(total).toBeLessThan(1.02)
  })

  it('엔진 버전을 항상 담습니다', () => {
    expect(run(many).engineVersion).toBe('v1')
  })
})

describe('완료 금액 우선 사용', () => {
  it('같은 표본 수라면 완료 금액이 입찰가보다 대표값을 더 끕니다', () => {
    const completedLow = Array.from({ length: 6 }, () => completed(70000))
    const bidsHigh = Array.from({ length: 6 }, () => bid(200000))
    const mixed = run([...completedLow, ...bidsHigh])
    const bidsOnly = run(Array.from({ length: 12 }, () => bid(200000)))
    expect(mixed.estimatedTypical as number).toBeLessThan(bidsOnly.estimatedTypical as number)
  })

  it('세부 항목 없는 입찰은 가중치가 낮습니다', () => {
    const withBreakdown = run(Array.from({ length: 12 }, () => bid(100000, 30, true)))
    const withoutBreakdown = run(Array.from({ length: 12 }, () => bid(100000, 30, false)))
    expect(withoutBreakdown.weightedEvidence).toBeLessThan(withBreakdown.weightedEvidence)
  })

  it('입찰가만 있으면 신뢰도가 high 가 되지 않습니다', () => {
    const result = run(Array.from({ length: 40 }, (_, i) => bid(90000 + i * 500, 10)))
    expect(result.confidenceLevel).not.toBe('high')
  })
})

describe('조건 반영', () => {
  it('긴급 요청은 카탈로그 가산이 적용되고 요인에 표시됩니다', () => {
    const many = Array.from({ length: 10 }, () => completed(80000))
    const normal = run(many, { urgency: 'normal' })
    const emergency = run(many, { urgency: 'emergency' })
    expect(emergency.estimatedTypical as number).toBeGreaterThan(normal.estimatedTypical as number)
    expect(emergency.adjustments.map((a) => a.label)).toContain('긴급 출동 가산')
    expect(emergency.factors).toContain('긴급 출동 가산')
  })

  it('긴급 가산이 없는 공정은 금액이 그대로입니다', () => {
    const silicone = DEFAULT_TRADES.find((t) => t.id === 'waterproof.silicone_caulking')!
    const samples = Array.from({ length: 10 }, () => ({
      source: 'completed_job' as const,
      value: 90000,
      occurredAt: daysAgo(20),
    }))
    const base = computePrice({ trade: silicone, request: {}, samples, settings: DEFAULT_SETTINGS, now: NOW })
    const urgent = computePrice({
      trade: silicone,
      request: { urgency: 'emergency' },
      samples,
      settings: DEFAULT_SETTINGS,
      now: NOW,
    })
    expect(urgent.estimatedTypical).toBe(base.estimatedTypical)
    expect(urgent.adjustments).toHaveLength(0)
  })

  it('방문이 필요 없으면 출장비를 뺍니다', () => {
    const many = Array.from({ length: 10 }, () => completed(80000))
    const withVisit = run(many, { visitRequired: true })
    const withoutVisit = run(many, { visitRequired: false })
    expect(withoutVisit.estimatedTypical as number).toBeLessThan(withVisit.estimatedTypical as number)
    expect(withoutVisit.adjustments.map((a) => a.label)).toContain('출장비 제외')
  })

  it('지역이 일치하면 신뢰도가 더 높습니다', () => {
    const samples = Array.from({ length: 10 }, () => completed(80000))
    const match = run(samples, { regionLevel1: '서울', regionLevel2: '강남구' })
    const mismatch = run(samples, { regionLevel1: '부산', regionLevel2: '해운대구' })
    expect(match.confidenceScore).toBeGreaterThan(mismatch.confidenceScore)
  })

  it('접근 난이도가 높으면 변동 요인으로 표시합니다', () => {
    const result = run(Array.from({ length: 10 }, () => completed(80000)), {
      accessDifficulty: 'hard',
    })
    expect(result.factors).toContain('현장 접근 난이도')
  })

  it('부가세 포함 여부가 섞여 있으면 요인에 표시합니다', () => {
    const samples = [
      ...Array.from({ length: 5 }, () => completed(80000, 30, { vatIncluded: true })),
      ...Array.from({ length: 5 }, () => completed(85000, 30, { vatIncluded: false })),
    ]
    expect(run(samples).factors).toContain('부가세 포함 여부(업체별 상이)')
  })
})

describe('이상치 제거가 결과에 반영됩니다', () => {
  it('오입력된 큰 금액이 대표값을 끌어올리지 않습니다', () => {
    const clean = Array.from({ length: 10 }, (_, i) => completed(78000 + i * 2000))
    const polluted = [...clean, completed(750000)]
    const a = run(clean)
    const b = run(polluted)
    expect(b.droppedOutlierCount).toBeGreaterThan(0)
    expect(b.estimatedTypical).toBe(a.estimatedTypical)
  })

  it('제거된 표본 수를 보고합니다', () => {
    const result = run([...Array.from({ length: 10 }, () => completed(80000)), completed(9_999_999)])
    expect(result.droppedOutlierCount).toBe(1)
  })
})

describe('baselineToSamples', () => {
  it('0 이하 값은 표본에서 제외', () => {
    const samples = baselineToSamples({ min_amount: 0, typical_amount: 90000, max_amount: 150000 })
    expect(samples).toHaveLength(2)
    expect(samples.every((s) => s.source === 'baseline')).toBe(true)
  })
})

describe('데이터 소스 우선순위 사다리', () => {
  it('완료 거래만으로 충분하면 입찰가를 아예 쓰지 않습니다', () => {
    const samples = [
      ...[95000, 98000, 100000, 100000, 100000, 101000, 102000, 105000].map((v) => completed(v, 10)),
      // 건수는 훨씬 많고 금액은 3배지만 계산에서 빠져야 합니다.
      ...Array.from({ length: 20 }, (_, i) => bid(300000 + i * 1000, i + 1)),
    ]
    const result = run(samples)
    expect(result.priceState).toBe('sufficient')
    expect(result.completedJobCount).toBe(8)
    expect(result.estimatedMax).toBeLessThan(150000)

    const bids = result.basis.find((b) => b.source === 'contractor_bid')!
    expect(bids.sampleCount).toBe(20)
    expect(bids.usedSampleCount).toBe(0)
    expect(bids.weightShare).toBe(0)
  })

  it('완료 거래가 부족하면 입찰가로 내려갑니다', () => {
    const result = run([completed(100000, 10), ...Array.from({ length: 6 }, (_, i) => bid(120000 + i * 1000, i + 1))])
    const bids = result.basis.find((b) => b.source === 'contractor_bid')!
    expect(bids.usedSampleCount).toBe(6)
    expect(result.estimatedTypical).toBeGreaterThan(0)
  })

  it('입찰 건수가 많아도 완료 거래를 밀어내지 못합니다', () => {
    const samples = [
      ...[95000, 100000, 105000].map((v) => completed(v, 10)),
      ...Array.from({ length: 30 }, (_, i) => bid(300000 + i * 1000, i + 1)),
    ]
    const result = run(samples)
    const done = result.basis.find((b) => b.source === 'completed_job')!
    const bids = result.basis.find((b) => b.source === 'contractor_bid')!
    // lowerTierWeightCap(0.6) 때문에 하위 소스 합계가 완료 거래를 넘지 못합니다.
    expect(done.weightShare).toBeGreaterThan(bids.weightShare)
    expect(result.estimatedTypical).toBeLessThan(150000)
  })

  it('완료 거래가 없으면 표준 단가·기준표 순서로 내려갑니다', () => {
    const rateCards: PriceSample[] = Array.from({ length: 4 }, (_, i) => ({
      source: 'rate_card',
      value: 85000 + i * 3000,
      occurredAt: daysAgo(i + 1),
    }))
    const baselines = baselineToSamples({
      min_amount: 60000,
      typical_amount: 90000,
      max_amount: 140000,
      updated_at: daysAgo(5),
    })
    const result = run([...rateCards, ...baselines])
    expect(result.priceState).toBe('preliminary')
    const cards = result.basis.find((b) => b.source === 'rate_card')!
    const base = result.basis.find((b) => b.source === 'baseline')!
    expect(cards.weightShare).toBeGreaterThan(base.weightShare)
  })

  it('이상치 판정은 소스별로 따로 합니다', () => {
    // 입찰가 무리가 완료 금액 전체를 이상치로 지워버리면 안 됩니다.
    const samples = [
      ...[95000, 100000, 105000].map((v) => completed(v, 10)),
      ...Array.from({ length: 30 }, (_, i) => bid(300000 + i * 500, i + 1)),
    ]
    const result = run(samples)
    expect(result.basis.find((b) => b.source === 'completed_job')!.usedSampleCount).toBe(3)
  })
})
