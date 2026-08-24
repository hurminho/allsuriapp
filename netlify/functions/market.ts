/// <reference types="node" />
// import { Config, Context } from "@netlify/functions"; // ✅ Removed this line

// import { createClient } from "@supabase/supabase-js"; // ✅ 제거

import { formatRating, formatWon, sendBidReceivedSms } from '../lib/solapi_sms'

const SUPABASE_URL = process.env.SUPABASE_URL as string
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY as string

export const handler = async (event: any, context: any) => {
  // Netlify redirects: /api/market/* -> /.netlify/functions/market/*
  // event.path will be like: /api/market/listings/xxx/claim
  let path = event.path
  
  // Remove /api/market prefix
  if (path.startsWith('/api/market')) {
    path = path.replace('/api/market', '')
  } else if (path.startsWith('/.netlify/functions/market')) {
    path = path.replace('/.netlify/functions/market', '')
  }
  
  const method = event.httpMethod

  console.log(`[market] ${method} ${event.path} -> ${path}`)

  try {
    // GET /listings
    if (method === 'GET' && path.startsWith('/listings') && !path.includes('/bids')) {
      return await handleGetListings(event)
    }

    // GET /bids
    if (method === 'GET' && path === '/bids') {
      return await handleListBids(event)
    }

    // POST /listings/:id/claim
    if (method === 'POST' && path.match(/^\/listings\/[^/]+\/claim$/)) {
      return await handleClaimListing(event, path)
    }

    // POST /listings/:id/bid
    if (method === 'POST' && path.match(/^\/listings\/[^/]+\/bid$/)) {
      return await handleBidListing(event, path)
    }

    // GET /listings/:id/bids
    if (method === 'GET' && path.match(/^\/listings\/[^/]+\/bids$/)) {
      return await handleGetBids(event, path)
    }

    // POST /listings/:id/select-bidder
    if (method === 'POST' && path.match(/^\/listings\/[^/]+\/select-bidder$/)) {
      return await handleSelectBidder(event, path)
    }

    // DELETE /bids/:listingId
    if (method === 'DELETE' && path.match(/^\/bids\/[^/]+$/)) {
      return await handleDeleteBid(event, path)
    }

    return { statusCode: 404, body: JSON.stringify({ message: 'Not found' }), headers: { 'Content-Type': 'application/json' } };
  } catch (error: any) {
    console.error('[market] error:', error)
    return { statusCode: 500, body: JSON.stringify({ message: 'Internal server error', error: error.message }), headers: { 'Content-Type': 'application/json' } };
  }
}

async function handleGetListings(event: any) {
  const params = event.queryStringParameters || {}
  const { status, region, category, limit, offset, postedBy, claimedBy, jobId, jobIds } = params

  let url = `${SUPABASE_URL}/rest/v1/marketplace_listings?select=*,jobs(*)`
  
  if (status && status !== 'all') {
    url += `&status=eq.${status}`
  }
  if (region) {
    url += `&region=eq.${encodeURIComponent(region)}`
  }
  if (category) {
    url += `&category=eq.${encodeURIComponent(category)}`
  }
  if (postedBy) {
    url += `&posted_by=eq.${encodeURIComponent(postedBy)}`
  }
  if (claimedBy) {
    url += `&claimed_by=eq.${encodeURIComponent(claimedBy)}`
  }
  if (jobId) {
    url += `&jobid=eq.${encodeURIComponent(jobId)}`
  }
  if (jobIds) {
    const ids = jobIds.split(',').map((id: string) => id.trim()).filter(Boolean)
    if (ids.length > 0) {
      url += `&jobid=in.(${ids.map((id: string) => encodeURIComponent(id)).join(',')})`
    }
  }

  url += '&order=createdat.desc'

  if (limit) {
    const l = Math.min(parseInt(limit, 10) || 50, 100)
    const o = Math.max(parseInt(offset || '0', 10), 0)
    url += `&limit=${l}&offset=${o}`
  } else {
    url += '&limit=50'
  }

  const response = await fetch(url, {
    headers: {
      apikey: SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
    }
  })

  const data = await response.json()
  
  return { statusCode: 200, body: JSON.stringify(data || []), headers: { 'Content-Type': 'application/json' } };
}

