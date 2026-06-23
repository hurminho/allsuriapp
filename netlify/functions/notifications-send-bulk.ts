/// <reference types="node" />
// Netlify Function: FCM 푸시 알림 일괄 전송
// POST /api/notifications/send-bulk → 서버에서 여러 사용자에게 일괄 발송
// 앱은 1회 호출, 서버가 DB 저장 + FCM 전송 처리

const SUPABASE_URL = process.env.SUPABASE_URL as string
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY as string
const FIREBASE_SERVICE_ACCOUNT_KEY = process.env.FIREBASE_SERVICE_ACCOUNT_KEY as string

const JSON_HEADERS = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
}

let _cachedToken: string | null = null
let _tokenExpiry = 0

async function getGoogleAccessToken(): Promise<string | null> {
  if (_cachedToken && Date.now() < _tokenExpiry) return _cachedToken
  if (!FIREBASE_SERVICE_ACCOUNT_KEY) {
    console.error('[FCM Bulk] FIREBASE_SERVICE_ACCOUNT_KEY 환경변수 미설정')
    return null
  }
  try {
    const serviceAccount = JSON.parse(FIREBASE_SERVICE_ACCOUNT_KEY)
    const { private_key, client_email } = serviceAccount
    if (!private_key || !client_email) return null

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

    const { createSign } = await import('crypto')
    const sign = createSign('RSA-SHA256')
    sign.update(unsigned)
    const signature = sign.sign(private_key, 'base64url')
    const jwt = `${unsigned}.${signature}`

    const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: jwt,
      }),
    })

    const tokenData = (await tokenRes.json()) as any
    if (!tokenRes.ok || !tokenData.access_token) return null

    _cachedToken = tokenData.access_token as string
    _tokenExpiry = Date.now() + (tokenData.expires_in - 60) * 1000
    return _cachedToken
  } catch (e: any) {
    console.error('[FCM Bulk] OAuth2 토큰 오류:', e.message)
    return null
  }
}

