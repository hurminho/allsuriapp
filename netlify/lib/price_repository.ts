// 가격 엔진 데이터 접근. PostgREST(fetch + service_role) 만 씁니다.
//
// 마이그레이션(database/price_engine_v1.sql)을 아직 실행하지 않은 환경에서도
// 500 이 나지 않도록, 테이블이 없으면 코드 기본값으로 조용히 내려갑니다.

import {
  DEFAULT_QUESTIONS,
  DEFAULT_SETTINGS,
  DEFAULT_TRADES,
  type EngineSettings,
  type QuestionDefinition,
  type QuestionInputType,
  type TradeDefinition,
} from './price_catalog'
import { baselineToSamples, type PriceRequest, type PriceSample } from './price_engine'

const SUPABASE_URL = process.env.SUPABASE_URL as string
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY as string

const GET_HEADERS = {
  apikey: SUPABASE_SERVICE_ROLE_KEY,
  Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
}
const WRITE_HEADERS = {
  ...GET_HEADERS,
  'Content-Type': 'application/json',
}

/** PostgREST 조회. 테이블이 없거나 조회가 실패하면 빈 배열. */
async function sbSelect<T = any>(pathAndQuery: string): Promise<T[]> {
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) return []
  try {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/${pathAndQuery}`, { headers: GET_HEADERS })
    if (!res.ok) {
      const text = await res.text().catch(() => '')
      // 42P01 = undefined_table (마이그레이션 미실행)
      if (text.includes('42P01') || res.status === 404) {
        console.warn(`[price] 테이블 없음 — 기본값 사용: ${pathAndQuery.split('?')[0]}`)
      } else {
        console.warn(`[price] select 실패 ${res.status}: ${text.slice(0, 200)}`)
      }
      return []
    }
    const json = await res.json()
    return Array.isArray(json) ? json : []
  } catch (e: any) {
    console.warn('[price] select 오류:', e?.message)
    return []
  }
}

async function sbWrite<T = any>(
  pathAndQuery: string,
  method: 'POST' | 'PATCH' | 'DELETE',
  body?: unknown,
  prefer = 'return=representation',
): Promise<{ ok: boolean; data: T[]; error?: string }> {
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    return { ok: false, data: [], error: 'supabase 환경변수 없음' }
  }
  try {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/${pathAndQuery}`, {
      method,
      headers: { ...WRITE_HEADERS, Prefer: prefer },
      body: body === undefined ? undefined : JSON.stringify(body),
    })
    const text = await res.text().catch(() => '')
    if (!res.ok) {
      const hint = text.includes('42P01')
        ? 'database/price_engine_v1.sql 을 먼저 실행해 주세요'
        : text.slice(0, 300)
      return { ok: false, data: [], error: hint }
    }
    let parsed: unknown = []
    try {
      parsed = text ? JSON.parse(text) : []
    } catch {
      parsed = []
    }
    return { ok: true, data: Array.isArray(parsed) ? (parsed as T[]) : [parsed as T] }
  } catch (e: any) {
    return { ok: false, data: [], error: e?.message || 'write 실패' }
  }
}

// -----------------------------------------------------------------------------
// 카탈로그 로딩 (웜 컨테이너 캐시 60초)
// -----------------------------------------------------------------------------

type Catalog = {
  trades: TradeDefinition[]
  questions: QuestionDefinition[]
  settings: EngineSettings
  /** DB 카탈로그를 읽었는지. false 면 코드 기본값입니다. */
  fromDatabase: boolean
}

let catalogCache: { at: number; value: Catalog } | null = null
const CATALOG_TTL_MS = 60_000

