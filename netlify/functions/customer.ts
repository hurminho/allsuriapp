/// <reference types="node" />
// Netlify function: 웹 비로그인 고객용 API
// 4자리 PIN으로 본인 확인 후 견적 요청 조회/낙찰/완료/평점 처리

import { customerOrderUrl, formatPhoneDisplay, sendSms, smsBidAwarded, smsWorkDoneReview } from '../lib/solapi_sms'

const SUPABASE_URL = process.env.SUPABASE_URL as string
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY as string
const ADMIN_TOKEN = process.env.ADMIN_TOKEN || process.env.ADMIN_DEVELOPER_TOKEN || 'devtoken'

const sbHeaders = {
  apikey: SUPABASE_SERVICE_ROLE_KEY,
  Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
  'Content-Type': 'application/json',
}

const JSON_HEADERS = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, x-order-password, x-customer-phone',
}

function ok(data: any, status = 200) {
  return { statusCode: status, body: JSON.stringify(data), headers: JSON_HEADERS }
}
function err(msg: string, status = 400) {
  return { statusCode: status, body: JSON.stringify({ error: msg }), headers: JSON_HEADERS }
}

/// Supabase JWT를 검증해 호출자 user id를 돌려줍니다. 실패하면 null.
/// 서버 간 호출(allsuri-web 등)은 service_role 키를 허용하고 'service_role'을 반환합니다.
async function authenticatedUserId(event: any): Promise<string | null> {
  const headers = event.headers || {}
  const raw = headers.authorization || headers.Authorization || ''
  const token = String(raw).replace(/^Bearer\s+/i, '').trim()
  if (!token) return null
  if (SUPABASE_SERVICE_ROLE_KEY && token === SUPABASE_SERVICE_ROLE_KEY) return 'service_role'

  const res = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${token}` },
  })
  if (!res.ok) {
    console.warn('[customer] JWT 검증 실패:', res.status)
    return null
  }
  const user = (await res.json().catch(() => null)) as any
  return user?.id ? String(user.id) : null
}

/// orderId(웹 오더)에 배정된 사업자가 callerId인지 확인합니다.
async function isAssignedBusiness(orderId: string, callerId: string): Promise<boolean> {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/jobs?web_order_id=eq.${encodeURIComponent(orderId)}&assigned_business_id=eq.${encodeURIComponent(callerId)}&select=id&limit=1`,
    { headers: sbHeaders }
  )
  if (!res.ok) return false
  const rows = (await res.json().catch(() => [])) as any
  return Array.isArray(rows) && rows.length > 0
}

// 알림 DB 저장 (FCM은 INSERT Webhook이 자동 발송)
async function insertNotification(userId: string, title: string, body: string, type: string, jobId?: string) {
  try {
    await fetch(`${SUPABASE_URL}/rest/v1/notifications`, {
      method: 'POST',
      headers: { ...sbHeaders, Prefer: 'return=minimal' },
      body: JSON.stringify({
        userid: userId, title, body, type,
        jobid: jobId || null,
        isread: false,
        createdat: new Date().toISOString(),
      }),
    })
  } catch (e: any) {
    console.warn('[customer] 알림 DB 저장 실패 (무시):', e.message)
  }
}

