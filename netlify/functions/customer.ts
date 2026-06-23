/// <reference types="node" />
// Netlify function: 웹 비로그인 고객용 API
// 4자리 PIN으로 본인 확인 후 견적 요청 조회/낙찰/완료/평점 처리

const SUPABASE_URL = process.env.SUPABASE_URL as string
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY as string
const ADMIN_TOKEN = process.env.ADMIN_TOKEN || process.env.ADMIN_DEVELOPER_TOKEN || 'devtoken'
const SITE_URL = process.env.URL || 'https://allsuricommerce.netlify.app'

const sbHeaders = {
  apikey: SUPABASE_SERVICE_ROLE_KEY,
  Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
  'Content-Type': 'application/json',
}

const JSON_HEADERS = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type, x-order-password, x-customer-phone',
}

function ok(data: any, status = 200) {
  return { statusCode: status, body: JSON.stringify(data), headers: JSON_HEADERS }
}
function err(msg: string, status = 400) {
  return { statusCode: status, body: JSON.stringify({ error: msg }), headers: JSON_HEADERS }
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
    // ─────────────────────────────────────────────────────────────
    if (event.httpMethod === 'GET' && /^\/order\/[^/]+$/.test(path)) {
      const orderId = path.split('/')[2]
      const phone = (qp.phone || '').replace(/[^0-9]/g, '')
      const password = String(qp.pwd || '').trim()

      if (!phone || !password) return err('인증 정보가 필요합니다.', 401)
      const order = await verifyOrder(orderId, phone, password)
      if (!order) return err('인증 실패 또는 주문을 찾을 수 없습니다.', 401)

      // estimates (사업자 입찰 목록) 조회
      const estRes = await fetch(
        `${SUPABASE_URL}/rest/v1/estimates?orderId=eq.${encodeURIComponent(orderId)}&select=id,businessid,businessname,businessphone,equipmenttype,amount,description,estimateddays,createdat,visitdate,status,awardedAt&order=createdat.asc`,
        { headers: sbHeaders }
      )
      const estimates = await estRes.json()

      // 낙찰된 사업자 정보 조회 (technicianId)
      let awardedBusiness: any = null
      const techId = order.technicianId || order.technicianid
      if (techId) {
        const bRes = await fetch(
          `${SUPABASE_URL}/rest/v1/users?id=eq.${encodeURIComponent(techId)}&select=id,name,businessname,phonenumber,email,category,region,description,profile_image_url,projects_awarded_count&limit=1`,
          { headers: sbHeaders }
        )
        const bArr = await bRes.json()
        awardedBusiness = Array.isArray(bArr) ? bArr[0] : null
      }

      return ok({
        order: {
          id: order.id, title: order.title, description: order.description,
          status: order.status, category: order.category, address: order.address,
          visitDate: order.visitDate || order.visitdate,
          createdAt: order.createdAt || order.createdat,
          isAwarded: order.isAwarded ?? false,
          awardedEstimateId: order.awardedEstimateId || order.awardedEstimateId,
          images: order.images || [],
          adminRating: order.adminRating,
          matchedJobId: order.matchedJobId,
        },
        estimates: Array.isArray(estimates) ? estimates.map((e: any) => ({
          id: e.id,
          businessId: e.businessid,
          businessName: e.businessname,
          equipmentType: e.equipmenttype,
          amount: e.amount,
          description: e.description,
          estimatedDays: e.estimateddays,
          createdAt: e.createdat,
          status: e.status,
          isAwarded: e.status === 'awarded',
        })) : [],
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
    // POST /order/:orderId/award  - 사업자 선택 (낙찰)
    // ─────────────────────────────────────────────────────────────
    if (event.httpMethod === 'POST' && /^\/order\/[^/]+\/award$/.test(path)) {
      const orderId = path.split('/')[2]
      const body = JSON.parse(event.body || '{}')
      const phone = (body.phone || '').replace(/[^0-9]/g, '')
      const password = String(body.password || '').trim()
      const { estimateId, businessId } = body

      if (!phone || !password) return err('인증 정보가 필요합니다.', 401)
      if (!estimateId || !businessId) return err('견적 ID와 사업자 ID가 필요합니다.')

      const order = await verifyOrder(orderId, phone, password)
      if (!order) return err('인증 실패 또는 주문을 찾을 수 없습니다.', 401)
      if (order.isAwarded) return err('이미 낙찰된 요청입니다.')

      const now = new Date().toISOString()

      // 1. estimate 낙찰 처리
      await fetch(`${SUPABASE_URL}/rest/v1/estimates?id=eq.${encodeURIComponent(estimateId)}`, {
        method: 'PATCH',
        headers: { ...sbHeaders, Prefer: 'return=minimal' },
        body: JSON.stringify({ status: 'awarded', awardedAt: now }),
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
          awardedEstimateId: estimateId,
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

      // 5. order 에 matchedJobId 업데이트
      if (jobId) {
        await fetch(`${SUPABASE_URL}/rest/v1/orders?id=eq.${encodeURIComponent(orderId)}`, {
          method: 'PATCH',
          headers: { ...sbHeaders, Prefer: 'return=minimal' },
          body: JSON.stringify({ matchedJobId: jobId }),
        })
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

      return ok({ success: true, jobId, message: `${bizName}에게 낙찰되었습니다.` })
    }

    // ─────────────────────────────────────────────────────────────
    // POST /order/:orderId/complete  - 공사 완료 확인
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

      await fetch(`${SUPABASE_URL}/rest/v1/orders?id=eq.${encodeURIComponent(orderId)}`, {
        method: 'PATCH',
        headers: { ...sbHeaders, Prefer: 'return=minimal' },
        body: JSON.stringify({ status: 'completed' }),
      })

      // job 상태도 awaiting_confirmation 으로 변경
      const jobId = order.matchedJobId
      if (jobId) {
        await fetch(`${SUPABASE_URL}/rest/v1/jobs?id=eq.${encodeURIComponent(jobId)}`, {
          method: 'PATCH',
          headers: { ...sbHeaders, Prefer: 'return=minimal' },
          body: JSON.stringify({ status: 'awaiting_confirmation', updated_at: new Date().toISOString() }),
        })
      }

      const techId = order.technicianId || order.technicianid
      if (techId) {
        await insertNotification(techId, '공사 완료 확인', '고객이 공사 완료를 확인했습니다.', 'job_complete', jobId)
      }

      return ok({ success: true, message: '공사 완료가 확인되었습니다.' })
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

      // business_reviews 저장
      if (businessId) {
        try {
          await fetch(`${SUPABASE_URL}/rest/v1/business_reviews`, {
            method: 'POST',
            headers: { ...sbHeaders, Prefer: 'return=minimal' },
            body: JSON.stringify({ business_id: businessId, order_id: orderId, rating, comment: comment || '', is_admin_review: false, created_at: now }),
          })
        } catch {}

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
