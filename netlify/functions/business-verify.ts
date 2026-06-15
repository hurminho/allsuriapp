/// <reference types="node" />
// Netlify Function: 사업자등록정보 진위확인 + 휴/폐업 상태조회
// 국세청 공공데이터 API (https://www.data.go.kr/tcs/dss/selectApiDataDetailView.do?publicDataPk=15081808)
//
// 호출 경로 (netlify.toml /api/* 일반 라우트 사용):
//   POST /api/business-verify
//   GET  /api/business-verify         → 환경변수 진단
//
// 요청 헤더:
//   Authorization: Bearer <Supabase access token>
//
// 요청 바디:
//   { b_no: "1234567890", p_nm: "홍길동", start_dt: "20240101", b_nm?: "올수리" }
//
// 응답 (성공):
//   { success: true, status: "verified", code: "OK",
//     rep_name: "홍**", tax_type: "일반과세자", b_stt: "계속사업자" }
//
// 응답 (실패): { success: false, code: "DUPLICATE|NOT_MATCHED|CLOSED|INVALID_FORMAT|RATE_LIMITED|UPSTREAM_ERROR|UNAUTHORIZED|...", message: "..." }

const SUPABASE_URL = process.env.SUPABASE_URL as string
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY as string
const BUSINESS_API_SERVICE_KEY = process.env.BUSINESS_API_SERVICE_KEY as string

const NTS_BASE = 'https://api.odcloud.kr/api/nts-businessman/v1'

const JSON_HEADERS = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
}

type ApiResp = { statusCode: number; body: string; headers: Record<string, string> }

const ok = (obj: any): ApiResp => ({ statusCode: 200, body: JSON.stringify(obj), headers: JSON_HEADERS })
const fail = (status: number, code: string, message: string, extra: Record<string, unknown> = {}): ApiResp =>
  ({ statusCode: status, body: JSON.stringify({ success: false, code, message, ...extra }), headers: JSON_HEADERS })

// ─────────────────────────────────────────────────────────────────────────
// 유틸
// ─────────────────────────────────────────────────────────────────────────

/** 사업자번호 정규화: 숫자만 남기고 10자리 검증 */
function normalizeBNo(input: unknown): string | null {
  if (typeof input !== 'string') return null
  const digits = input.replace(/[^0-9]/g, '')
  return digits.length === 10 ? digits : null
}

/** YYYYMMDD 검증 */
function normalizeStartDt(input: unknown): string | null {
  if (typeof input !== 'string') return null
  const digits = input.replace(/[^0-9]/g, '')
  if (digits.length !== 8) return null
  const y = Number(digits.slice(0, 4))
  const m = Number(digits.slice(4, 6))
  const d = Number(digits.slice(6, 8))
  if (y < 1900 || y > 2100 || m < 1 || m > 12 || d < 1 || d > 31) return null
  return digits
}

/** 대표자명 마스킹: 홍길동 → 홍*동 / 김철 → 김* / Smith → S***h */
function maskName(name: string): string {
  const trimmed = name.trim()
  if (trimmed.length <= 1) return '*'
  if (trimmed.length === 2) return trimmed[0] + '*'
  return trimmed[0] + '*'.repeat(trimmed.length - 2) + trimmed[trimmed.length - 1]
}

/** YYYYMMDD → YYYY-MM-DD (Postgres date 캐스팅 안전) */
function toIsoDate(yyyymmdd: string): string {
  return `${yyyymmdd.slice(0, 4)}-${yyyymmdd.slice(4, 6)}-${yyyymmdd.slice(6, 8)}`
}

// ─────────────────────────────────────────────────────────────────────────
// Supabase REST 헬퍼 (service role)
// ─────────────────────────────────────────────────────────────────────────

const sbHeaders = {
  apikey: SUPABASE_SERVICE_ROLE_KEY,
  Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
  'Content-Type': 'application/json',
}

