import 'package:flutter/material.dart';
import '../models/estimate.dart';
import 'package:intl/intl.dart';

class EstimateListItem extends StatelessWidget {
  final Estimate estimate;
  final VoidCallback? onTap;
  final VoidCallback? onSelect;

  const EstimateListItem({
    super.key,
    required this.estimate,
    this.onTap,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      estimate.technicianName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF102A43),
                      ),
                    ),
                  ),
                  _buildStatusChip(context, estimate.status),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                estimate.description,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 16,
                    color: Colors.grey[500],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat('yyyy-MM-dd').format(estimate.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00C6AE).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${estimate.price.toStringAsFixed(0)}원',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF00C6AE),
                      ),
                    ),
                  ),
                ],
              ),
              if (onSelect != null) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onSelect,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E74B5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '이 견적 선택하기',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(BuildContext context, String status) {
    String statusText;
    Color statusColor;
    IconData statusIcon;

    switch (status) {
      case 'pending':
        statusText = '검토 대기';
        statusColor = const Color(0xFFFFA726);
        statusIcon = Icons.schedule;
        break;
      case 'accepted':
        statusText = '수락됨';
        statusColor = const Color(0xFF2E74B5);
        statusIcon = Icons.check_circle;
        break;
      case 'rejected':
        statusText = '거절됨';
        statusColor = const Color(0xFFFF6B6B);
        statusIcon = Icons.cancel;
        break;
      case 'awarded':
        statusText = '선택됨';
        statusColor = const Color(0xFF00C6AE);
        statusIcon = Icons.emoji_events;
        break;
      default:
        statusText = '알 수 없음';
        statusColor = Colors.grey;
        statusIcon = Icons.help_outline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon, color: statusColor, size: 14),
          const SizedBox(width: 4),
          Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
} 