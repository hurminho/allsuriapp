/**
 * 고객 웹 오더의 플랫폼 수수료율(시스템 유지비, %). 수수료 = 낙찰된 입찰가 × 이 비율.
 * 사업자 간 오더의 수수료율은 오더를 올린 사업자(원청)가 정합니다(jobs.commission_rate).
 * 앱(lib/config/commission.dart)·웹(lib/commission.ts)과 같은 값이어야 합니다.
 */
export const WEB_ORDER_COMMISSION_RATE = 10
