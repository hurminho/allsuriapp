// 통합 테스트: 견적 요청 → 사업자 입찰 → 최종 완료금액 저장까지.
//
// PostgREST 를 메모리 저장소로 흉내내어 /api/price/* 와 /api/market/* 핸들러를
// 실제 라우팅·정규화·엔진 계산을 모두 통과시켜 검증합니다.

import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'

const SUPABASE_URL = 'https://fake.supabase.co'
const SERVICE_KEY = 'service-role-test-key'
const ADMIN_TOKEN = 'admin-test-token'

type Row = Record<string, any>

/** 테이블별 메모리 저장소. 마이그레이션을 실행한 환경을 흉내냅니다. */
const db = new Map<string, Row[]>()
/** 이 목록에 없는 테이블은 42P01(테이블 없음)로 응답합니다. */
const existingTables = new Set([
  'trade_catalog',
  'price_questions',
  'price_engine_settings',
  'price_baselines',
  'contractor_rate_cards',
  'completed_jobs',
  'price_estimates',
  'order_bids',
  'marketplace_listings',
  'orders',
  'users',
  'notifications',
  'jobs',
  'chat_rooms',
  'chat_messages',
])

function table(name: string): Row[] {
  if (!db.has(name)) db.set(name, [])
  return db.get(name)!
}

let idSeq = 0
const nextId = (prefix: string) => `${prefix}-${String(++idSeq).padStart(4, '0')}`

// -----------------------------------------------------------------------------
// 아주 작은 PostgREST 흉내 — 이 코드가 실제로 쓰는 연산자만 지원합니다.
// -----------------------------------------------------------------------------

function matches(row: Row, column: string, expr: string): boolean {
  const value = row[column]
  if (expr === 'not.is.null') return value != null
  if (expr === 'is.true') return value === true
  if (expr === 'is.false') return value === false
  if (expr === 'is.null') return value == null
  if (expr.startsWith('eq.')) return String(value) === decodeURIComponent(expr.slice(3))
  if (expr.startsWith('neq.')) return String(value) !== decodeURIComponent(expr.slice(4))
  if (expr.startsWith('gte.')) return String(value ?? '') >= decodeURIComponent(expr.slice(4))
  if (expr.startsWith('lte.')) return String(value ?? '') <= decodeURIComponent(expr.slice(4))
  if (expr.startsWith('in.')) {
    const set = decodeURIComponent(expr.slice(3)).replace(/^\(|\)$/g, '').split(',')
    return set.includes(String(value))
  }
  throw new Error(`흉내내지 않은 연산자: ${column}=${expr}`)
}

function runSelect(name: string, params: URLSearchParams): Row[] {
  let rows = table(name).slice()
  for (const [key, expr] of params.entries()) {
    if (['select', 'order', 'limit', 'offset', 'on_conflict', 'or'].includes(key)) continue
    rows = rows.filter((r) => matches(r, key, expr))
  }
  const order = params.get('order')
  if (order) {
    const [column, dir] = order.split('.')
    rows.sort((a, b) => {
      const av = a[column] ?? ''
      const bv = b[column] ?? ''
      const cmp = av < bv ? -1 : av > bv ? 1 : 0
      return dir === 'desc' ? -cmp : cmp
    })
  }
  const limit = Number(params.get('limit'))
  if (Number.isFinite(limit) && limit > 0) rows = rows.slice(0, limit)
  return rows
}

/** on_conflict 대상 컬럼이 모두 같은 기존 행을 찾습니다. */
function findConflict(name: string, keys: string[], row: Row): Row | undefined {
  if (!keys.length) return undefined
  return table(name).find((existing) => keys.every((k) => (existing[k] ?? null) === (row[k] ?? null)))
}

const requestLog: { method: string; table: string; body?: any }[] = []

/** 이 코드가 부르는 RPC 만 흉내냅니다. fn_business_can_act 는 없을 때(404)의 대체 판정을 검증합니다. */
function rpcHandler(fn: string, body: any): Response {
  if (fn === 'select_bidder') {
    const bid = table('order_bids').find((b) => b.listing_id === body.p_listing_id && b.bidder_id === body.p_bidder_id)
    if (!bid) return new Response(JSON.stringify({ code: 'P0001', message: 'bid not found' }), { status: 400 })
    bid.status = 'selected'
    return new Response('true', { status: 200 })
  }
  if (fn === 'claim_listing') {
    const listing = table('marketplace_listings').find((l) => l.id === body.p_listing_id && !l.claimed_by)
    if (!listing) return new Response('false', { status: 200 })
    listing.claimed_by = body.p_business_id
    listing.status = 'assigned'
    return new Response('true', { status: 200 })
  }
  return new Response(JSON.stringify({ code: 'PGRST202', message: `Could not find the function public.${fn}` }), { status: 404 })
}

function postgrestHandler(url: URL, init: RequestInit | undefined): Response {
  const name = url.pathname.replace('/rest/v1/', '')
  const method = String(init?.method || 'GET').toUpperCase()
  const body = init?.body ? JSON.parse(String(init.body)) : undefined
  requestLog.push({ method, table: name, body })
  if (name.startsWith('rpc/')) return rpcHandler(name.slice(4), body)

  if (!existingTables.has(name)) {
    return new Response(JSON.stringify({ code: '42P01', message: `relation "${name}" does not exist` }), {
      status: 404,
    })
  }

  if (method === 'GET') {
    return new Response(JSON.stringify(runSelect(name, url.searchParams)), { status: 200 })
  }

  if (method === 'POST') {
    const rows: Row[] = Array.isArray(body) ? body : [body]
    const conflictKeys = (url.searchParams.get('on_conflict') || '').split(',').filter(Boolean)
    const merge = String((init?.headers as any)?.Prefer || '').includes('merge-duplicates')
    const saved: Row[] = []
    for (const incoming of rows) {
      const existing = merge ? findConflict(name, conflictKeys, incoming) : undefined
      if (existing) {
        Object.assign(existing, incoming)
        saved.push(existing)
      } else {
        const created = { id: incoming.id ?? nextId(name), created_at: new Date().toISOString(), ...incoming }
        table(name).push(created)
        saved.push(created)
      }
    }
    return new Response(JSON.stringify(saved), { status: 201 })
  }

  if (method === 'PATCH') {
    const targets = runSelect(name, url.searchParams)
    for (const t of targets) Object.assign(t, body)
    return new Response(JSON.stringify(targets), { status: 200 })
  }

  return new Response('[]', { status: 200 })
}

