import 'package:flutter/material.dart';

import '../../models/bid_breakdown.dart';
import '../../theme/business_theme.dart';

/// 공사 완료 시 최종 확정금액을 받는 시트.
///
/// 입찰가와 실제 정산금액은 다르기 때문에 완료 시점에 따로 받습니다.
/// 가격 엔진은 이 금액을 1순위 표본으로 씁니다.
/// 건너뛸 수 있게 해 두어, 완료 처리 자체가 막히지 않습니다.
class CompletionAmountSheet extends StatefulWidget {
  const CompletionAmountSheet({
    super.key,
    required this.jobTitle,
    this.suggestedAmount,
  });

  final String jobTitle;

  /// 낙찰가·입찰가를 기본값으로 채워 입력 부담을 줄입니다.
  final int? suggestedAmount;

  /// 저장하면 [CompletedJobDraft], 건너뛰면 null 을 돌려줍니다.
  static Future<CompletedJobDraft?> show(
    BuildContext context, {
    required String jobTitle,
    int? suggestedAmount,
  }) {
    return showModalBottomSheet<CompletedJobDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => CompletionAmountSheet(
        jobTitle: jobTitle,
        suggestedAmount: suggestedAmount,
      ),
    );
  }

  @override
  State<CompletionAmountSheet> createState() => _CompletionAmountSheetState();
}

class _CompletionAmountSheetState extends State<CompletionAmountSheet> {
  final _total = TextEditingController();
  final _labor = TextEditingController();
  final _material = TextEditingController();
  final _additional = TextEditingController();

  bool _vatIncluded = false;
  bool _asOccurred = false;
  String? _paymentMethod;
  String? _error;

  @override
  void initState() {
    super.initState();
    final suggested = widget.suggestedAmount;
    if (suggested != null && suggested > 0) _total.text = suggested.toString();
  }

  @override
  void dispose() {
    _total.dispose();
    _labor.dispose();
    _material.dispose();
    _additional.dispose();
    super.dispose();
  }

  void _submit() {
    final total = BidBreakdown.parseWon(_total.text);
    if (total == null || total <= 0) {
      setState(() => _error = '최종 확정금액을 입력해 주세요.');
      return;
    }
    final draft = CompletedJobDraft(
      finalTotalAmount: total,
      finalLaborCost: BidBreakdown.parseWon(_labor.text),
      finalMaterialCost: BidBreakdown.parseWon(_material.text),
      finalAdditionalCost: BidBreakdown.parseWon(_additional.text),
      vatIncluded: _vatIncluded,
      paymentMethod: _paymentMethod,
      asOccurred: _asOccurred,
    );
    final validation = draft.validate();
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    Navigator.pop(context, draft);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('최종 정산금액',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: BusinessTheme.navy)),
            const SizedBox(height: 4),
            Text(widget.jobTitle,
                style: const TextStyle(fontSize: 13, color: BusinessTheme.textMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: BusinessTheme.lightBlue,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                '실제 받은 금액을 남겨 주시면, 같은 공정 오더의 예상 범위가 정확해지고\n지역·공정별 시장 리포트가 열립니다.',
                style: TextStyle(fontSize: 12, height: 1.5, color: BusinessTheme.navy),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _total,
              keyboardType: TextInputType.number,
              decoration: _decoration('총 정산금액 *', suffix: '원'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: TextField(
                  controller: _labor,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 13),
                  decoration: _decoration('인건비', suffix: '원'),
                )),
                const SizedBox(width: 8),
                Expanded(child: TextField(
                  controller: _material,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 13),
                  decoration: _decoration('자재비', suffix: '원'),
                )),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: TextField(
                  controller: _additional,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 13),
                  decoration: _decoration('추가 비용', suffix: '원'),
                )),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: _paymentMethod,
                    isExpanded: true,
                    style: const TextStyle(fontSize: 13, color: BusinessTheme.textPrimary),
                    decoration: _decoration('결제 방법'),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('선택 안 함', style: TextStyle(fontSize: 13))),
                      ...CompletedJobDraft.paymentMethods.entries.map(
                        (e) => DropdownMenuItem<String?>(
                          value: e.key,
                          child: Text(e.value, style: const TextStyle(fontSize: 13)),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _paymentMethod = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _switchRow('부가세 포함 금액', _vatIncluded,
                (v) => setState(() => _vatIncluded = v)),
            _switchRow('작업 후 AS 요청이 있었음', _asOccurred,
                (v) => setState(() => _asOccurred = v)),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: const TextStyle(fontSize: 12, color: BusinessTheme.danger)),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('나중에'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: BusinessTheme.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('금액 저장',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration(String label, {String? suffix}) {
    return InputDecoration(
      labelText: label,
      suffixText: suffix,
      isDense: true,
      labelStyle: const TextStyle(fontSize: 12.5, color: BusinessTheme.textMuted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      filled: true,
      fillColor: BusinessTheme.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: const TextStyle(fontSize: 12.5, color: BusinessTheme.textPrimary)),
        ),
        Switch.adaptive(value: value, onChanged: onChanged),
      ],
    );
  }
}
