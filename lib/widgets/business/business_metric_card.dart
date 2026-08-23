import 'package:flutter/material.dart';
import 'business_tokens.dart';

class BusinessMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
  final Color? accent;

  const BusinessMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.onTap,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ?? BusinessTokens.blue;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(BusinessTokens.cardRadius),
        child: Ink(
          decoration: BusinessTokens.card(),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 12),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: BusinessTokens.text,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: BusinessTokens.mutedText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