async function handleClaimListing(event: any, path: string) {
  const id = listingIdFromPath(path)
  const body = JSON.parse(event.body || '{}')
  const { businessId } = body

  if (!businessId) {
    return { statusCode: 400, body: JSON.stringify({ message: 'businessId는 필수입니다' }), headers: { 'Content-Type': 'application/json' } };
  }

  try {
    // RPC 호출
    const rpcResponse = await fetch(`${SUPABASE_URL}/rest/v1/rpc/claim_listing`, {
      method: 'POST',
      headers: {
        apikey: SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        p_listing_id: id,
        p_business_id: businessId,
      })
    })

    const rpcData = await rpcResponse.json()

    if (!rpcResponse.ok) {
      throw new Error(rpcData.message || 'RPC failed')
    }

    if (rpcData === true) {
      // 성공 - jobs_accepted_count 증가
      try {
        await fetch(`${SUPABASE_URL}/rest/v1/rpc/increment_user_jobs_accepted_count`, {
          method: 'POST',
          headers: {
            apikey: SUPABASE_SERVICE_ROLE_KEY,
            Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ user_id: businessId })
        })
      } catch (e: any) {
        console.warn('[market] increment count failed:', e.message)
      }

      return { statusCode: 200, body: JSON.stringify({ success: true }), headers: { 'Content-Type': 'application/json' } };
    }

    // 409는 클라이언트가 통신 실패와 구분하지 못하므로 200 + 플래그로 내립니다.
    return jsonRes(200, { success: false, alreadyClaimed: true, message: '이미 다른 사업자가 가져갔습니다' });
  } catch (error: any) {
    console.error('[market] claim error:', error.message)
    return { statusCode: 500, body: JSON.stringify({ message: '가져가기 처리 실패', error: error.message }), headers: { 'Content-Type': 'application/json' } };
  }
}

function jsonRes(statusCode: number, body: Record<string, unknown>) {
  return { statusCode, body: JSON.stringify(body), headers: { 'Content-Type': 'application/json' } }
}

/// `/api/market/...` 리다이렉트와 `/.netlify/functions/market/...` 직접 호출 모두에서
/// 동작하도록 세그먼트 이름을 기준으로 id를 찾습니다.
function listingIdFromPath(path: string, segment: string = 'listings'): string {
  const parts = String(path || '').split('/').filter(Boolean)
  const idx = parts.indexOf(segment)
  if (idx >= 0 && parts[idx + 1]) return parts[idx + 1]
  return parts[1] || ''
}

async function runWithTimeout(work: Promise<unknown>, ms: number): Promise<void> {
  let timer: ReturnType<typeof setTimeout> | undefined
  try {
    await Promise.race([
      work,
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error(`timeout ${ms}ms`)), ms)
      }),
    ])
  } finally {
    if (timer) clearTimeout(timer)
  }
}

async function handleBidListing(event: any, path: string) {
  const id = listingIdFromPath(path)
  const body = JSON.parse(event.body || '{}')
  const { businessId, message, bid_amount, estimated_days } = body

  if (!id) {
    return jsonRes(400, { message: 'listing id는 필수입니다' })
  }
  if (!businessId) {
    return jsonRes(400, { message: 'businessId는 필수입니다' })
  }

  try {
    // 중복 입찰 확인 (같은 사업자가 같은 오더에 이미 입찰했는지)
    const existingRes = await fetch(
      `${SUPABASE_URL}/rest/v1/order_bids?listing_id=eq.${encodeURIComponent(id)}&bidder_id=eq.${encodeURIComponent(businessId)}&select=id&limit=1`,
      {
        headers: {
          apikey: SUPABASE_SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
        }
      }
    )
    const existing = await existingRes.json()
    if (Array.isArray(existing) && existing.length > 0) {
      return jsonRes(200, { success: true, alreadyBid: true, bidId: existing[0]?.id, message: '이미 입찰하셨습니다' })
    }

    // 직접 INSERT (RPC 대신 - 여러 사업자가 동시 입찰 가능하도록)
    const now = new Date().toISOString()
    const insertRes = await fetch(`${SUPABASE_URL}/rest/v1/order_bids`, {
      method: 'POST',
      headers: {
        apikey: SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      },
      body: JSON.stringify({
        listing_id: id,
        bidder_id: businessId,
        message: message || null,
        bid_amount: bid_amount ?? null,
        estimated_days: estimated_days ?? null,
        status: 'pending',
        created_at: now,
        updated_at: now,
      })
    })

    const data = await insertRes.json()

    if (!insertRes.ok) {
      const code = data?.code || data?.[0]?.code
      // 23505 unique: 이미 입찰 — 클라이언트는 성공으로 처리해야 목록에 남음
      if (insertRes.status === 409 && code !== '23503') {
        return jsonRes(200, { success: true, alreadyBid: true, message: '이미 입찰하셨습니다' })
      }
      console.error('[market] bid insert error:', data)
      throw new Error(Array.isArray(data) ? data[0]?.message : data.message || 'Bid failed')
    }

    const bidId = Array.isArray(data) ? data[0]?.id : data?.id
    console.log(`[market] bid inserted listing=${id} bidder=${businessId} bidId=${bidId}`)

    // 문자/알림이 길어도 입찰 저장은 이미 끝난 상태. 응답을 막지 않습니다.
    // Netlify 함수 상한 10s 중 중복확인+INSERT에 쓴 시간을 빼고 남는 만큼 허용합니다.
    // (문자 발송은 Solapi 직접 호출 실패 시 allsuri-web으로 위임까지 하므로 여유가 필요)
    try {
      await runWithTimeout(afterBidInserted({
        listingId: id,
        businessId,
        bidAmount: bid_amount,
      }), 7500)
    } catch (e: any) {
      console.warn('[market] bid side effects skipped:', e.message)
    }

    return jsonRes(200, { success: true, bidId })
  } catch (error: any) {
    console.error('[market] bid error:', error.message)
    return jsonRes(500, { message: '입찰 처리 실패', error: error.message })
  }
}

