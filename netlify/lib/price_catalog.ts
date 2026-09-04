/// <reference types="node" />
// 가격 엔진 공정 카탈로그 — 구성 데이터.
//
// 여기 있는 값은 database/price_engine_v1.sql 의 시드와 같습니다.
// DB(trade_catalog / price_questions)에 행이 있으면 그 값이 이 기본값을 덮습니다.
// 새 공정을 지원할 때는 DB 행을 추가하세요. 코드에 분기문을 늘리지 않습니다.

export const ENGINE_VERSION = 'v1'

export const URGENCY_LEVELS = ['normal', 'soon', 'today', 'emergency'] as const
export type Urgency = (typeof URGENCY_LEVELS)[number]

export const PROPERTY_TYPES = [
  'apartment',
  'villa',
  'house',
  'officetel',
  'commercial',
  'office',
  'other',
] as const
export type PropertyType = (typeof PROPERTY_TYPES)[number]

export const ACCESS_DIFFICULTIES = ['easy', 'tight', 'hard', 'unknown'] as const
export type AccessDifficulty = (typeof ACCESS_DIFFICULTIES)[number]

export const PRICE_STATES = ['sufficient', 'preliminary', 'insufficient'] as const
export type PriceState = (typeof PRICE_STATES)[number]

export const CONFIDENCE_LEVELS = ['high', 'medium', 'low'] as const
export type ConfidenceLevel = (typeof CONFIDENCE_LEVELS)[number]

export type QuestionInputType = 'single' | 'multi' | 'bool' | 'text' | 'number' | 'photo'

export type QuestionOption = { value: string; label: string }

export type QuestionDefinition = {
  id: string
  label: string
  inputType: QuestionInputType
  options: QuestionOption[]
  /** 값이 있으면 가격 엔진 입력으로 정규화됩니다. null 은 사업자 참고용. */
  mapsTo:
    | 'urgency'
    | 'propertyType'
    | 'workScopeTags'
    | 'symptomTags'
    | 'accessDifficulty'
    | 'materialIncluded'
    | null
  affectsPrice: boolean
  /**
   * 선택지 value → 태그 목록. mapsTo 가 workScopeTags/symptomTags 일 때 씁니다.
   * 라벨 문자열 매칭에 의존하지 않도록 매핑을 명시합니다.
   * 여기서 나온 태그는 공정의 허용 태그로 한 번 더 걸러집니다.
   */
  tagMap?: Record<string, string[]>
  helpText?: string
  sortOrder: number
}

export type TradeDefinition = {
  id: string
  category: string
  subcategory: string
  aliases: string[]
  symptomTags: string[]
  workScopeTags: string[]
  requiredQuestions: string[]
  optionalQuestions: string[]
  priceFactors: string[]
  baseLabor: { min: number; typical: number; max: number }
  materialIncludedByDefault: boolean
  visitFee: { applies: boolean; typical: number }
  urgencySurchargeApplies: boolean
  urgencyMultipliers: Partial<Record<Urgency, number>>
  sanity: { min: number; max: number }
  thresholds: { sufficientCompletedJobs: number; preliminaryMinSamples: number }
  active: boolean
  sortOrder: number
}

export type EngineSettings = {
  thresholds: {
    sufficientCompletedJobs: number
    sufficientWeightedEvidence: number
    preliminaryMinSamples: number
    maxSampleAgeDays: number
    preliminaryWidenRatio: number
    roundToWon: number
  }
  weights: {
    completedJob: number
    contractorBid: number
    rateCard: number
    baseline: number
    bidWithoutBreakdown: number
    regionExact: number
    regionLevel1: number
    regionMismatch: number
    propertyMatch: number
    propertyMismatch: number
    /**
     * 상위 우선순위 표본이 있을 때, 하위 표본 전체가 가질 수 있는 최대 가중치 비율.
     * 0.6 이면 "완료 거래 가중치 × 0.6" 이 입찰·단가·기준표 합계의 상한입니다.
     * 입찰 건수가 많다는 이유로 완료 거래가 밀려나는 일을 막습니다.
     */
    lowerTierWeightCap: number
  }
  outliers: {
    iqrMultiplier: number
    iqrMinSamples: number
    madMultiplier: number
    madMinSamples: number
    /**
     * 중앙값 대비 이 비율 안에 있는 표본은 IQR·MAD 판정에서 살려둡니다.
     * 값이 촘촘히 모인 공정에서 정상 표본까지 잘려 나가는 것을 막습니다.
     */
    minRelativeDeviation: number
  }
}