function fakeFetch(input: any, init?: RequestInit): Promise<Response> {
  const url = new URL(String(input))
  if (url.pathname.startsWith('/rest/v1/')) {
    return Promise.resolve(postgrestHandler(url, init))
  }
  // 사업자 인증: Bearer <userId> 를 그대로 사용자로 인정합니다.
  if (url.pathname === '/auth/v1/user') {
    const auth = String((init?.headers as any)?.Authorization || '')
    const token = auth.replace(/^Bearer\s+/i, '')
    if (!token || token === 'invalid') return Promise.resolve(new Response('{}', { status: 401 }))
    return Promise.resolve(new Response(JSON.stringify({ id: token }), { status: 200 }))
  }
  // 백그라운드 함수 호출·SMS 등 외부 호출은 성공으로 흘려보냅니다.
  return Promise.resolve(new Response('{}', { status: 200 }))
}

// -----------------------------------------------------------------------------
// 픽스처
// -----------------------------------------------------------------------------

const TRADE_ID = 'plumbing.toilet_clog'
const CONTRACTOR = 'contractor-1111'

function daysAgo(n: number): string {
  return new Date(Date.now() - n * 86400000).toISOString()
}

function seedListing() {
  table('orders').push({
    id: 'order-1',
    title: '변기가 막혔어요',
    description: '물이 전혀 안 내려갑니다',
    category: '배관',
    subcategory: '변기 막힘',
    tradeId: TRADE_ID,
    address: '서울특별시 강남구 역삼동',
    propertyType: 'apartment',
    urgency: 'today',
    status: 'pending',
  })
  table('marketplace_listings').push({
    id: 'listing-1',
    title: '변기가 막혔어요',
    description: '물이 전혀 안 내려갑니다',
    category: '배관',
    region: '서울특별시 강남구',
    web_order_id: 'order-1',
    status: 'open',
    posted_by: 'web',
  })
}

/** 입찰 가능한 사업자(승인 + 사업자등록번호). fn_business_can_act 와 같은 기준입니다. */
function seedContractor(id: string = CONTRACTOR, overrides: Row = {}) {
  table('users').push({
    id,
    name: '올수리설비',
    role: 'business',
    businessstatus: 'approved',
    businessnumber: '123-45-67890',
    business_verify_bypass: false,
    ...overrides,
  })
}

function seedCompletedJobs(amounts: number[], overrides: Row = {}) {
  amounts.forEach((amount, i) => {
    table('completed_jobs').push({
      id: nextId('cj'),
      trade_id: TRADE_ID,
      final_total_amount: amount,
      completion_at: daysAgo(i * 3 + 1),
      // 저장·조회 모두 normalizeRegionLevel1 의 정규형('서울')을 씁니다.
      region_level1: '서울',
      region_level2: '강남구',
      property_type: 'apartment',
      final_work_scope_tags: ['관통 작업'],
      vat_included: true,
      ...overrides,
    })
  })
}

// -----------------------------------------------------------------------------

let price: { handler: (event: any) => Promise<any> }
let market: { handler: (event: any) => Promise<any> }
const realFetch = globalThis.fetch

function priceEvent(path: string, options: { method?: string; body?: any; headers?: Row; query?: Row } = {}) {
  return {
    path: `/api/price${path}`,
    httpMethod: options.method || 'GET',
    headers: options.headers || {},
    queryStringParameters: options.query || {},
    body: options.body ? JSON.stringify(options.body) : null,
  }
}

async function callPrice(path: string, options?: Parameters<typeof priceEvent>[1]) {
  const res = await price.handler(priceEvent(path, options))
  return { status: res.statusCode, body: JSON.parse(res.body || '{}') }
}

beforeAll(async () => {
  process.env.SUPABASE_URL = SUPABASE_URL
  process.env.SUPABASE_SERVICE_ROLE_KEY = SERVICE_KEY
  process.env.ADMIN_TOKEN = ADMIN_TOKEN
  process.env.MARKET_BID_SECRET = 'bid-secret'
  globalThis.fetch = fakeFetch as any
  vi.resetModules()
  price = await import('../functions/price')
  market = await import('../functions/market')
})

afterAll(() => {
  globalThis.fetch = realFetch
})

beforeEach(async () => {
  db.clear()
  requestLog.length = 0
  idSeq = 0
  // 카탈로그 캐시(60초)를 비웁니다. 설정 저장은 캐시를 무효화합니다.
  const repo = await import('../lib/price_repository')
  await repo.upsertSetting('thresholds', {}, 'test')
  db.clear()
})

// -----------------------------------------------------------------------------

describe('GET /catalog', () => {
  it('마이그레이션 미실행 환경에서도 코드 기본 카탈로그를 내려줍니다', async () => {
    existingTables.delete('trade_catalog')
    try {
      const { status, body } = await callPrice('/catalog')
      expect(status).toBe(200)
      expect(body.source).toBe('defaults')
      expect(body.trades).toHaveLength(10)
    } finally {
      existingTables.add('trade_catalog')
    }
  })

  it('공정과 질문, 열거값을 함께 내려줍니다', async () => {
    const { body } = await callPrice('/catalog')
    expect(body.engineVersion).toBe('v1')
    expect(body.categories).toContain('배관')
    expect(body.enums.priceState).toEqual(['sufficient', 'preliminary', 'insufficient'])
    const toilet = body.trades.find((t: Row) => t.id === TRADE_ID)
    expect(toilet.requiredQuestions).toContain('clog_severity')
  })
})

