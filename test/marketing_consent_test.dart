import 'package:allsuriapp/screens/profile/marketing_consent_screen.dart';
import 'package:allsuriapp/services/marketing_consent_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MarketingConsentState.fromRow', () {
    test('동의 칸과 일시를 읽는다', () {
      final s = MarketingConsentState.fromRow({
        'marketing_consent': true,
        'marketing_night_consent': false,
        'marketing_consent_at': '2026-10-13T05:00:00+00:00',
        'marketing_withdrawn_at': null,
        'marketing_consent_asked_at': '2026-10-13T05:00:00+00:00',
      });
      expect(s.consent, isTrue);
      expect(s.night, isFalse);
      expect(s.consentAt, isNotNull);
      expect(s.withdrawnAt, isNull);
      expect(s.askedAt, isNotNull);
    });

    test('값이 없으면 동의 안 함으로 본다', () {
      final s = MarketingConsentState.fromRow({});
      expect(s.consent, isFalse);
      expect(s.night, isFalse);
      expect(s.askedAt, isNull);
    });
  });

  testWidgets('안내 카드에 법정 안내 항목이 모두 보인다', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: MarketingConsentNoticeCard())),
    ));
    for (final text in [
      MarketingConsentNotice.sender,
      MarketingConsentNotice.purpose,
      MarketingConsentNotice.channels,
      MarketingConsentNotice.items,
      MarketingConsentNotice.retention,
      MarketingConsentNotice.refusal,
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.textContaining('(선택)'), findsOneWidget);
  });
}
