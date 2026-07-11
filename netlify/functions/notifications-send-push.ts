/// <reference types="node" />
// Netlify Function: FCM 푸시 알림 전송
// firebase-admin 없이 FCM HTTP v1 REST API 직접 호출
// POST /api/notifications/send-push  { userId, title, body, data? }
// GET  /api/notifications/send-push  → 환경변수 설정 상태 확인

const SUPABASE_URL = process.env.SUPABASE_URL as string
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY as string
const FIREBASE_SERVICE_ACCOUNT_KEY = process.env.FIREBASE_SERVICE_ACCOUNT_KEY as string

const JSON_HEADERS = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
}

// Google OAuth2 access token 캐시
let _cachedToken: string | null = null
let _tokenExpiry = 0

/**
 * 서비스 계정 키로 Google OAuth2 access token 발급
 * firebase-admin 없이 순수 HTTP로 구현
 */
async function getGoogleAccessToken(): Promise<string | null> {
  if (_cachedToken && Date.now() < _tokenExpiry) return _cachedToken

  if (!FIREBASE_SERVICE_ACCOUNT_KEY) {
    console.error('[FCM] FIREBASE_SERVICE_ACCOUNT_KEY 환경변수가 설정되지 않았습니다.')
    console.error('  → Netlify 대시보드 > Site configuration > Environment variables 에서 추가하세요')
    return null
  }

  try {
    const serviceAccount = JSON.parse(FIREBASE_SERVICE_ACCOUNT_KEY)
    const { private_key, client_email } = serviceAccount

    if (!private_key || !client_email) {
      console.error('[FCM] 서비스 계정 키에 private_key 또는 client_email이 없습니다.')
      return null
    }

    // JWT 생성 (RS256) - Web Crypto API 사용 (Node.js/Netlify 환경에서 사용 가능)
    const now = Math.floor(Date.now() / 1000)
    const payload = {
      iss: client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }

    const header = { alg: 'RS256', typ: 'JWT' }
    const b64 = (obj: object) =>
      Buffer.from(JSON.stringify(obj)).toString('base64url')
    const unsigned = `${b64(header)}.${b64(payload)}`

    // Node.js crypto로 RS256 서명
    const { createSign } = await import('crypto')
    const sign = createSign('RSA-SHA256')
    sign.update(unsigned)
    const signature = sign.sign(private_key, 'base64url')
    const jwt = `${unsigned}.${signature}`

    // Google OAuth2 토큰 교환
    const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: jwt,
      }),
    })

    const tokenData = await tokenRes.json() as any
    if (!tokenRes.ok || !tokenData.access_token) {
      console.error('[FCM] Google OAuth2 토큰 발급 실패:', JSON.stringify(tokenData))
      return null
    }

    _cachedToken = tokenData.access_token as string
    _tokenExpiry = Date.now() + (tokenData.expires_in - 60) * 1000
    console.log('[FCM] Google OAuth2 토큰 발급 성공')
    return _cachedToken
  } catch (e: any) {
    console.error('[FCM] OAuth2 토큰 발급 오류:', e.message)
    return null
  }
}

// notifications row를 "발송 처리 중"으로 원자적으로 선점(claim)한다.
// push_sent_at이 이미 채워져 있으면(= 다른 요청이 먼저 처리함) false를 반환해
// 같은 row에 대해 FCM이 중복 발송되는 것을 막는다.
// (Webhook 재시도, 대시보드 중복 webhook 설정 등 원인 불문 방어)
async function claimNotificationForPush(id: string): Promise<boolean> {
  if (!id) return true // id가 없으면(구버전 payload 등) 가드 없이 통과
  try {
    const res = await fetch(
      `${SUPABASE_URL}/rest/v1/notifications?id=eq.${encodeURIComponent(id)}&push_sent_at=is.null`,
      {
        method: 'PATCH',
        headers: {
          apikey: SUPABASE_SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
          'Content-Type': 'application/json',
          Prefer: 'return=representation',
        },
        body: JSON.stringify({ push_sent_at: new Date().toISOString() }),
      }
    )
    if (!res.ok) {
      console.warn(`[FCM] push_sent_at claim 실패 (${res.status}) - 가드 없이 진행`)
      return true // 컬럼 미존재(마이그레이션 전) 등의 경우 발송은 계속 진행
    }
    const rows = (await res.json()) as any[]
    return Array.isArray(rows) && rows.length > 0
  } catch (e: any) {
    console.warn('[FCM] push_sent_at claim 예외 - 가드 없이 진행:', e.message)
    return true
  }
}