describe('POST /estimate — 데이터 부족', () => {
  it('표본이 없으면 금액을 만들지 않습니다', async () => {
    const { status, body } = await callPrice('/estimate', {
      method: 'POST',
      body: { tradeId: TRADE_ID, locationLevel1: '서울', urgency: 'normal' },
    })
    expect(status).toBe(200)
    expect(body.priceState).toBe('insufficient')
    expect(body.estimatedMin).toBeNull()
    expect(body.estimatedMax).toBeNull()
    expect(body.uiCopy.showAmount).toBe(false)
    expect(body.uiCopy.headline).toBe('현장 조건에 따라 차이가 큰 작업')
    expect(body.uiCopy.cta).toBe('무료로 업체 견적 받기')
  })

  it('공정을 확정하지 못하면 후보를 돌려주고 숫자를 감춥니다', async () => {
    const { body } = await callPrice('/estimate', {
      method: 'POST',
      body: { text: '뭔가 이상해요' },
    })
    expect(body.needsTradeSelection).toBe(true)
    expect(body.trade).toBeNull()
    expect(body.priceState).toBe('insufficient')
    expect(body.estimatedMin).toBeNull()
  })

  it('부족 상태에서도 스냅샷과 엔진 버전을 남깁니다', async () => {
    await callPrice('/estimate', { method: 'POST', body: { tradeId: TRADE_ID, sessionId: 'sess-1' } })
    await new Promise((r) => setTimeout(r, 0))
    const snapshots = table('price_estimates')
    expect(snapshots).toHaveLength(1)
    expect(snapshots[0].engine_version).toBe('v1')
    expect(snapshots[0].price_state).toBe('insufficient')
    expect(snapshots[0].estimated_min).toBeNull()
  })
})

describe('POST /estimate — 운영자 기준표만 있을 때', () => {
  it('기준표는 참고 범위(preliminary)까지만 올립니다', async () => {
    await callPrice('/admin/baselines', {
      method: 'POST',
      headers: { 'admin-token': ADMIN_TOKEN },
      body: { tradeId: TRADE_ID, minAmount: 60000, typicalAmount: 90000, maxAmount: 140000 },
    })

    const { body } = await callPrice('/estimate', { method: 'POST', body: { tradeId: TRADE_ID } })
    expect(body.priceState).toBe('preliminary')
    expect(body.uiCopy.headline).toBe('유사 사례를 바탕으로 한 참고 범위')
    expect(body.uiCopy.showAmount).toBe(true)
    expect(body.estimatedMin).toBeGreaterThan(0)
    expect(body.estimatedMax).toBeGreaterThan(body.estimatedMin)
    expect(body.basis.map((b: Row) => b.source)).toContain('baseline')
  })

  it('운영자 기준표는 min ≤ typical ≤ max 를 강제합니다', async () => {
    const { status, body } = await callPrice('/admin/baselines', {
      method: 'POST',
      headers: { 'admin-token': ADMIN_TOKEN },
      body: { tradeId: TRADE_ID, minAmount: 200000, typicalAmount: 90000, maxAmount: 140000 },
    })
    expect(status).toBe(400)
    expect(body.error).toContain('min ≤ typical ≤ max')
  })

  it('admin-token 없이는 기준표를 못 만집니다', async () => {
    const { status } = await callPrice('/admin/baselines', {
      method: 'POST',
      body: { tradeId: TRADE_ID, minAmount: 1, typicalAmount: 2, maxAmount: 3 },
    })
    expect(status).toBe(401)
  })
})

