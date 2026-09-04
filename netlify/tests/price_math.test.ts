import { describe, expect, it } from 'vitest'
import {
  confidenceLevel,
  confidenceScore,
  median,
  percentile,
  recencyWeight,
  removeOutliers,
  roundToUnit,
  scopeMatchWeight,
  weightedPercentile,
  widenRange,
} from '../lib/price_math'

const OUTLIER_OPTS = {
  sanityMin: 20000,
  sanityMax: 800000,
  iqrMultiplier: 1.5,
  iqrMinSamples: 8,
  madMultiplier: 3.5,
  madMinSamples: 5,
}

describe('median / percentile', () => {
  it('빈 배열은 null', () => {
    expect(median([])).toBeNull()
    expect(percentile([], 0.5)).toBeNull()
  })

  it('짝수 개는 중앙 두 값의 평균', () => {
    expect(median([10, 20, 30, 40])).toBe(25)
  })

  it('백분위는 선형보간', () => {
    expect(percentile([100, 200, 300, 400, 500], 0.5)).toBe(300)
    expect(percentile([100, 200], 0.5)).toBe(150)
  })
})

describe('weightedPercentile', () => {
  it('가중치가 큰 값 쪽으로 대표값이 끌립니다', () => {
    const light = weightedPercentile(
      [
        { value: 50000, weight: 1 },
        { value: 200000, weight: 1 },
      ],
      0.5,
    )
    const heavy = weightedPercentile(
      [
        { value: 50000, weight: 1 },
        { value: 200000, weight: 9 },
      ],
      0.5,
    )
    expect(light).not.toBeNull()
    expect(heavy).not.toBeNull()
    expect(heavy as number).toBeGreaterThan(light as number)
  })

  it('가중치 0 표본은 무시', () => {
    expect(
      weightedPercentile(
        [
          { value: 999999, weight: 0 },
          { value: 80000, weight: 1 },
        ],
        0.5,
      ),
    ).toBe(80000)
  })

  it('표본이 없으면 null', () => {
    expect(weightedPercentile([], 0.5)).toBeNull()
    expect(weightedPercentile([{ value: 100, weight: 0 }], 0.5)).toBeNull()
  })
})

describe('removeOutliers', () => {
  it('0 이하와 sanity 범위 밖을 이유와 함께 제거', () => {
    const { kept, dropped } = removeOutliers(
      [{ value: -1 }, { value: 0 }, { value: 5000 }, { value: 9_000_000 }, { value: 80000 }],
      OUTLIER_OPTS,
    )
    expect(kept.map((k) => k.value)).toEqual([80000])
    expect(dropped.map((d) => d.reason).sort()).toEqual([
      'above_sanity_max',
      'below_sanity_min',
      'non_positive',
      'non_positive',
    ])
  })

  it('표본이 충분하면 IQR 로 극단값을 제거', () => {
    const values = [70000, 75000, 78000, 80000, 82000, 85000, 88000, 90000, 700000]
    const { kept, dropped } = removeOutliers(
      values.map((value) => ({ value })),
      OUTLIER_OPTS,
    )
    expect(kept.map((k) => k.value)).not.toContain(700000)
    expect(dropped.some((d) => d.reason === 'iqr_outlier')).toBe(true)
  })

  it('표본이 적으면 MAD 로 제거', () => {
    const values = [80000, 81000, 82000, 83000, 600000]
    const { kept, dropped } = removeOutliers(
      values.map((value) => ({ value })),
      OUTLIER_OPTS,
    )
    expect(kept).toHaveLength(4)
    expect(dropped[0].reason).toBe('mad_outlier')
  })

  it('표본이 아주 적으면 아무것도 버리지 않습니다', () => {
    const { kept, dropped } = removeOutliers([{ value: 50000 }, { value: 300000 }], OUTLIER_OPTS)
    expect(kept).toHaveLength(2)
    expect(dropped).toHaveLength(0)
  })
})

describe('recencyWeight', () => {
  it('최근일수록 크고, 최대 기간을 넘으면 0', () => {
    expect(recencyWeight(10, 540)).toBe(1)
    expect(recencyWeight(120, 540)).toBe(0.8)
    expect(recencyWeight(300, 540)).toBe(0.6)
    expect(recencyWeight(500, 540)).toBe(0.35)
    expect(recencyWeight(600, 540)).toBe(0)
  })
})

