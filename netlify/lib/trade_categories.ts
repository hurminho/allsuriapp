/**
 * 공종 목록 (대분류 → 세부 공종). 앱(lib/config/trade_categories.dart)·웹(allsuri-web lib/trade-categories.ts)·
 * DB 이전 SQL(database/trade_categories_2026_10.sql)과 같은 내용이어야 합니다.
 * orders.category 에는 대분류, orders.subcategory 에는 세부 공종이 들어갑니다.
 */
export type TradeGroup = { name: string; kind: '설비' | '청소' | '기타'; icon: string; items: string[] }

export const TRADE_GROUPS: TradeGroup[] = [
  { name: '하수구·막힘', kind: '설비', icon: '🚽', items: ['하수구·배수구 막힘', '변기 막힘', '싱크대 막힘', '세면대·욕조 막힘', '고압세척(배관 청소)', '배관 내시경 점검', '오수·배수 펌프'] },
  { name: '누수·방수', kind: '설비', icon: '💧', items: ['누수 탐지', '누수 보수', '욕실 방수', '옥상·외벽 방수', '베란다·발코니 방수', '실리콘·코킹', '지하·승강기 피트 물빼기'] },
  { name: '수도·급수', kind: '설비', icon: '🚰', items: ['수전·샤워기 교체', '세면대·양변기 설치·교체', '수도 배관 수리·교체', '동파·계량기', '급수펌프·물탱크', '정수기·연수기 설치'] },
  { name: '보일러·난방', kind: '설비', icon: '🔥', items: ['보일러 수리', '보일러 교체', '난방 배관 청소', '분배기 교체', '온수기 설치·수리', '바닥 난방'] },
  { name: '에어컨·공조', kind: '설비', icon: '❄️', items: ['에어컨 설치·이전', '에어컨 수리·가스 충전', '시스템 에어컨', '환기·전열교환기', '덕트·배기'] },
  { name: '전기', kind: '설비', icon: '💡', items: ['콘센트·스위치', '조명 교체·설치', '차단기·누전', '배선·증설', '인터폰·도어락'] },
  { name: '주방·욕실 설비', kind: '설비', icon: '🛁', items: ['싱크대 교체', '주방 후드', '욕실 부분 공사', '타일·줄눈 보수'] },
  { name: '입주·이사 청소', kind: '청소', icon: '🧹', items: ['입주 청소', '이사 청소', '거주 중 청소', '준공·공사 후 청소'] },
  { name: '상가·건물 청소', kind: '청소', icon: '🏢', items: ['사무실·상가 청소', '계단·건물 정기 청소', '유리창·외벽 청소', '바닥 왁스·광택'] },
  { name: '가전·설비 청소', kind: '청소', icon: '🧼', items: ['에어컨 분해 세척', '세탁기 분해 세척', '주방 후드 청소', '보일러·난방 배관 청소'] },
  { name: '위생·특수 청소', kind: '청소', icon: '🦠', items: ['욕실 곰팡이 제거', '줄눈 시공', '소독·방역·해충', '저수조·정화조 청소', '매트리스·소파 클리닝', '특수 청소'] },
  { name: '기타', kind: '기타', icon: '🛠️', items: [] },
]

export const TRADE_GROUP_NAMES = TRADE_GROUPS.map((g) => g.name)

/** 예전 값(오더 분류·사업자 전문분야) → 대분류. 앱·DB 이전 SQL 과 같은 표입니다. */
export const LEGACY_CATEGORY_MAP: Record<string, string> = {
  수도: '수도·급수', 배관: '수도·급수', 난방: '보일러·난방', 에어컨: '에어컨·공조',
  누수: '누수·방수', 방수: '누수·방수', 화장실: '주방·욕실 설비', 주방: '주방·욕실 설비',
  일반: '기타', 인테리어: '기타', 리모델링: '기타', 청소: '기타',
  배수장치: '하수구·막힘', 급수장치: '수도·급수', 정수기: '수도·급수',
  온수기: '보일러·난방', 보일러: '보일러·난방', 히터: '보일러·난방', 전기히터: '보일러·난방',
  온풍기: '보일러·난방', 전기장판: '보일러·난방', 전기담요: '보일러·난방',
  냉난방기: '에어컨·공조', 공조기: '에어컨·공조', 환기장치: '에어컨·공조',
  도어락: '전기', 인터폰: '전기', CCTV: '전기', 보안설비: '전기', 자동문: '전기',
  가스레인지: '주방·욕실 설비', 식기세척기: '주방·욕실 설비',
}

export function tradeGroup(name: string): TradeGroup | undefined {
  return TRADE_GROUPS.find((g) => g.name === name)
}

/** 값(대분류·세부 공종·예전 값)이 속한 대분류. 모르는 값은 '기타'. */
export function groupOf(value: string | null | undefined): string {
  const v = String(value ?? '').trim()
  if (!v) return '기타'
  const hit = TRADE_GROUPS.find((g) => g.name === v || g.items.includes(v))
  return hit ? hit.name : LEGACY_CATEGORY_MAP[v] ?? '기타'
}

/** 가격 카탈로그 공정(세부 이름) → 대분류. 카탈로그는 예전 분류(배관·화장실·누수·방수·주방)를 씁니다. */
export const PRICE_TRADE_GROUP: Record<string, string> = {
  '변기 막힘': '하수구·막힘', '싱크대 막힘': '하수구·막힘', '단순 배관 막힘': '하수구·막힘', '주방 배수 문제': '하수구·막힘',
  '세면대·수전 교체': '수도·급수', '샤워기 교체': '수도·급수',
  '누수 탐지': '누수·방수', '배관 누수 보수': '누수·방수', '실리콘·코킹 보수': '누수·방수', '소규모 방수 보수': '누수·방수',
}

/** 가격 카탈로그 공정이 속한 대분류 */
export function priceTradeGroup(trade: { category?: string | null; subcategory?: string | null }): string {
  const sub = String(trade.subcategory ?? '')
  return PRICE_TRADE_GROUP[sub] ?? (groupOf(sub) !== '기타' ? groupOf(sub) : groupOf(trade.category))
}