describe('POST /estimate — 완료 거래가 쌓였을 때', () => {
  it('완료 사례가 임계값을 넘으면 sufficient 로 올라갑니다', async () => {
    seedCompletedJobs([80000, 85000, 90000, 95000, 100000, 105000, 110000, 115000])
    const { body } = await callPrice('/estimate', {
      method: 'POST',
      body: { tradeId: TRADE_ID, locationLevel1: '서울특별시', locationLevel2: '강남구', propertyType: 'apartment' },
    })
    expect(body.priceState).toBe('sufficient')
    expect(body.completedJobCount).toBe(8)
    expect(body.uiCopy.headline).toBe('최근 유사 완료 작업 기준')
    expect(body.uiCopy.body).toContain('현장 상태, 자재, 긴급 출동 여부에 따라 달라질 수 있습니다')
    expect(body.estimatedMin).toBeLessThan(body.estimatedTypical)
    expect(body.estimatedTypical).toBeLessThan(body.estimatedMax)
    expect(body.confidenceLevel).toBe('high')
    expect(body.factors.length).toBeGreaterThan(0)
  })

  it('완료 금액이 입찰가보다 우선 반영됩니다', async () => {
    // 완료 금액은 10만원대, 입찰가는 30만원대. 결과는 완료 금액 쪽에 붙어야 합니다.
    seedCompletedJobs([95000, 100000, 100000, 105000, 100000, 98000, 102000, 101000])
    for (let i = 0; i < 20; i++) {
      table('order_bids').push({
        id: nextId('bid'),
        trade_id: TRADE_ID,
        bid_amount: 300000 + i * 1000,
        created_at: daysAgo(i + 1),
        work_scope_tags: ['관통 작업'],
        vat_included: true,
        breakdown_provided: true,
      })
    }
    const { body } = await callPrice('/estimate', { method: 'POST', body: { tradeId: TRADE_ID } })
    expect(body.priceState).toBe('sufficient')
    expect(body.estimatedTypical).toBeLessThan(150000)
    expect(body.estimatedMax).toBeLessThan(150000)

    // 완료 거래만으로 충분하므로 입찰 표본은 계산에서 제외되고, 근거에는 남습니다.
    const bidBasis = body.basis.find((b: Row) => b.source === 'contractor_bid')
    expect(bidBasis.sampleCount).toBe(20)
    expect(bidBasis.usedSampleCount).toBe(0)
    expect(bidBasis.weightShare).toBe(0)
    const completedBasis = body.basis.find((b: Row) => b.source === 'completed_job')
    expect(completedBasis.usedSampleCount).toBe(8)
    expect(completedBasis.weightShare).toBe(1)
  })

  it('완료 거래가 부족하면 입찰가로 내려가되 완료 거래를 밀어내지 않습니다', async () => {
    seedCompletedJobs([95000, 100000, 105000])
    for (let i = 0; i < 30; i++) {
      table('order_bids').push({
        id: nextId('bid'),
        trade_id: TRADE_ID,
        bid_amount: 300000 + i * 1000,
        created_at: daysAgo(i + 1),
        work_scope_tags: [],
        vat_included: true,
        breakdown_provided: true,
      })
    }
    const { body } = await callPrice('/estimate', { method: 'POST', body: { tradeId: TRADE_ID } })
    const completed = body.basis.find((b: Row) => b.source === 'completed_job')
    const bids = body.basis.find((b: Row) => b.source === 'contractor_bid')
    expect(bids.usedSampleCount).toBe(30)
    // 건수는 10배지만 가중치 상한(lowerTierWeightCap) 때문에 완료 거래가 과반을 지킵니다.
    expect(completed.weightShare).toBeGreaterThan(bids.weightShare)
    expect(body.estimatedTypical).toBeLessThan(150000)
  })

  it('이상치는 범위에서 빠집니다', async () => {
    seedCompletedJobs([90000, 92000, 95000, 98000, 100000, 102000, 105000, 108000])
    table('completed_jobs').push({
      id: 'cj-outlier',
      trade_id: TRADE_ID,
      final_total_amount: 700000, // sanity 안이지만 분포에서 크게 벗어남
      completion_at: daysAgo(2),
      region_level1: '서울',
      final_work_scope_tags: [],
      vat_included: true,
    })
    const { body } = await callPrice('/estimate', { method: 'POST', body: { tradeId: TRADE_ID } })
    expect(body.droppedOutlierCount).toBeGreaterThan(0)
    expect(body.estimatedMax).toBeLessThan(700000)
  })

  it('공정 통상 범위를 벗어난 금액은 표본에서 제외됩니다', async () => {
    seedCompletedJobs([90000, 95000, 100000, 105000])
    table('completed_jobs').push({
      id: 'cj-insane',
      trade_id: TRADE_ID,
      final_total_amount: 5_000_000, // sanity.max(800,000) 초과
      completion_at: daysAgo(1),
      final_work_scope_tags: [],
    })
    const { body } = await callPrice('/estimate', { method: 'POST', body: { tradeId: TRADE_ID } })
    expect(body.estimatedMax).toBeLessThan(800000)
  })

  it('긴급 조건은 범위를 올리고 변동 요인으로 표시됩니다', async () => {
    seedCompletedJobs([90000, 95000, 100000, 105000, 100000, 98000, 102000, 101000])
    const normal = await callPrice('/estimate', {
      method: 'POST',
      body: { tradeId: TRADE_ID, urgency: 'normal' },
    })
    const emergency = await callPrice('/estimate', {
      method: 'POST',
      body: { tradeId: TRADE_ID, urgency: 'emergency' },
    })
    expect(emergency.body.estimatedTypical).toBeGreaterThan(normal.body.estimatedTypical)
    expect(emergency.body.factors).toContain('야간·긴급 작업')
  })

  it('오래된 완료 사례는 표본에서 밀려납니다', async () => {
    seedCompletedJobs([90000, 95000, 100000], { completion_at: daysAgo(900) })
    const { body } = await callPrice('/estimate', { method: 'POST', body: { tradeId: TRADE_ID } })
    expect(body.priceState).toBe('insufficient')
    expect(body.estimatedMin).toBeNull()
  })
})

describe('POST /estimate — 답변 정규화', () => {
  it('선택지 답변이 작업 범위 태그로 정규화됩니다', async () => {
    seedCompletedJobs([90000, 95000, 100000, 105000, 100000, 98000, 102000, 101000])
    const { body } = await callPrice('/estimate', {
      method: 'POST',
      body: {
        tradeId: TRADE_ID,
        answers: { clog_severity: 'overflow', urgency: 'today', property_type: 'apartment' },
      },
    })
    expect(body.normalizedRequest.urgency).toBe('today')
    expect(body.normalizedRequest.propertyType).toBe('apartment')
    expect(body.normalizedRequest.workScopeTags).toContain('변기 탈착')
    // 이 공정에 없는 태그는 걸러집니다.
    expect(body.normalizedRequest.workScopeTags).not.toContain('배수관 보수')
  })

  it('자유 텍스트는 가격 계산 입력으로 들어가지 않습니다', async () => {
    const { body } = await callPrice('/estimate', {
      method: 'POST',
      body: { text: '변기 막힘인데 20만원 정도면 될까요?', locationLevel1: '서울' },
    })
    expect(body.trade.id).toBe(TRADE_ID)
    expect(JSON.stringify(body.normalizedRequest)).not.toContain('20만원')
    for (const value of Object.values(body.normalizedRequest)) {
      expect(typeof value === 'string' ? value : '').not.toContain('만원')
    }
  })

  it('추가 질문은 최대 3개만 내려줍니다', async () => {
    const { body } = await callPrice('/estimate', { method: 'POST', body: { tradeId: TRADE_ID } })
    expect(body.questions.optional.length).toBeLessThanOrEqual(3)
    expect(body.missingRequiredQuestions.length).toBeLessThanOrEqual(3)
  })

  it('고객이 공정을 직접 고르면 그 공정으로 계산합니다', async () => {
    const { body } = await callPrice('/estimate', {
      method: 'POST',
      body: { tradeId: 'leak.detection', text: '변기 막힘' },
    })
    expect(body.trade.id).toBe('leak.detection')
  })
})