export const DEFAULT_SETTINGS: EngineSettings = {
  thresholds: {
    sufficientCompletedJobs: 8,
    sufficientWeightedEvidence: 12,
    preliminaryMinSamples: 3,
    maxSampleAgeDays: 540,
    preliminaryWidenRatio: 0.18,
    roundToWon: 1000,
  },
  weights: {
    completedJob: 1.0,
    contractorBid: 0.55,
    rateCard: 0.35,
    baseline: 0.2,
    bidWithoutBreakdown: 0.7,
    regionExact: 1.0,
    regionLevel1: 0.85,
    regionMismatch: 0.6,
    propertyMatch: 1.0,
    propertyMismatch: 0.85,
    lowerTierWeightCap: 0.6,
  },
  outliers: {
    iqrMultiplier: 1.5,
    iqrMinSamples: 8,
    madMultiplier: 3.5,
    madMinSamples: 5,
    minRelativeDeviation: 0.25,
  },
}

const OPT = (value: string, label: string): QuestionOption => ({ value, label })

export const DEFAULT_QUESTIONS: QuestionDefinition[] = [
  {
    id: 'urgency',
    label: '언제 방문이 필요하세요?',
    inputType: 'single',
    options: [
      OPT('emergency', '지금 당장(긴급)'),
      OPT('today', '오늘 안에'),
      OPT('soon', '2~3일 안'),
      OPT('normal', '급하지 않아요'),
    ],
    mapsTo: 'urgency',
    affectsPrice: true,
    sortOrder: 10,
  },
  {
    id: 'property_type',
    label: '어떤 건물인가요?',
    inputType: 'single',
    options: [
      OPT('apartment', '아파트'),
      OPT('villa', '빌라·다세대'),
      OPT('house', '단독주택'),
      OPT('officetel', '오피스텔'),
      OPT('commercial', '상가·매장'),
      OPT('office', '사무실'),
      OPT('other', '그 외'),
    ],
    mapsTo: 'propertyType',
    affectsPrice: true,
    sortOrder: 20,
  },
  {
    id: 'access_difficulty',
    label: '작업 공간 접근은 어떤가요?',
    inputType: 'single',
    options: [
      OPT('easy', '바로 접근 가능'),
      OPT('tight', '좁거나 가구를 옮겨야 해요'),
      OPT('hard', '철거·해체가 필요해 보여요'),
      OPT('unknown', '잘 모르겠어요'),
    ],
    mapsTo: 'accessDifficulty',
    affectsPrice: true,
    sortOrder: 30,
  },
  {
    id: 'clog_severity',
    label: '물이 어떻게 내려가나요?',
    inputType: 'single',
    options: [
      OPT('slow', '천천히 내려가요'),
      OPT('none', '전혀 안 내려가요'),
      OPT('overflow', '역류해서 넘쳐요'),
      OPT('unknown', '잘 모르겠어요'),
    ],
    mapsTo: 'workScopeTags',
    tagMap: {
      slow: ['관통 작업', '트랩 청소'],
      none: ['관통 작업', '고압 세척', '트랩 청소'],
      overflow: ['관통 작업', '고압 세척', '변기 탈착', '배수관 보수'],
    },
    affectsPrice: true,
    sortOrder: 40,
  },
  {
    id: 'leak_visible',
    label: '물이 새는 곳이 눈에 보이나요?',
    inputType: 'single',
    options: [
      OPT('visible', '보이는 곳에서 새요'),
      OPT('hidden', '어디서 새는지 모르겠어요'),
      OPT('wall_ceiling', '벽·천장이 젖었어요'),
    ],
    mapsTo: 'workScopeTags',
    tagMap: {
      visible: ['연결부 보수', '배관 교체'],
      hidden: ['누수 탐지', '장비 점검'],
      wall_ceiling: ['누수 탐지', '부분 철거'],
    },
    affectsPrice: true,
    sortOrder: 50,
  },
  {
    id: 'fixture_supply',
    label: '기구(변기·수전 등)는 누가 준비하나요?',
    inputType: 'single',
    options: [
      OPT('contractor', '업체가 준비'),
      OPT('customer', '제가 준비했어요'),
      OPT('unknown', '잘 모르겠어요'),
    ],
    mapsTo: 'materialIncluded',
    affectsPrice: true,
    sortOrder: 60,
  },
  {
    id: 'area_size',
    label: '보수할 면적이 대략 어느 정도인가요?',
    inputType: 'single',
    options: [
      OPT('spot', '한 지점만'),
      OPT('under_3sqm', '3㎡ 이하'),
      OPT('over_3sqm', '3㎡ 이상'),
      OPT('unknown', '잘 모르겠어요'),
    ],
    mapsTo: 'workScopeTags',
    tagMap: {
      spot: ['균열 보수', '실리콘 재시공'],
      under_3sqm: ['균열 보수', '우레탄 도포', '기존 실리콘 제거', '실리콘 재시공'],
      over_3sqm: ['우레탄 도포', '프라이머 시공', '기존 실리콘 제거'],
    },
    affectsPrice: true,
    sortOrder: 70,
  },
  {
    id: 'symptom_started',
    label: '언제부터 그런가요?',
    inputType: 'single',
    options: [
      OPT('today', '오늘부터'),
      OPT('few_days', '2~3일 전'),
      OPT('week_plus', '일주일 이상'),
      OPT('unknown', '잘 모르겠어요'),
    ],
    mapsTo: null,
    affectsPrice: false,
    sortOrder: 80,
  },
  {
    id: 'photos',
    label: '현장 사진을 올려주실 수 있나요?',
    inputType: 'photo',
    options: [],
    mapsTo: null,
    affectsPrice: false,
    sortOrder: 90,
  },
  {
    id: 'prior_repair',
    label: '전에 같은 곳을 수리한 적이 있나요?',
    inputType: 'single',
    options: [OPT('yes', '있어요'), OPT('no', '없어요'), OPT('unknown', '잘 모르겠어요')],
    mapsTo: 'workScopeTags',
    tagMap: {
      yes: ['부분 철거', '배수관 보수'],
      no: [],
    },
    affectsPrice: true,
    sortOrder: 100,
  },
]

