import 'package:flutter/material.dart';

import '../../models/bid_breakdown.dart';
import '../../models/price_estimate.dart';
import '../../services/price_service.dart';
import '../../theme/business_theme.dart';
import '../../utils/api_failure.dart';
import '../../utils/app_logger.dart';
import '../../widgets/business/business_app_bar.dart';
import '../../widgets/error_state_view.dart';

/// 표준 단가 빠른 등록.
///
/// 긴 설문 대신 공정을 고르고 숫자 몇 개만 넣게 합니다.
/// 등록한 단가는 검증(사업자등록 진위확인)된 사업자에 한해 가격 엔진 3순위 근거가 됩니다.
class RateCardScreen extends StatefulWidget {
  const RateCardScreen({super.key});

  @override
  State<RateCardScreen> createState() => _RateCardScreenState();
}

class _RateCardScreenState extends State<RateCardScreen> {
  final _service = PriceService();

  List<TradeSummary> _trades = const [];
  List<Map<String, dynamic>> _rateCards = const [];
  bool _loading = true;

  /// 로드 실패 안내 문구. null 이면 정상입니다.
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      // 두 조회는 서로 의존하지 않으므로 함께 기다립니다.
      final results = await Future.wait([
        _service.trades(),
        _service.rateCards(),
      ]);
      if (!mounted) return;
      setState(() {
        _trades = results[0] as List<TradeSummary>;
        _rateCards = results[1] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e, stack) {
      AppLog.error('RateCardScreen', e, stack: stack, message: '표준 단가 로드');
      // try/catch 가 없으면 예외가 나도 _loading 이 true 로 남아
      // 스피너가 영구히 돌았습니다.
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = ApiFailure.from(e).message;
      });
    }
  }

  Map<String, dynamic>? _cardFor(String tradeId) {
    for (final card in _rateCards) {
      if (card['trade_id']?.toString() == tradeId) return card;
    }
    return null;
  }

  Future<void> _edit(TradeSummary trade) async {
    final saved = await _RateCardEditor.show(
      context,
      trade: trade,
      existing: _cardFor(trade.id),
      service: _service,
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BusinessTheme.background,
      appBar: const BusinessAppBar(title: '표준 단가'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? ErrorStateView(message: _loadError!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _benefits(),
                  const SizedBox(height: 16),
                  if (_trades.isEmpty)
                    _emptyCatalog()
                  else
                    ..._groupedTrades().entries.map(_categorySection),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Map<String, List<TradeSummary>> _groupedTrades() {
    final grouped = <String, List<TradeSummary>>{};
    for (final t in _trades) {
      grouped.putIfAbsent(t.category, () => []).add(t);
    }
    return grouped;
  }

  Widget _benefits() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BusinessTheme.surface,
        borderRadius: BorderRadius.circular(BusinessTheme.radius),
        border: Border.all(color: BusinessTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('단가를 등록하면',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: BusinessTheme.textPrimary)),
          const SizedBox(height: 10),
          ...[
            ('가격 기준 협력업체 배지', Icons.verified_outlined),
            ('신규 오더 우선 노출', Icons.trending_up_rounded),
            ('지역·공정별 시장 평균 리포트 열람', Icons.insights_outlined),
            ('고객에게 신뢰도 높은 견적으로 표시', Icons.thumb_up_alt_outlined),
          ].map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(item.$2, size: 16, color: BusinessTheme.success),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(item.$1,
                          style: const TextStyle(
                              fontSize: 12.5, color: BusinessTheme.textPrimary)),
                    ),
                  ],
                ),
              )),
          const Text('입력한 단가는 고객에게 그대로 공개되지 않습니다. 시장 범위를 계산하는 데만 씁니다.',
              style: TextStyle(
                  fontSize: 11.5, height: 1.45, color: BusinessTheme.textMuted)),
        ],
      ),
    );
  }

  Widget _emptyCatalog() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BusinessTheme.surface,
        borderRadius: BorderRadius.circular(BusinessTheme.radius),
        border: Border.all(color: BusinessTheme.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_outlined, color: BusinessTheme.textMuted),
          const SizedBox(height: 8),
          const Text('공정 목록을 불러오지 못했습니다.',
              style: TextStyle(fontSize: 13, color: BusinessTheme.textPrimary)),
          const SizedBox(height: 8),
          TextButton(onPressed: _load, child: const Text('다시 시도')),
        ],
      ),
    );
  }

  Widget _categorySection(MapEntry<String, List<TradeSummary>> entry) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(entry.key,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: BusinessTheme.textMuted)),
        ),
        ...entry.value.map(_tradeTile),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _tradeTile(TradeSummary trade) {
    final card = _cardFor(trade.id);
    final registered = card != null;
    final base = registered ? (num.tryParse(card['base_labor_cost'].toString()) ?? 0) : 0;
    final verified = card?['verified'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: BusinessTheme.surface,
        borderRadius: BorderRadius.circular(BusinessTheme.radiusSm),
        border: Border.all(color: BusinessTheme.border),
      ),
      child: ListTile(
        title: Text(trade.subcategory,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: BusinessTheme.textPrimary)),
        subtitle: Text(
          registered
              ? '기본 작업비 ${BusinessTheme.formatWon(base)}${verified ? ' · 시장 데이터 반영' : ' · 진위확인 후 반영'}'
              : '아직 등록하지 않았습니다',
          style: TextStyle(
            fontSize: 12,
            color: registered ? BusinessTheme.success : BusinessTheme.textMuted,
          ),
        ),
        trailing: Icon(
          registered ? Icons.edit_outlined : Icons.add_circle_outline,
          size: 20,
          color: BusinessTheme.blue,
        ),
        onTap: () => _edit(trade),
      ),
    );
  }
}