function rowToTrade(row: any): TradeDefinition {
  const fallback = DEFAULT_TRADES.find((t) => t.id === row.id)
  const num = (v: unknown, d: number) => (Number.isFinite(Number(v)) ? Number(v) : d)
  return {
    id: String(row.id),
    category: String(row.category || fallback?.category || ''),
    subcategory: String(row.subcategory || fallback?.subcategory || ''),
    aliases: Array.isArray(row.aliases) ? row.aliases.map(String) : fallback?.aliases || [],
    symptomTags: Array.isArray(row.symptom_tags) ? row.symptom_tags.map(String) : fallback?.symptomTags || [],
    workScopeTags: Array.isArray(row.work_scope_tags)
      ? row.work_scope_tags.map(String)
      : fallback?.workScopeTags || [],
    requiredQuestions: Array.isArray(row.required_questions)
      ? row.required_questions.map(String)
      : fallback?.requiredQuestions || [],
    optionalQuestions: Array.isArray(row.optional_questions)
      ? row.optional_questions.map(String)
      : fallback?.optionalQuestions || [],
    priceFactors: Array.isArray(row.price_factors)
      ? row.price_factors.map(String)
      : fallback?.priceFactors || [],
    baseLabor: {
      min: num(row.base_labor_min, fallback?.baseLabor.min ?? 0),
      typical: num(row.base_labor_typical, fallback?.baseLabor.typical ?? 0),
      max: num(row.base_labor_max, fallback?.baseLabor.max ?? 0),
    },
    materialIncludedByDefault: Boolean(row.material_included_by_default),
    visitFee: {
      applies: row.visit_fee_applies !== false,
      typical: num(row.visit_fee_typical, fallback?.visitFee.typical ?? 0),
    },
    urgencySurchargeApplies: row.urgency_surcharge_applies !== false,
    urgencyMultipliers:
      row.urgency_multipliers && typeof row.urgency_multipliers === 'object'
        ? row.urgency_multipliers
        : fallback?.urgencyMultipliers || {},
    sanity: {
      min: num(row.sanity_min, fallback?.sanity.min ?? 10000),
      max: num(row.sanity_max, fallback?.sanity.max ?? 5000000),
    },
    thresholds: {
      sufficientCompletedJobs: num(
        row.sufficient_completed_jobs,
        fallback?.thresholds.sufficientCompletedJobs ?? 8,
      ),
      preliminaryMinSamples: num(
        row.preliminary_min_samples,
        fallback?.thresholds.preliminaryMinSamples ?? 3,
      ),
    },
    active: row.active !== false,
    sortOrder: num(row.sort_order, fallback?.sortOrder ?? 100),
  }
}

/** tag_map jsonb → {선택지: 태그[]}. 형식이 어긋난 값은 조용히 버립니다. */
function normalizeTagMap(raw: any): Record<string, string[]> | undefined {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return undefined
  const out: Record<string, string[]> = {}
  for (const [key, value] of Object.entries(raw)) {
    if (!Array.isArray(value)) continue
    out[key] = value.map((v) => String(v ?? '')).filter(Boolean)
  }
  return Object.keys(out).length ? out : undefined
}

function rowToQuestion(row: any): QuestionDefinition {
  const allowed: QuestionInputType[] = ['single', 'multi', 'bool', 'text', 'number', 'photo']
  const inputType = allowed.includes(row.input_type) ? (row.input_type as QuestionInputType) : 'single'
  return {
    id: String(row.id),
    label: String(row.label || ''),
    inputType,
    options: Array.isArray(row.options)
      ? row.options
          .map((o: any) => ({ value: String(o?.value ?? ''), label: String(o?.label ?? o?.value ?? '') }))
          .filter((o: any) => o.value)
      : [],
    mapsTo: row.maps_to ? (row.maps_to as QuestionDefinition['mapsTo']) : null,
    tagMap: normalizeTagMap(row.tag_map),
    affectsPrice: Boolean(row.affects_price),
    helpText: row.help_text ? String(row.help_text) : undefined,
    sortOrder: Number.isFinite(Number(row.sort_order)) ? Number(row.sort_order) : 100,
  }
}

export async function loadCatalog(force = false): Promise<Catalog> {
  if (!force && catalogCache && Date.now() - catalogCache.at < CATALOG_TTL_MS) {
    return catalogCache.value
  }

  const [tradeRows, questionRows, settingRows] = await Promise.all([
    sbSelect('trade_catalog?select=*&order=sort_order.asc'),
    sbSelect('price_questions?select=*&order=sort_order.asc'),
    sbSelect('price_engine_settings?select=key,value'),
  ])

  const settings: EngineSettings = {
    thresholds: { ...DEFAULT_SETTINGS.thresholds },
    weights: { ...DEFAULT_SETTINGS.weights },
    outliers: { ...DEFAULT_SETTINGS.outliers },
  }
  for (const row of settingRows) {
    const key = String(row?.key || '')
    const value = row?.value
    if (!value || typeof value !== 'object') continue
    if (key === 'thresholds') Object.assign(settings.thresholds, value)
    else if (key === 'weights') Object.assign(settings.weights, value)
    else if (key === 'outliers') Object.assign(settings.outliers, value)
  }

  const value: Catalog = {
    trades: tradeRows.length ? tradeRows.map(rowToTrade) : DEFAULT_TRADES,
    questions: questionRows.length ? questionRows.map(rowToQuestion) : DEFAULT_QUESTIONS,
    settings,
    fromDatabase: tradeRows.length > 0,
  }
  catalogCache = { at: Date.now(), value }
  return value
}