function trade(t: Partial<TradeDefinition> & Pick<TradeDefinition, 'id' | 'category' | 'subcategory'>): TradeDefinition {
  return {
    aliases: [],
    symptomTags: [],
    workScopeTags: [],
    requiredQuestions: ['urgency', 'property_type'],
    optionalQuestions: ['photos', 'access_difficulty'],
    priceFactors: [],
    baseLabor: { min: 50000, typical: 90000, max: 200000 },
    materialIncludedByDefault: false,
    visitFee: { applies: true, typical: 15000 },
    urgencySurchargeApplies: true,
    urgencyMultipliers: {},
    sanity: { min: 20000, max: 1000000 },
    thresholds: { sufficientCompletedJobs: 8, preliminaryMinSamples: 3 },
    active: true,
    sortOrder: 100,
    ...t,
  }
}

/** 초기 지원 공정 10종. 견적 구조가 표준화되는 세부 공정만 담습니다. */
export const DEFAULT_TRADES: TradeDefinition[] = [
  trade({
    id: 'plumbing.toilet_clog',
    category: '배관',
    subcategory: '변기 막힘',
    aliases: ['변기막힘', '변기 뚫기', '양변기 막힘'],
    symptomTags: ['배수 지연', '역류', '악취'],
    workScopeTags: ['관통 작업', '변기 탈착', '고압 세척'],
    requiredQuestions: ['clog_severity', 'urgency', 'property_type'],
    optionalQuestions: ['photos', 'prior_repair', 'access_difficulty'],
    priceFactors: ['출장비', '기본 작업비', '변기 탈착 여부', '고압 세척 장비', '야간·긴급 작업'],
    baseLabor: { min: 50000, typical: 80000, max: 150000 },
    urgencyMultipliers: { emergency: 1.4, today: 1.15 },
    sanity: { min: 20000, max: 800000 },
    sortOrder: 10,
  }),
  trade({
    id: 'plumbing.sink_clog',
    category: '배관',
    subcategory: '싱크대 막힘',
    aliases: ['싱크대막힘', '싱크 막힘', '주방 싱크 막힘'],
    symptomTags: ['배수 지연', '악취', '배수 정체'],
    workScopeTags: ['관통 작업', '트랩 청소', '고압 세척'],
    requiredQuestions: ['clog_severity', 'urgency', 'property_type'],
    optionalQuestions: ['photos', 'prior_repair', 'access_difficulty'],
    priceFactors: ['출장비', '기본 작업비', '트랩 교체', '고압 세척 장비', '야간·긴급 작업'],
    baseLabor: { min: 50000, typical: 80000, max: 150000 },
    urgencyMultipliers: { emergency: 1.4, today: 1.15 },
    sanity: { min: 20000, max: 800000 },
    sortOrder: 20,
  }),
  trade({
    id: 'bath.washbasin_faucet_replace',
    category: '화장실',
    subcategory: '세면대·수전 교체',
    aliases: ['세면대 교체', '수전 교체', '수도꼭지 교체'],
    symptomTags: ['누수', '노후', '파손'],
    workScopeTags: ['기구 교체', '수전 교체', '실리콘 마감'],
    requiredQuestions: ['fixture_supply', 'urgency', 'property_type'],
    optionalQuestions: ['photos', 'access_difficulty'],
    priceFactors: ['출장비', '기본 작업비', '자재비(기구)', '기존 기구 철거', '실리콘 마감', '부가세 포함 여부'],
    baseLabor: { min: 60000, typical: 100000, max: 180000 },
    urgencyMultipliers: { emergency: 1.3, today: 1.1 },
    sanity: { min: 30000, max: 1500000 },
    sortOrder: 30,
  }),
  trade({
    id: 'bath.shower_replace',
    category: '화장실',
    subcategory: '샤워기 교체',
    aliases: ['샤워기 교체', '샤워수전 교체', '해바라기 교체'],
    symptomTags: ['누수', '수압 저하', '노후'],
    workScopeTags: ['기구 교체', '수전 교체', '실리콘 마감'],
    requiredQuestions: ['fixture_supply', 'urgency', 'property_type'],
    optionalQuestions: ['photos', 'access_difficulty'],
    priceFactors: ['출장비', '기본 작업비', '자재비(기구)', '벽체 타일 손상 위험', '부가세 포함 여부'],
    baseLabor: { min: 50000, typical: 80000, max: 150000 },
    urgencyMultipliers: { emergency: 1.3, today: 1.1 },
    sanity: { min: 25000, max: 1000000 },
    sortOrder: 40,
  }),
  trade({
    id: 'plumbing.drain_clog_basic',
    category: '배관',
    subcategory: '단순 배관 막힘',
    aliases: ['배관 막힘', '하수구 막힘', '배수구 막힘'],
    symptomTags: ['배수 지연', '악취', '역류'],
    workScopeTags: ['관통 작업', '고압 세척', '트랩 청소'],
    requiredQuestions: ['clog_severity', 'urgency', 'property_type'],
    optionalQuestions: ['photos', 'access_difficulty', 'prior_repair'],
    priceFactors: ['출장비', '기본 작업비', '관통 길이', '고압 세척 장비', '야간·긴급 작업'],
    baseLabor: { min: 50000, typical: 90000, max: 200000 },
    urgencyMultipliers: { emergency: 1.4, today: 1.15 },
    sanity: { min: 20000, max: 1000000 },
    sortOrder: 50,
  }),
  trade({
    id: 'leak.detection',
    category: '누수',
    subcategory: '누수 탐지',
    aliases: ['누수탐지', '누수 검사'],
    symptomTags: ['천장 누수', '벽체 누수', '수도 요금 급증'],
    workScopeTags: ['누수 탐지', '장비 점검', '부분 철거'],
    requiredQuestions: ['leak_visible', 'urgency', 'property_type'],
    optionalQuestions: ['photos', 'access_difficulty', 'symptom_started'],
    priceFactors: ['출장비', '탐지 장비비', '탐지 범위', '부분 철거 필요', '후속 보수 별도'],
    baseLabor: { min: 100000, typical: 180000, max: 350000 },
    visitFee: { applies: true, typical: 20000 },
    urgencyMultipliers: { emergency: 1.35, today: 1.15 },
    sanity: { min: 50000, max: 1500000 },
    thresholds: { sufficientCompletedJobs: 6, preliminaryMinSamples: 3 },
    sortOrder: 60,
  }),
  trade({
    id: 'waterproof.silicone_caulking',
    category: '방수',
    subcategory: '실리콘·코킹 보수',
    aliases: ['실리콘 재시공', '코킹', '줄눈 보수'],
    symptomTags: ['곰팡이', '들뜸', '틈새'],
    workScopeTags: ['기존 실리콘 제거', '실리콘 재시공', '곰팡이 제거'],
    requiredQuestions: ['area_size', 'urgency', 'property_type'],
    optionalQuestions: ['photos', 'access_difficulty'],
    priceFactors: ['출장비', '기본 작업비', '시공 길이', '기존 실리콘 제거', '자재비'],
    baseLabor: { min: 50000, typical: 90000, max: 200000 },
    materialIncludedByDefault: true,
    urgencySurchargeApplies: false,
    sanity: { min: 20000, max: 1200000 },
    sortOrder: 70,
  }),
  trade({
    id: 'waterproof.small_repair',
    category: '방수',
    subcategory: '소규모 방수 보수',
    aliases: ['부분 방수', '방수 보수', '우레탄 보수'],
    symptomTags: ['빗물 유입', '균열', '들뜸'],
    workScopeTags: ['균열 보수', '우레탄 도포', '프라이머 시공'],
    requiredQuestions: ['area_size', 'urgency', 'property_type'],
    optionalQuestions: ['photos', 'access_difficulty', 'symptom_started'],
    priceFactors: ['출장비', '기본 작업비', '시공 면적', '자재비(우레탄)', '날씨·건조 시간', '부가세 포함 여부'],
    baseLabor: { min: 150000, typical: 350000, max: 800000 },
    materialIncludedByDefault: true,
    visitFee: { applies: true, typical: 20000 },
    urgencySurchargeApplies: false,
    sanity: { min: 50000, max: 5000000 },
    thresholds: { sufficientCompletedJobs: 6, preliminaryMinSamples: 3 },
    sortOrder: 80,
  }),
  trade({
    id: 'plumbing.pipe_leak_repair',
    category: '배관',
    subcategory: '배관 누수 보수',
    aliases: ['배관 누수', '수도관 누수', '배관 보수'],
    symptomTags: ['누수', '천장 누수', '수압 저하'],
    workScopeTags: ['배관 교체', '부분 철거', '연결부 보수'],
    requiredQuestions: ['leak_visible', 'urgency', 'property_type'],
    optionalQuestions: ['photos', 'access_difficulty', 'prior_repair'],
    priceFactors: ['출장비', '기본 작업비', '부분 철거·복구', '자재비(배관)', '작업 난이도', '야간·긴급 작업'],
    baseLabor: { min: 100000, typical: 200000, max: 500000 },
    visitFee: { applies: true, typical: 20000 },
    urgencyMultipliers: { emergency: 1.4, today: 1.2 },
    sanity: { min: 50000, max: 3000000 },
    thresholds: { sufficientCompletedJobs: 6, preliminaryMinSamples: 3 },
    sortOrder: 90,
  }),
  trade({
    id: 'kitchen.drain_issue',
    category: '주방',
    subcategory: '주방 배수 문제',
    aliases: ['주방 배수', '싱크 배수 불량', '주방 하수'],
    symptomTags: ['배수 지연', '악취', '누수'],
    workScopeTags: ['트랩 교체', '관통 작업', '배수관 보수'],
    requiredQuestions: ['clog_severity', 'urgency', 'property_type'],
    optionalQuestions: ['photos', 'access_difficulty', 'prior_repair'],
    priceFactors: ['출장비', '기본 작업비', '트랩·배수관 자재', '싱크 하부 철거', '야간·긴급 작업'],
    baseLabor: { min: 50000, typical: 90000, max: 200000 },
    urgencyMultipliers: { emergency: 1.4, today: 1.15 },
    sanity: { min: 20000, max: 1000000 },
    sortOrder: 100,
  }),
]