describe('scopeMatchWeight', () => {
  it('요청 태그가 없으면 감점하지 않습니다', () => {
    expect(scopeMatchWeight([], ['관통 작업'])).toBe(1)
  })

  it('완전 일치가 부분 일치보다 큽니다', () => {
    const exact = scopeMatchWeight(['관통 작업'], ['관통 작업'])
    const partial = scopeMatchWeight(['관통 작업'], ['관통 작업', '고압 세척'])
    const none = scopeMatchWeight(['관통 작업'], ['실리콘 재시공'])
    expect(exact).toBeGreaterThan(partial)
    expect(partial).toBeGreaterThan(none)
  })
})

describe('confidence', () => {
  it('표본이 많고 실거래 비중이 높으면 high', () => {
    const score = confidenceScore({
      weightedEvidence: 20,
      sufficientWeightedEvidence: 12,
      completedJobShare: 0.9,
      averageRecency: 1,
      averageRegionMatch: 1,
      averageScopeMatch: 1,
    })
    expect(confidenceLevel(score, 0.9)).toBe('high')
  })

  it('실거래가 없으면 점수가 높아도 high 를 주지 않습니다', () => {
    const score = confidenceScore({
      weightedEvidence: 30,
      sufficientWeightedEvidence: 12,
      completedJobShare: 0,
      averageRecency: 1,
      averageRegionMatch: 1,
      averageScopeMatch: 1,
    })
    expect(confidenceLevel(score, 0)).not.toBe('high')
  })

  it('표본이 거의 없으면 low', () => {
    const score = confidenceScore({
      weightedEvidence: 0.5,
      sufficientWeightedEvidence: 12,
      completedJobShare: 0,
      averageRecency: 0.35,
      averageRegionMatch: 0,
      averageScopeMatch: 0.5,
    })
    expect(confidenceLevel(score, 0)).toBe('low')
  })
})

describe('roundToUnit / widenRange', () => {
  it('천원 단위로 반올림', () => {
    expect(roundToUnit(83400, 1000)).toBe(83000)
    expect(roundToUnit(83600, 1000)).toBe(84000)
  })

  it('참고 범위는 양쪽으로 넓어집니다', () => {
    const { min, max } = widenRange(100000, 200000, 0.2)
    expect(min).toBe(80000)
    expect(max).toBe(240000)
  })

  it('ratio 가 0 이면 그대로', () => {
    expect(widenRange(100000, 200000, 0)).toEqual({ min: 100000, max: 200000 })
  })
})

describe('촘촘한 표본 보호 (minRelativeDeviation)', () => {
  const opts = {
    sanityMin: 20000,
    sanityMax: 800000,
    iqrMultiplier: 1.5,
    iqrMinSamples: 8,
    madMultiplier: 3.5,
    madMinSamples: 5,
    minRelativeDeviation: 0.25,
  }

  it('값이 촘촘히 모여 있으면 몇 % 차이는 이상치로 보지 않습니다', () => {
    // 95,000 과 105,000 은 중앙값에서 5% 차이뿐인데 IQR 경계로는 밖에 놓입니다.
    const samples = [95000, 98000, 100000, 100000, 100000, 101000, 102000, 105000].map((value) => ({ value }))
    const { kept, dropped } = removeOutliers(samples, opts)
    expect(kept).toHaveLength(8)
    expect(dropped).toHaveLength(0)
  })

  it('보호 장치를 끄면 같은 표본이 잘려 나갑니다', () => {
    const samples = [95000, 98000, 100000, 100000, 100000, 101000, 102000, 105000].map((value) => ({ value }))
    const { dropped } = removeOutliers(samples, { ...opts, minRelativeDeviation: 0 })
    expect(dropped.length).toBeGreaterThan(0)
  })

  it('중앙값에서 크게 벗어난 값은 여전히 제거합니다', () => {
    const samples = [95000, 98000, 100000, 100000, 100000, 101000, 102000, 700000].map((value) => ({ value }))
    const { kept, dropped } = removeOutliers(samples, opts)
    expect(kept.map((s) => s.value)).not.toContain(700000)
    expect(dropped[0].reason).toBe('iqr_outlier')
  })

  it('sanity 범위 밖은 보호 장치와 무관하게 제거합니다', () => {
    const samples = [100000, 100000, 100000, 100000, 100000, 5_000_000].map((value) => ({ value }))
    const { kept, dropped } = removeOutliers(samples, opts)
    expect(kept).toHaveLength(5)
    expect(dropped[0].reason).toBe('above_sanity_max')
  })
})