// -----------------------------------------------------------------------------
// 표본 수집 — 우선순위: 완료 거래 > 최근 입찰 > 검증 사업자 표준 단가 > 운영자 기준표
// -----------------------------------------------------------------------------

const SAMPLE_LIMIT = 400

export async function loadSamples(
  trade: TradeDefinition,
  request: PriceRequest,
  settings: EngineSettings,
): Promise<PriceSample[]> {
  const tradeId = encodeURIComponent(trade.id)
  const since = new Date(
    Date.now() - settings.thresholds.maxSampleAgeDays * 86400000,
  ).toISOString()

  const [completed, bids, rateCards, baselines] = await Promise.all([
    sbSelect(
      `completed_jobs?trade_id=eq.${tradeId}&completion_at=gte.${since}` +
        `&select=id,final_total_amount,completion_at,region_level1,region_level2,property_type,final_work_scope_tags,vat_included` +
        `&order=completion_at.desc&limit=${SAMPLE_LIMIT}`,
    ),
    sbSelect(
      `order_bids?trade_id=eq.${tradeId}&bid_amount=not.is.null&created_at=gte.${since}` +
        `&select=id,bid_amount,created_at,work_scope_tags,vat_included,breakdown_provided` +
        `&order=created_at.desc&limit=${SAMPLE_LIMIT}`,
    ),
    sbSelect(
      `contractor_rate_cards?trade_id=eq.${tradeId}&active=is.true&verified=is.true` +
        `&select=id,base_labor_cost,material_avg_cost,visit_fee,material_included,vat_included,service_regions,updated_at` +
        `&limit=${SAMPLE_LIMIT}`,
    ),
    sbSelect(`price_baselines?trade_id=eq.${tradeId}&select=*`),
  ])

  const samples: PriceSample[] = []

  for (const row of completed) {
    samples.push({
      source: 'completed_job',
      value: Number(row.final_total_amount),
      occurredAt: row.completion_at ?? null,
      regionLevel1: row.region_level1 ?? null,
      regionLevel2: row.region_level2 ?? null,
      propertyType: row.property_type ?? null,
      workScopeTags: Array.isArray(row.final_work_scope_tags) ? row.final_work_scope_tags.map(String) : [],
      vatIncluded: row.vat_included ?? null,
      refId: row.id ?? null,
    })
  }

  for (const row of bids) {
    samples.push({
      source: 'contractor_bid',
      value: Number(row.bid_amount),
      occurredAt: row.created_at ?? null,
      workScopeTags: Array.isArray(row.work_scope_tags) ? row.work_scope_tags.map(String) : [],
      vatIncluded: row.vat_included ?? null,
      hasBreakdown: row.breakdown_provided === true,
      refId: row.id ?? null,
    })
  }

  for (const row of rateCards) {
    const labor = Number(row.base_labor_cost) || 0
    const material = row.material_included ? Number(row.material_avg_cost) || 0 : 0
    const visit = Number(row.visit_fee) || 0
    const regions = Array.isArray(row.service_regions) ? row.service_regions.map(String) : []
    samples.push({
      source: 'rate_card',
      value: labor + material + visit,
      occurredAt: row.updated_at ?? null,
      regionLevel1: regions[0] ?? null,
      workScopeTags: [],
      materialIncluded: row.material_included ?? null,
      vatIncluded: row.vat_included ?? null,
      refId: row.id ?? null,
    })
  }

  const baseline = pickBaseline(baselines, request)
  if (baseline) samples.push(...baselineToSamples(baseline))

  return samples
}

/** 요청 조건에 가장 구체적으로 맞는 기준표 한 줄. 지역+건물 > 지역 > 건물 > 전국. */
function pickBaseline(rows: any[], request: PriceRequest): any | null {
  if (!rows.length) return null
  const score = (row: any) => {
    const regionMatch = row.region_level1 && row.region_level1 === request.regionLevel1
    const propertyMatch = row.property_type && row.property_type === request.propertyType
    if (row.region_level1 && !regionMatch) return -1
    if (row.property_type && !propertyMatch) return -1
    return (regionMatch ? 2 : 0) + (propertyMatch ? 1 : 0)
  }
  const ranked = rows
    .map((row) => ({ row, s: score(row) }))
    .filter((r) => r.s >= 0)
    .sort((a, b) => b.s - a.s)
  return ranked[0]?.row ?? null
}

