import 'package:flutter/material.dart';
import '../../theme/business_theme.dart';

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
    final color = accent ?? BusinessTheme.blue;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(BusinessTheme.radius),
        child: Ink(
          decoration: BusinessTheme.cardDecoration(),
          padding: const EdgeInsets.all(16),
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
                  color: BusinessTheme.textPrimary,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: BusinessTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
