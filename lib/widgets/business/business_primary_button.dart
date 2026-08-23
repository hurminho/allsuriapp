import 'package:flutter/material.dart';
import 'business_tokens.dart';

class BusinessPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool expanded;
  final IconData? icon;
  final bool secondary;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const BusinessPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.expanded = true,
    this.icon,
    this.secondary = false,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: foregroundColor ?? Colors.white,
            ),
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
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ],
          );

    final button = secondary
        ? OutlinedButton(
            onPressed: loading ? null : onPressed,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(44, 48),
              foregroundColor: foregroundColor ?? BusinessTokens.navy,
            ),
            child: child,
          )
        : FilledButton(
            onPressed: loading ? null : onPressed,
            style: FilledButton.styleFrom(
              minimumSize: const Size(44, 48),
              backgroundColor: backgroundColor ?? BusinessTokens.blue,
              foregroundColor: foregroundColor ?? Colors.white,
            ),
            child: child,
          );

    if (!expanded) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}
