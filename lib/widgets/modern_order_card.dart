import 'package:flutter/material.dart';
import '../config/app_constants.dart';

/// Modern order card with E-commerce template styling
class ModernOrderCard extends StatelessWidget {
  final String? orderId; // Hero 태그용 ID
  final String title;
  final String description;
  final String? category;
  final String? region;
  final double? budget;
  final String status;
  final int? bidCount;
  final VoidCallback? onTap;
  final Widget? actionButton;
  final List<Widget>? badges;
  final bool enableHeroAnimation; // Hero 애니메이션 활성화 여부
  final String? customBudgetLabel; // "견적 금액" 등 커스텀 레이블

  const ModernOrderCard({
    Key? key,
    this.orderId,
    required this.title,
    required this.description,
    this.category,
    this.region,
    this.budget,
    required this.status,
    this.bidCount,
    this.onTap,
    this.actionButton,
    this.badges,
    this.enableHeroAnimation = true,
    this.customBudgetLabel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final cardWidget = OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.all(AppConstants.defaultPadding),
        side: BorderSide(
          width: 1.5,
          color: AppConstants.blackColor10,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.defaultBorderRadius),
        ),
        backgroundColor: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row - Status Badge & Budget
          Row(
            children: [
              // Status Badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.smallPadding,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _getStatusColor(status),
                  borderRadius: BorderRadius.circular(AppConstants.smallBorderRadius),
                ),
                child: Text(
                  _getStatusText(status),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: AppConstants.captionFontSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              // Budget
              if (budget != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (customBudgetLabel != null)
                      Text(
                        customBudgetLabel!,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    Text(
                      '₩${budget!.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}',
                      style: const TextStyle(
                        color: Color(0xFF0B2545),
                        fontSize: AppConstants.titleFontSize,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppConstants.smallPadding),
          
          // Title
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium!.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: AppConstants.titleFontSize,
            ),
          ),
          const SizedBox(height: AppConstants.smallPadding),
          
          // Description
          Text(
            description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: AppConstants.blackColor60,
              fontSize: AppConstants.bodySmallFontSize,
            ),
          ),
          const SizedBox(height: AppConstants.smallPadding),
          
          // Info Row - Category, Region, Bid Count
          Wrap(
            spacing: AppConstants.smallPadding,
            runSpacing: AppConstants.smallPadding / 2,
            children: [
              if (category != null)
                _buildInfoChip(
                  icon: Icons.category_outlined,
                  label: category!,
                ),
              if (region != null)
                _buildInfoChip(
                  icon: Icons.location_on_outlined,
                  label: region!,
                ),
              if (bidCount != null && bidCount! > 0)
                _buildInfoChip(
                  icon: Icons.people_outline,
                  label: '$bidCount명 입찰',
                  color: AppConstants.primaryColor,
                ),
            ],
          ),
          
          // Badges (custom badges like "내 입찰", "낙찰 대기" etc)
          if (badges != null && badges!.isNotEmpty) ...[
            const SizedBox(height: AppConstants.smallPadding),
            Wrap(
              spacing: AppConstants.smallPadding / 2,
              runSpacing: AppConstants.smallPadding / 2,
              children: badges!,
            ),
          ],
          
          // Action Button
          if (actionButton != null) ...[
            const SizedBox(height: AppConstants.defaultPadding),
            actionButton!,
          ],
        ],
      ),
    );

    // Hero 애니메이션 적용
    if (enableHeroAnimation && orderId != null && orderId!.isNotEmpty) {
      return Hero(
        tag: 'order-card-$orderId',
        child: Material(
          type: MaterialType.transparency,
          child: cardWidget,
        ),
      );
    }

    return cardWidget;
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    Color? color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: AppConstants.smallIconSize,
          color: color ?? AppConstants.blackColor60,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: AppConstants.captionFontSize,
            color: color ?? AppConstants.blackColor60,
            fontWeight: color != null ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'created':
      case 'open':
        return AppConstants.primaryColor;
      case 'assigned':
      case 'in_progress':
        return AppConstants.secondaryColor;
      case 'awaiting_confirmation':
        return AppConstants.warningColor;
      case 'completed':
        return const Color(0xFF31B0D8);
      case 'cancelled':
        return AppConstants.errorColor;
      default:
        return AppConstants.greyColor;
    }
  }

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'created':
        return '생성됨';
      case 'open':
        return '입찰 중';
      case 'assigned':
        return '배정됨';
      case 'in_progress':
        return '진행 중';
      case 'awaiting_confirmation':
        return '확인 대기';
      case 'completed':
        return '완료';
      case 'cancelled':
        return '취소됨';
      default:
        return status;
    }
  }
}

