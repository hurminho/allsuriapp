/// <reference types="node" />
// Netlify function: admin API router
// Proxies selected endpoints used by backend/public/admin.js
// import { createClient } from "@supabase/supabase-js"; // ✅ 제거

const ADMIN_TOKEN = process.env.ADMIN_TOKEN || process.env.ADMIN_DEVELOPER_TOKEN || 'devtoken'
const SUPABASE_URL = process.env.SUPABASE_URL as string
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY as string

function unauthorized() {
  return { statusCode: 401, body: JSON.stringify({ message: '관리자 권한이 필요합니다' }), headers: { 'Content-Type': 'application/json' } };
}

function withAuth(headers: Record<string, string>): boolean {
  const token = headers['admin-token'] || headers['x-admin-token'] || ''
  return token === ADMIN_TOKEN
}

export const handler = async (event: any) => { // event 타입 any로 임시 설정
  try {
    // method/path
    const path = (() => {
      const p = event.path || '/'
      const a = p.replace(/^\/\.netlify\/functions\/admin/, '')
      const b = a.replace(/^\/api\/admin/, '')
      return b || '/'
    })()

    if (!withAuth(event.headers as any)) {
      return unauthorized()
    }

    // Dashboard aggregate (direct Supabase queries)
    if (event.httpMethod === 'GET' && path === '/dashboard') {
      const headers = { apikey: SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}` }

      // Fetch users (Supabase 에러 객체 반환 시 빈 배열로 처리)
      const usersRes = await fetch(`${SUPABASE_URL}/rest/v1/users?select=role,businessstatus`, { headers })
      const usersRaw = await usersRes.json()
      const users = Array.isArray(usersRaw) ? usersRaw : (usersRaw?.code ? [] : [])
      const totalUsers = Array.isArray(users) ? users.length : 0
      const totalBusinessUsers = Array.isArray(users) ? users.filter((u: any) => u.role === 'business').length : 0
      const totalCustomers = Array.isArray(users) ? users.filter((u: any) => u.role === 'customer').length : 0
      const pendingBusinessUsers = Array.isArray(users) ? users.filter((u: any) => u.role === 'business' && u.businessstatus === 'pending').length : 0

      // Fetch estimates (에러 객체 시 빈 배열)
      const estimatesRes = await fetch(`${SUPABASE_URL}/rest/v1/estimates?select=status,amount`, { headers })
      const estimatesRaw = await estimatesRes.json()
      const estimates = Array.isArray(estimatesRaw) ? estimatesRaw : (estimatesRaw?.code ? [] : [])

      console.log('[ADMIN DASHBOARD] Estimates count:', Array.isArray(estimates) ? estimates.length : 0)
      console.log('[ADMIN DASHBOARD] Estimates sample:', Array.isArray(estimates) ? estimates.slice(0, 5) : [])

      const totalEstimates = Array.isArray(estimates) ? estimates.length : 0
      const pendingEstimates = Array.isArray(estimates) ? estimates.filter((e: any) => e.status === 'pending').length : 0
      const approvedEstimates = Array.isArray(estimates) ? estimates.filter((e: any) => e.status === 'approved').length : 0
      const completedEstimates = Array.isArray(estimates) ? estimates.filter((e: any) => e.status === 'completed').length : 0
      const inProgressEstimates = Array.isArray(estimates) ? estimates.filter((e: any) => e.status === 'in_progress').length : 0
      const awardedEstimates = Array.isArray(estimates) ? estimates.filter((e: any) => e.status === 'awarded').length : 0
      const transferredEstimates = Array.isArray(estimates) ? estimates.filter((e: any) => e.status === 'transferred').length : 0

      // 완료된 견적의 총 금액 계산
      // completed, awarded, transferred 상태의 견적 모두 포함
      const completedStatuses = ['completed', 'awarded', 'transferred']
      const completedEstimatesList = Array.isArray(estimates)
        ? estimates.filter((e: any) => completedStatuses.includes(e.status))
        : []

      const totalEstimateAmount = completedEstimatesList.reduce((sum: number, e: any) => {
        const amount = e.amount || 0
        console.log(`[ADMIN DASHBOARD] Estimate amount: ${amount}, status: ${e.status}`)
        return sum + amount
      }, 0)

      console.log('[ADMIN DASHBOARD] Total estimate amount:', totalEstimateAmount)
      console.log('[ADMIN DASHBOARD] Completed estimates count:', completedEstimatesList.length)

      // 총 수익: 완료된 견적 금액의 5% 계산
      const totalRevenue = totalEstimateAmount * 0.05

      // Fetch marketplace_listings (에러 객체 시 빈 배열)
      const listingsRes = await fetch(`${SUPABASE_URL}/rest/v1/marketplace_listings?select=id,status,claimed_by,budget_amount`, { headers })
      const listingsRaw = await listingsRes.json()
      const listings = Array.isArray(listingsRaw) ? listingsRaw : (listingsRaw?.code ? [] : [])
      console.log('[ADMIN DASHBOARD] Listings count:', Array.isArray(listings) ? listings.length : 0)
      console.log('[ADMIN DASHBOARD] Listings sample:', Array.isArray(listings) ? listings.slice(0, 3) : [])

      const totalOrders = Array.isArray(listings) ? listings.length : 0
      // 입찰 중: status가 'created' 또는 'open'이고 아직 claimed_by가 없는 경우
      const pendingOrders = Array.isArray(listings)
        ? listings.filter((l: any) => (l.status === 'created' || l.status === 'open') && !l.claimed_by).length
        : 0
      // 완료: status가 'assigned'이거나 claimed_by가 있는 경우
      const completedOrdersList = Array.isArray(listings)
        ? listings.filter((l: any) => l.status === 'assigned' || l.claimed_by)
        : []
      const completedOrders = completedOrdersList.length

      // 완료된 오더의 총 예산 금액
      const totalOrderAmount = completedOrdersList.reduce((sum: number, l: any) => {
        const budget = l.budget_amount || 0
        console.log(`[ADMIN DASHBOARD] Order budget: ${budget}, status: ${l.status}`)
        return sum + budget
      }, 0)

      console.log('[ADMIN DASHBOARD] Orders - Total:', totalOrders, 'Pending:', pendingOrders, 'Completed:', completedOrders)
      console.log('[ADMIN DASHBOARD] Total order amount:', totalOrderAmount)

      // Fetch jobs (에러 객체 시 빈 배열)
      const jobsRes = await fetch(`${SUPABASE_URL}/rest/v1/jobs?select=id,status`, { headers })
      const jobsRaw = await jobsRes.json()
      const jobs = Array.isArray(jobsRaw) ? jobsRaw : (jobsRaw?.code ? [] : [])
      const totalJobs = Array.isArray(jobs) ? jobs.length : 0
      const pendingJobs = Array.isArray(jobs) ? jobs.filter((j: any) => j.status === 'pending').length : 0
      const completedJobs = Array.isArray(jobs) ? jobs.filter((j: any) => j.status === 'completed').length : 0

      return {
        statusCode: 200,
        body: JSON.stringify({
          totalUsers,
          totalBusinessUsers,
          totalCustomers,
          approvedUsers: totalBusinessUsers - pendingBusinessUsers,
          totalEstimates,
          pendingEstimates,
          approvedEstimates,
          completedEstimates,
          inProgressEstimates,
          awardedEstimates,
          transferredEstimates,
          totalEstimateAmount: Math.round(totalEstimateAmount),
          totalRevenue: Math.round(totalRevenue),
          totalOrders,
          pendingOrders,
          completedOrders,
          totalOrderAmount: Math.round(totalOrderAmount),
          totalJobs,
          pendingJobs,
          completedJobs
        }),
        headers: { 'Content-Type': 'application/json' }
      };
    }

    // Admin me
    if (event.httpMethod === 'GET' && path === '/me') {
      return { statusCode: 200, body: JSON.stringify({ role: 'developer', permissions: { canManageUsers: true, canManageAds: true } }), headers: { 'Content-Type': 'application/json' } };
    }


    // Users list (from Supabase)
    if (event.httpMethod === 'GET' && path === '/users') {
      const res = await fetch(`${SUPABASE_URL}/rest/v1/users?select=*`, {
        headers: { apikey: SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}` },
      })
      const json = await res.json()
      return { statusCode: 200, body: JSON.stringify(Array.isArray(json) ? json : []), headers: { 'Content-Type': 'application/json' } };
    }

    // Users search
    if (event.httpMethod === 'GET' && path.startsWith('/users/search')) {
      const q = new URLSearchParams(event.queryStringParameters as any).get('q') || ''
      const like = encodeURIComponent(`%${q}%`)
      const url = `${SUPABASE_URL}/rest/v1/users?or=(name.ilike.${like},email.ilike.${like})`
      const res = await fetch(url, { headers: { apikey: SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}` } })
      const json = await res.json()
      return { statusCode: 200, body: JSON.stringify(Array.isArray(json) ? json : []), headers: { 'Content-Type': 'application/json' } };
    }

    // User admin toggle (관리자 권한 지정/해제)
    if (event.httpMethod === 'PATCH' && path.startsWith('/users/') && path.endsWith('/admin')) {
      const userId = path.split('/')[2]
      const body = JSON.parse(event.body || '{}')
      const is_admin = body.is_admin === true

      const upRes = await fetch(`${SUPABASE_URL}/rest/v1/users?id=eq.${encodeURIComponent(userId)}`, {
        method: 'PATCH',
        headers: {
          apikey: SUPABASE_SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
          'Content-Type': 'application/json',
          Prefer: 'return=representation',
        },
        body: JSON.stringify({ is_admin }),
      })

      if (!upRes.ok) {
        const errText = await upRes.text()
        console.error('❌ 관리자 권한 변경 실패:', upRes.status, errText)
        return { statusCode: 500, body: JSON.stringify({ success: false, message: '관리자 권한 변경 실패', error: errText }), headers: { 'Content-Type': 'application/json' } };
      }

      const updated = await upRes.json()
      const user = Array.isArray(updated) ? updated[0] : updated
      console.log('✅ 관리자 권한 변경 성공:', userId, '→', is_admin)
      return { 
        statusCode: 200, 
        body: JSON.stringify({ 
          success: true, 
          message: is_admin ? '관리자로 지정되었습니다' : '관리자 권한이 해제되었습니다',
          data: user 
        }), 
        headers: { 'Content-Type': 'application/json' } 
      };
    }

    // 사업자 진위확인 우회(화이트리스트) 토글
    // PATCH /users/:id/verify-bypass  body: { bypass: boolean, reason?: string }
    if (event.httpMethod === 'PATCH' && path.startsWith('/users/') && path.endsWith('/verify-bypass')) {
      const userId = path.split('/')[2]
      const body = JSON.parse(event.body || '{}')
      const bypass = body.bypass === true
      const reason: string | undefined = typeof body.reason === 'string' ? body.reason : undefined

      const updatePayload: Record<string, unknown> = {
        business_verify_bypass: bypass,
        business_verify_bypass_reason: bypass ? (reason ?? null) : null,
        business_verify_bypass_set_at: new Date().toISOString(),
        // 관리자 본인의 user id를 모르므로 set_by는 null로 둔다 (admin token 기반)
        business_verify_bypass_set_by: null,
        updatedat: new Date().toISOString(),
      }

      const upRes = await fetch(`${SUPABASE_URL}/rest/v1/users?id=eq.${encodeURIComponent(userId)}`, {
        method: 'PATCH',
        headers: {
          apikey: SUPABASE_SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
          'Content-Type': 'application/json',
          Prefer: 'return=representation',
        },
        body: JSON.stringify(updatePayload),
      })

      if (!upRes.ok) {
        const errText = await upRes.text()
        console.error('❌ verify-bypass 변경 실패:', upRes.status, errText)
        return { statusCode: 500, body: JSON.stringify({ success: false, message: '인증 우회 토글 실패', error: errText }), headers: { 'Content-Type': 'application/json' } }
      }

      const updated = await upRes.json()
      const user = Array.isArray(updated) ? updated[0] : updated
      console.log('✅ verify-bypass 변경 성공:', userId, '→', bypass)
      return {
        statusCode: 200,
        body: JSON.stringify({
          success: true,
          message: bypass ? '인증 우회가 활성화되었습니다' : '인증 우회가 해제되었습니다',
          data: user,
        }),
        headers: { 'Content-Type': 'application/json' },
      }
    }

    // User status update
    if (event.httpMethod === 'PATCH' && path.startsWith('/users/') && path.endsWith('/status')) {
      const userId = path.split('/')[2]
      const body = JSON.parse(event.body || '{}')
      const status = body.status || 'pending'

      // Supabase 테이블 컬럼명에 맞춤 (소문자)
      const updatePayload = {
        businessstatus: status  // 소문자로 통일
      }

      const upRes = await fetch(`${SUPABASE_URL}/rest/v1/users?id=eq.${encodeURIComponent(userId)}`, {
        method: 'PATCH',
        headers: {
          apikey: SUPABASE_SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
          'Content-Type': 'application/json',
          Prefer: 'return=representation',
        },
        body: JSON.stringify(updatePayload),
      })

      if (!upRes.ok) {
        const errText = await upRes.text()
        console.error('❌ 사용자 상태 업데이트 실패:', upRes.status, errText)
        return { statusCode: 500, body: JSON.stringify({ message: '상태 업데이트 실패', error: errText }), headers: { 'Content-Type': 'application/json' } };
      }

      const updated = await upRes.json()
      console.log('✅ 사용자 상태 업데이트 성공:', userId, '→', status)
      return { statusCode: 200, body: JSON.stringify({ success: true, user: Array.isArray(updated) ? updated[0] : updated }), headers: { 'Content-Type': 'application/json' } };
    }

    // PATCH /users/:id  – 사업자 프로필 수정 (상태 변경 엔드포인트와 충돌 방지)
    if (event.httpMethod === 'PATCH' && path.match(/^\/users\/[^/]+$/)
        && !path.endsWith('/admin') && !path.endsWith('/status')) {
      const userId = path.split('/')[2]
      const body = JSON.parse(event.body || '{}')
      const allowed = ['businessname', 'name', 'phonenumber', 'region', 'category', 'description', 'businessnumber', 'businessstatus']
      const updatePayload: Record<string, string> = {}
      for (const key of allowed) {
        if (body[key] !== undefined) updatePayload[key] = body[key]
      }
      if (Object.keys(updatePayload).length === 0) {
        return { statusCode: 400, body: JSON.stringify({ success: false, message: '수정할 필드가 없습니다.' }), headers: { 'Content-Type': 'application/json' } }
      }
      updatePayload['updatedat'] = new Date().toISOString()
      const upRes = await fetch(`${SUPABASE_URL}/rest/v1/users?id=eq.${encodeURIComponent(userId)}`, {
        method: 'PATCH',
        headers: {
          apikey: SUPABASE_SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
          'Content-Type': 'application/json',
          Prefer: 'return=representation',
        },
        body: JSON.stringify(updatePayload),
      })
      if (!upRes.ok) {
        const errText = await upRes.text()
        console.error('❌ 사용자 정보 수정 실패:', upRes.status, errText)
        return { statusCode: 500, body: JSON.stringify({ success: false, message: '정보 수정 실패', error: errText }), headers: { 'Content-Type': 'application/json' } }
      }
      const updated = await upRes.json()
      console.log('✅ 사용자 정보 수정 완료:', userId)
      return { statusCode: 200, body: JSON.stringify({ success: true, message: '정보가 수정되었습니다.', data: Array.isArray(updated) ? updated[0] : updated }), headers: { 'Content-Type': 'application/json' } }
    }

    // DELETE user (CASCADE 삭제 사용)
    if (event.httpMethod === 'DELETE' && path.startsWith('/users/')) {
      const userId = path.split('/')[2]
      
      console.log(`[ADMIN] 사용자 삭제 시작: userId=${userId}`)
      
      // RPC 함수 호출로 CASCADE 삭제
      const rpcRes = await fetch(`${SUPABASE_URL}/rest/v1/rpc/delete_user_cascade`, {
        method: 'POST',
        headers: {
          apikey: SUPABASE_SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ user_id_to_delete: userId }),
      })
      
      if (!rpcRes.ok) {
        const errText = await rpcRes.text()
        console.error('❌ 사용자 삭제 실패:', rpcRes.status, errText)
        return { 
          statusCode: 500, 
          body: JSON.stringify({ success: false, message: '사용자 삭제 실패', error: errText }), 
          headers: { 'Content-Type': 'application/json' } 
        };
      }
      
      const deleted_counts = await rpcRes.json()
      console.log(`[ADMIN] 사용자 삭제 완료:`, deleted_counts)
      
      return { 
        statusCode: 200, 
        body: JSON.stringify({ 
          success: true, 
          message: '사용자가 삭제되었습니다',
          deleted_counts 
        }), 
        headers: { 'Content-Type': 'application/json' } 
      };
    }

    // DELETE listing (오더 삭제)
    if (event.httpMethod === 'DELETE' && path.startsWith('/listings/')) {
      const listingId = path.split('/')[2]
      
      console.log(`[ADMIN] 오더 삭제 시작: listingId=${listingId}`)
      
      // marketplace_listings 삭제 (CASCADE로 order_bids도 삭제됨)
      const delRes = await fetch(`${SUPABASE_URL}/rest/v1/marketplace_listings?id=eq.${encodeURIComponent(listingId)}`, {
        method: 'DELETE',
        headers: {
          apikey: SUPABASE_SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
        },
      })
      
      if (!delRes.ok) {
        const errText = await delRes.text()
        console.error('❌ 오더 삭제 실패:', delRes.status, errText)
        return { 
          statusCode: 500, 
          body: JSON.stringify({ success: false, message: '오더 삭제 실패', error: errText }), 
          headers: { 'Content-Type': 'application/json' } 
        };
      }
      
      console.log(`[ADMIN] 오더 삭제 완료: ${listingId}`)
      
      return { 
        statusCode: 200, 
        body: JSON.stringify({ 
          success: true, 
          message: '오더가 삭제되었습니다'
        }), 
        headers: { 'Content-Type': 'application/json' } 
      };
    }

    // Estimates list
    if (event.httpMethod === 'GET' && path.startsWith('/estimates')) {
      const qs = (() => {
        const qp = event.queryStringParameters || {}
        const sp = new URLSearchParams()
        for (const [k, v] of Object.entries(qp)) if (v != null) sp.append(k, String(v))
        const s = sp.toString()
        return s ? `?${s}` : ''
      })()
      const sep = qs ? (qs.includes('?') ? '&' : '?') : '?'
      const res = await fetch(`${SUPABASE_URL}/rest/v1/estimates${qs}${sep}select=*`, {
        headers: { apikey: SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}` },
      })
      const json = await res.json()
      return { statusCode: 200, body: JSON.stringify(Array.isArray(json) ? json : []), headers: { 'Content-Type': 'application/json' } };
    }

    // Estimate status update
    if (event.httpMethod === 'PATCH' && path.startsWith('/estimates/') && path.endsWith('/status')) {
      const estimateId = path.split('/')[2]
      const body = JSON.parse(event.body || '{}')
      const status = body.status
      const res = await fetch(`${SUPABASE_URL}/rest/v1/estimates?id=eq.${encodeURIComponent(estimateId)}`, {
        method: 'PATCH',
        headers: {
          apikey: SUPABASE_SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
          'Content-Type': 'application/json',
          Prefer: 'return=representation',
        },
        body: JSON.stringify({ status }),
      })
      if (!res.ok) return { statusCode: 500, body: JSON.stringify({ message: '견적 상태 업데이트 실패' }), headers: { 'Content-Type': 'application/json' } };
      return { statusCode: 200, body: JSON.stringify({ success: true }), headers: { 'Content-Type': 'application/json' } };
    }

    // Market/Call listings
    if (path.startsWith('/market')) {
      const sub = path.replace(/^\/market/, '')
      if (event.httpMethod === 'GET' && (sub === '/listings' || sub.startsWith('/listings'))) {
        const qp = event.queryStringParameters || {}
        const status = qp.status || ''
        let url = `${SUPABASE_URL}/rest/v1/marketplace_listings?select=*`
        if (status && status !== 'all') {
          url += `&status=eq.${encodeURIComponent(status)}`
        }
        const res = await fetch(url, { headers: { apikey: SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}` } })
        const json = await res.json()
        return { statusCode: 200, body: JSON.stringify(Array.isArray(json) ? json : []), headers: { 'Content-Type': 'application/json' } };
      }
    }

    // ─── 헬퍼: Supabase 배치 유저 조회 ─────────────────────────────────
    const sbHeaders = { apikey: SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}` }
    const fetchUsers = async (ids: string[]): Promise<Record<string, any>> => {
      const validIds = ids.filter(Boolean).map(String)
      if (!validIds.length) return {}
      const idList = validIds.map(id => `"${id}"`).join(',')
      const res = await fetch(
        `${SUPABASE_URL}/rest/v1/users?select=id,name,businessname,phonenumber,role&id=in.(${idList})`,
        { headers: sbHeaders }
      )
      const users = await res.json()
      if (!Array.isArray(users) || (users as any)?.code) return {}
      const map: Record<string, any> = {}
      for (const u of users) {
        const key = u?.id != null ? String(u.id) : null
        if (key) map[key] = u
      }
      return map
    }
    const getUserName = (map: Record<string, any>, id: string | null | undefined) => {
      if (!id) return '알 수 없음'
      const u = map[String(id)] || map[id]
      return u ? (u.businessname || u.name || '알 수 없음') : '알 수 없음'
    }

    // 푸시 발송 대상 user id 목록 (PostgREST 페이지네이션)
    // 주의: &eq.role=business 는 잘못된 문법 → 항상 0건 반환됨. role=eq.business 사용.
    const fetchTargetUserIds = async (businessOnly: boolean): Promise<string[]> => {
      const roleFilter = businessOnly ? '&role=eq.business' : ''
      const pageSize = 1000
      const ids: string[] = []
      for (let offset = 0; offset < 20000; offset += pageSize) {
        const url = `${SUPABASE_URL}/rest/v1/users?select=id${roleFilter}&limit=${pageSize}&offset=${offset}`
        const res = await fetch(url, { headers: sbHeaders })
        const body = await res.json()
        if (!res.ok) {
          console.error('[push] users 조회 실패:', res.status, body)
          throw new Error(typeof body?.message === 'string' ? body.message : `users 조회 실패 (${res.status})`)
        }
        if (!Array.isArray(body) || body.length === 0) break
        ids.push(...body.map((u: { id?: string }) => u.id).filter(Boolean) as string[])
        if (body.length < pageSize) break
      }
      return ids
    }

    // Call 오더 목록 (marketplace_listings 테이블)
    if (event.httpMethod === 'GET' && path === '/calls') {
      const listRes = await fetch(
        `${SUPABASE_URL}/rest/v1/marketplace_listings?select=id,title,description,posted_by,claimed_by,claimed_at,budget_amount,status,region,category,createdat,updatedat,media_urls,bid_count&order=createdat.desc&limit=200`,
        { headers: sbHeaders }
      )
      const listings = await listRes.json()
      if (!Array.isArray(listings)) {
        return { statusCode: 200, body: JSON.stringify([]), headers: { 'Content-Type': 'application/json' } }
      }
      const allIds = [...new Set([...listings.map((l: any) => l.posted_by), ...listings.map((l: any) => l.claimed_by)].filter(Boolean))] as string[]
      const usersMap = await fetchUsers(allIds)
      const result = listings.map((l: any) => ({
        ...l,
        owner_business_name: getUserName(usersMap, l.posted_by),
        assigned_business_name: l.claimed_by ? getUserName(usersMap, l.claimed_by) : null,
        created_at: l.createdat,
        updated_at: l.updatedat,
        location: l.region,
      }))
      return { statusCode: 200, body: JSON.stringify(result), headers: { 'Content-Type': 'application/json' } }
    }

    // 오더 프로세스 상세 (낙찰→진행→완료→후기)
    if (event.httpMethod === 'GET' && /^\/listings\/[^/]+\/process$/.test(path)) {
      const listingId = path.split('/')[2]
      const [listingRes, reviewsRes] = await Promise.all([
        fetch(`${SUPABASE_URL}/rest/v1/marketplace_listings?id=eq.${listingId}&select=*&limit=1`, { headers: sbHeaders }),
        fetch(`${SUPABASE_URL}/rest/v1/order_reviews?listing_id=eq.${listingId}&select=id,reviewer_id,reviewee_id,rating,tags,comment,created_at&order=created_at.desc`, { headers: sbHeaders }),
      ])
      const [listingArr, reviews] = await Promise.all([listingRes.json(), reviewsRes.json()])
      const listing = Array.isArray(listingArr) ? listingArr[0] : null
      if (!listing) return { statusCode: 404, body: JSON.stringify({ message: '오더를 찾을 수 없습니다' }), headers: { 'Content-Type': 'application/json' } }

      // 입찰 조회: listing_id로만 필터 (order_bids에는 job_id 컬럼 없음)
      const bidsRes = await fetch(
        `${SUPABASE_URL}/rest/v1/order_bids?listing_id=eq.${listingId}&select=id,bidder_id,bid_amount,estimated_days,message,status,created_at&order=created_at.asc`,
        { headers: sbHeaders }
      )
      const bidsRaw = await bidsRes.json()
      const bids = Array.isArray(bidsRaw) && !(bidsRaw as any)?.code ? bidsRaw : []

      const userIds = [...new Set([
        listing.posted_by, listing.claimed_by,
        ...(Array.isArray(bids) ? bids.map((b: any) => b.bidder_id) : []),
        ...(Array.isArray(reviews) ? reviews.flatMap((r: any) => [r.reviewer_id, r.reviewee_id]) : []),
      ].filter(Boolean))] as string[]
      const usersMap = await fetchUsers(userIds)

      const winnerBid = Array.isArray(bids) && listing.claimed_by
        ? bids.find((b: any) => b.bidder_id === listing.claimed_by) || null
        : null

      return {
        statusCode: 200,
        body: JSON.stringify({
          listing: {
            ...listing,
            owner_name: getUserName(usersMap, listing.posted_by),
            winner_name: listing.claimed_by ? getUserName(usersMap, listing.claimed_by) : null,
            owner_phone: usersMap[listing.posted_by]?.phonenumber || null,
            winner_phone: listing.claimed_by ? (usersMap[listing.claimed_by]?.phonenumber || null) : null,
          },
          bids: Array.isArray(bids) ? bids.map((b: any) => ({ ...b, bidder_name: getUserName(usersMap, b.bidder_id), is_winner: b.bidder_id === listing.claimed_by })) : [],
          winner_bid: winnerBid,
          reviews: Array.isArray(reviews) ? reviews.map((r: any) => ({ ...r, reviewer_name: getUserName(usersMap, r.reviewer_id), reviewee_name: getUserName(usersMap, r.reviewee_id) })) : [],
        }),
        headers: { 'Content-Type': 'application/json' }
      }
    }

    // 오더 상태 변경
    if (event.httpMethod === 'PATCH' && /^\/listings\/[^/]+\/status$/.test(path)) {
      const listingId = path.split('/')[2]
      const body = JSON.parse(event.body || '{}')
      const res = await fetch(`${SUPABASE_URL}/rest/v1/marketplace_listings?id=eq.${listingId}`, {
        method: 'PATCH',
        headers: { ...sbHeaders, 'Content-Type': 'application/json', Prefer: 'return=representation' },
        body: JSON.stringify({ status: body.status, updatedat: new Date().toISOString() }),
      })
      const resText = await res.text()
      if (!res.ok) return { statusCode: 500, body: JSON.stringify({ success: false, error: resText }), headers: { 'Content-Type': 'application/json' } }
      return { statusCode: 200, body: JSON.stringify({ success: true }), headers: { 'Content-Type': 'application/json' } }
    }

    // 게시물 목록 (community_posts)
    if (event.httpMethod === 'GET' && path === '/posts') {
      const res = await fetch(
        `${SUPABASE_URL}/rest/v1/community_posts?select=id,title,content,author_id,created_at,updated_at,likes_count,comments_count,is_active,category&order=created_at.desc&limit=200`,
        { headers: sbHeaders }
      )
      const posts = await res.json()
      if (!Array.isArray(posts)) return { statusCode: 200, body: JSON.stringify([]), headers: { 'Content-Type': 'application/json' } }
      const authorIds = [...new Set(posts.map((p: any) => p.author_id).filter(Boolean))] as string[]
      const usersMap = await fetchUsers(authorIds)
      const result = posts.map((p: any) => ({
        ...p,
        author_name: getUserName(usersMap, p.author_id),
        author_role: usersMap[p.author_id]?.role || 'unknown',
      }))
      return { statusCode: 200, body: JSON.stringify(result), headers: { 'Content-Type': 'application/json' } }
    }

    // 게시물 삭제
    if (event.httpMethod === 'DELETE' && /^\/posts\/[^/]+$/.test(path)) {
      const postId = path.split('/')[2]
      const res = await fetch(`${SUPABASE_URL}/rest/v1/community_posts?id=eq.${postId}`, {
        method: 'DELETE',
        headers: sbHeaders,
      })
      if (!res.ok) {
        const errText = await res.text()
        return { statusCode: 500, body: JSON.stringify({ success: false, error: errText }), headers: { 'Content-Type': 'application/json' } }
      }
      return { statusCode: 200, body: JSON.stringify({ success: true, message: '게시글이 삭제되었습니다' }), headers: { 'Content-Type': 'application/json' } }
    }

    // 채팅방 목록 (createdat/created_at 스키마 호환)
    if (event.httpMethod === 'GET' && path === '/chats') {
      const selectCols = 'id,participant_a,participant_b,status'
      let rooms: any[] = []
      for (const orderCol of ['createdat', 'created_at']) {
        const res = await fetch(
          `${SUPABASE_URL}/rest/v1/chat_rooms?select=${selectCols},${orderCol}&order=${orderCol}.desc&limit=200`,
          { headers: sbHeaders }
        )
        const data = await res.json()
        if (Array.isArray(data) && !(data as any)?.code) {
          rooms = data
          break
        }
      }
      const pIds = [...new Set(rooms.flatMap((r: any) => [r.participant_a, r.participant_b]).filter(Boolean))] as string[]
      const usersMap = await fetchUsers(pIds)
      const result = rooms.map((r: any) => ({
        ...r,
        participant_a_name: getUserName(usersMap, r.participant_a),
        participant_b_name: getUserName(usersMap, r.participant_b),
        participant_a_role: usersMap[String(r.participant_a)]?.role || 'unknown',
        participant_b_role: usersMap[String(r.participant_b)]?.role || 'unknown',
      }))
      return { statusCode: 200, body: JSON.stringify(result), headers: { 'Content-Type': 'application/json' } }
    }

    // 채팅방 메시지 (createdat/created_at 스키마 호환)
    if (event.httpMethod === 'GET' && /^\/chats\/[^/]+\/messages$/.test(path)) {
      const roomId = path.split('/')[2]
      let messages: any[] = []
      for (const orderCol of ['created_at', 'createdat']) {
        const res = await fetch(
          `${SUPABASE_URL}/rest/v1/chat_messages?room_id=eq.${roomId}&select=id,sender_id,content,image_url,video_url,${orderCol},message_type&order=${orderCol}.asc&limit=100`,
          { headers: sbHeaders }
        )
        const data = await res.json()
        if (Array.isArray(data) && !(data as any)?.code) {
          messages = data
          break
        }
      }
      const senderIds = [...new Set(messages.map((m: any) => m.sender_id).filter(Boolean))] as string[]
      const usersMap = await fetchUsers(senderIds)
      const result = messages.map((m: any) => ({ ...m, sender_name: getUserName(usersMap, m.sender_id) }))
      return { statusCode: 200, body: JSON.stringify(result), headers: { 'Content-Type': 'application/json' } }
    }

    // 채팅방 삭제
    if (event.httpMethod === 'DELETE' && /^\/chats\/[^/]+$/.test(path)) {
      const roomId = path.split('/')[2]
      // 메시지 먼저 삭제
      await fetch(`${SUPABASE_URL}/rest/v1/chat_messages?room_id=eq.${roomId}`, { method: 'DELETE', headers: sbHeaders })
      // 채팅방 삭제
      const res = await fetch(`${SUPABASE_URL}/rest/v1/chat_rooms?id=eq.${roomId}`, { method: 'DELETE', headers: sbHeaders })
      if (!res.ok) {
        const errText = await res.text()
        return { statusCode: 500, body: JSON.stringify({ success: false, error: errText }), headers: { 'Content-Type': 'application/json' } }
      }
      return { statusCode: 200, body: JSON.stringify({ success: true, message: '채팅방이 삭제되었습니다' }), headers: { 'Content-Type': 'application/json' } }
    }

    // Ads endpoints via Supabase
    if (path.startsWith('/ads')) {
      const sub = path.replace(/^\/ads/, '')
      if (event.httpMethod === 'GET' && (sub === '' || sub === '/')) {
        const res = await fetch(`${SUPABASE_URL}/rest/v1/ads?select=*`, { headers: { apikey: SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}` } })
        const json = await res.json()
        return { statusCode: 200, body: JSON.stringify(Array.isArray(json) ? json : []), headers: { 'Content-Type': 'application/json' } };
      }
      if (event.httpMethod === 'POST' && (sub === '' || sub === '/')) {
        const payload = JSON.parse(event.body || '{}')
        payload.createdat = new Date().toISOString()
        payload.updatedat = new Date().toISOString()
        const res = await fetch(`${SUPABASE_URL}/rest/v1/ads`, {
          method: 'POST',
          headers: {
            apikey: SUPABASE_SERVICE_ROLE_KEY,
            Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
            'Content-Type': 'application/json',
            Prefer: 'return=representation',  // Supabase가 생성된 row를 JSON으로 반환하도록 요청
          },
          body: JSON.stringify(payload),
        })
        const resText = await res.text()
        if (!res.ok) {
          console.error('[ads POST] Supabase error:', res.status, resText)
          return { statusCode: 500, body: JSON.stringify({ message: '광고 생성 실패', error: resText }), headers: { 'Content-Type': 'application/json' } };
        }
        // 빈 응답 방어 처리
        const created = resText ? JSON.parse(resText) : []
        return { statusCode: 201, body: JSON.stringify(Array.isArray(created) ? (created[0] ?? {}) : created), headers: { 'Content-Type': 'application/json' } };
      }
      if (event.httpMethod === 'PUT' && /^\/(.+)/.test(sub)) {
        const id = sub.slice(1)
        const payload = JSON.parse(event.body || '{}')
        payload.updatedat = new Date().toISOString()
        const res = await fetch(`${SUPABASE_URL}/rest/v1/ads?id=eq.${encodeURIComponent(id)}`, {
          method: 'PATCH',
          headers: {
            apikey: SUPABASE_SERVICE_ROLE_KEY,
            Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
            'Content-Type': 'application/json',
            Prefer: 'return=representation',
          },
          body: JSON.stringify(payload),
        })
        const resText = await res.text()
        if (!res.ok) {
          console.error('[ads PUT] Supabase error:', res.status, resText)
          return { statusCode: 500, body: JSON.stringify({ message: '광고 업데이트 실패', error: resText }), headers: { 'Content-Type': 'application/json' } };
        }
        const updated = resText ? JSON.parse(resText) : []
        return { statusCode: 200, body: JSON.stringify(Array.isArray(updated) ? (updated[0] ?? {}) : updated), headers: { 'Content-Type': 'application/json' } };
      }
      if (event.httpMethod === 'DELETE' && /^\/(.+)/.test(sub)) {
        const id = sub.slice(1)
        const res = await fetch(`${SUPABASE_URL}/rest/v1/ads?id=eq.${encodeURIComponent(id)}`, {
          method: 'DELETE',
          headers: { apikey: SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}` },
        })
        if (!res.ok) {
          const errText = await res.text()
          console.error('[ads DELETE] Supabase error:', res.status, errText)
          return { statusCode: 500, body: JSON.stringify({ message: '광고 삭제 실패', error: errText }), headers: { 'Content-Type': 'application/json' } };
        }
        return { statusCode: 200, body: JSON.stringify({ success: true }), headers: { 'Content-Type': 'application/json' } };
      }
    }

    // ─── 공지 배너 CRUD ─────────────────────────────────────────────────
    if (path.startsWith('/announcements')) {
      const sub = path.replace(/^\/announcements/, '')

      // 전체 조회 (관리자)
      if (event.httpMethod === 'GET' && (sub === '' || sub === '/')) {
        const res = await fetch(
          `${SUPABASE_URL}/rest/v1/announcements?select=*&order=sort_order.asc,createdat.desc`,
          { headers: sbHeaders }
        )
        const json = await res.json()
        return { statusCode: 200, body: JSON.stringify(Array.isArray(json) ? json : []), headers: { 'Content-Type': 'application/json' } }
      }

      // 앱용 활성 공지 조회 (현재 시간 기준 유효한 것만)
      if (event.httpMethod === 'GET' && sub === '/active') {
        const now = new Date().toISOString()
        const url = `${SUPABASE_URL}/rest/v1/announcements?is_active=eq.true&or=(start_at.is.null,start_at.lte.${now})&or=(end_at.is.null,end_at.gte.${now})&order=sort_order.asc&limit=5`
        const res = await fetch(url, { headers: sbHeaders })
        const json = await res.json()
        return { statusCode: 200, body: JSON.stringify(Array.isArray(json) ? json : []), headers: { 'Content-Type': 'application/json' } }
      }

      // 생성
      if (event.httpMethod === 'POST' && (sub === '' || sub === '/')) {
        const payload = JSON.parse(event.body || '{}')
        payload.createdat = new Date().toISOString()
        payload.updatedat = new Date().toISOString()
        const res = await fetch(`${SUPABASE_URL}/rest/v1/announcements`, {
          method: 'POST',
          headers: { ...sbHeaders, 'Content-Type': 'application/json', Prefer: 'return=representation' },
          body: JSON.stringify(payload),
        })
        const resText = await res.text()
        if (!res.ok) return { statusCode: 500, body: JSON.stringify({ message: '공지 생성 실패', error: resText }), headers: { 'Content-Type': 'application/json' } }
        const created = resText ? JSON.parse(resText) : []
        return { statusCode: 201, body: JSON.stringify(Array.isArray(created) ? (created[0] ?? {}) : created), headers: { 'Content-Type': 'application/json' } }
      }

      // 수정
      if (event.httpMethod === 'PUT' && /^\/[^/]+$/.test(sub)) {
        const id = sub.slice(1)
        const payload = JSON.parse(event.body || '{}')
        payload.updatedat = new Date().toISOString()
        const res = await fetch(`${SUPABASE_URL}/rest/v1/announcements?id=eq.${id}`, {
          method: 'PATCH',
          headers: { ...sbHeaders, 'Content-Type': 'application/json', Prefer: 'return=representation' },
          body: JSON.stringify(payload),
        })
        const resText = await res.text()
        if (!res.ok) return { statusCode: 500, body: JSON.stringify({ message: '공지 수정 실패', error: resText }), headers: { 'Content-Type': 'application/json' } }
        return { statusCode: 200, body: JSON.stringify({ success: true }), headers: { 'Content-Type': 'application/json' } }
      }

      // 삭제
      if (event.httpMethod === 'DELETE' && /^\/[^/]+$/.test(sub)) {
        const id = sub.slice(1)
        const res = await fetch(`${SUPABASE_URL}/rest/v1/announcements?id=eq.${id}`, {
          method: 'DELETE',
          headers: sbHeaders,
        })
        if (!res.ok) {
          const errText = await res.text()
          return { statusCode: 500, body: JSON.stringify({ message: '공지 삭제 실패', error: errText }), headers: { 'Content-Type': 'application/json' } }
        }
        return { statusCode: 200, body: JSON.stringify({ success: true }), headers: { 'Content-Type': 'application/json' } }
      }
    }

    // ─── 웹 견적 요청 관리 ─────────────────────────────────────────────

    // DELETE /web-orders/:id - 웹 견적 삭제
    if (event.httpMethod === 'DELETE' && /^\/web-orders\/[^/]+$/.test(path)) {
      const orderId = path.split('/')[2]
      // estimates 먼저 삭제
      await fetch(`${SUPABASE_URL}/rest/v1/estimates?orderId=eq.${encodeURIComponent(orderId)}`, {
        method: 'DELETE', headers: sbHeaders,
      })
      // order 삭제
      const delRes = await fetch(`${SUPABASE_URL}/rest/v1/orders?id=eq.${encodeURIComponent(orderId)}`, {
        method: 'DELETE', headers: sbHeaders,
      })
      if (!delRes.ok) {
        const errText = await delRes.text()
        return { statusCode: 500, body: JSON.stringify({ success: false, error: errText }), headers: { 'Content-Type': 'application/json' } }
      }
      return { statusCode: 200, body: JSON.stringify({ success: true, message: '삭제되었습니다' }), headers: { 'Content-Type': 'application/json' } }
    }

    // DELETE /web-orders (bulk) - 여러 견적 일괄 삭제
    if (event.httpMethod === 'DELETE' && path === '/web-orders') {
      const body = JSON.parse(event.body || '{}')
      const ids: string[] = Array.isArray(body.ids) ? body.ids : []
      if (!ids.length) return { statusCode: 400, body: JSON.stringify({ error: 'ids 배열이 필요합니다' }), headers: { 'Content-Type': 'application/json' } }
      const idList = ids.map((id: string) => `"${id}"`).join(',')
      await fetch(`${SUPABASE_URL}/rest/v1/estimates?orderId=in.(${idList})`, { method: 'DELETE', headers: sbHeaders })
      await fetch(`${SUPABASE_URL}/rest/v1/orders?id=in.(${idList})`, { method: 'DELETE', headers: sbHeaders })
      return { statusCode: 200, body: JSON.stringify({ success: true, message: `${ids.length}건 삭제되었습니다` }), headers: { 'Content-Type': 'application/json' } }
    }

    // GET /web-orders - 웹에서 접수된 익명 견적 목록
    if (event.httpMethod === 'GET' && path === '/web-orders') {
      const qp = event.queryStringParameters || {}
      const status = qp.status || ''
      // orders 전체 조회 후 JS에서 isAnonymous 필터 (camelCase 컬럼명 호환성)
      let url = `${SUPABASE_URL}/rest/v1/orders?select=*&order=createdAt.desc&limit=500`
      const res = await fetch(url, { headers: sbHeaders })
      const all = await res.json()
      if (!Array.isArray(all)) {
        return { statusCode: 200, body: JSON.stringify([]), headers: { 'Content-Type': 'application/json' } }
      }
      let orders = all.filter((o: any) => o.isAnonymous === true || o['isAnonymous'] === true)
      if (status && status !== 'all') {
        orders = orders.filter((o: any) => o.status === status)
      }
      return { statusCode: 200, body: JSON.stringify(orders), headers: { 'Content-Type': 'application/json' } }
    }

    // GET /web-orders/businesses - 매칭 가능한 승인된 사업자 목록
    if (event.httpMethod === 'GET' && path === '/web-orders/businesses') {
      const qp = event.queryStringParameters || {}
      const q = (qp.q || '').trim()
      const category = (qp.category || '').trim()
      let url = `${SUPABASE_URL}/rest/v1/users?select=id,name,businessname,phonenumber,email,category,region,businessstatus,projects_awarded_count,estimates_created_count&role=eq.business&businessstatus=eq.approved&limit=200`
      if (q) {
        const like = encodeURIComponent(`%${q}%`)
        url = `${SUPABASE_URL}/rest/v1/users?select=id,name,businessname,phonenumber,email,category,region,businessstatus,projects_awarded_count,estimates_created_count&role=eq.business&businessstatus=eq.approved&or=(businessname.ilike.${like},name.ilike.${like},phonenumber.ilike.${like})&limit=200`
      }
      const res = await fetch(url, { headers: sbHeaders })
      let businesses = await res.json()
      if (!Array.isArray(businesses)) businesses = []
      if (category) {
        businesses = businesses.filter((b: any) => (b.category || '').includes(category))
      }
      return { statusCode: 200, body: JSON.stringify(businesses), headers: { 'Content-Type': 'application/json' } }
    }

    // POST /web-orders/:id/match - 웹 견적을 사업자에게 매칭
    if (event.httpMethod === 'POST' && /^\/web-orders\/[^/]+\/match$/.test(path)) {
      const orderId = path.split('/')[2]
      const body = JSON.parse(event.body || '{}')
      const { businessId, businessName, amount, notes } = body

      if (!orderId || !businessId) {
        return { statusCode: 400, body: JSON.stringify({ message: '오더 ID와 사업자 ID가 필요합니다' }), headers: { 'Content-Type': 'application/json' } }
      }

      // 1. orders 조회
      const orderRes = await fetch(`${SUPABASE_URL}/rest/v1/orders?id=eq.${encodeURIComponent(orderId)}&select=*&limit=1`, { headers: sbHeaders })
      const orderArr = await orderRes.json()
      const order = Array.isArray(orderArr) ? orderArr[0] : null
      if (!order) {
        return { statusCode: 404, body: JSON.stringify({ message: '견적 요청을 찾을 수 없습니다' }), headers: { 'Content-Type': 'application/json' } }
      }

      // 2. jobs 테이블에 공사 생성
      const now = new Date().toISOString()
      const jobPayload: any = {
        title: order.title || '웹 견적 요청',
        description: `[웹 견적] ${order.description || ''}\n고객명: ${order.customerName || ''}\n연락처: ${order.customerPhone || ''}\n주소: ${order.address || ''}`,
        owner_business_id: businessId,
        assigned_business_id: businessId,
        status: 'assigned',
        location: order.address || '',
        category: order.category || '',
        urgency: 'normal',
        budget_amount: amount || order.estimatedPrice || 0,
        awarded_amount: amount || order.estimatedPrice || 0,
        commission_rate: 5,
        created_at: now,
        updated_at: now,
      }
      if (notes) jobPayload.web_order_id = orderId  // web_order_id 컬럼이 있으면 설정

      const jobRes = await fetch(`${SUPABASE_URL}/rest/v1/jobs`, {
        method: 'POST',
        headers: { ...sbHeaders, 'Content-Type': 'application/json', Prefer: 'return=representation' },
        body: JSON.stringify(jobPayload),
      })
      const jobText = await jobRes.text()
      let jobData: any = null
      try { jobData = JSON.parse(jobText); if (Array.isArray(jobData)) jobData = jobData[0] } catch {}

      // web_order_id 컬럼이 없어 실패한 경우 컬럼 제외 후 재시도
      if (!jobRes.ok && jobText.includes('web_order_id')) {
        delete jobPayload.web_order_id
        const retryRes = await fetch(`${SUPABASE_URL}/rest/v1/jobs`, {
          method: 'POST',
          headers: { ...sbHeaders, 'Content-Type': 'application/json', Prefer: 'return=representation' },
          body: JSON.stringify(jobPayload),
        })
        const retryText = await retryRes.text()
        if (!retryRes.ok) {
          console.error('[web-orders match] job 생성 실패:', retryText)
          return { statusCode: 500, body: JSON.stringify({ message: 'job 생성 실패', error: retryText }), headers: { 'Content-Type': 'application/json' } }
        }
        try { jobData = JSON.parse(retryText); if (Array.isArray(jobData)) jobData = jobData[0] } catch {}
      } else if (!jobRes.ok) {
        console.error('[web-orders match] job 생성 실패:', jobText)
        return { statusCode: 500, body: JSON.stringify({ message: 'job 생성 실패', error: jobText }), headers: { 'Content-Type': 'application/json' } }
      }

      const jobId = jobData?.id || null

      // 3. orders 업데이트: 낙찰 처리
      const orderUpdate: any = {
        isAwarded: true,
        awardedAt: now,
        technicianId: businessId,
        status: 'in_progress',
      }
      if (jobId) orderUpdate.matchedJobId = jobId
      if (notes) orderUpdate.adminNotes = notes

      await fetch(`${SUPABASE_URL}/rest/v1/orders?id=eq.${encodeURIComponent(orderId)}`, {
        method: 'PATCH',
        headers: { ...sbHeaders, 'Content-Type': 'application/json', Prefer: 'return=minimal' },
        body: JSON.stringify(orderUpdate),
      })

      // 4. 사업자에게 알림
      try {
        await fetch(`${SUPABASE_URL}/rest/v1/notifications`, {
          method: 'POST',
          headers: { ...sbHeaders, 'Content-Type': 'application/json', Prefer: 'return=minimal' },
          body: JSON.stringify({
            userid: businessId,
            title: '새 공사가 배정되었습니다',
            body: `[${order.title || '웹 견적 요청'}] 관리자가 공사를 배정했습니다. 내 공사 관리에서 확인하세요.`,
            type: 'web_order_matched',
            jobid: jobId,
            isread: false,
            createdat: now,
          }),
        })
      } catch (notifErr) {
        console.warn('[web-orders match] 알림 전송 실패 (무시):', notifErr)
      }

      return {
        statusCode: 200,
        body: JSON.stringify({ success: true, jobId, message: `${businessName || '사업자'}에게 매칭 완료` }),
        headers: { 'Content-Type': 'application/json' }
      }
    }

    // POST /web-orders/:id/rate - 평점 입력
    if (event.httpMethod === 'POST' && /^\/web-orders\/[^/]+\/rate$/.test(path)) {
      const orderId = path.split('/')[2]
      const body = JSON.parse(event.body || '{}')
      const { rating, comment } = body

      if (!rating || rating < 1 || rating > 5) {
        return { statusCode: 400, body: JSON.stringify({ message: '평점은 1~5 사이여야 합니다' }), headers: { 'Content-Type': 'application/json' } }
      }

      // orders 에서 technicianId 조회
      const orderRes = await fetch(`${SUPABASE_URL}/rest/v1/orders?id=eq.${encodeURIComponent(orderId)}&select=technicianId,title&limit=1`, { headers: sbHeaders })
      const orderArr = await orderRes.json()
      const order = Array.isArray(orderArr) ? orderArr[0] : null

      const now = new Date().toISOString()

      // orders 에 평점 저장
      await fetch(`${SUPABASE_URL}/rest/v1/orders?id=eq.${encodeURIComponent(orderId)}`, {
        method: 'PATCH',
        headers: { ...sbHeaders, 'Content-Type': 'application/json', Prefer: 'return=minimal' },
        body: JSON.stringify({ adminRating: rating, adminRatingComment: comment || '', adminRatedAt: now, status: 'completed' }),
      })

      // 평점은 order_reviews 로 통합 저장한다 (앱 B2B 평점과 같은 원천).
      const businessId = order?.technicianId || order?.technicianid
      if (businessId) {
        try {
          await fetch(`${SUPABASE_URL}/rest/v1/order_reviews?on_conflict=order_id`, {
            method: 'POST',
            headers: { ...sbHeaders, 'Content-Type': 'application/json', Prefer: 'return=minimal,resolution=merge-duplicates' },
            body: JSON.stringify({
              reviewee_id: businessId,
              order_id: orderId,
              rating,
              comment: comment || '',
              is_admin_review: true,
              created_at: now,
              updated_at: now,
            }),
          })
        } catch (reviewErr) {
          console.warn('[web-orders rate] order_reviews 저장 실패 (무시):', reviewErr)
        }
      }

      return {
        statusCode: 200,
        body: JSON.stringify({ success: true, message: '평점이 저장되었습니다' }),
        headers: { 'Content-Type': 'application/json' }
      }
    }

    // ── 웹 콘텐츠 관리 (web_settings / web_ads) ─────────────────────
    if (path.startsWith('/web-content')) {
      const sub = path.replace(/^\/web-content/, '')

      // GET /web-content/settings
      if (event.httpMethod === 'GET' && sub === '/settings') {
        const res = await fetch(`${SUPABASE_URL}/rest/v1/web_settings?select=key,value`, { headers: sbHeaders })
        const json = await res.json()
        return { statusCode: 200, body: JSON.stringify(Array.isArray(json) ? json : []), headers: { 'Content-Type': 'application/json' } }
      }

      // POST /web-content/settings (bulk upsert)
      if (event.httpMethod === 'POST' && sub === '/settings') {
        const { settings } = JSON.parse(event.body || '{}')
        if (!Array.isArray(settings)) return { statusCode: 400, body: JSON.stringify({ error: 'settings array required' }), headers: { 'Content-Type': 'application/json' } }
        const rows = settings.map((s: { key: string; value: string }) => ({ ...s, updated_at: new Date().toISOString() }))
        await fetch(`${SUPABASE_URL}/rest/v1/web_settings`, {
          method: 'POST',
          headers: { ...sbHeaders, 'Content-Type': 'application/json', Prefer: 'resolution=merge-duplicates,return=minimal' },
          body: JSON.stringify(rows),
        })
        return { statusCode: 200, body: JSON.stringify({ success: true }), headers: { 'Content-Type': 'application/json' } }
      }

      // GET /web-content/ads  (모든 광고, 비활성 포함)
      if (event.httpMethod === 'GET' && (sub === '/ads' || sub === '/ads/')) {
        const res = await fetch(`${SUPABASE_URL}/rest/v1/web_ads?select=*&order=sort_order.asc,created_at.desc`, { headers: sbHeaders })
        const json = await res.json()
        return { statusCode: 200, body: JSON.stringify(Array.isArray(json) ? json : []), headers: { 'Content-Type': 'application/json' } }
      }

      // GET /web-content/ads/:id
      if (event.httpMethod === 'GET' && sub.match(/^\/ads\/[^/]+$/)) {
        const id = sub.split('/').pop()
        const res = await fetch(`${SUPABASE_URL}/rest/v1/web_ads?id=eq.${id}&select=*&limit=1`, { headers: sbHeaders })
        const json = await res.json()
        const ad = Array.isArray(json) ? json[0] : null
        if (!ad) return { statusCode: 404, body: JSON.stringify({ error: 'Not found' }), headers: { 'Content-Type': 'application/json' } }
        return { statusCode: 200, body: JSON.stringify({ ad }), headers: { 'Content-Type': 'application/json' } }
      }

      // POST /web-content/ads (create or update)
      if (event.httpMethod === 'POST' && (sub === '/ads' || sub === '/ads/')) {
        const payload = JSON.parse(event.body || '{}')
        payload.updated_at = new Date().toISOString()
        if (!payload.id) payload.created_at = payload.updated_at
        const res = await fetch(`${SUPABASE_URL}/rest/v1/web_ads`, {
          method: 'POST',
          headers: { ...sbHeaders, 'Content-Type': 'application/json', Prefer: 'resolution=merge-duplicates,return=representation' },
          body: JSON.stringify(payload),
        })
        const json = await res.json()
        return { statusCode: 200, body: JSON.stringify(json), headers: { 'Content-Type': 'application/json' } }
      }

      // DELETE /web-content/ads/:id
      if (event.httpMethod === 'DELETE' && sub.match(/^\/ads\/[^/]+$/)) {
        const id = sub.split('/').pop()
        await fetch(`${SUPABASE_URL}/rest/v1/web_ads?id=eq.${id}`, { method: 'DELETE', headers: sbHeaders })
        return { statusCode: 200, body: JSON.stringify({ success: true }), headers: { 'Content-Type': 'application/json' } }
      }
    }

    // ── 푸시 알림 발송 ──────────────────────────────────────────────
    if (path.startsWith('/push-notifications')) {
      const sub = path.replace(/^\/push-notifications/, '')

      // GET /push-notifications/users?q=검색어 – 사업자 목록 (발송 대상 선택용)
      if (event.httpMethod === 'GET' && sub.startsWith('/users')) {
        const q = event.queryStringParameters?.q || ''
        let url = `${SUPABASE_URL}/rest/v1/users?select=id,name,businessname&role=eq.business&order=businessname.asc&limit=50`
        if (q) url += `&or=(name.ilike.*${encodeURIComponent(q)}*,businessname.ilike.*${encodeURIComponent(q)}*)`
        const res = await fetch(url, { headers: sbHeaders })
        const json = await res.json()
        return { statusCode: 200, body: JSON.stringify(Array.isArray(json) ? json : []), headers: { 'Content-Type': 'application/json' } }
      }

      // POST /push-notifications/send
      // notificationType: 알림 type (기본 'admin_announcement'). 'app_update'로 보내면
      //   앱에서 탭 시 스토어로 바로 이동하는 업데이트 안내 알림이 됩니다.
      // allUserRoles: true면 역할(사업자/소비자) 구분 없이 전체 사용자 대상 (기본은 사업자만)
      if (event.httpMethod === 'POST' && sub === '/send') {
        const {
          title,
          body: msgBody,
          targetAll,
          userIds: targetIds,
          notificationType,
          allUserRoles,
        } = JSON.parse(event.body || '{}')
        if (!title || !msgBody) return { statusCode: 400, body: JSON.stringify({ error: 'title, body 필수' }), headers: { 'Content-Type': 'application/json' } }
        if (title.length > 30 || msgBody.length > 30) return { statusCode: 400, body: JSON.stringify({ error: '텍스트는 30자 이하' }), headers: { 'Content-Type': 'application/json' } }

        // 대상 user ID 목록 결정
        let userIds: string[] = []
        if (targetAll) {
          try {
            userIds = await fetchTargetUserIds(!allUserRoles)
          } catch (e: any) {
            return { statusCode: 500, body: JSON.stringify({ error: e.message || '발송 대상 조회 실패' }), headers: { 'Content-Type': 'application/json' } }
          }
        } else {
          userIds = Array.isArray(targetIds) ? targetIds : []
        }
        if (userIds.length === 0) return { statusCode: 400, body: JSON.stringify({ error: '발송 대상 없음' }), headers: { 'Content-Type': 'application/json' } }

        // notifications-send-bulk 함수 호출 (같은 Netlify 배포)
        const baseUrl = process.env.URL || 'https://allsuri.app'
        const bulkRes = await fetch(`${baseUrl}/.netlify/functions/notifications-send-bulk`, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${ADMIN_TOKEN}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ userIds, title, body: msgBody, data: { type: notificationType || 'admin_announcement' } }),
        })
        const bulkJson = await bulkRes.json()
        return { statusCode: 200, body: JSON.stringify({ success: true, ...bulkJson }), headers: { 'Content-Type': 'application/json' } }
      }
    }

    // ── 추천 업체 관리 ──────────────────────────────────────────────
    if (path.startsWith('/featured-businesses')) {
      const sub = path.replace(/^\/featured-businesses/, '')

      // GET /featured-businesses – 추천 업체 목록 (기존 fetchUsers 헬퍼 사용)
      if (event.httpMethod === 'GET' && (sub === '' || sub === '/')) {
        const featRes = await fetch(
          `${SUPABASE_URL}/rest/v1/web_featured_businesses?select=id,sort_order,user_id&order=sort_order.asc`,
          { headers: sbHeaders }
        )
        if (!featRes.ok) return { statusCode: 200, body: JSON.stringify([]), headers: { 'Content-Type': 'application/json' } }
        const featured = await featRes.json() as { id: string; user_id: string; sort_order: number }[]
        if (!Array.isArray(featured) || featured.length === 0) return { statusCode: 200, body: JSON.stringify([]), headers: { 'Content-Type': 'application/json' } }
        const ids = featured.map(f => f.user_id).filter(Boolean)
        // 기존 fetchUsers 헬퍼 사용 (ID 포맷 이슈 방지)
        const usersMap = await fetchUsers(ids)
        const result = featured.map(f => ({
          id: f.id,
          sort_order: f.sort_order,
          user_id: f.user_id,
          users: usersMap[f.user_id] || null,
        }))
        return { statusCode: 200, body: JSON.stringify(result), headers: { 'Content-Type': 'application/json' } }
      }

      // POST /featured-businesses – 추천 업체 추가
      if (event.httpMethod === 'POST' && (sub === '' || sub === '/')) {
        const { userId, sortOrder } = JSON.parse(event.body || '{}')
        if (!userId) return { statusCode: 400, body: JSON.stringify({ error: 'userId 필수' }), headers: { 'Content-Type': 'application/json' } }
        const res = await fetch(`${SUPABASE_URL}/rest/v1/web_featured_businesses`, {
          method: 'POST',
          headers: { ...sbHeaders, 'Content-Type': 'application/json', Prefer: 'resolution=merge-duplicates,return=representation' },
          body: JSON.stringify({ user_id: userId, sort_order: sortOrder ?? 0 }),
        })
        const json = await res.json()
        return { statusCode: 200, body: JSON.stringify(json), headers: { 'Content-Type': 'application/json' } }
      }

      // DELETE /featured-businesses/:id
      if (event.httpMethod === 'DELETE' && sub.match(/^\/[^/]+$/)) {
        const id = sub.slice(1)
        await fetch(`${SUPABASE_URL}/rest/v1/web_featured_businesses?id=eq.${id}`, { method: 'DELETE', headers: sbHeaders })
        return { statusCode: 200, body: JSON.stringify({ success: true }), headers: { 'Content-Type': 'application/json' } }
      }

      // GET /featured-businesses/public – 웹사이트용 (평점 포함 공개 데이터)
      if (event.httpMethod === 'GET' && sub === '/public') {
        const featRes = await fetch(
          `${SUPABASE_URL}/rest/v1/web_featured_businesses?select=id,sort_order,user_id&order=sort_order.asc`,
          { headers: sbHeaders }
        )
        if (!featRes.ok) return { statusCode: 200, body: JSON.stringify([]), headers: { 'Content-Type': 'application/json' } }
        const featured = await featRes.json() as { id: string; user_id: string }[]
        if (!Array.isArray(featured) || featured.length === 0) return { statusCode: 200, body: JSON.stringify([]), headers: { 'Content-Type': 'application/json' } }
        const ids = featured.map(f => f.user_id).filter(Boolean)
        // fetchUsers 헬퍼 사용 (ID 따옴표 포맷 통일)
        const usersMap = await fetchUsers(ids)
        // 평점 조회
        const idList = ids.map(id => `"${id}"`).join(',')
        const reviewsRes = await fetch(
          `${SUPABASE_URL}/rest/v1/business_reviews?select=business_id,rating&business_id=in.(${idList})`,
          { headers: sbHeaders }
        )
        const reviews = reviewsRes.ok ? await reviewsRes.json() as { business_id: string; rating: number }[] : []
        const ratingMap: Record<string, { sum: number; count: number }> = {}
        if (Array.isArray(reviews)) {
          for (const r of reviews) {
            if (!ratingMap[r.business_id]) ratingMap[r.business_id] = { sum: 0, count: 0 }
            ratingMap[r.business_id].sum += r.rating
            ratingMap[r.business_id].count += 1
          }
        }
        const result = featured.map(f => {
          const u = usersMap[f.user_id]
          if (!u) return null
          const rm = ratingMap[f.user_id]
          return {
            id: f.id, userId: u.id,
            businessName: u.businessname || u.name || '',
            phonenumber: u.phonenumber || '',
            category: u.category || '',
            region: u.region || '',
            avatarUrl: u.avatar_url || null,
            jobsCount: u.jobs_accepted_count || 0,
            avgRating: rm ? Math.round((rm.sum / rm.count) * 10) / 10 : null,
            reviewCount: rm?.count || 0,
          }
        }).filter(Boolean)
        return { statusCode: 200, body: JSON.stringify(result), headers: { 'Content-Type': 'application/json' } }
      }
    }

    return { statusCode: 404, body: JSON.stringify({ message: 'Not Found' }), headers: { 'Content-Type': 'application/json' } };
  } catch (e: any) {
    return { statusCode: 500, body: JSON.stringify({ message: 'Admin function error', error: String(e) }), headers: { 'Content-Type': 'application/json' } };
  }
}
