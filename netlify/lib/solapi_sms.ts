import crypto from 'crypto'
import { SMS_TEMPLATE_ENV_KEYS, SMS_TEMPLATES, type SmsTemplateId } from './sms_templates'

const SOLAPI_API_KEY = process.env.SOLAPI_API_KEY || ''
const SOLAPI_API_SECRET = process.env.SOLAPI_API_SECRET || ''
const SOLAPI_SENDER_PHONE = (process.env.SOLAPI_SENDER_PHONE || '').replace(/[^0-9]/g, '')
const DEFAULT_WEB_ORIGIN = 'https://allsuricommerce.netlify.app'

function buildSolapiAuthHeader(): string {
  const date = new Date().toISOString()
  const salt = crypto.randomBytes(16).toString('hex')
  const signature = crypto.createHmac('sha256', SOLAPI_API_SECRET).update(date + salt).digest('hex')
  return `HMAC-SHA256 apiKey=${SOLAPI_API_KEY}, date=${date}, salt=${salt}, signature=${signature}`
}

/** 내 견적 조회 URL. phone이 있으면 입력칸이 채워져 비밀번호만 입력하면 됩니다. */
export function customerOrderUrl(phone?: string): string {
  const base = (process.env.ALLSURI_WEB_URL || DEFAULT_WEB_ORIGIN).replace(/\/$/, '')
  const digits = (phone || '').replace(/[^0-9]/g, '')
  const qs = digits ? `?phone=${encodeURIComponent(digits)}` : ''
  return `${base}/my-order${qs}`
}

export function renderSms(id: SmsTemplateId, vars: Record<string, string>): string {
  const envKey = SMS_TEMPLATE_ENV_KEYS[id]
  const raw = (envKey && process.env[envKey]) || SMS_TEMPLATES[id]
  return raw.replace(/#\{([^}]+)\}/g, (_m, key: string) => vars[key] ?? '')
}

export function formatWon(amount: unknown): string {
  const n = typeof amount === 'number' ? amount : Number(amount)
  if (!Number.isFinite(n) || n <= 0) return '협의'
  const s = Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',')
  return `${s}원`
}

export function formatPhoneDisplay(phone: string): string {
  const d = (phone || '').replace(/[^0-9]/g, '')
  if (d.length === 11) return `${d.slice(0, 3)}-${d.slice(3, 7)}-${d.slice(7)}`
  if (d.length === 10) return `${d.slice(0, 3)}-${d.slice(3, 6)}-${d.slice(6)}`
  return phone || ''
}

export function formatRating(avg: number | null, count: number): string {
  if (avg == null || count <= 0) return '아직 없음'
  return `${avg.toFixed(1)}점 (${count}건)`
}

function clip(s: string, max: number): string {
  const t = (s || '').trim()
  if (!t) return ''
  return t.length <= max ? t : `${t.slice(0, max)}…`
}

export function smsBidReceived(opts: {
  orderTitle: string
  businessName: string
  priceLabel: string
  ratingLabel: string
  link: string
}): string {
  return renderSms('bid_received', {
    오더명: clip(opts.orderTitle, 40),
    상호: clip(opts.businessName, 30),
    견적가: opts.priceLabel,
    평점: opts.ratingLabel,
    링크: opts.link,
  })
}

export function smsBidAwarded(opts: {
  orderTitle: string
  businessName: string
  phoneLabel: string
  link: string
}): string {
  return renderSms('awarded', {
    오더명: clip(opts.orderTitle, 40),
    상호: clip(opts.businessName, 30),
    연락처: opts.phoneLabel,
    링크: opts.link,
  })
}

export function smsWorkDoneReview(opts: {
  orderTitle: string
  link: string
}): string {
  return renderSms('work_done', {
    오더명: clip(opts.orderTitle, 40),
    링크: opts.link,
  })
}

/** Solapi 문자만 발송. 카카오 채널/알림톡 불필요. 설정이 없으면 스킵. */
export async function sendSms(to: string, text: string, subject = '올수리'): Promise<void> {
  if (!SOLAPI_API_KEY || !SOLAPI_API_SECRET || !SOLAPI_SENDER_PHONE) {
    console.warn('[solapi-sms] SOLAPI_API_KEY/SECRET/SENDER_PHONE 미설정 - 발송 스킵')
    return
  }
  const toNormalized = (to || '').replace(/[^0-9]/g, '')
  if (!toNormalized) {
    console.warn('[solapi-sms] 수신번호 없음 - 발송 스킵')
    return
  }
  try {
    const res = await fetch('https://api.solapi.com/messages/v4/send', {
      method: 'POST',
      headers: {
        Authorization: buildSolapiAuthHeader(),
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          to: toNormalized,
          from: SOLAPI_SENDER_PHONE,
          text,
          subject,
          type: 'LMS',
        },
      }),
    })
    const result = await res.json().catch(() => ({}))
    if (!res.ok) {
      console.warn('[solapi-sms] 발송 실패:', JSON.stringify(result))
    } else {
      console.log(`[solapi-sms] 발송 성공 → ***${toNormalized.slice(-4)}`)
    }
  } catch (e: any) {
    console.warn('[solapi-sms] 발송 오류 (무시):', e.message)
  }
}
