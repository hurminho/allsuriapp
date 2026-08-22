import 'package:flutter/material.dart';
import '../../theme/business_theme.dart';
import 'business_primary_button.dart';

class BusinessEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const BusinessEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: BusinessTheme.lightBlue,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: BusinessTheme.blue),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: BusinessTheme.textPrimary,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: BusinessTheme.textMuted,
                  height: 1.4,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              BusinessPrimaryButton(
                label: actionLabel!,
                onPressed: onAction,
                expanded: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class BusinessListSkeleton extends StatelessWidget {
  final int itemCount;
  const BusinessListSkeleton({super.key, this.itemCount = 4});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: itemCount,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => Container(
        height: 128,
        decoration: BusinessTheme.cardDecoration(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 72, height: 16, color: BusinessTheme.lightBlue),
            const SizedBox(height: 12),
            Container(width: double.infinity, height: 18, color: BusinessTheme.lightBlue),
            const SizedBox(height: 8),
            Container(width: 180, height: 14, color: BusinessTheme.lightBlue),
          ],
        ),
      ),
    );
  }
}
