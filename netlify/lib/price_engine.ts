// 가격 엔진 — 계산 오케스트레이션.
//
// 데이터 조회는 price_repository.ts 가 담당하고, 이 파일은 표본을 받아 계산만 합니다.
// 덕분에 DB 없이 단위 테스트할 수 있습니다.
//
// 절대 원칙
//  * OpenAI 출력이나 인터넷 검색 결과는 표본이 될 수 없습니다.
//  * 표본이 부족하면 숫자를 만들지 않고 insufficient 를 돌려줍니다.
//  * 결과에는 항상 계산 근거(basis)와 엔진 버전을 담습니다.

import {
  ENGINE_VERSION,
  type AccessDifficulty,
  type ConfidenceLevel,
  type EngineSettings,
  type PriceState,
  type PropertyType,
  type TradeDefinition,
  type Urgency,
} from './price_catalog'
import {
  confidenceLevel,
  confidenceScore,
  recencyWeight,
  removeOutliers,
  roundToUnit,
  scopeMatchWeight,
  weightedPercentile,
  widenRange,
} from './price_math'

export type PriceSampleSource = 'completed_job' | 'contractor_bid' | 'rate_card' | 'baseline'

/** 가격 엔진이 받아들이는 유일한 표본 형태. 총액(원) 기준입니다. */
export type PriceSample = {
  source: PriceSampleSource
  value: number
  occurredAt?: string | null
  regionLevel1?: string | null
  regionLevel2?: string | null
  propertyType?: string | null
  workScopeTags?: string[]
  /** 입찰 표본이 세부 항목까지 입력했는지. 총액만 있으면 가중치를 낮춥니다. */
  hasBreakdown?: boolean
  materialIncluded?: boolean | null
  vatIncluded?: boolean | null
  /** 로그·감사용. 계산에는 쓰지 않습니다. */
  refId?: string | null
}

export type PriceRequest = {
  regionLevel1?: string | null
  regionLevel2?: string | null
  propertyType?: PropertyType | null
  urgency?: Urgency | null
  accessDifficulty?: AccessDifficulty | null
  workScopeTags?: string[]
  materialIncluded?: boolean | null
  visitRequired?: boolean | null
}

export type PriceBasisEntry = {
  source: PriceSampleSource
  sampleCount: number
  /** 우선순위 사다리를 통과해 실제 계산에 쓰인 표본 수. */
  usedSampleCount: number
  weightShare: number
  newestAt?: string | null
  oldestAt?: string | null
}

export type PriceAdjustment = {
  label: string
  kind: 'multiplier' | 'amount'
  value: number
  reason: string
}

export type PriceResult = {
  priceState: PriceState
  estimatedMin: number | null
  estimatedTypical: number | null
  estimatedMax: number | null
  confidenceLevel: ConfidenceLevel
  confidenceScore: number
  evidenceCount: number
  completedJobCount: number
  weightedEvidence: number
  factors: string[]
  adjustments: PriceAdjustment[]
  basis: PriceBasisEntry[]
  droppedOutlierCount: number
  disclaimer: string
  engineVersion: string
  /** insufficient 인 이유. UI 문구 분기와 운영 로그에 씁니다. */
  insufficientReason?: 'unknown_trade' | 'no_samples' | 'below_threshold'
}

const DISCLAIMER_SUFFICIENT =
  '최근 유사 완료 사례와 현재 입력 조건을 기준으로 한 참고 금액입니다. 현장 상태, 자재, 긴급 출동 여부에 따라 달라질 수 있습니다.'
const DISCLAIMER_PRELIMINARY =
  '유사 사례가 아직 적어 범위를 넓게 잡은 참고 금액입니다. 현장 확인 후 실제 견적과 차이가 날 수 있습니다.'
const DISCLAIMER_INSUFFICIENT =
  '현장 조건에 따라 금액 차이가 큰 작업이라, 확인된 데이터가 쌓이기 전에는 예상 금액을 표시하지 않습니다.'

