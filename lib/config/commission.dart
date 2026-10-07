/// 플랫폼 수수료율(%). 공사 금액(낙찰된 입찰가) × 이 비율이 수수료입니다.
/// 서버(netlify/lib/commission.ts)·웹(lib/commission.ts)·DB(allsuri_commission_rate)와 같은 값이어야 합니다.
const double kCommissionRatePercent = 10;