// -----------------------------------------------------------------------------
// 쓰기 경로
// -----------------------------------------------------------------------------

export async function saveEstimateSnapshot(row: Record<string, unknown>): Promise<void> {
  const res = await sbWrite('price_estimates', 'POST', row, 'return=minimal')
  if (!res.ok) console.warn('[price] 스냅샷 저장 생략:', res.error)
}

export async function upsertRateCard(row: Record<string, unknown>) {
  return sbWrite(
    'contractor_rate_cards?on_conflict=contractor_id,trade_id',
    'POST',
    row,
    'return=representation,resolution=merge-duplicates',
  )
}

export async function listRateCards(contractorId: string) {
  return sbSelect(
    `contractor_rate_cards?contractor_id=eq.${encodeURIComponent(contractorId)}&select=*&order=updated_at.desc`,
  )
}

export async function insertCompletedJob(row: Record<string, unknown>) {
  return sbWrite(
    'completed_jobs?on_conflict=listing_id',
    'POST',
    row,
    'return=representation,resolution=merge-duplicates',
  )
}

export async function listBaselines(tradeId?: string) {
  const filter = tradeId ? `trade_id=eq.${encodeURIComponent(tradeId)}&` : ''
  return sbSelect(`price_baselines?${filter}select=*&order=trade_id.asc`)
}

export async function upsertBaseline(row: Record<string, unknown>) {
  return sbWrite(
    'price_baselines?on_conflict=trade_id,region_level1,property_type',
    'POST',
    row,
    'return=representation,resolution=merge-duplicates',
  )
}

export async function upsertSetting(key: string, value: unknown, updatedBy: string) {
  catalogCache = null
  return sbWrite(
    'price_engine_settings?on_conflict=key',
    'POST',
    { key, value, updated_by: updatedBy, updated_at: new Date().toISOString() },
    'return=representation,resolution=merge-duplicates',
  )
}

export async function upsertTrade(row: Record<string, unknown>) {
  catalogCache = null
  return sbWrite(
    'trade_catalog?on_conflict=id',
    'POST',
    { ...row, updated_at: new Date().toISOString() },
    'return=representation,resolution=merge-duplicates',
  )
}

/** 사업자에게 보여줄 지역·공정 시장 리포트 (표본 수가 적으면 숫자를 감춥니다) */
export async function marketReport(tradeId: string, regionLevel1?: string | null) {
  const filter = regionLevel1
    ? `&region_level1=eq.${encodeURIComponent(regionLevel1)}`
    : ''
  const rows = await sbSelect(
    `completed_jobs?trade_id=eq.${encodeURIComponent(tradeId)}${filter}` +
      `&select=final_total_amount,completion_at&order=completion_at.desc&limit=200`,
  )
  return rows
    .map((r) => ({ value: Number(r.final_total_amount), at: r.completion_at as string }))
    .filter((r) => Number.isFinite(r.value) && r.value > 0)
}

/** 리스팅 → 공정 추정에 필요한 최소 정보. */
/** 낙찰된 입찰(공정 trade_id 포함). 사업자 간 오더는 고객 주문이 없어 공정을 여기서 이어받습니다. */
export async function selectedBidForListing(
  listingId: string,
): Promise<{ id: string; trade_id: string | null } | null> {
  const rows = await sbSelect(
    `order_bids?listing_id=eq.${encodeURIComponent(listingId)}&status=eq.selected&select=id,trade_id&limit=1`,
  )
  return rows[0] ?? null
}

export async function listingContext(listingId: string): Promise<{
  listing: any | null
  order: any | null
}> {
  const listings = await sbSelect(
    `marketplace_listings?id=eq.${encodeURIComponent(listingId)}` +
      `&select=id,title,description,category,region,web_order_id,jobid,posted_by,selected_bidder_id&limit=1`,
  )
  const listing = listings[0] ?? null
  if (!listing?.web_order_id) return { listing, order: null }
  const orders = await sbSelect(
    `orders?id=eq.${encodeURIComponent(listing.web_order_id)}` +
      `&select=id,title,description,category,address,"tradeId","subcategory","propertyType","urgency","locationLevel1","locationLevel2"&limit=1`,
  )
  return { listing, order: orders[0] ?? null }
}
