import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../widgets/business/business_app_shell.dart';
import '../../widgets/business/business_empty_state.dart';
import '../../widgets/business/business_primary_button.dart';
import '../../widgets/business/business_section_header.dart';
import '../../widgets/business/business_status_chip.dart';
import '../../widgets/business/business_tokens.dart';
import '../chat_screen.dart';
import 'order_review_screen.dart';

class OrderProcessScreen extends StatefulWidget {
  final String listingId;
  final String orderTitle;

  const OrderProcessScreen({
    super.key,
    required this.listingId,
    required this.orderTitle,
  });

  @override
  State<OrderProcessScreen> createState() => _OrderProcessScreenState();
}

class _OrderProcessScreenState extends State<OrderProcessScreen> {
  bool _loading = true;
  String? _loadError;
  Map<String, dynamic>? _listing;
  Map<String, dynamic>? _winnerBid;
  Map<String, dynamic>? _ownerInfo;
  Map<String, dynamic>? _winnerInfo;
  Map<String, dynamic>? _review;
  List<Map<String, dynamic>> _chatRooms = [];

  final _sb = Supabase.instance.client;
  final _fmt = NumberFormat('#,###', 'ko_KR');
  final _dateFmt = DateFormat('yyyy.MM.dd HH:mm', 'ko_KR');

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await Future.wait([
        _loadListing(),
        _loadChatRooms(),
      ]);
    } catch (_) {
      if (mounted) {
        setState(() => _loadError = '진행 정보를 불러오지 못했습니다');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadListing() async {
    final data = await _sb
        .from('marketplace_listings')
        .select('*, jobs(commission_rate, media_urls)')
        .eq('id', widget.listingId)
        .maybeSingle();
    if (data == null) return;
    _listing = Map<String, dynamic>.from(data);

    if (_listing!['posted_by'] != null) {
      final owner = await _sb
          .from('users')
          .select('id, name, businessname, phonenumber, profile_image_url')
          .eq('id', _listing!['posted_by'])
          .maybeSingle();
      _ownerInfo = owner != null ? Map<String, dynamic>.from(owner) : null;
    }

    // B2B 낙찰(select_bidder)은 selected_bidder_id에 기록되고, 즉시잡기(claim)는
    // claimed_by에 기록됩니다. 하나만 보면 낙찰자가 표시되지 않습니다.
    final claimedBy =
        _listing!['claimed_by'] ?? _listing!['selected_bidder_id'];
    if (claimedBy != null) {
      final bids = await _sb
          .from('order_bids')
          .select('*')
          .eq('listing_id', widget.listingId)
          .eq('bidder_id', claimedBy)
          .order('created_at', ascending: false)
          .limit(1);
      _winnerBid =
          bids.isNotEmpty ? Map<String, dynamic>.from(bids.first) : null;

      final winner = await _sb
          .from('users')
          .select('id, name, businessname, phonenumber, profile_image_url')
          .eq('id', claimedBy)
          .maybeSingle();
      _winnerInfo = winner != null ? Map<String, dynamic>.from(winner) : null;

      final reviews = await _sb
          .from('order_reviews')
          .select('*')
          .eq('listing_id', widget.listingId)
          .order('created_at', ascending: false)
          .limit(1);
      _review =
          reviews.isNotEmpty ? Map<String, dynamic>.from(reviews.first) : null;
    }
  }

  Future<void> _loadChatRooms() async {
    try {
      final rooms = await _sb
          .from('chat_rooms')
          .select('id, participant_a, participant_b, status')
          .or('listing_id.eq.${widget.listingId},job_id.eq.${widget.listingId}');
      _chatRooms = List<Map<String, dynamic>>.from(rooms);
    } catch (_) {
      // Some deployments do not expose listing_id on chat_rooms.
    }
  }

  @override
  Widget build(BuildContext context) {
    return BusinessAppShell(
      title: '진행 관리',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          tooltip: '새로고침',
          onPressed: _loadAll,
        ),
      ],
      body: _loading
          ? const BusinessListSkeleton(itemCount: 3)
          : _loadError != null
              ? BusinessEmptyState(
                  icon: Icons.refresh_rounded,
                  title: _loadError!,
                  subtitle: '네트워크 상태를 확인한 뒤 다시 시도해 주세요.',
                  actionLabel: '다시 시도',
                  onAction: _loadAll,
                )
              : _listing == null
                  ? BusinessEmptyState(
                      icon: Icons.assignment_outlined,
                      title: '진행 정보를 찾을 수 없습니다',
                      subtitle: '목록을 새로고침한 뒤 다시 확인해 주세요.',
                      actionLabel: '새로고침',
                      onAction: _loadAll,
                    )
                  : RefreshIndicator(
                      onRefresh: _loadAll,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding:
                            const EdgeInsets.all(BusinessTokens.pagePadding),
                        children: [
                          _buildAssignmentSummaryCard(),
                          const SizedBox(height: BusinessTokens.space16),
                          _buildCurrentInfoCard(),
                          const SizedBox(height: BusinessTokens.space16),
                          _buildTimeline(),
                          const SizedBox(height: BusinessTokens.space16),
                          _buildNextAction(),
                          if (_winnerInfo != null) ...[
                            const SizedBox(height: BusinessTokens.space16),
                            _buildParticipantsCard(),
                          ],
                          if (_review != null) ...[
                            const SizedBox(height: BusinessTokens.space16),
                            _buildReviewCard(),
                          ],
                          const SizedBox(height: BusinessTokens.space24),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildAssignmentSummaryCard() {
    final status = _listing!['status']?.toString() ?? 'created';
    final ownerName = _ownerInfo?['businessname']?.toString() ??
        _ownerInfo?['name']?.toString();
    final winnerName = _winnerInfo?['businessname']?.toString() ??
        _winnerInfo?['name']?.toString();

    return Container(
      padding: const EdgeInsets.all(BusinessTokens.space16),
      decoration: BusinessTokens.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('협업 일감', style: BusinessTokens.caption),
              ),
              _buildStatusChip(status),
            ],
          ),
          const SizedBox(height: BusinessTokens.space12),
          Text(
            _listing!['title']?.toString() ?? widget.orderTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: BusinessTokens.title,
          ),
          if (ownerName != null || winnerName != null) ...[
            const SizedBox(height: BusinessTokens.space16),
            const Divider(height: 1, color: BusinessTokens.border),
            const SizedBox(height: BusinessTokens.space12),
            if (ownerName != null) _buildAssignmentRow('요청 업체', ownerName),
            if (ownerName != null && winnerName != null)
              const SizedBox(height: BusinessTokens.space8),
            if (winnerName != null) _buildAssignmentRow('배정 업체', winnerName),
          ],
        ],
      ),
    );
  }

  Widget _buildAssignmentRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(label, style: BusinessTokens.caption),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: BusinessTokens.body.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentInfoCard() {
    final createdAt = _formatDateValue(_listing!['createdat']);
    final region = _listing!['region']?.toString().trim();
    final category = _listing!['category']?.toString().trim();
    final description = _listing!['description']?.toString().trim();
    final amount = _winnerBid?['bid_amount'] ?? _listing!['budget_amount'];
    final contactPolicy = _winnerInfo == null
        ? '연락처는 업체 배정 후 협업 과정에서 확인할 수 있습니다.'
        : '배정 이후 연락은 협업 채팅을 이용해 주세요.';

    return Container(
      padding: const EdgeInsets.all(BusinessTokens.space16),
      decoration: BusinessTokens.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BusinessSectionHeader(
            title: '현재 정보',
            subtitle: '확인된 정보만 표시합니다',
          ),
          const SizedBox(height: BusinessTokens.space16),
          if (category != null && category.isNotEmpty)
            _buildInfoRow(
              Icons.category_outlined,
              '공정',
              category,
            ),
          if (category != null &&
              category.isNotEmpty &&
              description != null &&
              description.isNotEmpty)
            const SizedBox(height: BusinessTokens.space12),
          if (description != null && description.isNotEmpty)
            _buildInfoRow(
              Icons.description_outlined,
              '작업 범위',
              description,
            ),
          if ((category != null && category.isNotEmpty) ||
              (description != null && description.isNotEmpty))
            const SizedBox(height: BusinessTokens.space12),
          if (createdAt != null)
            _buildInfoRow(
              Icons.calendar_today_outlined,
              '등록 일시',
              createdAt,
            ),
          if (createdAt != null && region != null && region.isNotEmpty)
            const SizedBox(height: BusinessTokens.space12),
          if (region != null && region.isNotEmpty)
            _buildInfoRow(
              Icons.location_on_outlined,
              '작업 위치',
              region,
            ),
          if ((createdAt != null || (region != null && region.isNotEmpty)) &&
              amount != null)
            const SizedBox(height: BusinessTokens.space12),
          if (amount != null)
            _buildInfoRow(
              Icons.payments_outlined,
              _winnerBid?['bid_amount'] != null ? '확정 금액' : '예상 금액',
              '${_fmt.format(amount)}원',
            ),
          if (createdAt != null ||
              (region != null && region.isNotEmpty) ||
              amount != null)
            const SizedBox(height: BusinessTokens.space12),
          _buildInfoRow(
            Icons.privacy_tip_outlined,
            '연락 안내',
            contactPolicy,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: BusinessTokens.blue),
        const SizedBox(width: BusinessTokens.space8),
        SizedBox(
          width: 64,
          child: Text(label, style: BusinessTokens.caption),
        ),
        const SizedBox(width: BusinessTokens.space8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: BusinessTokens.body,
          ),
        ),
      ],
    );
  }

  Widget _buildTimeline() {
    final status = _listing!['status']?.toString() ?? 'created';
    final current = _statusPhase(status);
    final isCompleted = status == 'completed';
    final winnerName = _winnerInfo?['businessname']?.toString() ??
        _winnerInfo?['name']?.toString();
    final steps = [
      _TimelineStep(
        title: '업체 배정',
        detail: winnerName == null
            ? '함께 진행할 업체를 확인하는 단계입니다.'
            : '$winnerName 업체가 배정되었습니다.',
        isCompleted: current > 0 || isCompleted,
        isActive: current == 0 && !isCompleted,
      ),
      _TimelineStep(
        title: '일정 확정',
        detail: '배정 업체와 작업 일정을 확인하는 단계입니다.',
        isCompleted: current > 1 || isCompleted,
        isActive: current == 1 && !isCompleted,
      ),
      _TimelineStep(
        title: '작업 진행',
        detail: '확정된 일정에 따라 작업을 진행하는 단계입니다.',
        isCompleted: current > 2 || isCompleted,
        isActive: current == 2 && !isCompleted,
      ),
      _TimelineStep(
        title: '완료 확인',
        detail: status == 'completed'
            ? '완료 확인이 끝났습니다.'
            : '작업 결과를 확인하고 마무리하는 단계입니다.',
        isCompleted: isCompleted,
        isActive: current == 3 && !isCompleted,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(BusinessTokens.space16),
      decoration: BusinessTokens.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BusinessSectionHeader(
            title: '진행 관리',
            subtitle: '현재 상태에 맞춰 협업 단계를 표시합니다',
          ),
          const SizedBox(height: BusinessTokens.space24),
          ...steps.asMap().entries.map(
                (entry) => _buildTimelineItem(
                  entry.value,
                  isLast: entry.key == steps.length - 1,
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(_TimelineStep step, {required bool isLast}) {
    final color = step.isActive || step.isCompleted
        ? BusinessTokens.blue
        : BusinessTokens.border;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: step.isCompleted
                        ? BusinessTokens.blue
                        : step.isActive
                            ? BusinessTokens.blueLight
                            : BusinessTokens.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2),
                  ),
                  child: Icon(
                    step.isCompleted
                        ? Icons.check_rounded
                        : step.isActive
                            ? Icons.circle
                            : Icons.circle_outlined,
                    size: step.isActive ? 10 : 17,
                    color: step.isCompleted
                        ? Colors.white
                        : step.isActive
                            ? BusinessTokens.blue
                            : BusinessTokens.border,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: step.isCompleted
                          ? BusinessTokens.blue
                          : BusinessTokens.border,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: BusinessTokens.space12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                top: 3,
                bottom: isLast ? 0 : BusinessTokens.space24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          step.title,
                          style: BusinessTokens.body.copyWith(
                            fontWeight: FontWeight.w800,
                            color: step.isActive || step.isCompleted
                                ? BusinessTokens.text
                                : BusinessTokens.mutedText,
                          ),
                        ),
                      ),
                      if (step.isActive)
                        const BusinessStatusChip(
                          label: '현재 단계',
                          tone: BusinessStatusTone.info,
                        ),
                    ],
                  ),
                  const SizedBox(height: BusinessTokens.space4),
                  Text(
                    step.detail,
                    style: BusinessTokens.caption.copyWith(
                      color: step.isActive || step.isCompleted
                          ? BusinessTokens.mutedText
                          : BusinessTokens.border,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextAction() {
    final status = _listing!['status']?.toString() ?? 'created';
    if (status == 'completed' && _review == null && _winnerInfo != null) {
      return BusinessPrimaryButton(
        label: '후기 작성',
        icon: Icons.rate_review_outlined,
        onPressed: _navigateToReview,
      );
    }
    if (_chatRooms.isNotEmpty &&
        (status == 'assigned' ||
            status == 'in_progress' ||
            status == 'awaiting_confirmation' ||
            status == 'completed')) {
      return BusinessPrimaryButton(
        label: '협업 채팅 열기',
        icon: Icons.chat_outlined,
        onPressed: _openChat,
      );
    }
    return BusinessPrimaryButton(
      label: '진행 상태 새로고침',
      icon: Icons.refresh_rounded,
      onPressed: _loadAll,
    );
  }

  Widget _buildParticipantsCard() {
    return Container(
      padding: const EdgeInsets.all(BusinessTokens.space16),
      decoration: BusinessTokens.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BusinessSectionHeader(title: '협업 업체'),
          const SizedBox(height: BusinessTokens.space12),
          if (_ownerInfo != null)
            _buildPersonCard(
              '요청 업체',
              _ownerInfo,
              Icons.storefront_outlined,
            ),
          if (_ownerInfo != null && _winnerInfo != null)
            const SizedBox(height: BusinessTokens.space8),
          if (_winnerInfo != null)
            _buildPersonCard(
              '배정 업체',
              _winnerInfo,
              Icons.handyman_outlined,
            ),
        ],
      ),
    );
  }

  Widget _buildPersonCard(
    String role,
    Map<String, dynamic>? info,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(BusinessTokens.space12),
      decoration: BusinessTokens.card(
        color: BusinessTokens.canvas,
        radius: BusinessTokens.controlRadius,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: BusinessTokens.blue),
          const SizedBox(width: BusinessTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(role, style: BusinessTokens.caption),
                const SizedBox(height: 2),
                Text(
                  info?['businessname']?.toString() ??
                      info?['name']?.toString() ??
                      '사업자',
                  style: BusinessTokens.body.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard() {
    final review = _review!;
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final comment = review['comment'] as String?;
    final tags = review['tags'] as List<dynamic>?;
    final createdAt = _formatDateValue(review['created_at']);

    return Container(
      padding: const EdgeInsets.all(BusinessTokens.space16),
      decoration: BusinessTokens.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BusinessSectionHeader(
            title: '완료 후기',
            subtitle: createdAt,
          ),
          const SizedBox(height: BusinessTokens.space12),
          Row(
            children: List.generate(
              5,
              (index) => Icon(
                index < rating
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                color: BusinessTokens.warning,
                size: 24,
              ),
            ),
          ),
          if (tags != null && tags.isNotEmpty) ...[
            const SizedBox(height: BusinessTokens.space12),
            Wrap(
              spacing: BusinessTokens.space8,
              runSpacing: BusinessTokens.space8,
              children: tags
                  .map(
                    (tag) => BusinessStatusChip(
                      label: tag.toString(),
                      tone: BusinessStatusTone.neutral,
                    ),
                  )
                  .toList(),
            ),
          ],
          if (comment != null && comment.isNotEmpty) ...[
            const SizedBox(height: BusinessTokens.space12),
            Text(comment, style: BusinessTokens.body),
          ],
        ],
      ),
    );
  }

  int _statusPhase(String status) {
    switch (status) {
      case 'assigned':
        return 1;
      case 'in_progress':
        return 2;
      case 'awaiting_confirmation':
      case 'completed':
        return 3;
      case 'created':
      case 'open':
      case 'cancelled':
      default:
        return 0;
    }
  }

  Widget _buildStatusChip(String status) {
    switch (status) {
      case 'created':
      case 'open':
        return const BusinessStatusChip(
          label: '업체 배정',
          tone: BusinessStatusTone.info,
        );
      case 'assigned':
        return const BusinessStatusChip(
          label: '일정 확정',
          tone: BusinessStatusTone.info,
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

  String? _formatDateValue(dynamic value) {
    if (value == null) return null;
    final parsed = DateTime.tryParse(value.toString());
    return parsed == null ? null : _dateFmt.format(parsed);
  }

  void _navigateToReview() async {
    if (_winnerInfo == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderReviewScreen(
          listingId: widget.listingId,
          jobId: _listing?['jobid']?.toString() ?? '',
          revieweeId: _winnerInfo!['id']?.toString() ??
              (_listing!['claimed_by'] ?? _listing!['selected_bidder_id'])
                  .toString(),
          revieweeName:
              _winnerInfo!['businessname'] ?? _winnerInfo!['name'] ?? '사업자',
          orderTitle: widget.orderTitle,
        ),
      ),
    );
    _loadAll();
  }

  void _openChat() {
    if (_chatRooms.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(chatRoomId: _chatRooms.first['id']),
      ),
    );
  }
}

class _TimelineStep {
  final String title;
  final bool isCompleted;
  final bool isActive;
  final String detail;

  const _TimelineStep({
    required this.title,
    required this.isCompleted,
    this.isActive = false,
    required this.detail,
  });
}
