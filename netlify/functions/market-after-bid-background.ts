import crypto from 'crypto'
import { afterBidInserted } from '../lib/market_after_bid'

const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY as string

function parseBody(event: any): Record<string, unknown> {
  const raw = event?.body
  if (raw && typeof raw === 'object') return raw as Record<string, unknown>
  let text = String(raw || '{}')
  if (event?.isBase64Encoded) {
    text = Buffer.from(text, 'base64').toString('utf8')
  }
  try {
    const parsed = JSON.parse(text || '{}')
    return parsed && typeof parsed === 'object' ? parsed : {}
  } catch {
    return {}
  }
}

function headerToken(event: any): string {
  const headers = event?.headers || {}
  const auth = String(
    headers.authorization ||
      headers.Authorization ||
      headers['x-allsuri-internal'] ||
      headers['X-Allsuri-Internal'] ||
      '',
  )
  return auth.replace(/^Bearer\s+/i, '').trim()
}

function expectedHmac(listingId: string, businessId: string): string {
  return crypto
    .createHmac('sha256', SUPABASE_SERVICE_ROLE_KEY || 'missing')
    .update(`${listingId}:${businessId}`)
    .digest('hex')
}

function authorized(event: any, body: Record<string, unknown>, listingId: string, businessId: string): boolean {
  if (!SUPABASE_SERVICE_ROLE_KEY) return false
  const token = headerToken(event)
  if (token && token === SUPABASE_SERVICE_ROLE_KEY) return true
  const t = String(body.t || '')
  const expected = expectedHmac(listingId, businessId)
  if (t && expected && t === expected) return true
  return false
}

/// 입찰 HTTP 응답을 막지 않도록 문자/알림만 백그라운드에서 처리합니다.
export const handler = async (event: any) => {
  const body = parseBody(event)
  const listingId = String(body.listingId || '')
  const businessId = String(body.businessId || '')
  console.log(
    `[market-after-bid-background] invoked listing=${listingId || 'none'} headerKeys=${Object.keys(event?.headers || {}).join(',')}`,
  )

  if (!listingId || !businessId) {
    console.warn('[market-after-bid-background] missing listingId/businessId')
    return { statusCode: 400, body: 'listingId and businessId required' }
  }

  if (!authorized(event, body, listingId, businessId)) {
    console.warn('[market-after-bid-background] unauthorized — SMS will not send')
    return { statusCode: 401, body: 'unauthorized' }
  }

  try {
    await afterBidInserted({
      listingId,
      businessId,
      bidAmount: body.bidAmount,
    })
    console.log(`[market-after-bid-background] done listing=${listingId}`)
    return { statusCode: 200, body: 'ok' }
  } catch (e: any) {
    console.warn('[market-after-bid-background] failed:', e?.message)
    return { statusCode: 500, body: e?.message || 'failed' }
  }
}
