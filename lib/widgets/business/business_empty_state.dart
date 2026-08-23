import 'package:flutter/material.dart';
import 'business_primary_button.dart';
import 'business_tokens.dart';

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
                color: BusinessTokens.blueLight,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: BusinessTokens.blue),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: BusinessTokens.text,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: BusinessTokens.mutedText,
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
        decoration: BusinessTokens.card(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 72, height: 16, color: BusinessTokens.blueLight),
            const SizedBox(height: 12),
            Container(
                width: double.infinity,
                height: 18,
                color: BusinessTokens.blueLight),
            const SizedBox(height: 8),
            Container(width: 180, height: 14, color: BusinessTokens.blueLight),
          ],
        ),
      ),
    );
  }
}