class _RateCardEditor extends StatefulWidget {
  const _RateCardEditor({
    required this.trade,
    required this.existing,
    required this.service,
  });

  final TradeSummary trade;
  final Map<String, dynamic>? existing;
  final PriceService service;

  static Future<bool?> show(
    BuildContext context, {
    required TradeSummary trade,
    required Map<String, dynamic>? existing,
    required PriceService service,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RateCardEditor(
        trade: trade,
        existing: existing,
        service: service,
      ),
    );
  }

  @override
  State<_RateCardEditor> createState() => _RateCardEditorState();
}

class _RateCardEditorState extends State<_RateCardEditor> {
  final _baseLabor = TextEditingController();
  final _materialAvg = TextEditingController();
  final _visitFee = TextEditingController();
  final _conditions = TextEditingController();
  final _regions = TextEditingController();

  bool _materialIncluded = false;
  bool _vatIncluded = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _baseLabor.text = existing['base_labor_cost']?.toString() ?? '';
      _materialAvg.text = existing['material_avg_cost']?.toString() ?? '';
      _visitFee.text = existing['visit_fee']?.toString() ?? '';
      _materialIncluded = existing['material_included'] == true;
      _vatIncluded = existing['vat_included'] == true;
      final conditions = existing['additional_cost_conditions'];
      if (conditions is List) _conditions.text = conditions.join(', ');
      final regions = existing['service_regions'];
      if (regions is List) _regions.text = regions.join(', ');
    } else {
      _materialIncluded = widget.trade.materialIncludedByDefault;
    }
  }

  @override
  void dispose() {
    _baseLabor.dispose();
    _materialAvg.dispose();
    _visitFee.dispose();
    _conditions.dispose();
    _regions.dispose();
    super.dispose();
  }

  List<String> _splitList(String raw) => raw
      .split(RegExp(r'[,\n]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .take(20)
      .toList();

  Future<void> _save() async {
    final base = BidBreakdown.parseWon(_baseLabor.text);
    if (base == null || base <= 0) {
      setState(() => _error = '기본 작업비를 입력해 주세요.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    final error = await widget.service.saveRateCard(
      tradeId: widget.trade.id,
      baseLaborCost: base,
      materialAvgCost: BidBreakdown.parseWon(_materialAvg.text) ?? 0,
      materialIncluded: _materialIncluded,
      visitFee: BidBreakdown.parseWon(_visitFee.text) ?? 0,
      vatIncluded: _vatIncluded,
      additionalCostConditions: _splitList(_conditions.text),
      serviceRegions: _splitList(_regions.text),
    );

    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    Navigator.pop(context, true);
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
            Text(widget.trade.subcategory,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: BusinessTheme.navy)),
            const SizedBox(height: 4),
            Text(widget.trade.category,
                style: const TextStyle(fontSize: 13, color: BusinessTheme.textMuted)),
            const SizedBox(height: 16),
            TextField(
              controller: _baseLabor,
              keyboardType: TextInputType.number,
              decoration: _decoration('기본 작업비 *', suffix: '원'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _materialAvg,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 13),
                    decoration: _decoration('자재 포함 평균', suffix: '원'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _visitFee,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 13),
                    decoration: _decoration('출장비', suffix: '원'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _conditions,
              maxLines: 2,
              style: const TextStyle(fontSize: 13),
              decoration: _decoration('추가 비용이 발생하는 조건',
                  hint: '쉼표로 구분 · 예: 벽체 철거, 야간 작업'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _regions,
              style: const TextStyle(fontSize: 13),
              decoration: _decoration('작업 가능 지역', hint: '쉼표로 구분 · 예: 서울, 경기'),
            ),
            const SizedBox(height: 4),
            _switchRow('자재비 포함 단가', _materialIncluded,
                (v) => setState(() => _materialIncluded = v)),
            _switchRow('부가세 포함 단가', _vatIncluded,
                (v) => setState(() => _vatIncluded = v)),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: const TextStyle(fontSize: 12, color: BusinessTheme.danger)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: BusinessTheme.navy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('저장',
                        style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
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