// -----------------------------------------------------------------------------
// 정규화 — AI 자유 텍스트를 검증 가능한 enum/tag 로 바꿉니다.
// -----------------------------------------------------------------------------

const URGENCY_ALIASES: Record<string, Urgency> = {
  emergency: 'emergency',
  urgent: 'emergency',
  high: 'today',
  today: 'today',
  soon: 'soon',
  normal: 'normal',
  low: 'normal',
  긴급: 'emergency',
  '지금 당장': 'emergency',
  오늘: 'today',
  '2~3일': 'soon',
  '급하지 않': 'normal',
}

export function normalizeUrgency(value: unknown): Urgency | null {
  const raw = String(value ?? '').trim()
  if (!raw) return null
  if ((URGENCY_LEVELS as readonly string[]).includes(raw)) return raw as Urgency
  const lower = raw.toLowerCase()
  if (URGENCY_ALIASES[lower]) return URGENCY_ALIASES[lower]
  const hit = Object.keys(URGENCY_ALIASES).find((k) => raw.includes(k))
  return hit ? URGENCY_ALIASES[hit] : null
}

const PROPERTY_ALIASES: Record<string, PropertyType> = {
  아파트: 'apartment',
  빌라: 'villa',
  다세대: 'villa',
  연립: 'villa',
  단독: 'house',
  주택: 'house',
  오피스텔: 'officetel',
  상가: 'commercial',
  매장: 'commercial',
  점포: 'commercial',
  사무실: 'office',
  오피스: 'office',
}