async function afterBidInserted(opts: {
  listingId: string
  businessId: string
  bidAmount: unknown
}) {
  const { listingId: id, businessId, bidAmount: bid_amount } = opts
  // 문자 발송이 타임아웃 예산을 최대한 쓸 수 있도록 대기하지 않습니다.
  void fetch(`${SUPABASE_URL}/rest/v1/rpc/increment_bid_count`, {
    method: 'POST',
    headers: {
      apikey: SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ p_listing_id: id })
  }).catch(() => {/* bid_count 업데이트 실패는 무시 */})

    // 알림 및 푸시 알림 전송
    try {
      const listingResponse = await fetch(
        `${SUPABASE_URL}/rest/v1/marketplace_listings?id=eq.${id}&select=title,posted_by,web_order_id`,
        {
          headers: {
            apikey: SUPABASE_SERVICE_ROLE_KEY,
            Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
          }
        }
      )
      const listings = await listingResponse.json()
      const listing = Array.isArray(listings) && listings.length > 0 ? listings[0] : null
      
      console.log(`[market] 📧 알림 전송 시작:`)
      console.log(`   - Listing: ${listing?.title}`)
      console.log(`   - 오더 소유자: ${listing?.posted_by}`)
      console.log(`   - 입찰자: ${businessId}`)

      // 웹 견적 요청인 경우: 고객에게 입찰 문자 발송
      if (listing?.web_order_id) {
        try {
          // 최초 입찰 시에만 orders.status 를 'bidding'으로 전환 (이미 진행 중이면 무시)
          // 문자 발송을 지연시키지 않도록 결과를 기다리지 않습니다.
          void fetch(`${SUPABASE_URL}/rest/v1/orders?id=eq.${encodeURIComponent(listing.web_order_id)}&status=eq.pending`, {
            method: 'PATCH',
            headers: {
              apikey: SUPABASE_SERVICE_ROLE_KEY,
              Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
              'Content-Type': 'application/json',
              Prefer: 'return=minimal',
            },
            body: JSON.stringify({ status: 'bidding' }),
          }).catch((e: any) => console.warn('[market] orders 상태 전환 실패 (무시):', e?.message))

          const orderRes = await fetch(
            `${SUPABASE_URL}/rest/v1/orders?id=eq.${encodeURIComponent(listing.web_order_id)}&select=title,customerName,customerPhone&limit=1`,
            {
              headers: {
                apikey: SUPABASE_SERVICE_ROLE_KEY,
                Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
              }
            }
          )
          const orderArr = await orderRes.json()
          const webOrder = Array.isArray(orderArr) ? orderArr[0] : null
          if (webOrder?.customerPhone) {
            const [bizRes, reviewsRes] = await Promise.all([
              fetch(
                `${SUPABASE_URL}/rest/v1/users?id=eq.${encodeURIComponent(businessId)}&select=businessname,name&limit=1`,
                {
                  headers: {
                    apikey: SUPABASE_SERVICE_ROLE_KEY,
                    Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
                  },
                }
              ),
              fetch(
                `${SUPABASE_URL}/rest/v1/order_reviews?reviewee_id=eq.${encodeURIComponent(businessId)}&select=rating`,
                {
                  headers: {
                    apikey: SUPABASE_SERVICE_ROLE_KEY,
                    Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
                  },
                }
              ),
            ])
            const bizArr = await bizRes.json().catch(() => [])
            const biz = Array.isArray(bizArr) ? bizArr[0] : null
            const bizName = biz?.businessname || biz?.name || '사업자'
            const reviewsArr = await reviewsRes.json().catch(() => [])
            const ratings = Array.isArray(reviewsArr) ? reviewsArr.map((r: any) => Number(r.rating) || 0) : []
            const avg = ratings.length
              ? Math.round((ratings.reduce((s: number, n: number) => s + n, 0) / ratings.length) * 10) / 10
              : null
            const orderTitle = webOrder.title || listing.title || '견적 요청'
            const smsResult = await sendBidReceivedSms({
              to: webOrder.customerPhone,
              orderTitle,
              businessName: bizName,
              priceLabel: formatWon(bid_amount),
              ratingLabel: formatRating(avg, ratings.length),
              serviceRoleKey: SUPABASE_SERVICE_ROLE_KEY,
            })
            if (!smsResult.ok) {
              console.warn('[market] 웹 오더 문자 미발송:', smsResult.error)
            }
          } else {
            console.warn('[market] 웹 오더 전화번호 없음 - 문자 스킵')
          }
        } catch (e: any) {
          console.warn('[market] 웹 오더 문자 발송 실패 (무시):', e.message)
        }
      }

      if (listing) {
        // 1. 오더 소유자에게 알림 (새로운 입찰)
        const ownerNotificationTitle = '새로운 입찰'
        const ownerNotificationBody = `${listing.title || '오더'}에 새로운 입찰이 들어왔습니다.`
        
        console.log(`[market] 📧 오더 소유자에게 알림 생성 중...`)
        const ownerNotifResponse = await fetch(`${SUPABASE_URL}/rest/v1/notifications`, {
          method: 'POST',
          headers: {
            apikey: SUPABASE_SERVICE_ROLE_KEY,
            Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
            'Content-Type': 'application/json',
            'Prefer': 'return=representation',
          },
          body: JSON.stringify({
            userid: listing.posted_by,
            title: ownerNotificationTitle,
            body: ownerNotificationBody,
            type: 'new_bid',
            jobid: id, // listing ID를 jobid로 저장
            isread: false,
            createdat: new Date().toISOString(),
          })
        })
        
        if (!ownerNotifResponse.ok) {
          const errText = await ownerNotifResponse.text()
          console.warn(`[market] ❌ 오더 소유자 알림 생성 실패: ${errText}`)
        } else {
          const ownerNotifData = await ownerNotifResponse.json()
          console.log(`[market] ✅ 오더 소유자 알림 생성 완료:`, ownerNotifData)
        }
        
        // 2. 입찰자에게 알림 (입찰 확인)
        const bidderNotificationTitle = '입찰 완료'
        const bidderNotificationBody = `${listing.title || '오더'}에 입찰이 완료되었습니다. 오더 소유자의 승인을 기다리고 있어요~`
        
        console.log(`[market] 📧 입찰자에게 알림 생성 중...`)
        const bidderNotifResponse = await fetch(`${SUPABASE_URL}/rest/v1/notifications`, {
          method: 'POST',
          headers: {
            apikey: SUPABASE_SERVICE_ROLE_KEY,
            Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
            'Content-Type': 'application/json',
            'Prefer': 'return=representation',
          },
          body: JSON.stringify({
            userid: businessId,
            title: bidderNotificationTitle,
            body: bidderNotificationBody,
            type: 'bid_pending',
            jobid: id,
            isread: false,
            createdat: new Date().toISOString(),
          })
        })
        
        if (!bidderNotifResponse.ok) {
          const errText = await bidderNotifResponse.text()
          console.warn(`[market] ❌ 입찰자 알림 생성 실패: ${errText}`)
        } else {
          const bidderNotifData = await bidderNotifResponse.json()
          console.log(`[market] ✅ 입찰자 알림 생성 완료:`, bidderNotifData)
        }

        // 📌 DB INSERT로 알림 저장 → Supabase DB Webhook이 자동으로 FCM push 발송
        // Edge Function 직접 호출 제거 (중복 push 방지)
      }
    } catch (e: any) {
      console.warn('[market] notification failed:', e.message)
    }
}

