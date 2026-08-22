import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_version_info.dart';
import '../services/android_in_app_update_service.dart';

/// 앱 업데이트 안내 다이얼로그.
///
/// - 강제 업데이트(`isForced: true`): 뒤로가기/바깥 탭으로 닫을 수 없고 "업데이트" 버튼만 노출됩니다.
/// - 선택 업데이트(`isForced: false`): "나중에" / "업데이트" 버튼이 노출되며 닫을 수 있습니다.
///
/// "업데이트" 버튼을 누르면:
/// - Android: Google Play In-App Update(Play Core)로 앱을 떠나지 않고 즉시/백그라운드 업데이트를 시도합니다.
///   (Play를 통해 설치되지 않은 환경 등으로 사용할 수 없는 경우) 스토어 링크로 자동 폴백합니다.
/// - iOS: 항상 App Store로 이동합니다 (Apple은 인앱 업데이트 API를 제공하지 않음).
class UpdateDialog extends StatefulWidget {
  final AppVersionInfo info;
  final bool isForced;

  const UpdateDialog({
    super.key,
    required this.info,
    required this.isForced,
  });

  /// 다이얼로그를 표시합니다.
  ///
  /// 강제 업데이트인 경우 반환되는 Future는 다이얼로그가 닫히기 전까지(즉, 사실상 영원히)
  /// 완료되지 않으므로, 호출부에서 `await`하면 자연스럽게 이후 화면 진입을 막을 수 있습니다.
  static Future<void> show(
    BuildContext context, {
    required AppVersionInfo info,
    required bool isForced,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: !isForced,
      builder: (dialogContext) => PopScope(
        canPop: !isForced,
        child: UpdateDialog(info: info, isForced: isForced),
      ),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isProcessing = false;

  Future<void> _handleUpdateTap() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      if (Platform.isAndroid) {
        if (!mounted) return;
        final handledNatively = widget.isForced
            ? await AndroidInAppUpdateService.instance.tryImmediateUpdate()
            : await AndroidInAppUpdateService.instance
                .tryFlexibleUpdate(context);

        if (handledNatively) {
          // 선택 업데이트는 백그라운드 다운로드가 시작됐으므로 다이얼로그를 닫고 앱을 계속 사용하게 합니다.
          // 강제 업데이트가 성공하면 앱이 이미 재시작되므로 이 코드는 대부분 실행되지 않습니다.
          if (!widget.isForced && mounted) {
            Navigator.of(context).pop();
          }
          return;
        }
        // 네이티브 플로우를 사용할 수 없는 경우(Play 미배포 설치, API 미지원, 사용자 취소 등) 스토어로 폴백
      }

      if (!mounted) return;
      await _openStore(context);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _openStore(BuildContext context) async {
    final storeUrl =
        Platform.isIOS ? widget.info.iosStoreUrl : widget.info.androidStoreUrl;

    if (storeUrl == null || storeUrl.isEmpty) {
      debugPrint('⚠️ [UpdateDialog] 스토어 URL이 설정되어 있지 않습니다.');
      _showLaunchError(context);
      return;
    }

    try {
      final uri = Uri.parse(storeUrl);
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        _showLaunchError(context);
      }
    } catch (e) {
      debugPrint('⚠️ [UpdateDialog] 스토어 이동 실패: $e');
      if (context.mounted) _showLaunchError(context);
    }
  }

  void _showLaunchError(BuildContext context) {
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (errorContext) => AlertDialog(
        title: const Text('스토어를 열 수 없습니다'),
        content: const Text(
          '잠시 후 다시 시도하시거나, 스토어 앱에서 직접 "올수리"를 검색해 업데이트해 주세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(errorContext).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final isForced = widget.isForced;
    final hasCustomMessage = (info.updateMessage ?? '').trim().isNotEmpty;
    final message = hasCustomMessage
        ? info.updateMessage!.trim()
        : (isForced
            ? '현재 버전은 더 이상 지원되지 않습니다.\n서비스를 계속 이용하려면 최신 버전으로 업데이트해 주세요.'
            : '새 버전이 출시되었어요.\n더 안정적인 서비스 이용을 위해 업데이트해 주세요.');

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(
            isForced ? Icons.warning_amber_rounded : Icons.system_update_rounded,
            color: isForced ? const Color(0xFFDC2626) : const Color(0xFF2E74B5),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isForced ? '필수 업데이트 안내' : '업데이트 안내',
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: const TextStyle(fontSize: 14, height: 1.5)),
          const SizedBox(height: 14),
          Text(
            '최신 버전: ${info.latestVersion}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      actions: [
        if (!isForced)
          TextButton(
            onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
            child: const Text('나중에', style: TextStyle(color: Colors.grey)),
          ),
        ElevatedButton(
          onPressed: _isProcessing ? null : _handleUpdateTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2E74B5),
            foregroundColor: Colors.white,
          ),
          child: _isProcessing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('업데이트'),
        ),
      ],
    );
  }
}