function ageInDays(occurredAt: string | null | undefined, now: Date): number | null {
  if (!occurredAt) return null
  const t = Date.parse(occurredAt)
  if (!Number.isFinite(t)) return null
  return Math.max(0, (now.getTime() - t) / 86400000)
}

type ScoredSample = PriceSample & {
  weight: number
  /** 우선순위 사다리의 가중치 상한을 적용하기 전 원래 가중치. */
  baseWeight: number
  recencyFactor: number
  regionFactor: number
  propertyFactor: number
  scopeFactor: number
}

function scoreSample(
  sample: PriceSample,
  request: PriceRequest,
  settings: EngineSettings,
  now: Date,
): ScoredSample {
  const w = settings.weights
  let base = w[camelSource(sample.source)]
  if (sample.source === 'contractor_bid' && sample.hasBreakdown === false) {
    base *= w.bidWithoutBreakdown
  }

  const age = ageInDays(sample.occurredAt, now)
  // 기준표·표준 단가는 운영자/사업자가 유지하는 값이라 날짜가 없으면 중립값을 씁니다.
  const recency =
    age == null
      ? sample.source === 'baseline' || sample.source === 'rate_card'
        ? 0.8
        : 0.35
      : recencyWeight(age, settings.thresholds.maxSampleAgeDays)

  let region = w.regionLevel1
  if (request.regionLevel1) {
    if (
      request.regionLevel2 &&
      sample.regionLevel2 &&
      request.regionLevel2 === sample.regionLevel2
    ) {
      region = w.regionExact
    } else if (sample.regionLevel1 && sample.regionLevel1 === request.regionLevel1) {
      region = w.regionLevel1
    } else if (sample.regionLevel1) {
      region = w.regionMismatch
    }
  }

  let property = w.propertyMatch
  if (request.propertyType && sample.propertyType && request.propertyType !== sample.propertyType) {
    property = w.propertyMismatch
  }

  const scope = scopeMatchWeight(request.workScopeTags || [], sample.workScopeTags || [])

  let material = 1
  if (
    request.materialIncluded != null &&
    sample.materialIncluded != null &&
    request.materialIncluded !== sample.materialIncluded
  ) {
    material = 0.8
  }

  const weight = base * recency * region * property * scope * material
  return {
    ...sample,
    recencyFactor: recency,
    regionFactor: region,
    propertyFactor: property,
    scopeFactor: scope,
    weight,
    baseWeight: weight,
  }
}

/** 데이터 소스 우선순위. 앞에 있을수록 신뢰합니다. */
const TIER_ORDER: PriceSampleSource[] = ['completed_job', 'contractor_bid', 'rate_card', 'baseline']

/**
 * 우선순위 사다리를 적용합니다.
 *
 *  1. 상위 소스부터 차례로 더해가며, 충분 기준을 만족하는 순간 멈춥니다.
 *     → 완료 거래만으로 충분하면 입찰가·표준 단가·기준표는 아예 쓰지 않습니다.
 *  2. 끝까지 충분하지 않으면 전부 씁니다. 대신 하위 소스 합계 가중치를
 *     "최상위 소스 가중치 × lowerTierWeightCap" 으로 눌러, 건수가 많은 입찰이
 *     완료 거래를 밀어내지 못하게 합니다.
 *
 * usedSources 는 basis 에 남겨 운영자가 근거를 추적할 수 있게 합니다.
 */