// 이름이 의미없는 기본값인지 확인
function isGenericName(name: string | null | undefined): boolean {
  if (!name || name.trim() === '') return true
  const t = name.trim().toLowerCase()
  // 고정 기본값 목록
  const generics = ['카카오 사용자', '카카오유저', 'kakao user', '사용자', '사업자', 'undefined', 'null']
  if (generics.some(g => t === g.toLowerCase())) return true
  // kakao-숫자, kakao_숫자 형식 (카카오 자동생성 ID)
  if (/^kakao[-_]\d+$/i.test(t)) return true
  // 숫자만 있는 이름
  if (/^\d+$/.test(t)) return true
  return false
}

// auth.users Admin API에서 사용자 정보 가져오기 (public.users에 없거나 기본값인 경우 폴백)
async function fetchAuthUser(userId: string): Promise<any | null> {
  try {
    const res = await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${userId}`, {
      headers: {
        apikey: SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
        // Content-Type 없음 - GET 요청
      }
    })
    if (!res.ok) return null
    const u = await res.json()
    if (!u?.id) return null
    const meta = u.user_metadata || {}
    // 상호명: businessname/business_name 전용 필드만 사용 (개인 이름 필드와 구분)
    const businessname = [meta.businessname, meta.business_name]
      .find(v => v && !isGenericName(v)) || ''
    // 개인 이름: preferred_username, nickname, full_name, name 순
    const personName = [
      meta.preferred_username, meta.nickname, meta.full_name, meta.name,
    ].find(v => v && !isGenericName(v)) || u.email?.split('@')[0] || ''
    return {
      id: u.id,
      name: personName,
      businessname: businessname,
      avatar_url: meta.avatar_url || meta.picture || null,
      estimates_created_count: meta.estimates_created_count || 0,
      jobs_accepted_count: meta.jobs_accepted_count || 0,
      region: meta.region || '',
      category: meta.category || '',
      description: meta.description || '',
      businessnumber: meta.businessnumber || meta.business_number || '',
    }
  } catch {
    return null
  }
}

async function handleGetBids(event: any, path: string) {
  const listingId = listingIdFromPath(path)

  // GET 요청용 헤더 — Content-Type 없음 (admin.ts와 동일, PostgREST GET 표준)
  const getHeaders = {
    apikey: SUPABASE_SERVICE_ROLE_KEY,
    Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
  }

  // 모든 컬럼 가져오기 (특정 컬럼명 의존 제거)
  const USER_COLS = '*'

  try {
    // ── 1단계: order_bids 조회 ─────────────────────────────────────
    const bidsRes = await fetch(
      `${SUPABASE_URL}/rest/v1/order_bids?listing_id=eq.${encodeURIComponent(listingId)}&select=*&order=created_at.desc`,
      { headers: getHeaders }
    )
    const bidsBody = await bidsRes.text()
    let bids: any[]
    try { bids = JSON.parse(bidsBody) } catch { bids = [] }

    if (!Array.isArray(bids) || bids.length === 0) {
      return { statusCode: 200, body: JSON.stringify([]), headers: { 'Content-Type': 'application/json' } }
    }

    // ── 2단계: public.users 조회 — 개별 id=eq.UUID 병렬 조회 (가장 확실한 방식) ──
    const bidderIds = [...new Set(bids.map((b: any) => b.bidder_id).filter(Boolean))] as string[]
    const usersMap: Record<string, any> = {}
    console.log(`[market] getBids: ${bidderIds.length}명 입찰자 조회 시작 ─ ${JSON.stringify(bidderIds)}`)

    if (bidderIds.length > 0) {
      const userResults = await Promise.all(
        bidderIds.map(async (uid) => {
          const url = `${SUPABASE_URL}/rest/v1/users?id=eq.${encodeURIComponent(uid)}&select=${USER_COLS}&limit=1`
          try {
            const res = await fetch(url, { headers: getHeaders })
            const text = await res.text()
            let data: any
            try { data = JSON.parse(text) } catch { data = null }
            if (!res.ok) {
              console.error(`[market] users[${uid}] HTTP ${res.status}:`, text.slice(0, 200))
              return null
            }
            if (Array.isArray(data) && data[0]) {
              console.log(`[market] users[${uid}] 성공: businessname="${data[0].businessname}", name="${data[0].name}"`)
              return data[0]
            }
            console.warn(`[market] users[${uid}] 데이터 없음:`, text.slice(0, 100))
            return null
          } catch (e: any) {
            console.error(`[market] users[${uid}] fetch 예외:`, e.message)
            return null
          }
        })
      )
      userResults.forEach((u: any) => { if (u?.id) usersMap[u.id] = u })
      console.log(`[market] public.users 조회 완료: ${Object.keys(usersMap).length}/${bidderIds.length}`)
    }

    // ── 3단계: public.users에 없거나 이름이 기본값인 경우 auth.users Admin API로 보완 ────
    const needsEnhance = bidderIds.filter(uid => {
      const u = usersMap[uid]
      if (!u) return true  // public.users에 없음
      // 상호명이 비어있거나 기본값이면 auth에서 보완 시도 (이름 여부와 무관)
      return isGenericName(u.businessname)
    })
    if (needsEnhance.length > 0) {
      console.warn(`[market] getBids auth-enhance for ${needsEnhance.length} users:`, needsEnhance)
      await Promise.all(needsEnhance.map(async (uid) => {
        const authUser = await fetchAuthUser(uid)
        if (authUser) {
          const existing = usersMap[uid] || {}
          // 상호명: 기존 public.users 값이 좋으면 유지, 아니면 auth 값 사용
          const mergedBusinessname = !isGenericName(existing.businessname)
            ? existing.businessname
            : authUser.businessname
          // 개인 이름: 기존 값 우선
          const mergedName = !isGenericName(existing.name)
            ? existing.name
            : authUser.name
          usersMap[uid] = { ...existing, ...authUser, businessname: mergedBusinessname, name: mergedName }
        }
      }))
    }

    // ── 병합 ─────────────────────────────────────────────────────────
    const merged = bids.map((b: any) => ({
      ...b,
      bidder: usersMap[b.bidder_id] || null,
    }))

    const foundCount = merged.filter((b: any) => b.bidder !== null).length
    console.log(`[market] getBids done: ${merged.length} bids, ${foundCount} with bidder info`)

    return { statusCode: 200, body: JSON.stringify(merged), headers: { 'Content-Type': 'application/json' } }

  } catch (error: any) {
    console.error('[market] get bids error:', error.message)
    return { statusCode: 500, body: JSON.stringify({ message: '입찰 목록 조회 실패', error: error.message }), headers: { 'Content-Type': 'application/json' } }
  }
}

async function handleListBids(event: any) {
  const params = event.queryStringParameters || {}
  const { bidderId, status, statuses } = params

  const filters: string[] = []
  if (bidderId) {
    filters.push(`bidder_id=eq.${encodeURIComponent(bidderId)}`)
  }
  if (statuses) {
    const statusList = statuses.split(',').map((s: string) => s.trim()).filter(Boolean)
    if (statusList.length > 0) {
      filters.push(`status=in.(${statusList.map((s: string) => encodeURIComponent(s)).join(',')})`)
    }
  } else if (status) {
    filters.push(`status=eq.${encodeURIComponent(status)}`)
  }
  filters.push('order=created_at.desc')

  const qs = filters.join('&')
  const selects = [
    '*,marketplace_listings(id,title,status,region,category,description,web_order_id)',
    '*',
  ]

  let data: any = null
  for (const select of selects) {
    const response = await fetch(
      `${SUPABASE_URL}/rest/v1/order_bids?select=${encodeURIComponent(select)}&${qs}`,
      {
        headers: {
          apikey: SUPABASE_SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
        }
      }
    )
    data = await response.json()
    if (response.ok && Array.isArray(data)) break
    console.warn('[market] list bids select failed:', select, data)
  }

  if (!Array.isArray(data)) {
    console.error('[market] list bids error:', data)
    return jsonRes(500, { message: '입찰 목록 조회 실패' })
  }

  return { statusCode: 200, body: JSON.stringify(data), headers: { 'Content-Type': 'application/json' } }
}

async function handleSelectBidder(event: any, path: string) {
  const id = listingIdFromPath(path)
  const body = JSON.parse(event.body || '{}')
  const { bidderId, ownerId } = body

  console.log(`[handleSelectBidder] 시작:`, { id, bidderId, ownerId })

  if (!bidderId || !ownerId) {
    return { statusCode: 400, body: JSON.stringify({ message: 'bidderId, ownerId는 필수입니다' }), headers: { 'Content-Type': 'application/json' } };
  }

  try {
    console.log(`[handleSelectBidder] RPC 호출 중...`)
    const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/select_bidder`, {
      method: 'POST',
      headers: {
        apikey: SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        p_listing_id: id,
        p_bidder_id: bidderId,
        p_owner_id: ownerId,
      })
    })

    const data = await response.json()
    console.log(`[handleSelectBidder] RPC 응답:`, { status: response.status, data })

    if (!response.ok) {
      console.error(`[handleSelectBidder] RPC 실패:`, data)
      const detail = [data?.message, data?.hint, data?.details].filter(Boolean).join(' ')
      // 업무 규칙 차단은 500이 아니라 200 + code로 내려야 클라이언트가
      // 'HTTP 500' 대신 실제 안내 문구를 보여줄 수 있습니다.
      if (detail.includes('BIDDER_NOT_VERIFIED')) {
        return jsonRes(200, { success: false, code: 'BIDDER_NOT_VERIFIED', message: detail })
      }
      throw new Error(detail || 'Select bidder failed')
    }

    // 알림/채팅 생성이 느려도 낙찰(select_bidder RPC)은 이미 커밋된 상태입니다.
    // 응답을 막으면 타임아웃 시 클라이언트가 실패로 오인해 재시도하고,
    // 알림·채팅방이 중복 생성됩니다.
    const sideEffects = (async () => {
    try {
      // 오더 정보 조회
      const listingResponse = await fetch(
        `${SUPABASE_URL}/rest/v1/marketplace_listings?id=eq.${id}&select=title,jobid`,
        {
          headers: {
            apikey: SUPABASE_SERVICE_ROLE_KEY,
            Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
          }
        }
      )
      const listings = await listingResponse.json()
      const listing = Array.isArray(listings) && listings.length > 0 ? listings[0] : null

      if (listing) {
        const nowIso = new Date().toISOString()

        // 선택된 입찰자에게 알림
        const selectedTitle = '오더 선택됨'
        const selectedBody = `${listing.title || '오더'}에 선택되었습니다!`
        
        const selectedNotifResponse = await fetch(`${SUPABASE_URL}/rest/v1/notifications`, {
          method: 'POST',
          headers: {
            apikey: SUPABASE_SERVICE_ROLE_KEY,
            Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
            'Content-Type': 'application/json',
            'Prefer': 'return=representation',
          },
          body: JSON.stringify({
            userid: bidderId,
            title: selectedTitle,
            body: selectedBody,
            type: 'bid_selected',
            jobid: listing.jobid,
            isread: false,
            createdat: nowIso,
          })
        })
        
        if (!selectedNotifResponse.ok) {
          console.warn('[market] 선택 알림 생성 실패:', await selectedNotifResponse.text())
        } else {
          console.log('[market] 선택 알림 생성 완료')
        }

        // 📌 DB INSERT → Supabase DB Webhook이 자동으로 FCM push 발송 (중복 방지)

        // 거절된 입찰자들에게 알림
        const rejectedResponse = await fetch(
          `${SUPABASE_URL}/rest/v1/order_bids?listing_id=eq.${id}&status=eq.rejected&select=bidder_id`,
          {
            headers: {
              apikey: SUPABASE_SERVICE_ROLE_KEY,
              Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
            }
          }
        )
        const rejectedBids = await rejectedResponse.json()

        if (Array.isArray(rejectedBids) && rejectedBids.length > 0) {
          const rejectedTitle = '입찰 결과 안내'
          const rejectedBody = '입찰하신 견적이 다른 사업자께 낙찰 되었어요.. 다른 견적에 입찰을 시도해 보세요!'

          // 각 거절된 입찰자에게 DB 알림 (webhook이 자동으로 FCM push 발송)
          for (const bid of rejectedBids) {
            const rejectedNotifResponse = await fetch(`${SUPABASE_URL}/rest/v1/notifications`, {
              method: 'POST',
              headers: {
                apikey: SUPABASE_SERVICE_ROLE_KEY,
                Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
                'Content-Type': 'application/json',
                'Prefer': 'return=representation',
              },
              body: JSON.stringify({
                userid: bid.bidder_id,
                title: rejectedTitle,
                body: rejectedBody,
                type: 'bid_rejected',
                jobid: listing.jobid,
                isread: false,
                createdat: nowIso,
              })
            })
            if (!rejectedNotifResponse.ok) {
              console.warn('[market] 거절 알림 생성 실패:', await rejectedNotifResponse.text())
            }
          }
        }
        
        // 채팅방 생성 (오더 소유자와 선택된 입찰자 간)
        try {
          const ownerResponse = await fetch(
            `${SUPABASE_URL}/rest/v1/marketplace_listings?id=eq.${id}&select=posted_by`,
            {
              headers: {
                apikey: SUPABASE_SERVICE_ROLE_KEY,
                Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
              }
            }
          )
          const ownerData = await ownerResponse.json()
          const owner = Array.isArray(ownerData) && ownerData.length > 0 ? ownerData[0] : null
          
          if (owner && owner.posted_by) {
            const roomId = `order_${id}`
            console.log('[market] 채팅방 생성 중:', { roomId, owner: owner.posted_by, bidder: bidderId })
            
            // 채팅방 생성 (upsert)
            const chatRoomResponse = await fetch(`${SUPABASE_URL}/rest/v1/chat_rooms`, {
              method: 'POST',
              headers: {
                apikey: SUPABASE_SERVICE_ROLE_KEY,
                Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
                'Content-Type': 'application/json',
                'Prefer': 'resolution=merge-duplicates',
              },
              body: JSON.stringify({
                id: roomId,
                listingid: id,
                jobid: listing.jobid,
                participant_a: owner.posted_by,
                participant_b: bidderId,
                createdat: nowIso,
                updatedat: nowIso,
                active: true,
              })
            })
            
            if (!chatRoomResponse.ok) {
              console.warn('[market] 채팅방 생성 실패:', await chatRoomResponse.text())
            } else {
              console.log('[market] 채팅방 생성 완료:', roomId)
              
              // 시스템 메시지 추가
              const messageResponse = await fetch(`${SUPABASE_URL}/rest/v1/chat_messages`, {
                method: 'POST',
                headers: {
                  apikey: SUPABASE_SERVICE_ROLE_KEY,
                  Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
                  'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                  room_id: roomId,
                  sender_id: owner.posted_by,
                  content: '안녕하세요, 오더 관련 채팅방입니다',
                  type: 'system',
                  createdat: nowIso,
                })
              })
              
              if (!messageResponse.ok) {
                console.warn('[market] 시스템 메시지 생성 실패:', await messageResponse.text())
              } else {
                console.log('[market] 시스템 메시지 생성 완료')
              }
            }
          }
        } catch (chatErr: any) {
          console.warn('[market] 채팅방 생성 실패 (무시):', chatErr.message)
        }
      }
    } catch (e: any) {
      console.warn('[market] notification/push failed:', e.message)
    }
    })()

    try {
      await runWithTimeout(sideEffects, 6000)
    } catch (e: any) {
      console.warn('[market] select-bidder side effects skipped:', e.message)
    }

    return jsonRes(200, { success: true })
  } catch (error: any) {
    console.error('[handleSelectBidder] 에러:', error.message)
    return { statusCode: 500, body: JSON.stringify({ 
      success: false,
      message: error.message || '입찰자 선택 실패',
      error: error.message 
    }), headers: { 'Content-Type': 'application/json' } };
  }
}