export function normalizePropertyType(value: unknown): PropertyType | null {
  const raw = String(value ?? '').trim()
  if (!raw) return null
  if ((PROPERTY_TYPES as readonly string[]).includes(raw)) return raw as PropertyType
  const hit = Object.keys(PROPERTY_ALIASES).find((k) => raw.includes(k))
  return hit ? PROPERTY_ALIASES[hit] : null
}

export function normalizeAccessDifficulty(value: unknown): AccessDifficulty | null {
  const raw = String(value ?? '').trim()
  if (!raw) return null
  if ((ACCESS_DIFFICULTIES as readonly string[]).includes(raw)) return raw as AccessDifficulty
  if (/철거|해체/.test(raw)) return 'hard'
  if (/좁|가구/.test(raw)) return 'tight'
  if (/바로|쉬움|easy/i.test(raw)) return 'easy'
  return null
}

const REGION_LEVEL1: { canonical: string; patterns: RegExp }[] = [
  { canonical: '서울', patterns: /서울/ },
  { canonical: '부산', patterns: /부산/ },
  { canonical: '대구', patterns: /대구/ },
  { canonical: '인천', patterns: /인천/ },
  { canonical: '광주', patterns: /광주/ },
  { canonical: '대전', patterns: /대전/ },
  { canonical: '울산', patterns: /울산/ },
  { canonical: '세종', patterns: /세종/ },
  { canonical: '경기', patterns: /경기/ },
  { canonical: '강원', patterns: /강원/ },
  { canonical: '충북', patterns: /충북|충청북/ },
  { canonical: '충남', patterns: /충남|충청남/ },
  { canonical: '전북', patterns: /전북|전라북/ },
  { canonical: '전남', patterns: /전남|전라남/ },
  { canonical: '경북', patterns: /경북|경상북/ },
  { canonical: '경남', patterns: /경남|경상남/ },
  { canonical: '제주', patterns: /제주/ },
]

