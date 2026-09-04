import 'package:flutter/material.dart';

/// 목록·상세 로드 실패를 사용자에게 알리고 재시도를 제공하는 공통 화면.
///
/// 지금까지는 로드가 실패해도 "항목이 없습니다" 빈 상태가 나와서, 사용자가
/// 데이터가 없는 것으로 오해하고 재시도할 방법도 없었습니다.
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({
    super.key,
    required this.message,
    this.onRetry,
    this.title = '불러오지 못했습니다',
    this.icon = Icons.cloud_off_rounded,
  });

  /// 사용자에게 보여줄 한국어 문구. 예외 문자열을 그대로 넘기지 마세요.
  final String message;
  final VoidCallback? onRetry;
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              // 최소 터치 영역 44px 을 확보합니다.
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48, minWidth: 140),
                child: FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 20),
                  label: const Text('다시 시도'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
