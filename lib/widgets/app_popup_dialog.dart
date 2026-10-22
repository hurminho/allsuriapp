import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;

import '../services/app_popup_service.dart';
import '../theme/business_theme.dart';

/// 앱을 열 때 관리자가 등록한 안내 팝업을 하나 띄웁니다. 해당하는 팝업이 없으면 아무것도 하지 않습니다.
Future<void> maybeShowAppPopup(BuildContext context, {AppPopupService? service}) async {
  final popups = service ?? AppPopupService();
  final popup = await popups.next();
  if (popup == null || !context.mounted) return;

  // 띄운 순간 '봤음'으로 기록해야 한 번만·하루 한 번 팝업이 반복되지 않습니다.
  await popups.record(popup.id, 'seen');
  if (!context.mounted) return;

  final action = await showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (_) => AppPopupDialog(popup: popup),
  );

  if (action == 'click') {
    await popups.record(popup.id, 'click');
    final uri = Uri.tryParse(popup.buttonUrl ?? '');
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
      await url_launcher.launchUrl(uri, mode: url_launcher.LaunchMode.externalApplication);
    }
  } else if (action == 'hide') {
    await popups.record(popup.id, 'hide');
  }
}

class AppPopupDialog extends StatelessWidget {
  final AppPopup popup;

  const AppPopupDialog({super.key, required this.popup});

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.75;
    final hasButton = popup.buttonUrl != null;

    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 420, maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (popup.imageUrl != null)
                      CachedNetworkImage(
                        imageUrl: popup.imageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const AspectRatio(
                          aspectRatio: 16 / 9,
                          child: ColoredBox(color: BusinessTheme.lightBlue),
                        ),
                        errorWidget: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                      child: Text(
                        popup.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: BusinessTheme.textPrimary,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      child: Text(
                        popup.body,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: BusinessTheme.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (hasButton)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, 'click'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: BusinessTheme.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(popup.buttonLabel ?? '자세히 보기',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                children: [
                  if (popup.canHide)
                    TextButton(
                      onPressed: () => Navigator.pop(context, 'hide'),
                      style: TextButton.styleFrom(foregroundColor: BusinessTheme.textMuted),
                      child: const Text('다시 보지 않기'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context, 'close'),
                    child: const Text('닫기'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
