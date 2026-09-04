/// <reference types="node" />
// /api/price/* — 가격 엔진 API
//
// 공개(로그인 불필요): GET /catalog, POST /estimate
//   → 고객이 로그인 없이 견적을 요청하는 현재 정책을 유지합니다.
// 사업자(Supabase JWT 필요): GET|POST /rate-cards, POST /completed-jobs, GET /market-report
// 운영자(admin-token 필요): /admin/*

import {
  ENGINE_VERSION,
  PROPERTY_TYPES,
  URGENCY_LEVELS,
  answersToPriceInput,
  normalizeAccessDifficulty,
  normalizePropertyType,
  normalizeRegionLevel1,
  normalizeRegionLevel2,
  normalizeTags,
  normalizeUrgency,
  questionsForTrade,
  resolveTrade,
  type PriceState,
  type TradeDefinition,
} from '../lib/price_catalog'
import { computePrice, type PriceRequest, type PriceResult } from '../lib/price_engine'
import {
  insertCompletedJob,
  listBaselines,
  listRateCards,
  listingContext,
  loadCatalog,
  loadSamples,
  marketReport,
  saveEstimateSnapshot,
  upsertBaseline,
  upsertRateCard,
  upsertSetting,
  upsertTrade,
} from '../lib/price_repository'

const SUPABASE_URL = process.env.SUPABASE_URL as string
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY as string
const ADMIN_TOKEN = process.env.ADMIN_TOKEN || process.env.ADMIN_DEVELOPER_TOKEN || 'devtoken'

const JSON_HEADERS = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, admin-token, x-admin-token',
  'Access-Control-Allow-Methods': 'GET, POST, PATCH, OPTIONS',
}

function ok(data: unknown, status = 200) {
  return { statusCode: status, body: JSON.stringify(data), headers: JSON_HEADERS }
}
function fail(message: string, status = 400, extra?: Record<string, unknown>) {
  return { statusCode: status, body: JSON.stringify({ error: message, ...extra }), headers: JSON_HEADERS }
}

function parseBody(event: any): Record<string, any> {
  const raw = event?.body
  if (raw && typeof raw === 'object') return raw
  let text = String(raw || '')
  if (event?.isBase64Encoded && text) text = Buffer.from(text, 'base64').toString('utf8')
  if (!text) return {}
  try {
    const parsed = JSON.parse(text)
    return parsed && typeof parsed === 'object' ? parsed : {}
  } catch {
    return {}
  }
}

function header(event: any, name: string): string {
  const headers = event?.headers || {}
  const lower = name.toLowerCase()
  const key = Object.keys(headers).find((k) => k.toLowerCase() === lower)
  return key ? String(headers[key] || '') : ''
}

function isAdmin(event: any): boolean {
  const token = header(event, 'admin-token') || header(event, 'x-admin-token')
  return Boolean(token) && token === ADMIN_TOKEN
}