// Supabase Webhook 경로 처리 (/send-push-webhook)
async function handleSupabaseWebhook(event: any) {
  const ADMIN_TOKEN = process.env.ADMIN_TOKEN || process.env.ADMIN_DEVELOPER_TOKEN || ''
  const authHeader = (event.headers['authorization'] || event.headers['Authorization'] || '') as string
  const token = authHeader.replace(/^Bearer\s+/i, '').trim()

  // 관리자 토큰 검증
  if (!ADMIN_TOKEN || token !== ADMIN_TOKEN) {
    return { statusCode: 401, body: JSON.stringify({ error: 'Unauthorized' }), headers: JSON_HEADERS }
  }

  try {
    const webhookBody = JSON.parse(event.body || '{}')
    const record = webhookBody.record // Supabase webhook payload

    if (!record?.userid || !record?.title || !record?.body) {
      return { statusCode: 200, body: JSON.stringify({ skipped: true, reason: 'missing_fields' }), headers: JSON_HEADERS }
    }

    // 같은 notifications row에 대한 중복 webhook 호출(재시도/중복 설정) 방지
    const claimed = await claimNotificationForPush(record.id)
    if (!claimed) {
      console.log(`[webhook] 이미 발송된 알림 (id=${record.id}) - 중복 발송 스킵`)
      return { statusCode: 200, body: JSON.stringify({ skipped: true, reason: 'already_sent' }), headers: JSON_HEADERS }
    }

    return await sendFCMToUser(record.userid, record.title, record.body, {
      type: record.type || '',
      orderId: record.orderid || '',
      chatRoomId: record.chatroom_id || '',
    })
  } catch (e: any) {
    console.error('[webhook] 오류:', e)
    return { statusCode: 500, body: JSON.stringify({ error: e.message }), headers: JSON_HEADERS }
  }
}

// FCM 전송 공통 함수
async function sendFCMToUser(userId: string, title: string, msgBody: string, data: Record<string, string> = {}) {
  // FCM 토큰 조회
  const userRes = await fetch(
    `${SUPABASE_URL}/rest/v1/users?id=eq.${encodeURIComponent(userId)}&select=fcm_token`,
    { headers: { apikey: SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}` } }
  )
  const users = await userRes.json() as any[]
  const fcmToken: string | null = Array.isArray(users) && users[0]?.fcm_token ? users[0].fcm_token : null

  if (!fcmToken) {
    console.log(`[FCM] userId=${userId} 토큰 없음`)
    return { statusCode: 200, body: JSON.stringify({ sent: false, reason: 'no_fcm_token' }), headers: JSON_HEADERS }
  }

  // 미읽음 수 조회
  let unreadCount = 1
  try {
    const unreadRes = await fetch(
      `${SUPABASE_URL}/rest/v1/notifications?userid=eq.${encodeURIComponent(userId)}&isread=eq.false&select=id`,
      { headers: { apikey: SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}` } }
    )
    const unreadData = await unreadRes.json() as any[]
    unreadCount = (Array.isArray(unreadData) ? unreadData.length : 0) + 1
  } catch (_) {}

  const accessToken = await getGoogleAccessToken()
  if (!accessToken) {
    return { statusCode: 200, body: JSON.stringify({ sent: false, reason: 'firebase_not_configured' }), headers: JSON_HEADERS }
  }

  const serviceAccount = JSON.parse(FIREBASE_SERVICE_ACCOUNT_KEY)
  const safeData: Record<string, string> = { sentAt: new Date().toISOString(), badge: String(unreadCount), ...data }

  const fcmRes = await fetch(
    `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${accessToken}` },
      body: JSON.stringify({
        message: {
          token: fcmToken,
          notification: { title, body: msgBody },
          data: safeData,
          android: { priority: 'high', notification: { channel_id: 'allsuri_notifications', sound: 'default', notification_count: unreadCount } },
          apns: { payload: { aps: { sound: 'default', badge: unreadCount } } },
        },
      }),
    }
  )

  const fcmResult = await fcmRes.json() as any
  if (!fcmRes.ok) {
    console.error(`[FCM] 실패 (${fcmRes.status}):`, JSON.stringify(fcmResult))
    return { statusCode: 200, body: JSON.stringify({ sent: false, reason: 'fcm_error', detail: fcmResult?.error?.message }), headers: JSON_HEADERS }
  }

  console.log(`[FCM] 성공: userId=${userId}, badge=${unreadCount}`)
  return { statusCode: 200, body: JSON.stringify({ sent: true, messageId: fcmResult.name }), headers: JSON_HEADERS }
}