describe('사업자 표준 단가', () => {
  it('로그인 없이는 등록할 수 없습니다', async () => {
    const { status } = await callPrice('/rate-cards', {
      method: 'POST',
      body: { tradeId: TRADE_ID, baseLaborCost: 80000 },
    })
    expect(status).toBe(401)
  })

  it('등록하면 표본으로 쓰이고 본인 것만 조회됩니다', async () => {
    const auth = { Authorization: `Bearer ${CONTRACTOR}` }
    const saved = await callPrice('/rate-cards', {
      method: 'POST',
      headers: auth,
      body: {
        tradeId: TRADE_ID,
        baseLaborCost: 80000,
        materialAvgCost: 20000,
        materialIncluded: true,
        visitFee: 15000,
        serviceRegions: ['서울'],
      },
    })
    expect(saved.status).toBe(200)
    expect(saved.body.rateCard.contractor_id).toBe(CONTRACTOR)
    expect(saved.body.rateCard.trade_id).toBe(TRADE_ID)

    const list = await callPrice('/rate-cards', { headers: auth })
    expect(list.body.rateCards).toHaveLength(1)

    const other = await callPrice('/rate-cards', { headers: { Authorization: 'Bearer contractor-9999' } })
    expect(other.body.rateCards).toHaveLength(0)
  })

  it('같은 공정을 다시 등록하면 덮어씁니다', async () => {
    const auth = { Authorization: `Bearer ${CONTRACTOR}` }
    const body = { tradeId: TRADE_ID, baseLaborCost: 80000 }
    await callPrice('/rate-cards', { method: 'POST', headers: auth, body })
    await callPrice('/rate-cards', { method: 'POST', headers: auth, body: { ...body, baseLaborCost: 95000 } })
    const list = await callPrice('/rate-cards', { headers: auth })
    expect(list.body.rateCards).toHaveLength(1)
    expect(list.body.rateCards[0].base_labor_cost).toBe(95000)
  })

  it('통상 범위를 크게 벗어난 단가는 되돌려보냅니다', async () => {
    const { status, body } = await callPrice('/rate-cards', {
      method: 'POST',
      headers: { Authorization: `Bearer ${CONTRACTOR}` },
      body: { tradeId: TRADE_ID, baseLaborCost: 90_000_000 },
    })
    expect(status).toBe(400)
    expect(body.expectedRange.max).toBe(800000)
  })

  it('검증되지 않은 표준 단가는 표본에 들어가지 않습니다', async () => {
    for (let i = 0; i < 5; i++) {
      table('contractor_rate_cards').push({
        id: nextId('rc'),
        contractor_id: `c-${i}`,
        trade_id: TRADE_ID,
        base_labor_cost: 90000,
        visit_fee: 0,
        material_included: false,
        active: true,
        verified: false, // 미검증
        updated_at: daysAgo(1),
      })
    }
    const { body } = await callPrice('/estimate', { method: 'POST', body: { tradeId: TRADE_ID } })
    expect(body.priceState).toBe('insufficient')
  })

  it('검증된 표준 단가는 참고 범위를 만듭니다', async () => {
    for (let i = 0; i < 5; i++) {
      table('contractor_rate_cards').push({
        id: nextId('rc'),
        contractor_id: `c-${i}`,
        trade_id: TRADE_ID,
        base_labor_cost: 85000 + i * 3000,
        visit_fee: 15000,
        material_included: false,
        active: true,
        verified: true,
        updated_at: daysAgo(i + 1),
      })
    }
    const { body } = await callPrice('/estimate', { method: 'POST', body: { tradeId: TRADE_ID } })
    expect(body.priceState).toBe('preliminary')
    expect(body.basis.map((b: Row) => b.source)).toContain('rate_card')
  })
})

describe('완료 금액 기록', () => {
  const auth = { Authorization: `Bearer ${CONTRACTOR}` }

  it('로그인 없이는 기록할 수 없습니다', async () => {
    const { status } = await callPrice('/completed-jobs', {
      method: 'POST',
      body: { tradeId: TRADE_ID, finalTotalAmount: 100000 },
    })
    expect(status).toBe(401)
  })

  it('리스팅에서 공정·지역을 이어받아 저장합니다', async () => {
    seedListing()
    const { status, body } = await callPrice('/completed-jobs', {
      method: 'POST',
      headers: auth,
      body: {
        listingId: 'listing-1',
        finalTotalAmount: 120000,
        finalLaborCost: 90000,
        finalMaterialCost: 30000,
        paymentMethod: 'transfer',
        vatIncluded: true,
      },
    })
    expect(status).toBe(200)
    expect(body.tradeId).toBe(TRADE_ID)

    const saved = table('completed_jobs')[0]
    expect(saved.final_total_amount).toBe(120000)
    expect(saved.selected_contractor_id).toBe(CONTRACTOR)
    // 주소 문자열이 시·도/시·군·구 정규형으로 쪼개져 저장됩니다.
    expect(saved.region_level1).toBe('서울')
    expect(saved.region_level2).toBe('강남구')
    expect(saved.property_type).toBe('apartment')
    expect(saved.order_id).toBe('order-1')
  })

  it('세부 항목 합계가 총액과 어긋나면 거부합니다', async () => {
    const { status, body } = await callPrice('/completed-jobs', {
      method: 'POST',
      headers: auth,
      body: {
        tradeId: TRADE_ID,
        finalTotalAmount: 120000,
        finalLaborCost: 50000,
        finalMaterialCost: 10000,
        finalAdditionalCost: 5000,
      },
    })
    expect(status).toBe(400)
    expect(body.error).toContain('세부 항목 합계')
  })

  it('총액만 입력해도 저장됩니다', async () => {
    const { status } = await callPrice('/completed-jobs', {
      method: 'POST',
      headers: auth,
      body: { tradeId: TRADE_ID, finalTotalAmount: 110000 },
    })
    expect(status).toBe(200)
    const saved = table('completed_jobs')[0]
    expect(saved.final_total_amount).toBe(110000)
    expect(saved.final_labor_cost).toBeNull()
  })

  it('비정상적으로 높은 금액은 거부합니다', async () => {
    const { status, body } = await callPrice('/completed-jobs', {
      method: 'POST',
      headers: auth,
      body: { tradeId: TRADE_ID, finalTotalAmount: 50_000_000 },
    })
    expect(status).toBe(400)
    expect(body.expectedRange).toEqual({ min: 20000, max: 800000 })
  })

  it('같은 리스팅을 두 번 보내도 한 건으로 합쳐집니다', async () => {
    seedListing()
    const body = { listingId: 'listing-1', finalTotalAmount: 120000 }
    await callPrice('/completed-jobs', { method: 'POST', headers: auth, body })
    await callPrice('/completed-jobs', { method: 'POST', headers: auth, body: { ...body, finalTotalAmount: 130000 } })
    expect(table('completed_jobs')).toHaveLength(1)
    expect(table('completed_jobs')[0].final_total_amount).toBe(130000)
  })
})