/** Supabase JWT → user id. 없거나 무효면 null. */
async function authenticatedUserId(event: any): Promise<string | null> {
  const token = header(event, 'authorization').replace(/^Bearer\s+/i, '').trim()
  if (!token) return null
  if (token === SUPABASE_SERVICE_ROLE_KEY) return 'service_role'
  try {
    const res = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
      headers: { apikey: SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${token}` },
    })
    if (!res.ok) return null
    const user = await res.json()
    return user?.id ? String(user.id) : null
  } catch {
    return null
  }
}

function toInt(value: unknown): number | null {
  const n = Number(value)
  return Number.isFinite(n) ? Math.round(n) : null
}

function nonNegative(value: unknown): number | null {
  const n = toInt(value)
  return n != null && n >= 0 ? n : null
}

// -----------------------------------------------------------------------------
// UI 문구 — 앱과 웹이 같은 문구를 쓰도록 서버가 내려줍니다.
// -----------------------------------------------------------------------------
function uiCopy(state: PriceState): { headline: string; body: string; showAmount: boolean; cta: string } {
  if (state === 'sufficient') {
    return {
      headline: '최근 유사 완료 작업 기준',
      body: '최근 유사 완료 사례 및 현재 입력 조건을 기준으로 한 참고 금액입니다.\n현장 상태, 자재, 긴급 출동 여부에 따라 달라질 수 있습니다.',
      showAmount: true,
      cta: '이 조건으로 견적 요청',
    }
  }
  if (state === 'preliminary') {
    return {
      headline: '유사 사례를 바탕으로 한 참고 범위',
      body: '아직 유사 완료 사례가 적어 범위를 넓게 잡았습니다.\n실제 견적은 현장 확인 후 업체가 제시합니다.',
      showAmount: true,
      cta: '이 조건으로 견적 요청',
    }
  }
  return {
    headline: '현장 조건에 따라 차이가 큰 작업',
    body: '아직 확인된 유사 완료 사례가 부족해 예상 금액을 표시하지 않습니다.\n실제 업체 견적을 받아 비교하시는 편이 정확합니다.',
    showAmount: false,
    cta: '무료로 업체 견적 받기',
  }
}

function tradeSummary(t: TradeDefinition) {
  return {
    id: t.id,
    category: t.category,
    subcategory: t.subcategory,
    priceFactors: t.priceFactors,
    symptomTags: t.symptomTags,
    workScopeTags: t.workScopeTags,
    materialIncludedByDefault: t.materialIncludedByDefault,
    visitFeeApplies: t.visitFee.applies,
  }
}

// -----------------------------------------------------------------------------
// 라우터
// -----------------------------------------------------------------------------
export const handler = async (event: any) => {
  let path = String(event?.path || '')
  if (path.startsWith('/api/price')) path = path.replace('/api/price', '')
  else if (path.startsWith('/.netlify/functions/price')) path = path.replace('/.netlify/functions/price', '')
  path = path.replace(/\/+$/, '') || '/'

  const method = String(event?.httpMethod || 'GET').toUpperCase()
  console.log(`[price] ${method} ${event?.path} -> ${path}`)

  if (method === 'OPTIONS') return { statusCode: 204, body: '', headers: JSON_HEADERS }

  try {
    if (method === 'GET' && (path === '/catalog' || path === '/')) return await handleCatalog()
    if (method === 'POST' && path === '/estimate') return await handleEstimate(event)
    if (path === '/rate-cards') {
      if (method === 'GET') return await handleListRateCards(event)
      if (method === 'POST') return await handleUpsertRateCard(event)
    }
    if (method === 'POST' && path === '/completed-jobs') return await handleCompletedJob(event)
    if (method === 'GET' && path === '/market-report') return await handleMarketReport(event)

    if (path.startsWith('/admin/')) {
      if (!isAdmin(event)) return fail('admin-token 이 필요합니다', 401)
      if (method === 'GET' && path === '/admin/baselines') {
        const tradeId = event?.queryStringParameters?.tradeId
        return ok({ baselines: await listBaselines(tradeId || undefined) })
      }
      if (method === 'POST' && path === '/admin/baselines') return await handleAdminBaseline(event)
      if (method === 'POST' && path === '/admin/settings') return await handleAdminSettings(event)
      if (method === 'POST' && path === '/admin/trades') return await handleAdminTrade(event)
    }

    return fail('Not found', 404)
  } catch (e: any) {
    console.error('[price] 처리 실패:', e?.message)
    return fail('가격 엔진 오류', 500, { detail: e?.message })
  }
}

// -----------------------------------------------------------------------------
// GET /catalog
// -----------------------------------------------------------------------------
async function handleCatalog() {
  const catalog = await loadCatalog()
  const trades = catalog.trades.filter((t) => t.active).sort((a, b) => a.sortOrder - b.sortOrder)
  return ok({
    engineVersion: ENGINE_VERSION,
    source: catalog.fromDatabase ? 'database' : 'defaults',
    enums: {
      urgency: URGENCY_LEVELS,
      propertyType: PROPERTY_TYPES,
      priceState: ['sufficient', 'preliminary', 'insufficient'],
      confidenceLevel: ['high', 'medium', 'low'],
    },
    categories: Array.from(new Set(trades.map((t) => t.category))),
    trades: trades.map((t) => ({
      ...tradeSummary(t),
      aliases: t.aliases,
      requiredQuestions: t.requiredQuestions,
      optionalQuestions: t.optionalQuestions,
    })),
    questions: catalog.questions.sort((a, b) => a.sortOrder - b.sortOrder),
  })
}

// -----------------------------------------------------------------------------
// POST /estimate
// -----------------------------------------------------------------------------
async function handleEstimate(event: any) {
  const body = parseBody(event)
  const catalog = await loadCatalog()

  // 앱에서 리스팅 기준으로 물어보는 경로 (사업자에게 시장 범위를 보여줄 때)
  let category = body.category
  let subcategory = body.subcategory
  let text = String(body.text || body.description || '')
  let addressLike = String(body.address || body.region || '')
  let tradeIdHint = body.tradeId
  let orderId: string | null = body.orderId ? String(body.orderId) : null

  if (body.listingId) {
    const ctx = await listingContext(String(body.listingId))
    if (ctx.listing) {
      category = category || ctx.order?.category || ctx.listing.category
      subcategory = subcategory || ctx.order?.subcategory
      tradeIdHint = tradeIdHint || ctx.order?.tradeId
      text = text || `${ctx.listing.title || ''} ${ctx.listing.description || ''}`
      addressLike = addressLike || ctx.order?.address || ctx.listing.region || ''
      orderId = orderId || (ctx.order?.id ? String(ctx.order.id) : null)
    }
  }

  const match = resolveTrade(catalog.trades, {
    tradeId: tradeIdHint,
    category,
    subcategory,
    text,
  })

  // 공정을 확정하지 못하면 금액을 만들지 않고 고객에게 선택지를 돌려줍니다.
  if (!match.trade) {
    const result = computePrice({
      trade: null,
      request: {},
      samples: [],
      settings: catalog.settings,
    })
    return ok({
      ...serializeResult(result),
      trade: null,
      candidates: match.candidates.map(tradeSummary),
      needsTradeSelection: true,
      uiCopy: uiCopy('insufficient'),
    })
  }

  const trade = match.trade
  const answers = body.answers && typeof body.answers === 'object' ? body.answers : {}
  const fromAnswers = answersToPriceInput(catalog.questions, trade, answers)

  const regionLevel1 =
    normalizeRegionLevel1(body.locationLevel1) ?? normalizeRegionLevel1(addressLike)
  const regionLevel2 =
    normalizeRegionLevel2(body.locationLevel2) ?? normalizeRegionLevel2(addressLike)

  const request: PriceRequest = {
    regionLevel1,
    regionLevel2,
    propertyType: normalizePropertyType(body.propertyType) ?? fromAnswers.propertyType,
    urgency: normalizeUrgency(body.urgency) ?? fromAnswers.urgency,
    accessDifficulty: normalizeAccessDifficulty(body.accessDifficulty) ?? fromAnswers.accessDifficulty,
    workScopeTags: Array.from(
      new Set([...normalizeTags(trade.workScopeTags, body.workScopeTags), ...fromAnswers.workScopeTags]),
    ),
    materialIncluded:
      typeof body.materialIncluded === 'boolean' ? body.materialIncluded : fromAnswers.materialIncluded,
    visitRequired: typeof body.visitRequired === 'boolean' ? body.visitRequired : null,
  }

  const samples = await loadSamples(trade, request, catalog.settings)
  const result = computePrice({ trade, request, samples, settings: catalog.settings })

  const questions = questionsForTrade(catalog.questions, trade)
  const missingRequired = questions.required
    .filter((q) => {
      if (q.mapsTo === 'urgency') return !request.urgency
      if (q.mapsTo === 'propertyType') return !request.propertyType
      if (q.mapsTo === 'accessDifficulty') return !request.accessDifficulty
      if (q.mapsTo === 'materialIncluded') return request.materialIncluded == null
      if (q.mapsTo === 'workScopeTags') return (request.workScopeTags || []).length === 0
      return !(q.id in answers)
    })
    .map((q) => ({ id: q.id, label: q.label, inputType: q.inputType, options: q.options }))

  // 감사 로그. 실패해도 응답은 막지 않습니다.
  void saveEstimateSnapshot({
    order_id: orderId,
    session_id: body.sessionId ? String(body.sessionId) : null,
    trade_id: trade.id,
    engine_version: result.engineVersion,
    request: { ...request, tradeId: trade.id, answers },
    price_state: result.priceState,
    estimated_min: result.estimatedMin,
    estimated_typical: result.estimatedTypical,
    estimated_max: result.estimatedMax,
    confidence_level: result.confidenceLevel,
    confidence_score: result.confidenceScore,
    evidence_count: result.evidenceCount,
    weighted_evidence: result.weightedEvidence,
    factors: result.factors,
    basis: result.basis,
  })

  return ok({
    ...serializeResult(result),
    trade: tradeSummary(trade),
    candidates: match.candidates.length > 1 ? match.candidates.map(tradeSummary) : [],
    needsTradeSelection: false,
    normalizedRequest: request,
    questions: {
      required: questions.required.map((q) => ({ id: q.id, label: q.label, inputType: q.inputType, options: q.options })),
      // 추가 질문은 한 번에 3개까지만 노출합니다.
      optional: questions.optional
        .slice(0, 3)
        .map((q) => ({ id: q.id, label: q.label, inputType: q.inputType, options: q.options })),
    },
    missingRequiredQuestions: missingRequired.slice(0, 3),
    uiCopy: uiCopy(result.priceState),
  })
}

function serializeResult(result: PriceResult) {
  return {
    priceState: result.priceState,
    estimatedMin: result.estimatedMin,
    estimatedTypical: result.estimatedTypical,
    estimatedMax: result.estimatedMax,
    confidenceLevel: result.confidenceLevel,
    confidenceScore: result.confidenceScore,
    evidenceCount: result.evidenceCount,
    completedJobCount: result.completedJobCount,
    weightedEvidence: result.weightedEvidence,
    factors: result.factors,
    adjustments: result.adjustments,
    basis: result.basis,
    droppedOutlierCount: result.droppedOutlierCount,
    disclaimer: result.disclaimer,
    engineVersion: result.engineVersion,
    insufficientReason: result.insufficientReason ?? null,
  }
}

// -----------------------------------------------------------------------------
// 사업자 표준 단가
// -----------------------------------------------------------------------------
async function handleListRateCards(event: any) {
  const userId = await authenticatedUserId(event)
  if (!userId) return fail('로그인이 필요합니다', 401)
  const contractorId =
    userId === 'service_role' ? String(event?.queryStringParameters?.contractorId || '') : userId
  if (!contractorId) return fail('contractorId 가 필요합니다')
  const catalog = await loadCatalog()
  return ok({
    rateCards: await listRateCards(contractorId),
    trades: catalog.trades.filter((t) => t.active).map(tradeSummary),
  })
}

async function handleUpsertRateCard(event: any) {
  const userId = await authenticatedUserId(event)
  if (!userId) return fail('로그인이 필요합니다', 401)
  const body = parseBody(event)
  const contractorId = userId === 'service_role' ? String(body.contractorId || '') : userId
  if (!contractorId) return fail('contractorId 가 필요합니다')

  const catalog = await loadCatalog()
  const trade = catalog.trades.find((t) => t.id === String(body.tradeId || ''))
  if (!trade) return fail('지원하지 않는 공정입니다', 400, { tradeId: body.tradeId })

  const baseLabor = nonNegative(body.baseLaborCost)
  if (baseLabor == null) return fail('기본 작업비를 입력해 주세요')
  if (baseLabor < trade.sanity.min / 4 || baseLabor > trade.sanity.max) {
    return fail(
      `기본 작업비가 이 공정의 통상 범위를 크게 벗어납니다. 다시 확인해 주세요.`,
      400,
      { expectedRange: { min: Math.round(trade.sanity.min / 4), max: trade.sanity.max } },
    )
  }

  const now = new Date().toISOString()
  const res = await upsertRateCard({
    contractor_id: contractorId,
    trade_id: trade.id,
    base_labor_cost: baseLabor,
    material_avg_cost: nonNegative(body.materialAvgCost) ?? 0,
    material_included: body.materialIncluded === true,
    visit_fee: nonNegative(body.visitFee) ?? 0,
    vat_included: body.vatIncluded === true,
    additional_cost_conditions: Array.isArray(body.additionalCostConditions)
      ? body.additionalCostConditions.map((s: unknown) => String(s)).slice(0, 10)
      : [],
    service_regions: Array.isArray(body.serviceRegions)
      ? body.serviceRegions.map((s: unknown) => normalizeRegionLevel1(s) || String(s)).slice(0, 20)
      : [],
    active: body.active !== false,
    updated_at: now,
  })
  if (!res.ok) return fail(res.error || '표준 단가 저장 실패', 500)
  return ok({ success: true, rateCard: res.data[0] ?? null })
}

// -----------------------------------------------------------------------------
// 최종 거래 금액 기록
// -----------------------------------------------------------------------------
async function handleCompletedJob(event: any) {
  const userId = await authenticatedUserId(event)
  if (!userId) return fail('로그인이 필요합니다', 401)
  const body = parseBody(event)

  const total = toInt(body.finalTotalAmount)
  if (total == null || total <= 0) return fail('최종 확정금액을 입력해 주세요')

  const catalog = await loadCatalog()
  let trade = catalog.trades.find((t) => t.id === String(body.tradeId || '')) || null
  let addressLike = String(body.address || '')
  let orderId = body.orderId ? String(body.orderId) : null
  // 요청 시점에 고객이 입력한 조건을 이어받습니다. 표본의 조건이 비어 있으면
  // 나중에 지역·건물 유형별로 범위를 좁힐 수 없습니다.
  let propertyType = normalizePropertyType(body.propertyType)
  let urgency = normalizeUrgency(body.urgency)

  if (body.listingId) {
    const ctx = await listingContext(String(body.listingId))
    if (ctx.listing && !trade) {
      trade =
        resolveTrade(catalog.trades, {
          tradeId: ctx.order?.tradeId,
          category: ctx.order?.category || ctx.listing.category,
          subcategory: ctx.order?.subcategory,
          text: `${ctx.listing.title || ''} ${ctx.listing.description || ''}`,
        }).trade || null
    }
    addressLike = addressLike || ctx.order?.address || ctx.listing?.region || ''
    orderId = orderId || (ctx.order?.id ? String(ctx.order.id) : null)
    propertyType = propertyType ?? normalizePropertyType(ctx.order?.propertyType)
    urgency = urgency ?? normalizeUrgency(ctx.order?.urgency)
  }

  // 공정을 특정할 수 없어도 기록은 남깁니다(trade_id=null). 가격 표본으로는 쓰이지 않습니다.
  if (trade && (total < trade.sanity.min || total > trade.sanity.max)) {
    return fail('금액이 이 공정의 통상 범위를 크게 벗어납니다. 확인 후 다시 입력해 주세요.', 400, {
      expectedRange: trade.sanity,
    })
  }

  const labor = nonNegative(body.finalLaborCost)
  const material = nonNegative(body.finalMaterialCost)
  const additional = nonNegative(body.finalAdditionalCost)
  const parts = [labor, material, additional].filter((n): n is number => n != null)
  if (parts.length === 3 && Math.abs(parts.reduce((a, b) => a + b, 0) - total) > 1000) {
    return fail('세부 항목 합계와 총액이 맞지 않습니다.', 400, {
      sum: parts.reduce((a, b) => a + b, 0),
      total,
    })
  }

  const res = await insertCompletedJob({
    order_id: orderId,
    listing_id: body.listingId ? String(body.listingId) : null,
    job_id: body.jobId ? String(body.jobId) : null,
    bid_id: body.bidId ? String(body.bidId) : null,
    trade_id: trade?.id ?? null,
    category: trade?.category ?? (body.category ? String(body.category) : null),
    subcategory: trade?.subcategory ?? (body.subcategory ? String(body.subcategory) : null),
    region_level1: normalizeRegionLevel1(body.locationLevel1) ?? normalizeRegionLevel1(addressLike),
    region_level2: normalizeRegionLevel2(body.locationLevel2) ?? normalizeRegionLevel2(addressLike),
    property_type: propertyType,
    urgency,
    selected_contractor_id:
      userId === 'service_role' ? (body.selectedContractorId ? String(body.selectedContractorId) : null) : userId,
    final_labor_cost: labor,
    final_material_cost: material,
    final_additional_cost: additional,
    final_total_amount: total,
    vat_included: body.vatIncluded === true,
    payment_method: body.paymentMethod ? String(body.paymentMethod) : null,
    completion_at: body.completionAt ? String(body.completionAt) : new Date().toISOString(),
    as_occurred: body.asOccurred === true,
    customer_rating: Number.isFinite(Number(body.customerRating)) ? Number(body.customerRating) : null,
    final_work_scope_tags: trade ? normalizeTags(trade.workScopeTags, body.finalWorkScopeTags) : [],
    source: body.source ? String(body.source) : 'app',
  })
  if (!res.ok) return fail(res.error || '완료 금액 저장 실패', 500)
  return ok({ success: true, completedJob: res.data[0] ?? null, tradeId: trade?.id ?? null })
}

// -----------------------------------------------------------------------------
// 사업자용 시장 리포트
// -----------------------------------------------------------------------------
async function handleMarketReport(event: any) {
  const userId = await authenticatedUserId(event)
  if (!userId) return fail('로그인이 필요합니다', 401)

  const q = event?.queryStringParameters || {}
  const catalog = await loadCatalog()
  const trade = catalog.trades.find((t) => t.id === String(q.tradeId || ''))
  if (!trade) return fail('tradeId 가 필요합니다')

  const region = normalizeRegionLevel1(q.region)
  const rows = await marketReport(trade.id, region)
  const minSamples = catalog.settings.thresholds.preliminaryMinSamples

  if (rows.length < minSamples) {
    return ok({
      trade: tradeSummary(trade),
      region,
      sampleCount: rows.length,
      dataState: 'insufficient',
      message: `이 조건의 완료 사례가 ${rows.length}건뿐이라 시장 평균을 공개하지 않습니다. 완료 금액을 입력해 주시면 리포트가 열립니다.`,
    })
  }

  const result = computePrice({
    trade,
    request: { regionLevel1: region },
    samples: rows.map((r) => ({
      source: 'completed_job' as const,
      value: r.value,
      occurredAt: r.at,
      regionLevel1: region,
    })),
    settings: catalog.settings,
  })

  return ok({
    trade: tradeSummary(trade),
    region,
    sampleCount: rows.length,
    dataState: result.priceState,
    ...serializeResult(result),
  })
}

// -----------------------------------------------------------------------------
// 운영자
// -----------------------------------------------------------------------------
async function handleAdminBaseline(event: any) {
  const body = parseBody(event)
  const catalog = await loadCatalog()
  const trade = catalog.trades.find((t) => t.id === String(body.tradeId || ''))
  if (!trade) return fail('지원하지 않는 공정입니다')

  const min = nonNegative(body.minAmount)
  const typical = nonNegative(body.typicalAmount)
  const max = nonNegative(body.maxAmount)
  if (min == null || typical == null || max == null) return fail('minAmount/typicalAmount/maxAmount 필수')
  if (!(min > 0 && min <= typical && typical <= max)) return fail('min ≤ typical ≤ max 여야 합니다')

  const res = await upsertBaseline({
    trade_id: trade.id,
    region_level1: normalizeRegionLevel1(body.regionLevel1),
    property_type: normalizePropertyType(body.propertyType),
    min_amount: min,
    typical_amount: typical,
    max_amount: max,
    material_included: body.materialIncluded === true,
    vat_included: body.vatIncluded === true,
    note: body.note ? String(body.note) : null,
    updated_by: 'admin',
    updated_at: new Date().toISOString(),
  })
  if (!res.ok) return fail(res.error || '기준표 저장 실패', 500)
  return ok({ success: true, baseline: res.data[0] ?? null })
}

async function handleAdminSettings(event: any) {
  const body = parseBody(event)
  const key = String(body.key || '')
  if (!['thresholds', 'weights', 'outliers'].includes(key)) {
    return fail('key 는 thresholds | weights | outliers 중 하나여야 합니다')
  }
  if (!body.value || typeof body.value !== 'object') return fail('value 는 객체여야 합니다')
  const res = await upsertSetting(key, body.value, 'admin')
  if (!res.ok) return fail(res.error || '설정 저장 실패', 500)
  const refreshed = await loadCatalog(true)
  return ok({ success: true, settings: refreshed.settings })
}

async function handleAdminTrade(event: any) {
  const body = parseBody(event)
  if (!body.id || !body.category || !body.subcategory) {
    return fail('id, category, subcategory 는 필수입니다')
  }
  const res = await upsertTrade(body)
  if (!res.ok) return fail(res.error || '공정 저장 실패', 500)
  return ok({ success: true, trade: res.data[0] ?? null })
}
