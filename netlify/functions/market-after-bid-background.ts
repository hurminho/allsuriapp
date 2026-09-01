import { afterBidInserted } from '../lib/market_after_bid'

const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY as string

/// 입찰 HTTP 응답을 막지 않도록 문자/알림만 백그라운드에서 처리합니다.
export const handler = async (event: any) => {
  const auth = String(event.headers?.authorization || event.headers?.Authorization || '')
  const token = auth.replace(/^Bearer\s+/i, '').trim()
  if (!SUPABASE_SERVICE_ROLE_KEY || token !== SUPABASE_SERVICE_ROLE_KEY) {
    return { statusCode: 401, body: 'unauthorized' }
  }

  const body = JSON.parse(event.body || '{}')
  const listingId = String(body.listingId || '')
  const businessId = String(body.businessId || '')
  if (!listingId || !businessId) {
    return { statusCode: 400, body: 'listingId and businessId required' }
  }

  try {
    await afterBidInserted({
      listingId,
      businessId,
      bidAmount: body.bidAmount,
    })
    return { statusCode: 200, body: 'ok' }
  } catch (e: any) {
    console.warn('[market-after-bid-background] failed:', e?.message)
    return { statusCode: 500, body: e?.message || 'failed' }
  }
}