/** 주소 문자열이나 지역명에서 시·도를 뽑습니다. 못 찾으면 null. */
export function normalizeRegionLevel1(value: unknown): string | null {
  const raw = String(value ?? '').trim()
  if (!raw) return null
  const hit = REGION_LEVEL1.find((r) => r.patterns.test(raw))
  return hit ? hit.canonical : null
}

/** 주소에서 시/군/구를 뽑습니다. "경기 성남시 분당구 ..." → "성남시". */
export function normalizeRegionLevel2(value: unknown): string | null {
  const raw = String(value ?? '').trim()
  if (!raw) return null
  const match = raw.match(/([가-힣]{2,10}(?:시|군|구))/g)
  if (!match) return null
  const first = match.find((m) => !REGION_LEVEL1.some((r) => r.patterns.test(m)))
  return first || match[0] || null
}

/** 허용 목록에 있는 값만 남깁니다. 없는 값은 조용히 버립니다(가격 계산 오염 방지). */
export function normalizeTags(allowed: string[], values: unknown): string[] {
  if (!Array.isArray(values)) return []
  const allowedSet = new Set(allowed)
  const out: string[] = []
  for (const v of values) {
    const s = String(v ?? '').trim()
    if (!s) continue
    if (allowedSet.has(s) && !out.includes(s)) {
      out.push(s)
      continue
    }
    const loose = allowed.find((a) => a === s || s.includes(a) || a.includes(s))
    if (loose && !out.includes(loose)) out.push(loose)
  }
  return out
}

