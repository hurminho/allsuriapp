// 가격 계산의 순수 함수 모음. 네트워크·DB 접근이 없어 단위 테스트로 검증합니다.

export type WeightedSample = {
  value: number
  weight: number
}

export type OutlierReason =
  | 'non_positive'
  | 'below_sanity_min'
  | 'above_sanity_max'
  | 'iqr_outlier'
  | 'mad_outlier'

export type OutlierOptions = {
  sanityMin: number
  sanityMax: number
  iqrMultiplier: number
  iqrMinSamples: number
  madMultiplier: number
  madMinSamples: number
  /** 중앙값 대비 이 비율 안이면 이상치로 보지 않습니다. 생략하면 0. */
  minRelativeDeviation?: number
}

export function median(values: number[]): number | null {
  const sorted = values.filter((v) => Number.isFinite(v)).sort((a, b) => a - b)
  if (sorted.length === 0) return null
  const mid = Math.floor(sorted.length / 2)
  return sorted.length % 2 === 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
}

/** 정렬된 값 배열의 선형보간 백분위. p 는 0~1. */
export function percentile(values: number[], p: number): number | null {
  const sorted = values.filter((v) => Number.isFinite(v)).sort((a, b) => a - b)
  if (sorted.length === 0) return null
  if (sorted.length === 1) return sorted[0]
  const clamped = Math.min(1, Math.max(0, p))
  const pos = clamped * (sorted.length - 1)
  const lo = Math.floor(pos)
  const hi = Math.ceil(pos)
  if (lo === hi) return sorted[lo]
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo)
}

/**
 * 가중 백분위. 표본마다 신뢰 가중치가 다르므로 평균 하나가 아니라
 * 최소·대표·최대를 이 함수로 뽑습니다.
 */
export function weightedPercentile(samples: WeightedSample[], p: number): number | null {
  const usable = samples
    .filter((s) => Number.isFinite(s.value) && Number.isFinite(s.weight) && s.weight > 0)
    .sort((a, b) => a.value - b.value)
  if (usable.length === 0) return null
  if (usable.length === 1) return usable[0].value

  const total = usable.reduce((sum, s) => sum + s.weight, 0)
  if (total <= 0) return null
  const target = Math.min(1, Math.max(0, p)) * total

  let cumulative = 0
  for (let i = 0; i < usable.length; i += 1) {
    const previous = cumulative
    cumulative += usable[i].weight
    if (cumulative < target) continue
    if (i === 0) return usable[0].value
    const span = usable[i].weight
    const ratio = span > 0 ? (target - previous) / span : 0
    const bounded = Math.min(1, Math.max(0, ratio))
    return usable[i - 1].value + (usable[i].value - usable[i - 1].value) * bounded
  }
  return usable[usable.length - 1].value
}

/**
 * 이상치 제거. 순서가 중요합니다.
 *  1) 0 이하 / 공정별 sanity 범위 밖은 오입력으로 즉시 제거
 *  2) 표본이 충분하면 IQR, 그보다 적으면 MAD 로 잔여 이상치 제거
 *  3) 표본이 아주 적으면 아무것도 버리지 않고 신뢰도로만 낮게 표시
 */
export function removeOutliers<T extends { value: number }>(
  samples: T[],
  options: OutlierOptions,
): { kept: T[]; dropped: { sample: T; reason: OutlierReason }[] } {
  const dropped: { sample: T; reason: OutlierReason }[] = []
  const withinSanity: T[] = []

  for (const sample of samples) {
    const v = sample.value
    if (!Number.isFinite(v) || v <= 0) {
      dropped.push({ sample, reason: 'non_positive' })
      continue
    }
    if (v < options.sanityMin) {
      dropped.push({ sample, reason: 'below_sanity_min' })
      continue
    }
    if (v > options.sanityMax) {
      dropped.push({ sample, reason: 'above_sanity_max' })
      continue
    }
    withinSanity.push(sample)
  }

  const values = withinSanity.map((s) => s.value)
  const center = median(values)
  const guard = options.minRelativeDeviation ?? 0

  /**
   * 중앙값에 가까운 표본은 이상치 판정에서 빼줍니다.
   * IQR·MAD 는 산포에 비례해 경계를 잡기 때문에, 값이 촘촘히 모여 있으면
   * 몇 % 차이나는 정상 표본까지 잘려 나갑니다.
   */
  const nearCenter = (value: number) => {
    if (guard <= 0 || center == null || center <= 0) return false
    return Math.abs(value - center) / center <= guard
  }

  if (withinSanity.length >= options.iqrMinSamples) {
    const q1 = percentile(values, 0.25)
    const q3 = percentile(values, 0.75)
    if (q1 != null && q3 != null) {
      const iqr = q3 - q1
      const low = q1 - options.iqrMultiplier * iqr
      const high = q3 + options.iqrMultiplier * iqr
      const kept: T[] = []
      for (const sample of withinSanity) {
        const outside = sample.value < low || sample.value > high
        if (outside && !nearCenter(sample.value)) dropped.push({ sample, reason: 'iqr_outlier' })
        else kept.push(sample)
      }
      return { kept, dropped }
    }
  }

  if (withinSanity.length >= options.madMinSamples) {
    if (center != null) {
      const mad = median(values.map((v) => Math.abs(v - center)))
      if (mad != null && mad > 0) {
        // 0.6745 는 MAD 를 표준편차 척도로 환산하는 상수입니다.
        const kept: T[] = []
        for (const sample of withinSanity) {
          const score = (0.6745 * Math.abs(sample.value - center)) / mad
          if (score > options.madMultiplier && !nearCenter(sample.value)) {
            dropped.push({ sample, reason: 'mad_outlier' })
          } else {
            kept.push(sample)
          }
        }
        return { kept, dropped }
      }
    }
  }

  return { kept: withinSanity, dropped }
}

