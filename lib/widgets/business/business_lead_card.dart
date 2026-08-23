import 'package:flutter/material.dart';
import '../../theme/business_theme.dart';
import 'business_status_badge.dart';
import 'business_tokens.dart';

class BusinessLeadCard extends StatelessWidget {
  final String title;
  final String? category;
  final String? region;
  final String? timeLabel;
  final String? symptom;
  final String? amountLabel;
  final bool hasPhoto;
  final bool isNew;
  final bool isUrgent;
  final bool isClosingSoon;
  final bool canBid;
  final String? statusLabel;
  final Color? statusColor;
  final String? nextAction;
  final VoidCallback? onTap;
  final Widget? trailingAction;

  const BusinessLeadCard({
    super.key,
    required this.title,
    this.category,
    this.region,
    this.timeLabel,
    this.symptom,
    this.amountLabel,
    this.hasPhoto = false,
    this.isNew = false,
    this.isUrgent = false,
    this.isClosingSoon = false,
    this.canBid = false,
    this.statusLabel,
    this.statusColor,
    this.nextAction,
    this.onTap,
    this.trailingAction,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(BusinessTokens.cardRadius),
        child: Ink(
          decoration: BusinessTokens.card(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (category != null && category!.isNotEmpty)
                    BusinessStatusBadge(
                      label: category!,
                      color: BusinessTheme.blue,
                    ),
                  if (isNew)
                    const BusinessStatusBadge(
                      label: '신규',
                      color: BusinessTheme.blue,
                      icon: Icons.fiber_new_rounded,
                    ),
                  if (isUrgent)
                    const BusinessStatusBadge(
                      label: '긴급',
                      color: BusinessTheme.danger,
                      icon: Icons.priority_high_rounded,
                    ),
                  if (isClosingSoon)
                    const BusinessStatusBadge(
                      label: '마감 임박',
                      color: BusinessTheme.warning,
                      icon: Icons.schedule_rounded,
                    ),
                  if (statusLabel != null)
                    BusinessStatusBadge(
                      label: statusLabel!,
                      color: statusColor ?? BusinessTheme.textMuted,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: BusinessTheme.textPrimary,
                  height: 1.3,
                ),
              ),
              if (symptom != null && symptom!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  symptom!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: BusinessTheme.textMuted,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  if (region != null) _meta(Icons.place_outlined, region!),
                  if (timeLabel != null)
                    _meta(Icons.schedule_outlined, timeLabel!),
                  if (hasPhoto) _meta(Icons.photo_outlined, '사진 있음'),
                ],
              ),
              if (amountLabel != null) ...[
                const SizedBox(height: 12),
                Text(
                  amountLabel!,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: BusinessTokens.navy,
                  ),
                ),
              ],
              if (canBid || nextAction != null || trailingAction != null) ...[
                const SizedBox(height: 14),
                const Divider(height: 1, color: BusinessTokens.border),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (canBid)
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_outline_rounded,
                            size: 16,
                            color: BusinessTokens.success,
                          ),
                          SizedBox(width: 5),
                          Text(
                            '입찰 가능',
                            style: TextStyle(
                              color: BusinessTokens.success,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      )
                    else if (nextAction != null && trailingAction == null)
                      Text(
                        nextAction!,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: BusinessTokens.blue,
                        ),
                      ),
                    const Spacer(),
                    if (canBid && trailingAction == null)
                      TextButton(
                        onPressed: onTap,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(44, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '견적 작성',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            Icon(Icons.chevron_right_rounded, size: 18),
                          ],
                        ),
                      ),
                    if (trailingAction != null) trailingAction!,
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: BusinessTheme.textMuted),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(fontSize: 12, color: BusinessTheme.textMuted),
        ),
      ],
    );
  }
}
