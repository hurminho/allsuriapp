import 'package:flutter/material.dart';

import 'business_tokens.dart';

enum BusinessStatusTone { neutral, info, success, warning, danger }

class BusinessStatusChip extends StatelessWidget {
  final String label;
  final BusinessStatusTone tone;
  final IconData? icon;

  const BusinessStatusChip({
    super.key,
    required this.label,
    this.tone = BusinessStatusTone.neutral,
    this.icon,
  });

  factory BusinessStatusChip.forEstimate(String status) {
    switch (status) {
      case 'pending':
        return const BusinessStatusChip(
          label: '입찰 대기',
          tone: BusinessStatusTone.warning,
        );
      case 'approved':
      case 'awarded':
      case 'selected':
        return const BusinessStatusChip(
          label: '선택됨',
          tone: BusinessStatusTone.success,
        );
      case 'accepted':
      case 'in_progress':
        return const BusinessStatusChip(
          label: '작업 진행',
          tone: BusinessStatusTone.info,
        );
      case 'completed':
        return const BusinessStatusChip(
          label: '완료',
          tone: BusinessStatusTone.success,
        );
      case 'rejected':
        return const BusinessStatusChip(
          label: '미선정',
          tone: BusinessStatusTone.danger,
        );
      case 'transferred':
        return const BusinessStatusChip(label: '이관됨');
      default:
        return BusinessStatusChip(label: status);
    }
  }

  factory BusinessStatusChip.forJob(String status) {
    switch (status) {
      case 'created':
      case 'open':
        return const BusinessStatusChip(
          label: '모집 중',
          tone: BusinessStatusTone.info,
        );
      case 'pending_transfer':
        return const BusinessStatusChip(
          label: '수락 대기',
          tone: BusinessStatusTone.warning,
        );
      case 'assigned':
        return const BusinessStatusChip(
          label: '배정 완료',
          tone: BusinessStatusTone.success,
        );
      case 'in_progress':
        return const BusinessStatusChip(
          label: '작업 진행',
          tone: BusinessStatusTone.info,
        );
      case 'awaiting_confirmation':
        return const BusinessStatusChip(
          label: '완료 확인',
          tone: BusinessStatusTone.warning,
        );
      case 'completed':
        return const BusinessStatusChip(
          label: '완료',
          tone: BusinessStatusTone.success,
        );
      case 'cancelled':
        return const BusinessStatusChip(
          label: '취소',
          tone: BusinessStatusTone.danger,
        );
      default:
        return BusinessStatusChip(label: status);
    }
  }

  Color get _color {
    switch (tone) {
      case BusinessStatusTone.info:
        return BusinessTokens.blue;
      case BusinessStatusTone.success:
        return BusinessTokens.success;
      case BusinessStatusTone.warning:
        return BusinessTokens.warning;
      case BusinessStatusTone.danger:
        return BusinessTokens.danger;
      case BusinessStatusTone.neutral:
        return BusinessTokens.mutedText;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: _color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: _color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
