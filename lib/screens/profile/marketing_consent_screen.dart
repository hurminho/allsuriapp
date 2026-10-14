import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../services/marketing_consent_service.dart';
import '../../theme/business_theme.dart';
import '../../widgets/business/business_app_bar.dart';

/// 광고성 정보(새 기능·이벤트·혜택 소식) 수신 동의·철회.
class MarketingConsentScreen extends StatefulWidget {
  const MarketingConsentScreen({super.key});

  @override
  State<MarketingConsentScreen> createState() => _MarketingConsentScreenState();
}

class _MarketingConsentScreenState extends State<MarketingConsentScreen> {
  final _service = MarketingConsentService();
  MarketingConsentState? _state;
  bool _loading = true;
  bool _saving = false;

  String get _userId => context.read<AuthService>().currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final state = await _service.load(_userId);
    if (!mounted) return;
    setState(() {
      _state = state;
      _loading = false;
    });
  }

  Future<void> _save({required bool consent, required bool night}) async {
    setState(() => _saving = true);
    final next = await _service.save(_userId, consent: consent, night: night);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (next != null) _state = next;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(next == null
            ? '저장하지 못했어요. 잠시 후 다시 시도해 주세요.'
            : '저장했어요. 처리 결과를 앱 알림으로 보내 드렸어요.'),
      ),
    );
  }

  static String _fmt(DateTime? d) => d == null
      ? '-'
      : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return Scaffold(
      backgroundColor: BusinessTheme.background,
      appBar: const BusinessAppBar(title: '소식·혜택 받기'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : state == null
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('지금은 설정을 불러올 수 없어요. 잠시 후 다시 시도해 주세요.',
                        textAlign: TextAlign.center),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const MarketingConsentNoticeCard(),
                    const SizedBox(height: 16),
                    Card(
                      child: Column(
                        children: [
                          SwitchListTile(
                            title: const Text('광고성 정보 받기 (선택)'),
                            subtitle: const Text(MarketingConsentNotice.channels),
                            value: state.consent,
                            onChanged: _saving
                                ? null
                                : (v) => _save(consent: v, night: v && state.night),
                          ),
                          const Divider(height: 1),
                          SwitchListTile(
                            title: const Text('밤 9시~아침 8시에도 받기 (선택)'),
                            value: state.consent && state.night,
                            onChanged: (_saving || !state.consent)
                                ? null
                                : (v) => _save(consent: true, night: v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      state.consent
                          ? '동의 일시: ${_fmt(state.consentAt)}'
                          : (state.withdrawnAt != null
                              ? '철회 일시: ${_fmt(state.withdrawnAt)}'
                              : '아직 동의하지 않았어요.'),
                      style: const TextStyle(fontSize: 13, color: BusinessTheme.textMuted),
                    ),
                  ],
                ),
    );
  }
}

/// 동의 화면과 처음 안내 창이 함께 쓰는 안내 문구.
class MarketingConsentNoticeCard extends StatelessWidget {
  const MarketingConsentNoticeCard({super.key});

  @override
  Widget build(BuildContext context) {
    const label = TextStyle(fontSize: 13, color: BusinessTheme.textMuted);
    const value = TextStyle(fontSize: 13, color: BusinessTheme.textPrimary, height: 1.4);
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 72, child: Text(k, style: label)),
              Expanded(child: Text(v, style: value)),
            ],
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('광고성 정보 수신 동의 (선택)',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 12),
            row('보내는 곳', MarketingConsentNotice.sender),
            row('내용', MarketingConsentNotice.purpose),
            row('받는 방법', MarketingConsentNotice.channels),
            row('이용 정보', MarketingConsentNotice.items),
            row('보관 기간', MarketingConsentNotice.retention),
            const SizedBox(height: 4),
            const Text(MarketingConsentNotice.refusal, style: label),
          ],
        ),
      ),
    );
  }
}

/// 대시보드에서 한 번만 묻는 안내 창. 이미 물어봤거나 동의했거나 SQL 실행 전이면 띄우지 않습니다.
Future<void> maybeAskMarketingConsent(BuildContext context, String userId) async {
  if (userId.isEmpty) return;
  final service = MarketingConsentService();
  final state = await service.load(userId);
  if (state == null || state.consent || state.askedAt != null) return;
  if (!context.mounted) return;

  final agreed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('새 기능·이벤트 소식을 받아 보시겠어요?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('혜택과 새 서비스 소식을 문자·앱 푸시로 알려 드려요. 언제든 [내 정보]에서 끌 수 있어요.',
                style: TextStyle(fontSize: 13, color: BusinessTheme.textMuted, height: 1.4)),
            const SizedBox(height: 12),
            const MarketingConsentNoticeCard(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: const Text('괜찮아요'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: BusinessTheme.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('받을게요'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  if (agreed == true) {
    final saved = await service.save(userId, consent: true);
    if (saved != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('소식 받기에 동의하셨어요. 처리 결과를 앱 알림으로 보내 드렸어요.')),
      );
    }
  } else {
    // 닫거나 '괜찮아요' → 다시 묻지 않습니다(동의 상태는 바꾸지 않음).
    await service.markAsked(userId);
  }
}