export const handler = async (event: any) => {
  // Supabase Webhook 경로
  const path = (event.path || '').replace(/^\/\.netlify\/functions\/notifications-send-push/, '').replace(/^\/api\/notifications\//, '')
  if (path === 'send-push-webhook' || event.path?.endsWith('/send-push-webhook')) {
    return handleSupabaseWebhook(event)
  }

  // ── GET: 환경변수 진단 엔드포인트 ───────────────────────────────────
  if (event.httpMethod === 'GET') {
    return {
      statusCode: 200,
      body: JSON.stringify({
        status: 'ok',
        env: {
          SUPABASE_URL: !!SUPABASE_URL,
          SUPABASE_SERVICE_ROLE_KEY: !!SUPABASE_SERVICE_ROLE_KEY,
          FIREBASE_SERVICE_ACCOUNT_KEY: !!FIREBASE_SERVICE_ACCOUNT_KEY,
        },
      }),
      headers: JSON_HEADERS,
    }
  }

  if (event.httpMethod === 'OPTIONS') {
    return { statusCode: 204, headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'Content-Type, Authorization' }, body: '' }
  }

  if (event.httpMethod !== 'POST') {
    return { statusCode: 405, body: JSON.stringify({ error: 'Method Not Allowed' }), headers: JSON_HEADERS }
  }

  try {
    // ── 1. 인증 ───────────────────────────────────────────────────────
    const authHeader = (event.headers['authorization'] || event.headers['Authorization'] || '') as string
    const token = authHeader.replace(/^Bearer\s+/i, '').trim()
    if (!token) {
      return { statusCode: 401, body: JSON.stringify({ error: 'Authorization header required' }), headers: JSON_HEADERS }
    }

    // 관리자 토큰으로도 호출 가능 (테스트 및 서버 측 호출용)
    const ADMIN_TOKEN = process.env.ADMIN_TOKEN || process.env.ADMIN_DEVELOPER_TOKEN || ''
    const isAdminToken = ADMIN_TOKEN && token === ADMIN_TOKEN

    if (!isAdminToken) {
      // 일반 Supabase JWT 검증
      const verifyRes = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
        headers: { apikey: SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${token}` },
      })
      if (!verifyRes.ok) {
        console.warn('[send-push] JWT 검증 실패:', verifyRes.status, 'token 앞 20자:', token.substring(0, 20))
        return { statusCode: 401, body: JSON.stringify({ error: 'Invalid token' }), headers: JSON_HEADERS }
      }
    } else {
      console.log('[send-push] 관리자 토큰으로 인증됨')
    }

    // ── 2. 요청 파싱 후 공통 함수 호출 ──────────────────────────────
    const body = JSON.parse(event.body || '{}')
    const { userId, title, body: msgBody, data = {} } = body
    if (!userId || !title || !msgBody) {
      return { statusCode: 400, body: JSON.stringify({ error: 'userId, title, body are required' }), headers: JSON_HEADERS }
    }

    return await sendFCMToUser(userId, title, msgBody, data)

  } catch (e: any) {
    console.error('[send-push] 예외:', e)
    return { statusCode: 500, body: JSON.stringify({ error: e.message }), headers: JSON_HEADERS }
  }
}

