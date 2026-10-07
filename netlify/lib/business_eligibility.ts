// 사업자 활동 가능 여부 (입찰·가져가기·낙찰 대상).
//
// 기준은 DB 함수 fn_business_can_act 와 같습니다: 사업자 계정 + 승인(approved)
// + (사업자등록번호 등록 또는 관리자 우회). B2B 낙찰(select_bidder)은 이 함수로
// 막고 있었지만 입찰·웹 낙찰은 확인하지 않아, 승인 대기 계정도 입찰할 수 있었습니다.

export const NOT_ELIGIBLE_MESSAGE =
  '사업자 승인과 사업자등록번호 등록이 끝나야 지원할 수 있습니다. 프로필에서 사업자 정보를 확인해 주세요.'

function headers() {
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY as string
  return { apikey: key, Authorization: `Bearer ${key}` }
}

type EligibilityRow = {
  role?: string | null
  businessstatus?: string | null
  businessnumber?: string | null
  businessnumber_norm?: string | null
  business_verify_bypass?: boolean | null
}

/** fn_business_can_act 를 쓸 수 없을 때의 같은 판정. */
export function canActFromRow(row: EligibilityRow | null | undefined): boolean {
  if (!row) return false
  if (row.role !== 'business') return false
  if (String(row.businessstatus || '') !== 'approved') return false
  if (row.business_verify_bypass === true) return true
  if (row.businessnumber_norm) return true
  return String(row.businessnumber || '').replace(/[^0-9]/g, '').length === 10
}

export async function businessCanAct(userId: string): Promise<boolean> {
  const SUPABASE_URL = process.env.SUPABASE_URL as string
  if (!userId) return false
  try {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/fn_business_can_act`, {
      method: 'POST',
      headers: { ...headers(), 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_uid: userId }),
    })
    if (res.ok) {
      const data = await res.json().catch(() => null)
      if (typeof data === 'boolean') return data
    }
  } catch {
    // 아래 직접 조회로 판정합니다.
  }
  try {
    const res = await fetch(
      `${SUPABASE_URL}/rest/v1/users?id=eq.${encodeURIComponent(userId)}` +
        `&select=role,businessstatus,businessnumber,businessnumber_norm,business_verify_bypass&limit=1`,
      { headers: headers() },
    )
    if (!res.ok) return false
    const rows = await res.json().catch(() => [])
    return canActFromRow(Array.isArray(rows) ? rows[0] : null)
  } catch {
    return false
  }
}