async function handleDeleteBid(event: any, path: string) {
  const listingId = listingIdFromPath(path, 'bids')
  const params = event.queryStringParameters || {}
  const { bidderId } = params

  console.log(`[handleDeleteBid] listingId=${listingId}, bidderId=${bidderId}`)

  if (!listingId) {
    return { statusCode: 400, body: JSON.stringify({ success: false, message: 'listing id는 필수입니다' }), headers: { 'Content-Type': 'application/json' } };
  }
  if (!bidderId) {
    return { statusCode: 400, body: JSON.stringify({ success: false, message: 'bidderId는 필수입니다' }), headers: { 'Content-Type': 'application/json' } };
  }

  try {
    // Service Role로 RLS 우회하여 삭제
    const response = await fetch(
      `${SUPABASE_URL}/rest/v1/order_bids?listing_id=eq.${encodeURIComponent(listingId)}&bidder_id=eq.${encodeURIComponent(bidderId)}`,
      {
        method: 'DELETE',
        headers: {
          apikey: SUPABASE_SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
          'Prefer': 'return=representation',
        }
      }
    )

    if (!response.ok) {
      const errorText = await response.text()
      console.error('[handleDeleteBid] DELETE 실패:', errorText)
      return { statusCode: response.status, body: JSON.stringify({ success: false, message: '입찰 삭제 실패' }), headers: { 'Content-Type': 'application/json' } };
    }

    const data = await response.json()
    const deletedCount = Array.isArray(data) ? data.length : 0
    
    console.log(`[handleDeleteBid] ${deletedCount}개 행 삭제 완료`)

    // 이미 삭제된 입찰이면 취소 목적은 달성된 상태이므로 성공으로 응답합니다.
    // (재시도/중복 탭에서 실패로 보이지 않게 하기 위함)
    if (deletedCount === 0) {
      return { statusCode: 200, body: JSON.stringify({ success: true, deleted: 0, alreadyDeleted: true, message: '이미 취소된 입찰입니다' }), headers: { 'Content-Type': 'application/json' } };
    }

    return { statusCode: 200, body: JSON.stringify({ success: true, deleted: deletedCount }), headers: { 'Content-Type': 'application/json' } };
  } catch (error: any) {
    console.error('[handleDeleteBid] error:', error.message)
    return { statusCode: 500, body: JSON.stringify({ success: false, message: '입찰 삭제 실패', error: error.message }), headers: { 'Content-Type': 'application/json' } };
  }
}