async function sbSelect(path: string): Promise<any[]> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, { headers: sbHeaders })
  if (!res.ok) {
    const text = await res.text()
    throw new Error(`supabase select failed: ${res.status} ${text}`)
  }
  return (await res.json()) as any[]
}

async function sbPatch(path: string, payload: Record<string, unknown>): Promise<void> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    method: 'PATCH',
    headers: { ...sbHeaders, Prefer: 'return=minimal' },
    body: JSON.stringify(payload),
  })
  if (!res.ok) {
    const text = await res.text()
    throw new Error(`supabase patch failed: ${res.status} ${text}`)
  }
}

async function sbInsert(table: string, payload: Record<string, unknown>): Promise<void> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${table}`, {
    method: 'POST',
    headers: { ...sbHeaders, Prefer: 'return=minimal' },
    body: JSON.stringify(payload),
  })
  if (!res.ok) {
    const text = await res.text()
    throw new Error(`supabase insert failed: ${res.status} ${text}`)
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 국세청 공공데이터 API 호출
// ─────────────────────────────────────────────────────────────────────────

/** 휴/폐업 상태 조회 */
async function ntsStatus(bNo: string): Promise<any> {
  const url = `${NTS_BASE}/status?serviceKey=${encodeURIComponent(BUSINESS_API_SERVICE_KEY)}&returnType=JSON`
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ b_no: [bNo] }),
  })
  if (!res.ok) {
    const text = await res.text()
    throw new Error(`nts status failed: ${res.status} ${text}`)
  }
  return res.json()
}

/** 진위확인 (사업자번호+개업일+대표자명) */
async function ntsValidate(payload: {
  b_no: string
  start_dt: string
  p_nm: string
  b_nm?: string
}): Promise<any> {
  const url = `${NTS_BASE}/validate?serviceKey=${encodeURIComponent(BUSINESS_API_SERVICE_KEY)}&returnType=JSON`
  const businesses: Record<string, string> = {
    b_no: payload.b_no,
    start_dt: payload.start_dt,
    p_nm: payload.p_nm,
  }
  if (payload.b_nm && payload.b_nm.trim()) businesses.b_nm = payload.b_nm.trim()
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ businesses: [businesses] }),
  })
  if (!res.ok) {
    const text = await res.text()
    throw new Error(`nts validate failed: ${res.status} ${text}`)
  }
  return res.json()
}

// ─────────────────────────────────────────────────────────────────────────
// Supabase JWT → 사용자 ID 추출
// ─────────────────────────────────────────────────────────────────────────

async function authenticateUser(authHeader: string): Promise<string | null> {
  const token = authHeader.replace(/^Bearer\s+/i, '').trim()
  if (!token) return null

  const verifyRes = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${token}` },
  })
  if (!verifyRes.ok) return null
  const u = (await verifyRes.json()) as any
  return (u && typeof u.id === 'string') ? u.id : null
}

// ─────────────────────────────────────────────────────────────────────────
// 메인 핸들러
// ─────────────────────────────────────────────────────────────────────────

