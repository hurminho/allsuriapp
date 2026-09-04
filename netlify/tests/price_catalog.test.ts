import { describe, expect, it } from 'vitest'
import {
  DEFAULT_QUESTIONS,
  DEFAULT_TRADES,
  answersToPriceInput,
  normalizeAccessDifficulty,
  normalizePropertyType,
  normalizeRegionLevel1,
  normalizeRegionLevel2,
  normalizeTags,
  normalizeUrgency,
  questionsForTrade,
  resolveTrade,
} from '../lib/price_catalog'

const toiletClog = DEFAULT_TRADES.find((t) => t.id === 'plumbing.toilet_clog')!

describe('초기 공정 카탈로그', () => {
  it('초기 지원 공정 10종이 모두 정의되어 있습니다', () => {
    expect(DEFAULT_TRADES).toHaveLength(10)
    const subcategories = DEFAULT_TRADES.map((t) => t.subcategory)
    for (const expected of [
      '변기 막힘',
      '싱크대 막힘',
      '세면대·수전 교체',
      '샤워기 교체',
      '단순 배관 막힘',
      '누수 탐지',
      '실리콘·코킹 보수',
      '소규모 방수 보수',
      '배관 누수 보수',
      '주방 배수 문제',
    ]) {
      expect(subcategories).toContain(expected)
    }
  })

  it('모든 공정에 필수 질문·가격 요인·sanity 범위가 있습니다', () => {
    for (const t of DEFAULT_TRADES) {
      expect(t.requiredQuestions.length).toBeGreaterThan(0)
      expect(t.priceFactors.length).toBeGreaterThan(0)
      expect(t.sanity.min).toBeGreaterThan(0)
      expect(t.sanity.max).toBeGreaterThan(t.sanity.min)
      expect(t.baseLabor.min).toBeLessThanOrEqual(t.baseLabor.typical)
      expect(t.baseLabor.typical).toBeLessThanOrEqual(t.baseLabor.max)
    }
  })

  it('필수·선택 질문 id 가 모두 질문 은행에 있습니다', () => {
    const known = new Set(DEFAULT_QUESTIONS.map((q) => q.id))
    for (const t of DEFAULT_TRADES) {
      for (const id of [...t.requiredQuestions, ...t.optionalQuestions]) {
        expect(known.has(id)).toBe(true)
      }
    }
  })
})

describe('열거값 정규화', () => {
  it('긴급도는 한국어·영어·웹 표기를 모두 받습니다', () => {
    expect(normalizeUrgency('emergency')).toBe('emergency')
    expect(normalizeUrgency('긴급')).toBe('emergency')
    expect(normalizeUrgency('high')).toBe('today')
    expect(normalizeUrgency('low')).toBe('normal')
    expect(normalizeUrgency('')).toBeNull()
    expect(normalizeUrgency('아무말')).toBeNull()
  })

  it('건물 유형', () => {
    expect(normalizePropertyType('아파트')).toBe('apartment')
    expect(normalizePropertyType('빌라·다세대')).toBe('villa')
    expect(normalizePropertyType('commercial')).toBe('commercial')
    expect(normalizePropertyType('우주선')).toBeNull()
  })

  it('접근 난이도', () => {
    expect(normalizeAccessDifficulty('철거·해체가 필요해 보여요')).toBe('hard')
    expect(normalizeAccessDifficulty('좁거나 가구를 옮겨야 해요')).toBe('tight')
    expect(normalizeAccessDifficulty('바로 접근 가능')).toBe('easy')
  })

  it('주소에서 시·도와 시·군·구를 뽑습니다', () => {
    expect(normalizeRegionLevel1('경기 성남시 분당구 판교로 1')).toBe('경기')
    expect(normalizeRegionLevel1('서울특별시 강남구')).toBe('서울')
    expect(normalizeRegionLevel1('충청북도 청주시')).toBe('충북')
    expect(normalizeRegionLevel1('')).toBeNull()
    expect(normalizeRegionLevel2('경기 성남시 분당구 판교로 1')).toBe('성남시')
  })

  it('허용 목록 밖 태그는 버립니다 (가격 계산 오염 방지)', () => {
    const tags = normalizeTags(toiletClog.workScopeTags, ['관통 작업', '금 도금 변기 설치'])
    expect(tags).toEqual(['관통 작업'])
  })

  it('배열이 아니면 빈 배열', () => {
    expect(normalizeTags(toiletClog.workScopeTags, '관통 작업')).toEqual([])
  })
})

