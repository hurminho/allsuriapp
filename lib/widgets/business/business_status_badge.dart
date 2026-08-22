import 'package:flutter/material.dart';
import '../../theme/business_theme.dart';

class BusinessStatusInfo {
  final String label;
  final Color color;
  const BusinessStatusInfo(this.label, this.color);

  static BusinessStatusInfo forEstimate(String status) {
    switch (status) {
      case 'pending':
        return const BusinessStatusInfo('입찰 대기', BusinessTheme.warning);
      case 'awarded':
      case 'approved':
        return const BusinessStatusInfo('채택됨', BusinessTheme.success);
      case 'accepted':
        return const BusinessStatusInfo('작업 진행', BusinessTheme.blue);
      case 'completed':
        return const BusinessStatusInfo('완료', BusinessTheme.navy);
      case 'rejected':
        return const BusinessStatusInfo('미선정', BusinessTheme.danger);
      case 'transferred':
        return const BusinessStatusInfo('이관됨', BusinessTheme.textMuted);
      default:
        return BusinessStatusInfo(status, BusinessTheme.textMuted);
    }
  }

  static BusinessStatusInfo forJob(String status) {
    switch (status) {
      case 'created':
      case 'open':
        return const BusinessStatusInfo('입찰 대기', BusinessTheme.warning);
      case 'pending_transfer':
        return const BusinessStatusInfo('이관 대기', BusinessTheme.warning);
      case 'assigned':
      case 'in_progress':
        return const BusinessStatusInfo('작업 진행', BusinessTheme.blue);
      case 'awaiting_confirmation':
        return const BusinessStatusInfo('완료 확인 대기', BusinessTheme.warning);
      case 'completed':
        return const BusinessStatusInfo('완료', BusinessTheme.success);
      case 'cancelled':
        return const BusinessStatusInfo('취소', BusinessTheme.danger);
      default:
        return BusinessStatusInfo(status, BusinessTheme.textMuted);
    }
  }

  static String nextActionForEstimate(String status) {
    switch (status) {
      case 'pending':
        return '고객 선정 대기';
      case 'awarded':
      case 'approved':
        return '작업 시작·일정 확인';
      case 'accepted':
        return '작업 진행';
      case 'completed':
        return '완료됨';
      case 'rejected':
        return '다른 일감 보기';
      case 'transferred':
        return '이관 상태 확인';
      default:
        return '상세 보기';
    }
  }
}

class BusinessStatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const BusinessStatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  factory BusinessStatusBadge.estimate(String status) {
    final info = BusinessStatusInfo.forEstimate(status);
    return BusinessStatusBadge(label: info.label, color: info.color);
  }

  factory BusinessStatusBadge.job(String status) {
    final info = BusinessStatusInfo.forJob(status);
    return BusinessStatusBadge(label: info.label, color: info.color);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