describe('사업자 시장 리포트', () => {
  const auth = { Authorization: `Bearer ${CONTRACTOR}` }

  it('표본이 적으면 숫자 대신 안내를 내려줍니다', async () => {
    seedCompletedJobs([100000])
    const { body } = await callPrice('/market-report', { headers: auth, query: { tradeId: TRADE_ID } })
    expect(body.dataState).toBe('insufficient')
    expect(body.message).toContain('완료 금액을 입력해 주시면')
    expect(body.estimatedMin).toBeUndefined()
  })

  it('표본이 쌓이면 지역 시장 범위를 공개합니다', async () => {
    seedCompletedJobs([90000, 95000, 100000, 105000, 110000, 100000, 98000, 102000])
    const { body } = await callPrice('/market-report', {
      headers: auth,
      query: { tradeId: TRADE_ID, region: '서울' },
    })
    expect(body.sampleCount).toBe(8)
    expect(body.estimatedMin).toBeGreaterThan(0)
    expect(body.region).toBe('서울')
  })
})

describe('운영자 설정', () => {
  it('전역 가중 근거 임계값을 낮추면 같은 표본이 sufficient 가 됩니다', async () => {
    seedCompletedJobs([95000, 100000, 105000])
    const before = await callPrice('/estimate', { method: 'POST', body: { tradeId: TRADE_ID } })
    expect(before.body.priceState).toBe('preliminary')

    const applied = await callPrice('/admin/settings', {
      method: 'POST',
      headers: { 'admin-token': ADMIN_TOKEN },
      body: { key: 'thresholds', value: { sufficientWeightedEvidence: 2 } },
    })
    expect(applied.status).toBe(200)
    expect(applied.body.settings.thresholds.sufficientWeightedEvidence).toBe(2)

    const after = await callPrice('/estimate', { method: 'POST', body: { tradeId: TRADE_ID } })
    expect(after.body.priceState).toBe('sufficient')
  })

  it('공정별 완료 건수 임계값은 전역 설정보다 우선합니다', async () => {
    seedCompletedJobs([95000, 100000, 105000, 98000])
    expect((await callPrice('/estimate', { method: 'POST', body: { tradeId: TRADE_ID } })).body.priceState).toBe(
      'preliminary',
    )

    // 운영자가 이 공정의 충분 기준을 4건으로 낮춥니다.
    const updated = await callPrice('/admin/trades', {
      method: 'POST',
      headers: { 'admin-token': ADMIN_TOKEN },
      body: {
        id: TRADE_ID,
        category: '배관',
        subcategory: '변기 막힘',
        sufficient_completed_jobs: 4,
        sanity_min: 20000,
        sanity_max: 800000,
      },
    })
    expect(updated.status).toBe(200)

    const after = await callPrice('/estimate', { method: 'POST', body: { tradeId: TRADE_ID } })
    expect(after.body.priceState).toBe('sufficient')
    expect(after.body.completedJobCount).toBe(4)
  })

  it('허용되지 않은 설정 키는 거부합니다', async () => {
    const { status } = await callPrice('/admin/settings', {
      method: 'POST',
      headers: { 'admin-token': ADMIN_TOKEN },
      body: { key: 'anything', value: {} },
    })
    expect(status).toBe(400)
  })

  it('운영자가 공정을 추가하면 카탈로그에 바로 반영됩니다', async () => {
    const { status } = await callPrice('/admin/trades', {
      method: 'POST',
      headers: { 'admin-token': ADMIN_TOKEN },
      body: { id: 'plumbing.new_trade', category: '배관', subcategory: '신규 공정' },
    })
    expect(status).toBe(200)
    const { body } = await callPrice('/catalog')
    expect(body.trades.map((t: Row) => t.id)).toContain('plumbing.new_trade')
  })
})

// -----------------------------------------------------------------------------
// 견적 요청 → 입찰 → 완료금액: 한 흐름으로 이어 붙입니다.
// -----------------------------------------------------------------------------