/** 최근 표본에 더 큰 가중치. maxAgeDays 를 넘으면 0(=사용 안 함). */
export function recencyWeight(ageDays: number, maxAgeDays: number): number {
  if (!Number.isFinite(ageDays) || ageDays < 0) return 0
  if (ageDays > maxAgeDays) return 0
  if (ageDays <= 90) return 1
  if (ageDays <= 180) return 0.8
  if (ageDays <= 365) return 0.6
  return 0.35
}

/** 작업 범위 태그 일치도(자카드). 요청에 태그가 없으면 감점하지 않습니다. */
export function scopeMatchWeight(requested: string[], sample: string[]): number {
  if (requested.length === 0) return 1
  if (sample.length === 0) return 0.75
  const a = new Set(requested)
  const b = new Set(sample)
  let intersection = 0
  for (const tag of a) if (b.has(tag)) intersection += 1
  const union = new Set([...a, ...b]).size
  const jaccard = union > 0 ? intersection / union : 0
  return 0.6 + 0.4 * jaccard
}

export type ConfidenceInput = {
  /** 가중치 합계. 표본 수가 아니라 신뢰 가중 표본량입니다. */
  weightedEvidence: number
  sufficientWeightedEvidence: number
  /** 전체 가중치 중 실거래(완료 금액)가 차지하는 비율 0~1. */
  completedJobShare: number
  /** 채택된 표본들의 평균 최근성 가중치 0~1. */
  averageRecency: number
  /** 채택된 표본들의 평균 지역 일치도 0~1 로 정규화된 값. */
  averageRegionMatch: number
  /** 채택된 표본들의 평균 작업범위 일치도 0~1 로 정규화된 값. */
  averageScopeMatch: number
}

export function confidenceScore(input: ConfidenceInput): number {
  const clamp01 = (n: number) => Math.min(1, Math.max(0, Number.isFinite(n) ? n : 0))
  const sampleSize = clamp01(
    input.sufficientWeightedEvidence > 0
      ? input.weightedEvidence / input.sufficientWeightedEvidence
      : 0,
  )
  const score =
    0.35 * sampleSize +
    0.25 * clamp01(input.completedJobShare) +
    0.15 * clamp01(input.averageRecency) +
    0.15 * clamp01(input.averageRegionMatch) +
    0.1 * clamp01(input.averageScopeMatch)
  return Math.round(score * 1000) / 1000
}

/**
 * 점수를 등급으로. 실거래 비중이 낮으면 high 를 주지 않습니다.
 * (입찰가·기준표만으로 "확실한 가격"처럼 보이면 안 됩니다)
 */
export function confidenceLevel(score: number, completedJobShare: number): 'high' | 'medium' | 'low' {
  if (score >= 0.7 && completedJobShare >= 0.3) return 'high'
  if (score >= 0.45) return 'medium'
  return 'low'
}

export function roundToUnit(value: number, unit: number): number {
  if (!Number.isFinite(value)) return 0
  if (!Number.isFinite(unit) || unit <= 1) return Math.round(value)
  return Math.round(value / unit) * unit
}

/** 참고 범위는 넓게 보여주는 편이 안전합니다. ratio 0.18 → ±18%. */
export function widenRange(min: number, max: number, ratio: number): { min: number; max: number } {
  const safeRatio = Number.isFinite(ratio) && ratio > 0 ? ratio : 0
  return {
    min: Math.max(0, min * (1 - safeRatio)),
    max: max * (1 + safeRatio),
  }
}