export type TradeMatch = {
  trade: TradeDefinition | null
  /** 어느 공정인지 확정하지 못했을 때 고객에게 보여줄 후보. */
  candidates: TradeDefinition[]
}

/**
 * category/subcategory/자유 텍스트로 공정을 찾습니다.
 * 확정하지 못하면 trade=null 과 후보 목록을 돌려주고, 호출부는 고객에게 선택지를 보여줍니다.
 */
export function resolveTrade(
  trades: TradeDefinition[],
  input: { tradeId?: unknown; category?: unknown; subcategory?: unknown; text?: unknown },
): TradeMatch {
  const active = trades.filter((t) => t.active)
  const tradeId = String(input.tradeId ?? '').trim()
  if (tradeId) {
    const byId = active.find((t) => t.id === tradeId)
    if (byId) return { trade: byId, candidates: [byId] }
  }

  const category = String(input.category ?? '').trim()
  const subcategory = String(input.subcategory ?? '').trim()
  const text = String(input.text ?? '').trim()

  if (subcategory) {
    const exact = active.find((t) => t.subcategory === subcategory)
    if (exact) return { trade: exact, candidates: [exact] }
    const alias = active.find(
      (t) => t.aliases.includes(subcategory) || t.aliases.some((a) => subcategory.includes(a)),
    )
    if (alias) return { trade: alias, candidates: [alias] }
  }

  const haystack = `${subcategory} ${text}`.trim()
  if (haystack) {
    const keywordHits = active.filter((t) =>
      [t.subcategory, ...t.aliases].some((k) => k && haystack.includes(k)),
    )
    if (keywordHits.length === 1) return { trade: keywordHits[0], candidates: keywordHits }
    if (keywordHits.length > 1) return { trade: null, candidates: keywordHits }
  }

  if (category) {
    const inCategory = active.filter((t) => t.category === category)
    if (inCategory.length === 1) return { trade: inCategory[0], candidates: inCategory }
    if (inCategory.length > 1) return { trade: null, candidates: inCategory }
  }

  return { trade: null, candidates: [] }
}

