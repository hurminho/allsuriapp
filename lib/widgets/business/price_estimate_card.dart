import 'package:flutter/material.dart';

import '../../models/price_estimate.dart';
import '../../theme/business_theme.dart';

/// 가격 엔진 결과 카드. 상태에 따라 화면이 세 갈래로 갈립니다.
///
///  * 충분  → 예상 범위 + "최근 유사 완료 작업 기준"
///  * 일부  → 넓은 참고 범위 + 참고 배지
///  * 부족  → 숫자 없이 "현장 조건에 따라 차이가 큰 작업"
///
/// 문구는 서버 `uiCopy` 를 그대로 씁니다. 앱에서 금액을 만들거나 보정하지 않습니다.
class PriceEstimateCard extends StatelessWidget {
  const PriceEstimateCard({
    super.key,
    required this.estimate,
    this.loading = false,
    this.onSelectTrade,
    this.compact = false,
    this.title = 'AI 예상 가격 범위',
  });

  final PriceEstimate? estimate;
  final bool loading;
  final ValueChanged<TradeSummary>? onSelectTrade;

  /// 입찰 시트처럼 공간이 좁은 곳에서 요약만 보여줍니다.
  final bool compact;

  /// 고객 화면과 사업자 화면에서 제목이 다릅니다.
  final String title;

  @override
  Widget build(BuildContext context) {
    if (loading) return _shell(child: _loading());

    final e = estimate;
    if (e == null || !e.hasRange) return _shell(child: _insufficient(e));
    return _shell(child: _withRange(e));
  }

  Widget _shell({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BusinessTheme.surface,
        borderRadius: BorderRadius.circular(BusinessTheme.radius),
        border: Border.all(color: BusinessTheme.border),
      ),
      child: child,
    );
  }

  Widget _loading() {
    return Row(
      children: const [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 10),
        Text('예상 범위를 확인하는 중…',
            style: TextStyle(fontSize: 13, color: BusinessTheme.textMuted)),
      ],
    );
  }

  Widget _insufficient(PriceEstimate? e) {
    final headline = e?.headline ?? PriceEstimate.unavailable.headline;
    final body = e?.body ?? PriceEstimate.unavailable.body;
    final candidates = e?.needsTradeSelection == true ? e!.candidates : const <TradeSummary>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.info_outline, size: 18, color: BusinessTheme.textMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(headline,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: BusinessTheme.textPrimary)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(body,
            style: const TextStyle(
                fontSize: 12.5, height: 1.5, color: BusinessTheme.textMuted)),
        if (candidates.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('어떤 작업에 가까운가요?',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: BusinessTheme.textPrimary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: candidates
                .map((t) => ActionChip(
                      label: Text(t.subcategory, style: const TextStyle(fontSize: 12)),
                      onPressed: onSelectTrade == null ? null : () => onSelectTrade!(t),
                    ))
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _withRange(PriceEstimate e) {
    final isPreliminary = e.state == PriceState.preliminary;
    final accent = isPreliminary ? BusinessTheme.warning : BusinessTheme.blue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: BusinessTheme.textMuted)),
            const SizedBox(width: 6),
            if (isPreliminary)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: BusinessTheme.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('참고',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: BusinessTheme.warning)),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${BusinessTheme.formatWon(e.min!)} ~ ${BusinessTheme.formatWon(e.max!)}',
          style: TextStyle(
              fontSize: compact ? 19 : 22,
              fontWeight: FontWeight.bold,
              color: accent,
              letterSpacing: -0.5),
        ),
        const SizedBox(height: 8),
        Text(e.headline,
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: BusinessTheme.textPrimary)),
        if (!compact) ...[
          const SizedBox(height: 4),
          Text(e.body,
              style: const TextStyle(
                  fontSize: 12, height: 1.5, color: BusinessTheme.textMuted)),
        ],
        if (e.factors.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('가격 변동 요인',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: BusinessTheme.textMuted)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: e.factors
                .take(compact ? 4 : 8)
                .map((f) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: BusinessTheme.lightBlue,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(f,
                          style: const TextStyle(
                              fontSize: 11, color: BusinessTheme.navy)),
                    ))
                .toList(),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          '유사 완료 사례 ${e.completedJobCount}건 · 전체 표본 ${e.evidenceCount}건 · 신뢰도 ${e.confidenceLabel}',
          style: const TextStyle(fontSize: 11, color: BusinessTheme.textMuted),
        ),
        if (e.disclaimer.isNotEmpty && !compact) ...[
          const SizedBox(height: 6),
          Text(e.disclaimer,
              style: const TextStyle(
                  fontSize: 11, height: 1.45, color: BusinessTheme.textMuted)),
        ],
      ],
    );
  }
}
