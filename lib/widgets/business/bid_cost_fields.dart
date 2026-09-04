import 'package:flutter/material.dart';

import '../../models/bid_breakdown.dart';
import '../../theme/business_theme.dart';

/// 입찰 세부 원가 입력 상태. 다이얼로그/시트가 생성하고 dispose 합니다.
class BidCostFormController {
  final visitFee = TextEditingController();
  final laborCost = TextEditingController();
  final materialCost = TextEditingController();
  final additionalCost = TextEditingController();
  final additionalNote = TextEditingController();
  final estimatedHours = TextEditingController();

  bool vatIncluded = false;
  int? asPeriodMonths;
  String? availability;
  bool siteVisitRequired = true;

  BidBreakdown build() {
    return BidBreakdown(
      visitFee: BidBreakdown.parseWon(visitFee.text),
      laborCost: BidBreakdown.parseWon(laborCost.text),
      materialCost: BidBreakdown.parseWon(materialCost.text),
      additionalCost: BidBreakdown.parseWon(additionalCost.text),
      additionalNote: additionalNote.text,
      vatIncluded: vatIncluded,
      estimatedHours: BidBreakdown.parseHours(estimatedHours.text),
      asPeriodMonths: asPeriodMonths,
      availability: availability,
      siteVisitRequired: siteVisitRequired,
    );
  }

  void dispose() {
    visitFee.dispose();
    laborCost.dispose();
    materialCost.dispose();
    additionalCost.dispose();
    additionalNote.dispose();
    estimatedHours.dispose();
  }
}

/// 견적 작성 과정 자체가 구조화된 가격 데이터를 남기게 하는 폼.
/// 모든 항목이 선택 입력이라 총액만 넣어도 입찰이 그대로 됩니다.
class BidCostFields extends StatefulWidget {
  const BidCostFields({
    super.key,
    required this.controller,
    this.initiallyExpanded = false,
    this.onChanged,
  });

  final BidCostFormController controller;
  final bool initiallyExpanded;
  final VoidCallback? onChanged;

  @override
  State<BidCostFields> createState() => _BidCostFieldsState();
}

class _BidCostFieldsState extends State<BidCostFields> {
  late bool _expanded = widget.initiallyExpanded;

  static const _asOptions = <int?, String>{
    null: '선택 안 함',
    0: '없음',
    1: '1개월',
    3: '3개월',
    6: '6개월',
    12: '12개월',
  };

  void _notify() {
    widget.onChanged?.call();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final sum = c.build().partsSum;

    return Container(
      decoration: BoxDecoration(
        color: BusinessTheme.background,
        borderRadius: BorderRadius.circular(BusinessTheme.radiusSm),
        border: Border.all(color: BusinessTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(BusinessTheme.radiusSm),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long_outlined,
                      size: 18, color: BusinessTheme.navy),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('견적 상세 (선택)',
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: BusinessTheme.textPrimary)),
                  ),
                  if (!_expanded && sum != null)
                    Text(BusinessTheme.formatWon(sum),
                        style: const TextStyle(
                            fontSize: 12, color: BusinessTheme.textMuted)),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                      size: 20, color: BusinessTheme.textMuted),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('나눠 적으면 고객이 금액을 더 신뢰하고, 지역 시장 리포트가 열립니다.',
                      style: TextStyle(
                          fontSize: 11.5, height: 1.4, color: BusinessTheme.textMuted)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _wonField(c.visitFee, '출장비')),
                      const SizedBox(width: 8),
                      Expanded(child: _wonField(c.laborCost, '인건비')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _wonField(c.materialCost, '자재비')),
                      const SizedBox(width: 8),
                      Expanded(child: _wonField(c.additionalCost, '추가 비용')),
                    ],
                  ),
                  if (sum != null) ...[
                    const SizedBox(height: 6),
                    Text('세부 합계 ${BusinessTheme.formatWon(sum)}',
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: BusinessTheme.blue)),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    controller: c.additionalNote,
                    maxLines: 2,
                    style: const TextStyle(fontSize: 13),
                    decoration: _decoration('추가 비용이 생기는 조건 (선택)',
                        hint: '예: 벽체 철거가 필요하면 5만원 추가'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: c.estimatedHours,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(fontSize: 13),
                          decoration: _decoration('예상 작업 시간', hint: '예: 2'),
                          onChanged: (_) => widget.onChanged?.call(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<int?>(
                          initialValue: c.asPeriodMonths,
                          isExpanded: true,
                          style: const TextStyle(
                              fontSize: 13, color: BusinessTheme.textPrimary),
                          decoration: _decoration('AS 기간'),
                          items: _asOptions.entries
                              .map((e) => DropdownMenuItem<int?>(
                                    value: e.key,
                                    child: Text(e.value,
                                        style: const TextStyle(fontSize: 13)),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            c.asPeriodMonths = v;
                            _notify();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    initialValue: c.availability,
                    isExpanded: true,
                    style: const TextStyle(fontSize: 13, color: BusinessTheme.textPrimary),
                    decoration: _decoration('방문 가능 시점'),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('선택 안 함', style: TextStyle(fontSize: 13))),
                      ...BidBreakdown.availabilityOptions.entries.map(
                        (e) => DropdownMenuItem<String?>(
                          value: e.key,
                          child: Text(e.value, style: const TextStyle(fontSize: 13)),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      c.availability = v;
                      _notify();
                    },
                  ),
                  const SizedBox(height: 4),
                  _switchRow(
                    '부가세 포함 금액',
                    c.vatIncluded,
                    (v) {
                      c.vatIncluded = v;
                      _notify();
                    },
                  ),
                  _switchRow(
                    '현장 확인 후 금액 변동 가능',
                    c.siteVisitRequired,
                    (v) {
                      c.siteVisitRequired = v;
                      _notify();
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _wonField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      style: const TextStyle(fontSize: 13),
      decoration: _decoration(label, suffix: '원'),
      onChanged: (_) => _notify(),
    );
  }

  InputDecoration _decoration(String label, {String? hint, String? suffix}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      suffixText: suffix,
      isDense: true,
      labelStyle: const TextStyle(fontSize: 12.5, color: BusinessTheme.textMuted),
      hintStyle: const TextStyle(fontSize: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      filled: true,
      fillColor: BusinessTheme.surface,
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