function selectByPriority(
  kept: ScoredSample[],
  trade: TradeDefinition,
  settings: EngineSettings,
): { samples: ScoredSample[]; sufficient: boolean } {
  const tiers = TIER_ORDER.map((source) => kept.filter((s) => s.source === source)).filter(
    (list) => list.length > 0,
  )
  if (!tiers.length) return { samples: [], sufficient: false }

  const meetsSufficient = (list: ScoredSample[]) => {
    const completed = list.filter((s) => s.source === 'completed_job').length
    const weight = list.reduce((sum, s) => sum + s.weight, 0)
    return (
      completed >= trade.thresholds.sufficientCompletedJobs ||
      weight >= settings.thresholds.sufficientWeightedEvidence
    )
  }

  const cap = Math.max(0, settings.weights.lowerTierWeightCap)
  const topWeight = tiers[0].reduce((sum, s) => sum + s.baseWeight, 0)

  /**
   * 최상위 소스 아래 단계들의 가중치 합을 "최상위 × cap" 으로 눌러 담습니다.
   * 매번 baseWeight 에서 다시 계산하므로 여러 번 호출해도 누적되지 않습니다.
   */
  const applyDominanceCap = (lowerTiers: ScoredSample[][]) => {
    const lower = lowerTiers.flat()
    for (const s of lower) s.weight = s.baseWeight
    const lowerWeight = lower.reduce((sum, s) => sum + s.baseWeight, 0)
    const allowed = topWeight * cap
    if (lowerWeight > allowed && lowerWeight > 0) {
      const scale = allowed / lowerWeight
      for (const s of lower) s.weight = s.baseWeight * scale
    }
  }

  const acc: ScoredSample[] = []
  for (let i = 0; i < tiers.length; i += 1) {
    acc.push(...tiers[i])
    if (i > 0) applyDominanceCap(tiers.slice(1, i + 1))
    if (meetsSufficient(acc)) return { samples: acc, sufficient: true }
  }
  return { samples: acc, sufficient: false }
}

function camelSource(source: PriceSampleSource): keyof EngineSettings['weights'] {
  switch (source) {
    case 'completed_job':
      return 'completedJob'
    case 'contractor_bid':
      return 'contractorBid'
    case 'rate_card':
      return 'rateCard'
    default:
      return 'baseline'
  }
}

function normalizeTo01(value: number, min: number, max: number): number {
  if (!Number.isFinite(value) || max <= min) return 1
  return Math.min(1, Math.max(0, (value - min) / (max - min)))
}

function buildBasis(
  samples: ScoredSample[],
  totalWeight: number,
  used: Set<ScoredSample>,
): PriceBasisEntry[] {
  const bySource = new Map<PriceSampleSource, ScoredSample[]>()
  for (const s of samples) {
    const list = bySource.get(s.source) || []
    list.push(s)
    bySource.set(s.source, list)
  }
  return TIER_ORDER.filter((source) => bySource.has(source)).map((source) => {
    const list = bySource.get(source) as ScoredSample[]
    const usedList = list.filter((s) => used.has(s))
    const weight = usedList.reduce((sum, s) => sum + s.weight, 0)
    const dates = list
      .map((s) => s.occurredAt)
      .filter((d): d is string => !!d)
      .sort()
    return {
      source,
      sampleCount: list.length,
      // 우선순위 사다리에서 상위 소스만으로 충분했다면 하위 소스는 usedSampleCount=0 입니다.
      usedSampleCount: usedList.length,
      weightShare: totalWeight > 0 ? Math.round((weight / totalWeight) * 1000) / 1000 : 0,
      oldestAt: dates[0] ?? null,
      newestAt: dates[dates.length - 1] ?? null,
    }
  })
}

function insufficient(
  reason: NonNullable<PriceResult['insufficientReason']>,
  trade: TradeDefinition | null,
  evidenceCount: number,
  droppedOutlierCount: number,
  basis: PriceBasisEntry[],
): PriceResult {
  return {
    priceState: 'insufficient',
    estimatedMin: null,
    estimatedTypical: null,
    estimatedMax: null,
    confidenceLevel: 'low',
    confidenceScore: 0,
    evidenceCount,
    completedJobCount: 0,
    weightedEvidence: 0,
    factors: trade ? trade.priceFactors : [],
    adjustments: [],
    basis,
    droppedOutlierCount,
    disclaimer: DISCLAIMER_INSUFFICIENT,
    engineVersion: ENGINE_VERSION,
    insufficientReason: reason,
  }
}

