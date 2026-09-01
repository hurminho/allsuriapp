import { formatRating, formatWon, sendBidReceivedSms } from './solapi_sms'

const SUPABASE_URL = process.env.SUPABASE_URL as string
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY as string

/** notifications.jobid → jobs.id FK. 리스팅 id를 넣으면 웹 오더에서 23503이 납니다. */
function notificationRow(opts: {
  userid: string
  title: string
  body: string
  type: string
  jobid?: string | null
}) {
  const row: Record<string, unknown> = {
    userid: opts.userid,
    title: opts.title,
    body: opts.body,
    type: opts.type,
    isread: false,
    createdat: new Date().toISOString(),
  }
  if (opts.jobid) row.jobid = opts.jobid
  return row
}

export async function afterBidInserted(opts: {
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
        `${SUPABASE_URL}/rest/v1/marketplace_listings?id=eq.${id}&select=title,posted_by,web_order_id,jobid`,
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
      console.log(`   - Listing: ${listing?.title} (${id})`)
      console.log(`   - web_order_id: ${listing?.web_order_id || '없음'}`)
      console.log(`   - jobid: ${listing?.jobid || '없음(웹 오더는 jobs 없음)'}`)
      console.log(`   - 오더 소유자: ${listing?.posted_by || '없음(웹 고객)'}`)
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
            } else {
              console.log('[market] 웹 오더 문자 발송 완료')
            }
          } else {
            console.warn('[market] 웹 오더 전화번호 없음 - 문자 스킵')
          }
        } catch (e: any) {
          console.warn('[market] 웹 오더 문자 발송 실패 (무시):', e.message)
        }
      }

      if (listing) {
        const jobIdForNotif = listing.jobid || null

        // 1. 오더 소유자에게 알림 (앱 사업자 오더만. 웹 고객은 posted_by 없음 → 문자로 안내)
        if (listing.posted_by) {
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
            body: JSON.stringify(notificationRow({
              userid: listing.posted_by,
              title: ownerNotificationTitle,
              body: ownerNotificationBody,
              type: 'new_bid',
              jobid: jobIdForNotif,
            })),
          })

          if (!ownerNotifResponse.ok) {
            const errText = await ownerNotifResponse.text()
            console.warn(`[market] ❌ 오더 소유자 알림 생성 실패: ${errText}`)
          } else {
            const ownerNotifData = await ownerNotifResponse.json()
            console.log(`[market] ✅ 오더 소유자 알림 생성 완료:`, ownerNotifData)
          }
        } else {
          console.log('[market] 웹 오더 — 앱 소유자 알림 생략 (고객은 문자)')
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
          body: JSON.stringify(notificationRow({
            userid: businessId,
            title: bidderNotificationTitle,
            body: bidderNotificationBody,
            type: 'bid_pending',
            jobid: jobIdForNotif,
          })),
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