describe('통합 흐름', () => {
  function marketEvent(path: string, body: any) {
    return {
      path: `/api/market${path}`,
      httpMethod: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${CONTRACTOR}` },
      queryStringParameters: {},
      body: JSON.stringify(body),
    }
  }

  it('견적 요청 → 입찰(세부 원가) → 완료 금액 저장까지 이어집니다', async () => {
    seedListing()
    seedContractor()

    // 1) 요청 시점: 표본이 없으니 금액을 만들지 않습니다.
    const first = await callPrice('/estimate', { method: 'POST', body: { listingId: 'listing-1' } })
    expect(first.body.trade.id).toBe(TRADE_ID)
    expect(first.body.priceState).toBe('insufficient')
    expect(first.body.estimatedMin).toBeNull()

    // 2) 사업자 입찰 — 세부 원가를 함께 보냅니다.
    const bidRes = await market.handler(
      marketEvent('/listings/listing-1/bid', {
        businessId: CONTRACTOR,
        bidAmount: 120000,
        message: '오늘 방문 가능합니다',
        estimated_days: 1,
        visitFee: 15000,
        laborCost: 80000,
        materialCost: 25000,
        vatIncluded: true,
        estimatedHours: 2,
        asPeriodMonths: 6,
        siteVisitRequired: false,
      }),
    )
    expect(bidRes.statusCode).toBe(200)
    const bid = JSON.parse(bidRes.body)
    expect(bid.success).toBe(true)
    expect(bid.breakdownProvided).toBe(true)

    const savedBid = table('order_bids')[0]
    expect(savedBid.bid_amount).toBe(120000)
    expect(savedBid.visit_fee).toBe(15000)
    expect(savedBid.labor_cost).toBe(80000)
    expect(savedBid.material_cost).toBe(25000)
    expect(savedBid.vat_included).toBe(true)
    expect(savedBid.as_period_months).toBe(6)
    expect(savedBid.estimated_hours).toBe(2)

    // 3) 완료 금액은 입찰가와 별도 컬럼에 저장됩니다.
    const done = await callPrice('/completed-jobs', {
      method: 'POST',
      headers: { Authorization: `Bearer ${CONTRACTOR}` },
      body: {
        listingId: 'listing-1',
        bidId: bid.bidId,
        finalTotalAmount: 145000, // 현장에서 추가 작업이 생겨 입찰가보다 높습니다
        finalLaborCost: 95000,
        finalMaterialCost: 30000,
        finalAdditionalCost: 20000,
        paymentMethod: 'card',
        vatIncluded: true,
        asOccurred: false,
        customerRating: 5,
      },
    })
    expect(done.status).toBe(200)

    const job = table('completed_jobs')[0]
    expect(job.final_total_amount).toBe(145000)
    expect(job.bid_id).toBe(bid.bidId)
    // 입찰가는 그대로 남아 있어야 합니다.
    expect(table('order_bids')[0].bid_amount).toBe(120000)
    expect(job.final_total_amount).not.toBe(table('order_bids')[0].bid_amount)
  })

  it('완료 거래가 임계값을 넘으면 같은 요청이 sufficient 로 바뀝니다', async () => {
    seedListing()
    const before = await callPrice('/estimate', { method: 'POST', body: { listingId: 'listing-1' } })
    expect(before.body.priceState).toBe('insufficient')

    seedCompletedJobs([115000, 120000, 125000, 130000, 118000, 122000, 128000, 124000])

    const after = await callPrice('/estimate', { method: 'POST', body: { listingId: 'listing-1' } })
    expect(after.body.priceState).toBe('sufficient')
    expect(after.body.uiCopy.showAmount).toBe(true)
    expect(after.body.estimatedMin).toBeGreaterThan(0)
    // 리스팅의 urgency=today 가산이 반영됩니다.
    expect(after.body.factors).toContain('야간·긴급 작업')
  })

  it('세부 원가 컬럼이 없는 환경에서도 입찰이 실패하지 않습니다', async () => {
    seedListing()
    seedContractor()
    const originalPost = postgrestHandler
    // order_bids 에 세부 원가 컬럼이 없는 상태를 흉내냅니다.
    const spy = vi.spyOn(globalThis, 'fetch' as any).mockImplementation(((input: any, init?: RequestInit) => {
      const url = new URL(String(input))
      const isBidInsert =
        url.pathname === '/rest/v1/order_bids' && String(init?.method || '').toUpperCase() === 'POST'
      if (isBidInsert) {
        const body = JSON.parse(String(init?.body || '{}'))
        if ('visit_fee' in body) {
          return Promise.resolve(
            new Response(
              JSON.stringify({ code: 'PGRST204', message: "Could not find the 'visit_fee' column of 'order_bids'" }),
              { status: 400 },
            ),
          )
        }
      }
      return fakeFetch(input, init)
    }) as any)

    try {
      const res = await market.handler(
        marketEvent('/listings/listing-1/bid', {
          businessId: CONTRACTOR,
          bidAmount: 120000,
          visitFee: 15000,
          laborCost: 105000,
        }),
      )
      expect(res.statusCode).toBe(200)
      const saved = table('order_bids')[0]
      expect(saved.bid_amount).toBe(120000)
      expect(saved.visit_fee).toBeUndefined()
    } finally {
      spy.mockRestore()
      globalThis.fetch = fakeFetch as any
      void originalPost
    }
  })
})

// -----------------------------------------------------------------------------
// market 인증: 로그인 없이, 또는 다른 사업자 이름으로 처리할 수 없습니다.
// -----------------------------------------------------------------------------

describe('market 인증', () => {
  function event(path: string, method: string, opts: { token?: string; body?: any; query?: any } = {}) {
    return {
      path: `/api/market${path}`,
      httpMethod: method,
      headers: {
        'Content-Type': 'application/json',
        ...(opts.token ? { Authorization: `Bearer ${opts.token}` } : {}),
      },
      queryStringParameters: opts.query || {},
      body: opts.body ? JSON.stringify(opts.body) : undefined,
    }
  }

  it('토큰이 없으면 401', async () => {
    const res = await market.handler(event('/listings', 'GET'))
    expect(res.statusCode).toBe(401)
  })

  it('다른 사업자 이름으로 입찰·취소하면 403', async () => {
    seedListing()
    const bid = await market.handler(
      event('/listings/listing-1/bid', 'POST', { token: 'contractor-9999', body: { businessId: CONTRACTOR, bidAmount: 1000 } }),
    )
    expect(bid.statusCode).toBe(403)
    const del = await market.handler(
      event('/bids/listing-1', 'DELETE', { token: 'contractor-9999', query: { bidderId: CONTRACTOR } }),
    )
    expect(del.statusCode).toBe(403)
  })

  it('다른 사업자의 입찰 목록은 요청해도 본인 것만 받습니다', async () => {
    const res = await market.handler(
      event('/bids', 'GET', { token: 'contractor-9999', query: { bidderId: CONTRACTOR } }),
    )
    expect(res.statusCode).toBe(403)
  })

  it('오더 등록자가 아니면 낙찰자를 고를 수 없습니다', async () => {
    seedListing()
    const res = await market.handler(
      event('/listings/listing-1/select-bidder', 'POST', {
        token: 'contractor-9999',
        body: { bidderId: CONTRACTOR, ownerId: 'someone-else' },
      }),
    )
    expect(res.statusCode).toBe(403)
  })
})

// -----------------------------------------------------------------------------
// 입찰 자격·공사 금액(수수료 기준)
// -----------------------------------------------------------------------------

describe('입찰 자격과 공사 금액', () => {
  function event(path: string, token: string, body: any) {
    return {
      path: `/api/market${path}`,
      httpMethod: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      queryStringParameters: {},
      body: JSON.stringify(body),
    }
  }

  function seedB2B() {
    table('jobs').push({ id: 'job-b2b', title: '배관 교체', owner_business_id: 'owner-1', budget_amount: 500000, commission_rate: 10 })
    table('marketplace_listings').push({
      id: 'listing-b2b', title: '배관 교체', posted_by: 'owner-1', budget_amount: 500000, jobid: 'job-b2b', status: 'open',
    })
  }

  it('승인 대기 사업자는 입찰할 수 없습니다', async () => {
    seedListing()
    seedContractor(CONTRACTOR, { businessstatus: 'pending' })
    const res = await market.handler(event('/listings/listing-1/bid', CONTRACTOR, { businessId: CONTRACTOR, bidAmount: 100000 }))
    expect(res.statusCode).toBe(403)
    expect(JSON.parse(res.body).code).toBe('BUSINESS_NOT_ELIGIBLE')
    expect(table('order_bids')).toHaveLength(0)
  })

  it('사업자등록번호가 없으면 입찰할 수 없고, 관리자 우회면 됩니다', async () => {
    seedListing()
    seedContractor(CONTRACTOR, { businessnumber: null })
    const blocked = await market.handler(event('/listings/listing-1/bid', CONTRACTOR, { businessId: CONTRACTOR, bidAmount: 100000 }))
    expect(blocked.statusCode).toBe(403)
    table('users')[0].business_verify_bypass = true
    const ok = await market.handler(event('/listings/listing-1/bid', CONTRACTOR, { businessId: CONTRACTOR, bidAmount: 100000 }))
    expect(ok.statusCode).toBe(200)
  })

  it('고객 웹 오더는 금액 없이 입찰할 수 없습니다', async () => {
    seedListing()
    seedContractor()
    const res = await market.handler(event('/listings/listing-1/bid', CONTRACTOR, { businessId: CONTRACTOR }))
    expect(res.statusCode).toBe(400)
    expect(JSON.parse(res.body).code).toBe('BID_AMOUNT_REQUIRED')
  })

  it('낙찰하면 낙찰된 입찰가를 공사 금액으로 저장합니다(예산 아님)', async () => {
    seedB2B()
    seedContractor()
    table('users').push({ id: 'owner-1', role: 'business', businessstatus: 'approved', businessnumber: '2234567890' })
    await market.handler(event('/listings/listing-b2b/bid', CONTRACTOR, { businessId: CONTRACTOR, bidAmount: 480000 }))
    const res = await market.handler(event('/listings/listing-b2b/select-bidder', 'owner-1', { bidderId: CONTRACTOR, ownerId: 'owner-1' }))
    expect(res.statusCode).toBe(200)
    expect(JSON.parse(res.body).awardedAmount).toBe(480000)
    expect(table('jobs')[0].awarded_amount).toBe(480000)
    expect(table('order_bids')[0].job_id).toBe('job-b2b')
  })

  it('금액 없이 바로 지원한 입찰은 올라온 금액(예산)을 입찰가로 봅니다', async () => {
    seedB2B()
    seedContractor()
    await market.handler(event('/listings/listing-b2b/bid', CONTRACTOR, { businessId: CONTRACTOR }))
    const res = await market.handler(event('/listings/listing-b2b/select-bidder', 'owner-1', { bidderId: CONTRACTOR, ownerId: 'owner-1' }))
    expect(JSON.parse(res.body).awardedAmount).toBe(500000)
    expect(table('jobs')[0].awarded_amount).toBe(500000)
  })

  it('가져가기는 올라온 금액을 공사 금액으로 저장하고, 웹 오더는 가져가기 대신 입찰을 안내합니다', async () => {
    seedB2B()
    seedListing()
    seedContractor()
    const res = await market.handler(event('/listings/listing-b2b/claim', CONTRACTOR, { businessId: CONTRACTOR }))
    expect(JSON.parse(res.body).success).toBe(true)
    expect(table('jobs')[0].awarded_amount).toBe(500000)
    const web = await market.handler(event('/listings/listing-1/claim', CONTRACTOR, { businessId: CONTRACTOR }))
    expect(JSON.parse(web.body).code).toBe('WEB_ORDER_NEEDS_BID')
  })
})