/**
 * 표본으로 가격 범위를 계산합니다.
 * trade 가 null 이면(공정 미확정) 절대 금액을 만들지 않습니다.
 */
export function computePrice(input: {
  trade: TradeDefinition | null
  request: PriceRequest
  samples: PriceSample[]
  settings: EngineSettings
  now?: Date
}): PriceResult {
  const { trade, request, settings } = input
  const now = input.now ?? new Date()

  if (!trade) {
    return insufficient('unknown_trade', null, 0, 0, [])
  }
  if (!input.samples.length) {
    return insufficient('no_samples', trade, 0, 0, [])
  }

  const scored = input.samples.map((s) => scoreSample(s, request, settings, now))
  const positive = scored.filter((s) => s.weight > 0)

  // 이상치 제거는 소스별로 따로 합니다. 완료 금액과 입찰가는 분포가 달라서,
  // 한데 섞어 계산하면 건수가 많은 쪽이 반대쪽을 통째로 이상치로 지워버립니다.
  const outlierOptions = {
    sanityMin: trade.sanity.min,
    sanityMax: trade.sanity.max,
    iqrMultiplier: settings.outliers.iqrMultiplier,
    iqrMinSamples: settings.outliers.iqrMinSamples,
    madMultiplier: settings.outliers.madMultiplier,
    madMinSamples: settings.outliers.madMinSamples,
    minRelativeDeviation: settings.outliers.minRelativeDeviation,
  }
  const kept: ScoredSample[] = []
  const dropped: { sample: ScoredSample; reason: string }[] = []
  for (const source of TIER_ORDER) {
    const group = positive.filter((s) => s.source === source)
    if (!group.length) continue
    const result = removeOutliers(group, outlierOptions)
    kept.push(...result.kept)
    dropped.push(...result.dropped)
  }

  // 우선순위 사다리: 완료 거래 > 최근 입찰 > 검증 표준 단가 > 운영자 기준표.
  const selected = selectByPriority(kept, trade, settings)
  const used = selected.samples

  const totalWeight = used.reduce((sum, s) => sum + s.weight, 0)
  // basis 는 제외된 소스까지 함께 남겨 운영자가 근거를 추적할 수 있게 합니다.
  const usedSet = new Set(used)
  const basis = buildBasis(kept, totalWeight, usedSet)
  const completedJobCount = used.filter((s) => s.source === 'completed_job').length
  const evidenceCount = used.length

  if (evidenceCount === 0 || totalWeight <= 0) {
    return insufficient('no_samples', trade, 0, dropped.length, basis)
  }

  const preliminaryMin = Math.max(
    trade.thresholds.preliminaryMinSamples,
    settings.thresholds.preliminaryMinSamples,
  )
  const isSufficient = selected.sufficient
  const isPreliminary = evidenceCount >= preliminaryMin

  if (!isSufficient && !isPreliminary) {
    return insufficient('below_threshold', trade, evidenceCount, dropped.length, basis)
  }

  const state: PriceState = isSufficient ? 'sufficient' : 'preliminary'

  let low = weightedPercentile(used, 0.2)
  let typical = weightedPercentile(used, 0.5)
  let high = weightedPercentile(used, 0.8)
  if (low == null || typical == null || high == null) {
    return insufficient('no_samples', trade, evidenceCount, dropped.length, basis)
  }

  const adjustments: PriceAdjustment[] = []

  if (trade.urgencySurchargeApplies && request.urgency) {
    const multiplier = trade.urgencyMultipliers[request.urgency]
    if (multiplier && multiplier !== 1) {
      low *= multiplier
      typical *= multiplier
      high *= multiplier
      adjustments.push({
        label: request.urgency === 'emergency' ? '긴급 출동 가산' : '당일 방문 가산',
        kind: 'multiplier',
        value: multiplier,
        reason: '공정 카탈로그의 긴급 가산 설정',
      })
    }
  }

  if (request.visitRequired === false && trade.visitFee.applies && trade.visitFee.typical > 0) {
    const fee = trade.visitFee.typical
    low = Math.max(trade.sanity.min, low - fee)
    typical = Math.max(trade.sanity.min, typical - fee)
    high = Math.max(trade.sanity.min, high - fee)
    adjustments.push({
      label: '출장비 제외',
      kind: 'amount',
      value: -fee,
      reason: '방문 없이 처리 가능한 요청',
    })
  }

  if (state === 'preliminary') {
    const widened = widenRange(low, high, settings.thresholds.preliminaryWidenRatio)
    low = widened.min
    high = widened.max
  }

  const unit = settings.thresholds.roundToWon
  const estimatedMin = roundToUnit(Math.min(low, typical), unit)
  const estimatedTypical = roundToUnit(typical, unit)
  const estimatedMax = roundToUnit(Math.max(high, typical), unit)

  const completedJobShare =
    totalWeight > 0
      ? used.filter((s) => s.source === 'completed_job').reduce((sum, s) => sum + s.weight, 0) /
        totalWeight
      : 0
  const weightedAvg = (pick: (s: ScoredSample) => number) =>
    used.reduce((sum, s) => sum + pick(s) * s.weight, 0) / totalWeight

  const score = confidenceScore({
    weightedEvidence: totalWeight,
    sufficientWeightedEvidence: settings.thresholds.sufficientWeightedEvidence,
    completedJobShare,
    averageRecency: weightedAvg((s) => s.recencyFactor),
    averageRegionMatch: normalizeTo01(
      weightedAvg((s) => s.regionFactor),
      settings.weights.regionMismatch,
      settings.weights.regionExact,
    ),
    averageScopeMatch: normalizeTo01(weightedAvg((s) => s.scopeFactor), 0.6, 1),
  })

  let level = confidenceLevel(score, completedJobShare)
  if (state === 'preliminary' && level === 'high') level = 'medium'

  const factors = Array.from(
    new Set([...trade.priceFactors, ...adjustments.map((a) => a.label)]),
  )
  if (request.accessDifficulty === 'hard' || request.accessDifficulty === 'tight') {
    factors.push('현장 접근 난이도')
  }
  if (used.some((s) => s.vatIncluded === true) && used.some((s) => s.vatIncluded === false)) {
    factors.push('부가세 포함 여부(업체별 상이)')
  }

  return {
    priceState: state,
    estimatedMin,
    estimatedTypical,
    estimatedMax,
    confidenceLevel: level,
    confidenceScore: score,
    evidenceCount,
    completedJobCount,
    weightedEvidence: Math.round(totalWeight * 1000) / 1000,
    factors: Array.from(new Set(factors)),
    adjustments,
    basis,
    droppedOutlierCount: dropped.length,
    disclaimer: state === 'sufficient' ? DISCLAIMER_SUFFICIENT : DISCLAIMER_PRELIMINARY,
    engineVersion: ENGINE_VERSION,
  }
}

/** 기준표 한 줄을 표본 3개(최소·대표·최대)로 펼칩니다. */
export function baselineToSamples(baseline: {
  min_amount: number
  typical_amount: number
  max_amount: number
  region_level1?: string | null
  property_type?: string | null
  material_included?: boolean | null
  vat_included?: boolean | null
  updated_at?: string | null
}): PriceSample[] {
  const common = {
    source: 'baseline' as const,
    regionLevel1: baseline.region_level1 ?? null,
    regionLevel2: null,
    propertyType: baseline.property_type ?? null,
    workScopeTags: [],
    materialIncluded: baseline.material_included ?? null,
    vatIncluded: baseline.vat_included ?? null,
    occurredAt: baseline.updated_at ?? null,
  }
  return [baseline.min_amount, baseline.typical_amount, baseline.max_amount]
    .filter((v) => Number.isFinite(v) && v > 0)
    .map((value) => ({ ...common, value }))
}