describe('resolveTrade', () => {
  it('tradeId 가 있으면 그대로 확정', () => {
    const match = resolveTrade(DEFAULT_TRADES, { tradeId: 'leak.detection' })
    expect(match.trade?.id).toBe('leak.detection')
  })

  it('subcategory 정확 일치', () => {
    expect(resolveTrade(DEFAULT_TRADES, { subcategory: '변기 막힘' }).trade?.id).toBe(
      'plumbing.toilet_clog',
    )
  })

  it('별칭으로도 찾습니다', () => {
    expect(resolveTrade(DEFAULT_TRADES, { subcategory: '변기막힘' }).trade?.id).toBe(
      'plumbing.toilet_clog',
    )
  })

  it('자유 텍스트 키워드 단일 일치', () => {
    const match = resolveTrade(DEFAULT_TRADES, { text: '누수 탐지를 받고 싶어요' })
    expect(match.trade?.id).toBe('leak.detection')
  })

  it('후보가 여러 개면 확정하지 않고 후보를 돌려줍니다', () => {
    const match = resolveTrade(DEFAULT_TRADES, { category: '배관' })
    expect(match.trade).toBeNull()
    expect(match.candidates.length).toBeGreaterThan(1)
  })

  it('아무 정보도 없으면 후보도 없습니다', () => {
    const match = resolveTrade(DEFAULT_TRADES, {})
    expect(match.trade).toBeNull()
    expect(match.candidates).toEqual([])
  })

  it('active=false 공정은 매칭되지 않습니다', () => {
    const disabled = DEFAULT_TRADES.map((t) =>
      t.id === 'leak.detection' ? { ...t, active: false } : t,
    )
    expect(resolveTrade(disabled, { tradeId: 'leak.detection' }).trade).toBeNull()
  })
})

describe('answersToPriceInput', () => {
  it('선택지 value 를 엔진 입력으로 정규화합니다', () => {
    const input = answersToPriceInput(DEFAULT_QUESTIONS, toiletClog, {
      urgency: 'emergency',
      property_type: 'apartment',
      access_difficulty: 'hard',
      clog_severity: 'none',
      fixture_supply: 'contractor',
    })
    expect(input.urgency).toBe('emergency')
    expect(input.propertyType).toBe('apartment')
    expect(input.accessDifficulty).toBe('hard')
    expect(input.materialIncluded).toBe(true)
    // tag_map 을 통해 선택지가 작업 범위 태그로 바뀝니다.
    expect(input.workScopeTags).toContain('관통 작업')
    expect(input.workScopeTags).toContain('고압 세척')
  })

  it('선택지 태그는 해당 공정이 허용한 것만 남습니다', () => {
    // overflow 는 '배수관 보수'도 내놓지만 변기 막힘 공정에는 없는 태그입니다.
    const input = answersToPriceInput(DEFAULT_QUESTIONS, toiletClog, { clog_severity: 'overflow' })
    expect(input.workScopeTags).toEqual(expect.arrayContaining(['관통 작업', '고압 세척', '변기 탈착']))
    expect(input.workScopeTags).not.toContain('배수관 보수')
    for (const tag of input.workScopeTags) {
      expect(toiletClog.workScopeTags).toContain(tag)
    }
  })

  it('매핑이 없는 선택지(unknown)는 태그를 만들지 않습니다', () => {
    const input = answersToPriceInput(DEFAULT_QUESTIONS, toiletClog, { clog_severity: 'unknown' })
    expect(input.workScopeTags).toEqual([])
  })

  it('공정별로 같은 답이 다른 태그를 만듭니다', () => {
    const leakDetection = DEFAULT_TRADES.find((t) => t.id === 'leak.detection')!
    const pipeRepair = DEFAULT_TRADES.find((t) => t.id === 'plumbing.pipe_leak_repair')!
    const answers = { leak_visible: 'hidden' }
    expect(answersToPriceInput(DEFAULT_QUESTIONS, leakDetection, answers).workScopeTags).toEqual(
      expect.arrayContaining(['누수 탐지', '장비 점검']),
    )
    // 배관 누수 보수에는 '누수 탐지' 태그가 없으므로 아무 태그도 남지 않습니다.
    expect(answersToPriceInput(DEFAULT_QUESTIONS, pipeRepair, answers).workScopeTags).toEqual([])
  })

  it('고객이 준비한 자재는 materialIncluded=false', () => {
    const input = answersToPriceInput(DEFAULT_QUESTIONS, toiletClog, { fixture_supply: 'customer' })
    expect(input.materialIncluded).toBe(false)
  })

  it('모르는 질문 id 는 무시합니다', () => {
    const input = answersToPriceInput(DEFAULT_QUESTIONS, toiletClog, { 아무거나: '값' })
    expect(input.urgency).toBeNull()
    expect(input.workScopeTags).toEqual([])
  })

  it('참고용 질문(maps_to=null)은 가격 입력에 들어가지 않습니다', () => {
    const input = answersToPriceInput(DEFAULT_QUESTIONS, toiletClog, { symptom_started: 'today' })
    expect(input.urgency).toBeNull()
  })
})

describe('questionsForTrade', () => {
  it('공정 정의 순서대로 필수·선택 질문을 돌려줍니다', () => {
    const { required, optional } = questionsForTrade(DEFAULT_QUESTIONS, toiletClog)
    expect(required.map((q) => q.id)).toEqual(toiletClog.requiredQuestions)
    expect(optional.map((q) => q.id)).toEqual(toiletClog.optionalQuestions)
  })
})