export function questionsForTrade(
  questions: QuestionDefinition[],
  t: TradeDefinition,
): { required: QuestionDefinition[]; optional: QuestionDefinition[] } {
  const byId = new Map(questions.map((q) => [q.id, q]))
  const pick = (ids: string[]) => ids.map((id) => byId.get(id)).filter((q): q is QuestionDefinition => !!q)
  return { required: pick(t.requiredQuestions), optional: pick(t.optionalQuestions) }
}

/**
 * 선택지에 매핑된 태그를 뽑습니다. tagMap 이 있으면 그것만 씁니다.
 * tagMap 이 없는 질문은 라벨을 그대로 후보로 넘겨 기존 동작을 유지합니다.
 */
function tagCandidates(q: QuestionDefinition, values: unknown[], labels: string[]): string[] {
  if (!q.tagMap) return labels
  const out: string[] = []
  for (const v of values) {
    const mapped = q.tagMap[String(v ?? '')]
    if (mapped) out.push(...mapped)
  }
  return out
}

/** 답변 맵({questionId: value})을 가격 엔진 입력으로 정규화합니다. */
export function answersToPriceInput(
  questions: QuestionDefinition[],
  t: TradeDefinition,
  answers: Record<string, unknown>,
): {
  urgency: Urgency | null
  propertyType: PropertyType | null
  accessDifficulty: AccessDifficulty | null
  materialIncluded: boolean | null
  workScopeTags: string[]
  symptomTags: string[]
} {
  const byId = new Map(questions.map((q) => [q.id, q]))
  const out = {
    urgency: null as Urgency | null,
    propertyType: null as PropertyType | null,
    accessDifficulty: null as AccessDifficulty | null,
    materialIncluded: null as boolean | null,
    workScopeTags: [] as string[],
    symptomTags: [] as string[],
  }

  for (const [id, rawValue] of Object.entries(answers || {})) {
    const q = byId.get(id)
    if (!q || !q.mapsTo) continue
    const values = Array.isArray(rawValue) ? rawValue : [rawValue]
    const labels = values.map((v) => {
      const s = String(v ?? '')
      return q.options.find((o) => o.value === s)?.label || s
    })

    switch (q.mapsTo) {
      case 'urgency':
        out.urgency = normalizeUrgency(values[0]) ?? normalizeUrgency(labels[0])
        break
      case 'propertyType':
        out.propertyType = normalizePropertyType(values[0]) ?? normalizePropertyType(labels[0])
        break
      case 'accessDifficulty':
        out.accessDifficulty = normalizeAccessDifficulty(values[0]) ?? normalizeAccessDifficulty(labels[0])
        break
      case 'materialIncluded': {
        const v = String(values[0] ?? '')
        if (v === 'contractor') out.materialIncluded = true
        else if (v === 'customer') out.materialIncluded = false
        break
      }
      case 'workScopeTags':
        out.workScopeTags.push(...normalizeTags(t.workScopeTags, tagCandidates(q, values, labels)))
        break
      case 'symptomTags':
        out.symptomTags.push(...normalizeTags(t.symptomTags, tagCandidates(q, values, labels)))
        break
    }
  }

  out.workScopeTags = Array.from(new Set(out.workScopeTags))
  out.symptomTags = Array.from(new Set(out.symptomTags))
  return out
}
