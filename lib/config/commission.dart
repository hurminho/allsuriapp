/// 고객 웹 오더의 플랫폼 수수료율(시스템 유지비, %). 낙찰된 입찰가 × 이 비율.
/// 서버(netlify/lib/commission.ts)·웹(lib/commission.ts)과 같은 값이어야 합니다.
const double kWebOrderCommissionRatePercent = 10;

/// 사업자 간 오더의 수수료율은 오더를 올린 사업자(원청)가 정합니다. 입력칸의 기본값입니다.
/// DB 기본값(public.allsuri_default_commission_rate)과 같은 값이어야 합니다.
const double kDefaultB2BCommissionRatePercent = 10;