export const handler = async (event: any): Promise<ApiResp> => {
  // 진단 엔드포인트
  if (event.httpMethod === 'GET') {
    const qs = (event.queryStringParameters || {}) as Record<string, string>

    // 국세청(NTS) 업스트림 실연동 셀프테스트.
    //  - 키 인코딩 오류 / NTS 다운 / 정상 여부를 구분하기 위함.
    //  - 공개적으로 알려진 사업자번호(삼성전자 124-81-00998)로 status 조회만 수행.
    //  - 키 값 자체는 절대 응답에 노출하지 않는다.
    if (qs.selftest === '1') {
      if (!BUSINESS_API_SERVICE_KEY) {
        return ok({ selftest: true, ok: false, reason: 'NO_SERVICE_KEY' })
      }
      // 파라미터로 임의 사업자 테스트 가능 (없으면 공개번호 삼성전자로 키 점검).
      // 인증/DB쓰기 없이 국세청 status, (p_nm 있으면) validate 만 호출하는 읽기전용 진단.
      const testBNo = normalizeBNo(qs.b_no) || '1248100998'
      const testStartDt = normalizeStartDt(qs.start_dt || '')
      const testPNm = (qs.p_nm || '').trim()
      const testBNm = (qs.b_nm || '').trim()
      try {
        // 1) status
        const statusUrl = `${NTS_BASE}/status?serviceKey=${encodeURIComponent(BUSINESS_API_SERVICE_KEY)}&returnType=JSON`
        const sres = await fetch(statusUrl, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ b_no: [testBNo] }),
        })
        const sraw = await sres.text()
        let sparsed: any = null
        try { sparsed = JSON.parse(sraw) } catch (_) { /* not JSON */ }
        const sitem = sparsed && Array.isArray(sparsed.data) ? sparsed.data[0] : null

        // 2) validate (대표자명이 있을 때만)
        let validateResult: any = null
        if (testPNm.length >= 2 && testStartDt) {
          const businesses: Record<string, string> = { b_no: testBNo, start_dt: testStartDt, p_nm: testPNm }
          if (testBNm) businesses.b_nm = testBNm
          const vUrl = `${NTS_BASE}/validate?serviceKey=${encodeURIComponent(BUSINESS_API_SERVICE_KEY)}&returnType=JSON`
          const vres = await fetch(vUrl, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ businesses: [businesses] }),
          })
          const vraw = await vres.text()
          let vparsed: any = null
          try { vparsed = JSON.parse(vraw) } catch (_) { /* not JSON */ }
          const vitem = vparsed && Array.isArray(vparsed.data) ? vparsed.data[0] : null
          validateResult = {
            upstreamHttpStatus: vres.status,
            valid: vitem?.valid ?? null,
            valid_msg: vitem?.valid_msg ?? null,
            rawSnippet: vparsed ? undefined : vraw.slice(0, 300),
          }
        }

        return ok({
          selftest: true,
          tested_b_no: testBNo,
          status: {
            upstreamHttpStatus: sres.status,
            nts_status_code: sparsed?.status_code ?? null,
            match_cnt: sparsed?.match_cnt ?? null,
            b_stt: sitem?.b_stt ?? null,
            tax_type: sitem?.tax_type ?? null,
            end_dt: sitem?.end_dt ?? null,
            rawSnippet: sparsed ? undefined : sraw.slice(0, 300),
          },
          validate: validateResult,
        })
      } catch (e: any) {
        return ok({ selftest: true, ok: false, reason: 'FETCH_ERROR', detail: e?.message })
      }
    }

    return ok({
      status: 'ok',
      env: {
        SUPABASE_URL: !!SUPABASE_URL,
        SUPABASE_SERVICE_ROLE_KEY: !!SUPABASE_SERVICE_ROLE_KEY,
        BUSINESS_API_SERVICE_KEY: !!BUSINESS_API_SERVICE_KEY,
      },
    })
  }
  if (event.httpMethod === 'OPTIONS') {
    return { statusCode: 204, body: '', headers: JSON_HEADERS }
  }
  if (event.httpMethod !== 'POST') {
    return fail(405, 'METHOD_NOT_ALLOWED', 'POST only')
  }

  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY || !BUSINESS_API_SERVICE_KEY) {
    return fail(500, 'SERVER_MISCONFIGURED', '필수 환경 변수가 누락되었습니다.')
  }

  // 1) 인증
  const authHeader = (event.headers['authorization'] || event.headers['Authorization'] || '') as string
  const userId = await authenticateUser(authHeader)
  if (!userId) {
    return fail(401, 'UNAUTHORIZED', '로그인이 필요합니다.')
  }

  // 2) 입력 파싱/정규화
  let body: any
  try {
    body = JSON.parse(event.body || '{}')
  } catch (_) {
    return fail(400, 'INVALID_FORMAT', '요청 본문을 해석할 수 없습니다.')
  }

  const bNo = normalizeBNo(body.b_no)
  const startDt = normalizeStartDt(body.start_dt)
  const pNmRaw: string = (typeof body.p_nm === 'string' ? body.p_nm : '').trim()
  const bNmRaw: string | undefined = typeof body.b_nm === 'string' ? body.b_nm.trim() : undefined

  if (!bNo) return fail(400, 'INVALID_FORMAT', '사업자번호 10자리를 입력해 주세요.')
  if (!startDt) return fail(400, 'INVALID_FORMAT', '개업일을 YYYYMMDD 형식으로 입력해 주세요.')
  if (pNmRaw.length < 2) return fail(400, 'INVALID_FORMAT', '대표자명을 입력해 주세요.')

  const repNameMasked = maskName(pNmRaw)

  try {
    // 3) 호출 한도 가드 (마지막 시도 시각 기준 분당 3회)
    const me = await sbSelect(
      `users?id=eq.${encodeURIComponent(userId)}&select=id,role,businessstatus,business_verify_status,business_verify_attempts,business_verify_last_attempt_at`
    )
    if (!me.length) return fail(403, 'FORBIDDEN', '사용자 정보를 찾을 수 없습니다.')

    const meRow = me[0]
    if (meRow.role !== 'business') {
      return fail(403, 'FORBIDDEN', '사업자 회원만 진위확인을 진행할 수 있습니다.')
    }

    if (meRow.business_verify_last_attempt_at) {
      const lastMs = new Date(meRow.business_verify_last_attempt_at).getTime()
      if (Date.now() - lastMs < 1000) {
        return fail(429, 'RATE_LIMITED', '잠시 후 다시 시도해 주세요.')
      }
    }

    // 4) 중복 체크: 본인 외 verified 동일 번호 존재?
    const dup = await sbSelect(
      `users?businessnumber_norm=eq.${bNo}&business_verify_status=eq.verified&id=neq.${encodeURIComponent(userId)}&select=id`
    )
    if (dup.length > 0) {
      await sbInsert('business_verifications', {
        user_id: userId,
        businessnumber_norm: bNo,
        rep_name_masked: repNameMasked,
        open_date: toIsoDate(startDt),
        api_endpoint: 'duplicate_check',
        api_response: { conflict_user_count: dup.length },
        is_valid: false,
        reason: 'DUPLICATE',
      })
      await sbPatch(`users?id=eq.${encodeURIComponent(userId)}`, {
        business_verify_attempts: (meRow.business_verify_attempts ?? 0) + 1,
        business_verify_last_attempt_at: new Date().toISOString(),
      })
      return fail(409, 'DUPLICATE', '이미 다른 계정에서 인증된 사업자번호입니다.')
    }

    // 5) 휴/폐업 상태 조회
    let statusJson: any
    try {
      statusJson = await ntsStatus(bNo)
    } catch (e: any) {
      console.error('[business-verify] status upstream error:', e?.message)
      return fail(502, 'UPSTREAM_ERROR', '국세청 서비스 응답을 받지 못했습니다. 잠시 후 다시 시도해 주세요.')
    }
    const statusItem = Array.isArray(statusJson?.data) ? statusJson.data[0] : null
    const bStt: string = statusItem?.b_stt || ''
    const taxType: string = statusItem?.tax_type || ''
    const endDt: string = statusItem?.end_dt || ''

    // 국세청 응답: b_stt가 '계속사업자'가 아니거나 비어있으면 휴/폐업/등록되지 않은 번호
    if (!bStt) {
      await sbInsert('business_verifications', {
        user_id: userId,
        businessnumber_norm: bNo,
        rep_name_masked: repNameMasked,
        open_date: toIsoDate(startDt),
        api_endpoint: 'status',
        api_response: statusItem ?? statusJson,
        is_valid: false,
        reason: 'NOT_REGISTERED',
      })
      await sbPatch(`users?id=eq.${encodeURIComponent(userId)}`, {
        business_verify_status: 'failed',
        business_verify_attempts: (meRow.business_verify_attempts ?? 0) + 1,
        business_verify_last_attempt_at: new Date().toISOString(),
      })
      return fail(404, 'NOT_REGISTERED', '국세청에 등록되지 않은 사업자번호입니다.')
    }
    if (bStt !== '계속사업자') {
      await sbInsert('business_verifications', {
        user_id: userId,
        businessnumber_norm: bNo,
        rep_name_masked: repNameMasked,
        open_date: toIsoDate(startDt),
        api_endpoint: 'status',
        api_response: statusItem,
        is_valid: false,
        reason: 'CLOSED',
      })
      await sbPatch(`users?id=eq.${encodeURIComponent(userId)}`, {
        business_verify_status: 'closed',
        business_verify_attempts: (meRow.business_verify_attempts ?? 0) + 1,
        business_verify_last_attempt_at: new Date().toISOString(),
      })
      return fail(409, 'CLOSED', `현재 ${bStt} 상태입니다.${endDt ? ` (변동일: ${endDt})` : ''}`)
    }

    // 6) 진위확인 (사업자번호 + 개업일 + 대표자명)
    let validateJson: any
    try {
      validateJson = await ntsValidate({ b_no: bNo, start_dt: startDt, p_nm: pNmRaw, b_nm: bNmRaw })
    } catch (e: any) {
      console.error('[business-verify] validate upstream error:', e?.message)
      return fail(502, 'UPSTREAM_ERROR', '국세청 서비스 응답을 받지 못했습니다. 잠시 후 다시 시도해 주세요.')
    }
    const validItem = Array.isArray(validateJson?.data) ? validateJson.data[0] : null
    const valid: string = validItem?.valid || ''
    const validMsg: string = validItem?.valid_msg || ''

    if (valid !== '01') {
      await sbInsert('business_verifications', {
        user_id: userId,
        businessnumber_norm: bNo,
        rep_name_masked: repNameMasked,
        open_date: toIsoDate(startDt),
        api_endpoint: 'validate',
        api_response: { valid, valid_msg: validMsg },
        is_valid: false,
        reason: 'NOT_MATCHED',
      })
      await sbPatch(`users?id=eq.${encodeURIComponent(userId)}`, {
        business_verify_status: 'failed',
        business_verify_attempts: (meRow.business_verify_attempts ?? 0) + 1,
        business_verify_last_attempt_at: new Date().toISOString(),
      })
      return fail(409, 'NOT_MATCHED', '사업자번호와 대표자명/개업일이 일치하지 않습니다.')
    }

    // 7) 성공: 사용자/감사 테이블 갱신
    const nowIso = new Date().toISOString()
    await sbInsert('business_verifications', {
      user_id: userId,
      businessnumber_norm: bNo,
      rep_name_masked: repNameMasked,
      open_date: toIsoDate(startDt),
      api_endpoint: 'validate',
      api_response: { valid, valid_msg: validMsg, b_stt: bStt, tax_type: taxType },
      is_valid: true,
      reason: 'OK',
    })
    await sbPatch(`users?id=eq.${encodeURIComponent(userId)}`, {
      businessnumber: bNo,
      business_repname: pNmRaw, // 대표자명은 users에 평문 저장 (DB 접근 권한자만 조회 가능)
      business_open_date: toIsoDate(startDt),
      business_verify_status: 'verified',
      business_verified_at: nowIso,
      business_grace_until: null, // 인증 완료 시 유예 만료 무효화
      business_verify_last_attempt_at: nowIso,
    })

    return ok({
      success: true,
      status: 'verified',
      code: 'OK',
      rep_name: repNameMasked,
      tax_type: taxType,
      b_stt: bStt,
    })
  } catch (e: any) {
    console.error('[business-verify] internal error:', e?.message, e?.stack)
    return fail(500, 'INTERNAL_ERROR', '내부 오류가 발생했습니다.')
  }
}