// 단일 사용자 FCM 전송 (결과만 반환)
async function sendFCMToUser(
  userId: string,
  title: string,
  msgBody: string,
  data: Record<string, string>,
  accessToken: string,
  serviceAccount: any
): Promise<{ sent: boolean; reason?: string }> {
  const userRes = await fetch(
    `${SUPABASE_URL}/rest/v1/users?id=eq.${encodeURIComponent(userId)}&select=fcm_token`,
    {
      headers: {
        apikey: SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
      },
    }
  )
  const users = (await userRes.json()) as any[]
  const fcmToken: string | null =
    Array.isArray(users) && users[0]?.fcm_token ? users[0].fcm_token : null

  if (!fcmToken) {
    return { sent: false, reason: 'no_fcm_token' }
  }

  let unreadCount = 1
  try {
    const unreadRes = await fetch(
      `${SUPABASE_URL}/rest/v1/notifications?userid=eq.${encodeURIComponent(userId)}&isread=eq.false&select=id`,
      {
        headers: {
          apikey: SUPABASE_SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
        },
      }
    )
    const unreadData = (await unreadRes.json()) as any[]
    unreadCount = (Array.isArray(unreadData) ? unreadData.length : 0) + 1
  } catch (_) {}

  const safeData: Record<string, string> = {
    sentAt: new Date().toISOString(),
    badge: String(unreadCount),
    ...data,
  }

  const fcmRes = await fetch(
    `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify({
        message: {
          token: fcmToken,
          notification: { title, body: msgBody },
          data: safeData,
          android: {
            priority: 'high',
            notification: {
              channel_id: 'allsuri_notifications',
              sound: 'default',
              notification_count: unreadCount,
            },
          },
          apns: {
            payload: { aps: { sound: 'default', badge: unreadCount } },
          },
        },
      }),
    }
  )

  const fcmResult = (await fcmRes.json()) as any
  if (!fcmRes.ok) {
    return {
      sent: false,
      reason: fcmResult?.error?.message || 'fcm_error',
    }
  }
  return { sent: true }
}

const delay = (ms: number) => new Promise((r) => setTimeout(r, ms))

export const handler = async (event: any) => {
  if (event.httpMethod === 'OPTIONS') {
    return {
      statusCode: 204,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      },
      body: '',
    }
  }

  if (event.httpMethod !== 'POST') {
    return {
      statusCode: 405,
      body: JSON.stringify({ error: 'Method Not Allowed' }),
      headers: JSON_HEADERS,
    }
  }

  try {
    // ── 1. 인증 ───────────────────────────────────────────────────────
    const authHeader =
      (event.headers['authorization'] || event.headers['Authorization'] ||
        '') as string
    const token = authHeader.replace(/^Bearer\s+/i, '').trim()
    if (!token) {
      return {
        statusCode: 401,
        body: JSON.stringify({ error: 'Authorization header required' }),
        headers: JSON_HEADERS,
      }
    }

    const ADMIN_TOKEN =
      process.env.ADMIN_TOKEN || process.env.ADMIN_DEVELOPER_TOKEN || ''
    const isAdminToken = ADMIN_TOKEN && token === ADMIN_TOKEN
    // allsuri-web 등 서버 간 호출: Supabase service_role 키도 허용
    const isServiceRole = SUPABASE_SERVICE_ROLE_KEY && token === SUPABASE_SERVICE_ROLE_KEY

    if (!isAdminToken && !isServiceRole) {
      const verifyRes = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
        headers: {
          apikey: SUPABASE_SERVICE_ROLE_KEY,
          Authorization: `Bearer ${token}`,
        },
      })
      if (!verifyRes.ok) {
        return {
          statusCode: 401,
          body: JSON.stringify({ error: 'Invalid token' }),
          headers: JSON_HEADERS,
        }
      }
    }

    // ── 2. 요청 파싱 ─────────────────────────────────────────────────
    const body = JSON.parse(event.body || '{}')
    const { userIds, title, body: msgBody, data = {}, skipDbInsert = false } = body

    if (
      !Array.isArray(userIds) ||
      userIds.length === 0 ||
      !title ||
      !msgBody
    ) {
      return {
        statusCode: 400,
        body: JSON.stringify({
          error: 'userIds (array), title, body are required',
        }),
        headers: JSON_HEADERS,
      }
    }

    // 최대 500명 제한
    const ids = userIds.slice(0, 500)
    const now = new Date().toISOString()

    // ── 3. DB 일괄 저장 (skipDbInsert=true 이면 호출자가 이미 저장한 것) ──
    const safeData = data as Record<string, string>
    const rows = ids.map((uid: string) => ({
      userid: uid,
      title,
      body: msgBody,
      type: safeData.type || '',
      isread: false,
      createdat: now,
      ...(safeData.orderId && { orderid: safeData.orderId }),
      ...(safeData.jobTitle && { jobtitle: safeData.jobTitle }),
      ...(safeData.region && { region: safeData.region }),
    }))

    if (!skipDbInsert) {
      try {
        const insertRes = await fetch(`${SUPABASE_URL}/rest/v1/notifications`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            apikey: SUPABASE_SERVICE_ROLE_KEY,
            Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
            Prefer: 'return=minimal',
          },
          body: JSON.stringify(rows),
        })
        if (!insertRes.ok) {
          const err = await insertRes.text()
          console.error('[FCM Bulk] DB insert 실패:', err)
          return {
            statusCode: 500,
            body: JSON.stringify({ error: 'DB insert failed' }),
            headers: JSON_HEADERS,
          }
        }
      } catch (e: any) {
        console.error('[FCM Bulk] DB insert 예외:', e.message)
        return {
          statusCode: 500,
          body: JSON.stringify({ error: e.message }),
          headers: JSON_HEADERS,
        }
      }
    }

    // ── 4. FCM은 notifications INSERT Webhook(send-push-webhook)에서 1회 발송 ──
    console.log(`[FCM Bulk] DB 저장 완료: ${ids.length}건 → Webhook이 FCM 발송`)

    return {
      statusCode: 200,
      body: JSON.stringify({
        total: ids.length,
        sent: ids.length,
        failed: 0,
        delivery: 'webhook',
      }),
      headers: JSON_HEADERS,
    }
  } catch (e: any) {
    console.error('[FCM Bulk] 예외:', e)
    return {
      statusCode: 500,
      body: JSON.stringify({ error: e.message }),
      headers: JSON_HEADERS,
    }
  }
}