// 비밀번호로 주문 인증 (phone + webPassword)
async function verifyOrder(orderId: string, phone: string, password: string): Promise<any | null> {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/orders?id=eq.${encodeURIComponent(orderId)}&select=*&limit=1`,
    { headers: sbHeaders }
  )
  const arr = await res.json()
  const order = Array.isArray(arr) ? arr[0] : null
  if (!order) return null
  const storedPhone = order.customerPhone || order.customerphone || ''
  const storedPwd = order.webPassword || order.webpassword || ''
  const normalizePhone = (p: string) => p.replace(/[^0-9]/g, '')
  if (normalizePhone(storedPhone) !== normalizePhone(phone)) return null
  if (storedPwd !== password) return null
  return order
}

export const handler = async (event: any) => {
  if (event.httpMethod === 'OPTIONS') {
    return { statusCode: 204, headers: JSON_HEADERS, body: '' }
  }

  try {
    const rawPath = event.path || '/'
    const path = rawPath
      .replace(/^\/\.netlify\/functions\/customer/, '')
      .replace(/^\/api\/customer/, '')
      || '/'

    const qp = event.queryStringParameters || {}

    // ─────────────────────────────────────────────────────────────
    // POST /verify  - phone + webPassword → 주문 목록 반환
    // ─────────────────────────────────────────────────────────────
    if (event.httpMethod === 'POST' && path === '/verify') {
      const body = JSON.parse(event.body || '{}')
      const phone: string = (body.phone || '').replace(/[^0-9]/g, '')
      const password: string = String(body.password || '').trim()

      if (!phone || !password) return err('전화번호와 비밀번호를 입력해 주세요.')

      // 모든 orders 에서 phone + password 조회
      const res = await fetch(
        `${SUPABASE_URL}/rest/v1/orders?select=id,title,status,category,address,createdAt,isAnonymous,isAwarded,customerPhone,webPassword,images,visitDate&order=createdAt.desc&limit=200`,
        { headers: sbHeaders }
      )
      const all = await res.json()
      if (!Array.isArray(all)) return err('조회 중 오류가 발생했습니다.', 500)

      const normalize = (p: string) => p.replace(/[^0-9]/g, '')
      const orders = all.filter((o: any) => {
        const p = o.customerPhone || o.customerphone || ''
        const pwd = o.webPassword || o.webpassword || ''
        return normalize(p) === normalize(phone) && pwd === password
      })

      if (!orders.length) return err('일치하는 견적 요청을 찾을 수 없습니다.\n전화번호와 비밀번호를 확인해 주세요.', 404)

      return ok({ orders: orders.map((o: any) => ({
        id: o.id, title: o.title, status: o.status,
        category: o.category, address: o.address,
        createdAt: o.createdAt || o.createdat,
        isAwarded: o.isAwarded ?? false,
        images: o.images || [],
        visitDate: o.visitDate || o.visitdate,
      })) })
    }

    // ─────────────────────────────────────────────────────────────
    // GET /order/:orderId  - 주문 상세 + 입찰 목록 (phone+pwd 인증)
    // order_bids를 단일 소스로 사용 (앱 사업자 입찰과 동일한 데이터)
    // ─────────────────────────────────────────────────────────────
    if (event.httpMethod === 'GET' && /^\/order\/[^/]+$/.test(path)) {
      const orderId = path.split('/')[2]
      const phone = (qp.phone || '').replace(/[^0-9]/g, '')
      const password = String(qp.pwd || '').trim()

      if (!phone || !password) return err('인증 정보가 필요합니다.', 401)
      const order = await verifyOrder(orderId, phone, password)
      if (!order) return err('인증 실패 또는 주문을 찾을 수 없습니다.', 401)

      // 1. 이 오더에 연결된 marketplace_listings 조회 (web_order_id로 역참조)
      const listingRes = await fetch(
        `${SUPABASE_URL}/rest/v1/marketplace_listings?web_order_id=eq.${encodeURIComponent(orderId)}&select=id&limit=1`,
        { headers: sbHeaders }
      )
      const listingArr = await listingRes.json()
      const listingId = Array.isArray(listingArr) && listingArr[0] ? listingArr[0].id : null

      // 2. order_bids (사업자 입찰 목록) 조회 - 앱 입찰과 동일한 단일 소스
      let bids: any[] = []
      if (listingId) {
        const bidsRes = await fetch(
          `${SUPABASE_URL}/rest/v1/order_bids?listing_id=eq.${encodeURIComponent(listingId)}&status=neq.withdrawn&select=id,bidder_id,message,bid_amount,estimated_days,status,created_at&order=created_at.asc`,
          { headers: sbHeaders }
        )
        const bidsRaw = await bidsRes.json()
        bids = Array.isArray(bidsRaw) ? bidsRaw : []
      }

      // 3. 입찰 사업자들의 프로필 + 평점 일괄 조회
      const bidderIds = Array.from(new Set(bids.map((b) => b.bidder_id).filter(Boolean)))
      let bidderProfiles: Record<string, any> = {}
      let bidderRatings: Record<string, { avg: number | null; count: number; recent: any[] }> = {}
      if (bidderIds.length > 0) {
        const idsFilter = bidderIds.map((id) => encodeURIComponent(id)).join(',')
        const [usersRes, reviewsRes] = await Promise.all([
          fetch(
            `${SUPABASE_URL}/rest/v1/users?id=in.(${idsFilter})&select=id,name,businessname,phonenumber,category,region,description,profile_image_url,projects_awarded_count`,
            { headers: sbHeaders }
          ),
          fetch(
            `${SUPABASE_URL}/rest/v1/business_reviews?business_id=in.(${idsFilter})&select=business_id,rating,comment,created_at&order=created_at.desc`,
            { headers: sbHeaders }
          ),
        ])
        const usersArr = await usersRes.json()
        const reviewsArr = await reviewsRes.json()
        if (Array.isArray(usersArr)) {
          for (const u of usersArr) bidderProfiles[u.id] = u
        }
        if (Array.isArray(reviewsArr)) {
          for (const bid of bidderIds) {
            const rs = reviewsArr.filter((r: any) => r.business_id === bid)
            const avg = rs.length ? Math.round((rs.reduce((s: number, r: any) => s + (r.rating || 0), 0) / rs.length) * 10) / 10 : null
            bidderRatings[bid] = { avg, count: rs.length, recent: rs.slice(0, 3) }
          }
        }
      }

      // 4. 낙찰된 사업자 정보 (technicianId 기준)
      let awardedBusiness: any = null
      const techId = order.technicianId || order.technicianid
      if (techId) {
        awardedBusiness = bidderProfiles[techId] || null
        if (!awardedBusiness) {
          const bRes = await fetch(
            `${SUPABASE_URL}/rest/v1/users?id=eq.${encodeURIComponent(techId)}&select=id,name,businessname,phonenumber,email,category,region,description,profile_image_url,projects_awarded_count&limit=1`,
            { headers: sbHeaders }
          )
          const bArr = await bRes.json()
          awardedBusiness = Array.isArray(bArr) ? bArr[0] : null
        }
        if (awardedBusiness) {
          const r = bidderRatings[techId]
          awardedBusiness = { ...awardedBusiness, avgRating: r?.avg ?? null, reviewCount: r?.count ?? 0 }
        }
      }

      return ok({
        order: {
          id: order.id, title: order.title, description: order.description,
          status: order.status, category: order.category, address: order.address,
          visitDate: order.visitDate || order.visitdate,
          createdAt: order.createdAt || order.createdat,
          isAwarded: order.isAwarded ?? false,
          awardedBidId: order.awarded_bid_id || null,
          images: order.images || [],
          adminRating: order.adminRating,
          adminRatingComment: order.adminRatingComment,
          matchedJobId: order.matchedJobId,
        },
        bids: bids.map((b) => {
          const profile = bidderProfiles[b.bidder_id] || {}
          const rating = bidderRatings[b.bidder_id] || { avg: null, count: 0, recent: [] }
          return {
            id: b.id,
            businessId: b.bidder_id,
            businessName: profile.businessname || profile.name || '사업자',
            category: profile.category,
            region: profile.region,
            amount: b.bid_amount,
            message: b.message,
            estimatedDays: b.estimated_days,
            createdAt: b.created_at,
            status: b.status,
            isAwarded: b.status === 'selected',
            avgRating: rating.avg,
            reviewCount: rating.count,
            recentReviews: rating.recent,
          }
        }),
        awardedBusiness,
      })
    }

    // ─────────────────────────────────────────────────────────────
    // GET /business/:bizId  - 사업자 상세 + 평점/리뷰
    // ─────────────────────────────────────────────────────────────
    if (event.httpMethod === 'GET' && /^\/business\/[^/]+$/.test(path)) {
      const bizId = path.split('/')[2]

      const [bizRes, reviewsRes] = await Promise.all([
        fetch(
          `${SUPABASE_URL}/rest/v1/users?id=eq.${encodeURIComponent(bizId)}&select=id,name,businessname,phonenumber,email,category,region,description,profile_image_url,projects_awarded_count,estimates_created_count&limit=1`,
          { headers: sbHeaders }
        ),
        fetch(
          `${SUPABASE_URL}/rest/v1/business_reviews?business_id=eq.${encodeURIComponent(bizId)}&select=id,rating,comment,is_admin_review,created_at&order=created_at.desc&limit=20`,
          { headers: sbHeaders }
        ),
      ])

      const [bizArr, reviewsRaw] = await Promise.all([bizRes.json(), reviewsRes.json()])
      const biz = Array.isArray(bizArr) ? bizArr[0] : null
      if (!biz) return err('사업자를 찾을 수 없습니다.', 404)

      const reviews = Array.isArray(reviewsRaw) ? reviewsRaw : []
      const avgRating = reviews.length
        ? Math.round((reviews.reduce((s: number, r: any) => s + (r.rating || 0), 0) / reviews.length) * 10) / 10
        : null

      return ok({ business: biz, reviews, avgRating })
    }

    // ─────────────────────────────────────────────────────────────
    // POST /order/:orderId/award  - 사업자 선택 (낙찰) - order_bids.id(bidId) 기준
    // ─────────────────────────────────────────────────────────────
    if (event.httpMethod === 'POST' && /^\/order\/[^/]+\/award$/.test(path)) {
      const orderId = path.split('/')[2]
      const body = JSON.parse(event.body || '{}')
      const phone = (body.phone || '').replace(/[^0-9]/g, '')
      const password = String(body.password || '').trim()
      const { bidId } = body

      if (!phone || !password) return err('인증 정보가 필요합니다.', 401)
      if (!bidId) return err('입찰 ID가 필요합니다.')

      const order = await verifyOrder(orderId, phone, password)
      if (!order) return err('인증 실패 또는 주문을 찾을 수 없습니다.', 401)
      if (order.isAwarded) return err('이미 낙찰된 요청입니다.')

      // 0. 입찰(order_bids) 조회 + 해당 오더 소속 검증
      const bidRes = await fetch(
        `${SUPABASE_URL}/rest/v1/order_bids?id=eq.${encodeURIComponent(bidId)}&select=id,listing_id,bidder_id,status,marketplace_listings!inner(web_order_id)&limit=1`,
        { headers: sbHeaders }
      )
      const bidArr = await bidRes.json()
      const bid = Array.isArray(bidArr) ? bidArr[0] : null
      const bidOrderId = bid?.marketplace_listings?.web_order_id
      if (!bid || bidOrderId !== orderId) return err('입찰 정보를 찾을 수 없습니다.', 404)
      if (bid.status !== 'pending') return err('이미 처리된 입찰입니다.')

      const businessId = bid.bidder_id
      const now = new Date().toISOString()

      // 1. order_bids 낙찰 처리 (트리거가 marketplace_listings.selected_bidder_id 설정 + 다른 입찰 rejected 처리)
      await fetch(`${SUPABASE_URL}/rest/v1/order_bids?id=eq.${encodeURIComponent(bidId)}`, {
        method: 'PATCH',
        headers: { ...sbHeaders, Prefer: 'return=minimal' },
        body: JSON.stringify({ status: 'selected', updated_at: now }),
      })

      // 2. 사업자 정보 조회 (알림 전송용)
      const bizRes = await fetch(
        `${SUPABASE_URL}/rest/v1/users?id=eq.${encodeURIComponent(businessId)}&select=id,name,businessname,phonenumber&limit=1`,
        { headers: sbHeaders }
      )
      const bizArr = await bizRes.json()
      const biz = Array.isArray(bizArr) ? bizArr[0] : null
      const bizName = biz?.businessname || biz?.name || '사업자'

      // 3. order 낙찰 처리
      await fetch(`${SUPABASE_URL}/rest/v1/orders?id=eq.${encodeURIComponent(orderId)}`, {
        method: 'PATCH',
        headers: { ...sbHeaders, Prefer: 'return=minimal' },
        body: JSON.stringify({
          isAwarded: true,
          awardedAt: now,
          awarded_bid_id: bidId,
          technicianId: businessId,
          status: 'in_progress',
        }),
      })

      // 4. jobs 테이블에 공사 생성 → 사업자 앱 '내 공사 관리' 표시
      const customerPhone = order.customerPhone || order.customerphone || ''
      const customerName = order.customerName || order.customername || '고객'
      const jobPayload: any = {
        title: order.title || '웹 견적 요청',
        description: `[웹 고객 낙찰]\n요청 내용: ${order.description || ''}\n\n📞 고객 연락처: ${customerPhone}\n👤 고객명: ${customerName}\n📍 상세 주소: ${order.address || ''}`,
        owner_business_id: businessId,
        assigned_business_id: businessId,
        status: 'assigned',
        location: order.address || '',
        category: order.category || '',
        urgency: 'normal',
        budget_amount: 0,
        awarded_amount: 0,
        commission_rate: 5,
        created_at: now,
        updated_at: now,
      }

      // web_order_id 컬럼 있으면 설정
      let jobId: string | null = null
      const jobRes = await fetch(`${SUPABASE_URL}/rest/v1/jobs`, {
        method: 'POST',
        headers: { ...sbHeaders, Prefer: 'return=representation' },
        body: JSON.stringify({ ...jobPayload, web_order_id: orderId }),
      })
      const jobText = await jobRes.text()
      if (!jobRes.ok && jobText.includes('web_order_id')) {
        // web_order_id 컬럼 없으면 제외 후 재시도
        const retryRes = await fetch(`${SUPABASE_URL}/rest/v1/jobs`, {
          method: 'POST',
          headers: { ...sbHeaders, Prefer: 'return=representation' },
          body: JSON.stringify(jobPayload),
        })
        const retryText = await retryRes.text()
        try {
          const d = JSON.parse(retryText)
          jobId = (Array.isArray(d) ? d[0] : d)?.id || null
        } catch {}
      } else {
        try {
          const d = JSON.parse(jobText)
          jobId = (Array.isArray(d) ? d[0] : d)?.id || null
        } catch {}
      }

      // 5. order 에 matchedJobId 업데이트 + order_bids에 job_id 연결
      if (jobId) {
        await fetch(`${SUPABASE_URL}/rest/v1/orders?id=eq.${encodeURIComponent(orderId)}`, {
          method: 'PATCH',
          headers: { ...sbHeaders, Prefer: 'return=minimal' },
          body: JSON.stringify({ matchedJobId: jobId }),
        })
        await fetch(`${SUPABASE_URL}/rest/v1/order_bids?id=eq.${encodeURIComponent(bidId)}`, {
          method: 'PATCH',
          headers: { ...sbHeaders, Prefer: 'return=minimal' },
          body: JSON.stringify({ job_id: jobId }),
        }).catch(() => {})
      }

      // 6. 사업자 앱 알림 (고객 연락처 포함)
      const visitDate = (order.visitDate || order.visitdate || '').slice(0, 10)
      const notifBody = `📞 고객: ${customerName} / ${customerPhone}\n📍 주소: ${order.address || ''}\n📅 방문일: ${visitDate}`
      await insertNotification(businessId,
        `🎉 낙찰되었습니다 - ${order.title || '견적 요청'}`,
        notifBody,
        'web_order_awarded',
        jobId || undefined
      )

      // FCM은 notifications INSERT Webhook이 1회 발송

      // 7. 고객에게 낙찰 문자 (사업자 연락처 + 웹 링크)
      try {
        const bizPhone = formatPhoneDisplay(biz?.phonenumber || '')
        const awardLink = customerOrderUrl(customerPhone)
        await sendSms(
          customerPhone,
          smsBidAwarded({
            orderTitle: order.title || '견적 요청',
            businessName: bizName,
            phoneLabel: bizPhone || '웹에서 확인',
            link: awardLink,
          })
        )
      } catch (e: any) {
        console.warn('[customer] 낙찰 문자 발송 실패 (무시):', e.message)
      }

      return ok({ success: true, jobId, message: `${bizName}에게 낙찰되었습니다.` })
    }

    // ─────────────────────────────────────────────────────────────
    // POST /order/:orderId/complete  - 공사 완료 확인 (소비자만 최종 확정 가능)
    // 완료 정책: 사업자의 "완료 유도" 여부와 무관하게, 소비자의 이 확인 1회로 최종 완료 처리됨
    // ─────────────────────────────────────────────────────────────
    if (event.httpMethod === 'POST' && /^\/order\/[^/]+\/complete$/.test(path)) {
      const orderId = path.split('/')[2]
      const body = JSON.parse(event.body || '{}')
      const phone = (body.phone || '').replace(/[^0-9]/g, '')
      const password = String(body.password || '').trim()

      if (!phone || !password) return err('인증 정보가 필요합니다.', 401)
      const order = await verifyOrder(orderId, phone, password)
      if (!order) return err('인증 실패', 401)
      if (!order.isAwarded) return err('낙찰 전에는 완료 처리할 수 없습니다.')
      if (order.status === 'completed') return err('이미 완료 처리된 요청입니다.')

      const now = new Date().toISOString()

      await fetch(`${SUPABASE_URL}/rest/v1/orders?id=eq.${encodeURIComponent(orderId)}`, {
        method: 'PATCH',
        headers: { ...sbHeaders, Prefer: 'return=minimal' },
        body: JSON.stringify({ status: 'completed' }),
      })

      // jobs / marketplace_listings 상태도 최종 completed로 동기화 (소비자 확인 = 최종 완료)
      const jobId = order.matchedJobId
      if (jobId) {
        await fetch(`${SUPABASE_URL}/rest/v1/jobs?id=eq.${encodeURIComponent(jobId)}`, {
          method: 'PATCH',
          headers: { ...sbHeaders, Prefer: 'return=minimal' },
          body: JSON.stringify({ status: 'completed', updated_at: now }),
        })
      }
      const listingRes = await fetch(
        `${SUPABASE_URL}/rest/v1/marketplace_listings?web_order_id=eq.${encodeURIComponent(orderId)}&select=id&limit=1`,
        { headers: sbHeaders }
      )
      const listingArr = await listingRes.json()
      const listingId = Array.isArray(listingArr) && listingArr[0] ? listingArr[0].id : null
      if (listingId) {
        await fetch(`${SUPABASE_URL}/rest/v1/marketplace_listings?id=eq.${encodeURIComponent(listingId)}`, {
          method: 'PATCH',
          headers: { ...sbHeaders, Prefer: 'return=minimal' },
          body: JSON.stringify({ status: 'completed', updatedat: now }),
        })
      }

      const techId = order.technicianId || order.technicianid
      if (techId) {
        await insertNotification(techId, '공사 완료 확인', '고객이 공사 완료를 확인했습니다.', 'job_complete', jobId)
      }

      return ok({ success: true, message: '공사 완료가 확인되었습니다.' })
    }

    // ─────────────────────────────────────────────────────────────
    // POST /order/:orderId/notify-work-done  - 사업자가 "공사 완료"를 눌렀을 때
    // 소비자에게 완료 확인 + 평점 요청 문자 발송
    // 오더 ID만 알면 누구나 고객에게 문자를 보낼 수 있었으므로,
    // 로그인 검증 + 해당 오더 담당 사업자인지 확인합니다.
    // ─────────────────────────────────────────────────────────────
    if (event.httpMethod === 'POST' && /^\/order\/[^/]+\/notify-work-done$/.test(path)) {
      const orderId = path.split('/')[2]

      const callerId = await authenticatedUserId(event)
      if (!callerId) return err('인증이 필요합니다.', 401)
      if (callerId !== 'service_role' && !(await isAssignedBusiness(orderId, callerId))) {
        return err('이 요청의 담당 사업자만 완료 알림을 보낼 수 있습니다.', 403)
      }

      const orderRes = await fetch(
        `${SUPABASE_URL}/rest/v1/orders?id=eq.${encodeURIComponent(orderId)}&select=id,title,customerName,customerPhone,isAwarded,status&limit=1`,
        { headers: sbHeaders }
      )
      const orderArr = await orderRes.json()
      const order = Array.isArray(orderArr) ? orderArr[0] : null
      if (!order) return err('요청을 찾을 수 없습니다.', 404)
      if (!order.isAwarded) return err('낙찰 전 요청입니다.')
      if (order.status !== 'in_progress') return err('이미 처리된 요청입니다.')

      const customerPhone = order.customerPhone || ''
      try {
        const link = customerOrderUrl(customerPhone)
        await sendSms(
          customerPhone,
          smsWorkDoneReview({
            orderTitle: order.title || '견적 요청',
            link,
          })
        )
      } catch (e: any) {
        console.warn('[customer] 공사완료 문자 발송 실패 (무시):', e.message)
      }

      return ok({ success: true })
    }

    // ─────────────────────────────────────────────────────────────
    // POST /order/:orderId/rate  - 평점 입력
    // ─────────────────────────────────────────────────────────────
    if (event.httpMethod === 'POST' && /^\/order\/[^/]+\/rate$/.test(path)) {
      const orderId = path.split('/')[2]
      const body = JSON.parse(event.body || '{}')
      const phone = (body.phone || '').replace(/[^0-9]/g, '')
      const password = String(body.password || '').trim()
      const { rating, comment } = body

      if (!phone || !password) return err('인증 정보가 필요합니다.', 401)
      if (!rating || rating < 1 || rating > 5) return err('평점은 1~5 사이여야 합니다.')

      const order = await verifyOrder(orderId, phone, password)
      if (!order) return err('인증 실패', 401)

      const now = new Date().toISOString()
      const businessId = order.technicianId || order.technicianid

      // order 평점 저장
      await fetch(`${SUPABASE_URL}/rest/v1/orders?id=eq.${encodeURIComponent(orderId)}`, {
        method: 'PATCH',
        headers: { ...sbHeaders, Prefer: 'return=minimal' },
        body: JSON.stringify({ adminRating: rating, adminRatingComment: comment || '', adminRatedAt: now }),
      })

      // 평점은 order_reviews 로 통합 저장한다 (앱 B2B 평점과 같은 원천).
      // order_id 유니크 인덱스 + upsert 라서 같은 오더를 두 번 평가해도 갱신된다.
      if (businessId) {
        try {
          await fetch(`${SUPABASE_URL}/rest/v1/order_reviews?on_conflict=order_id`, {
            method: 'POST',
            headers: { ...sbHeaders, Prefer: 'return=minimal,resolution=merge-duplicates' },
            body: JSON.stringify({ reviewee_id: businessId, order_id: orderId, rating, comment: comment || '', is_admin_review: false, created_at: now, updated_at: now }),
          })
        } catch (reviewErr: any) {
          console.warn('[customer] order_reviews 저장 실패:', reviewErr?.message)
        }

        await insertNotification(businessId, '⭐ 새로운 평점이 등록되었습니다', `고객이 ${rating}점을 남겼습니다.`, 'new_review')
      }

      return ok({ success: true, message: '평점이 등록되었습니다.' })
    }

    return err('Not Found', 404)
  } catch (e: any) {
    console.error('[customer] 오류:', e)
    return err(`서버 오류: ${e.message}`, 500)
  }
}
