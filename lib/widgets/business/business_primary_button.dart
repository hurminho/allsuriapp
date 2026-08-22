import 'package:flutter/material.dart';
import '../../theme/business_theme.dart';

class BusinessPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool expanded;
  final IconData? icon;
  final bool secondary;

  const BusinessPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.expanded = true,
    this.icon,
    this.secondary = false,
  });

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ],
          );

    final button = secondary
        ? OutlinedButton(
            onPressed: loading ? null : onPressed,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(44, 48),
              foregroundColor: BusinessTheme.navy,
            ),
            child: child,
          )
        : FilledButton(
            onPressed: loading ? null : onPressed,
            style: FilledButton.styleFrom(
              minimumSize: const Size(44, 48),
              backgroundColor: BusinessTheme.blue,
            ),
            child: child,
          );

    if (!expanded) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}
