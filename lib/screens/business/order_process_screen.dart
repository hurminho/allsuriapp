import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../chat_screen.dart';
import 'order_review_screen.dart';

/// 오더 1개당 전체 프로세스를 한 눈에 볼 수 있는 화면
/// 낙찰 → 진행 → 완료 → 후기 타임라인
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
    setState(() => _loading = true);
    try {
      await Future.wait([
        _loadListing(),
        _loadChatRooms(),
      ]);
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

    // 오너 정보
    if (_listing!['posted_by'] != null) {
      final owner = await _sb
          .from('users')
          .select('id, name, businessname, phonenumber, profile_image_url')
          .eq('id', _listing!['posted_by'])
          .maybeSingle();
      _ownerInfo = owner != null ? Map<String, dynamic>.from(owner) : null;
    }

    // 낙찰된 입찰 정보
    final claimedBy = _listing!['claimed_by'];
    if (claimedBy != null) {
      // order_bids 테이블에서 낙찰된 입찰 조회
      final bids = await _sb
          .from('order_bids')
          .select('*')
          .eq('listing_id', widget.listingId)
          .eq('bidder_id', claimedBy)
          .order('created_at', ascending: false)
          .limit(1);
      _winnerBid = bids.isNotEmpty ? Map<String, dynamic>.from(bids.first) : null;

      // 낙찰자 정보
      final winner = await _sb
          .from('users')
          .select('id, name, businessname, phonenumber, profile_image_url')
          .eq('id', claimedBy)
          .maybeSingle();
      _winnerInfo = winner != null ? Map<String, dynamic>.from(winner) : null;

      // 후기 조회
      final reviews = await _sb
          .from('order_reviews')
          .select('*')
          .eq('listing_id', widget.listingId)
          .order('created_at', ascending: false)
          .limit(1);
      _review = reviews.isNotEmpty ? Map<String, dynamic>.from(reviews.first) : null;
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
      // listing_id 컬럼 없을 수 있음 - 무시
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: Text(
          widget.orderTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadAll,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _listing == null
              ? const Center(child: Text('오더 정보를 찾을 수 없습니다.'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildOrderSummaryCard(),
                      const SizedBox(height: 16),
                      _buildTimeline(),
                      const SizedBox(height: 16),
                      if (_winnerInfo != null) _buildParticipantsCard(),
                      const SizedBox(height: 16),
                      if (_review != null) _buildReviewCard(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  Widget _buildOrderSummaryCard() {
    final order = _listing!;
    final status = order['status']?.toString() ?? 'created';
    final budget = order['budget_amount'];
    final region = order['region'] ?? '-';
    final category = order['category'] ?? '-';
    final createdAt = order['createdat'] != null
        ? _dateFmt.format(DateTime.parse(order['createdat']))
        : '-';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _getStatusColor(status).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _getStatusLabel(status),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _getStatusColor(status),
                  ),
                ),
              ),
              const Spacer(),
              Text(
                createdAt,
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            order['title'] ?? widget.orderTitle,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF0B2545)),
          ),
          if (order['description'] != null) ...[
            const SizedBox(height: 8),
            Text(
              order['description'],
              style: TextStyle(fontSize: 14, color: Colors.grey[600], height: 1.5),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _buildInfoChip(Icons.location_on_outlined, region),
              _buildInfoChip(Icons.category_outlined, category),
              if (budget != null)
                _buildInfoChip(Icons.payments_outlined, '₩${_fmt.format(budget)}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: Colors.grey[500]),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
      ],
    );
  }

  Widget _buildTimeline() {
    final status = _listing!['status']?.toString() ?? 'created';
    final claimedAt = _listing!['claimed_at'];
    final updatedAt = _listing!['updatedat'];

    final steps = [
      _TimelineStep(
        icon: Icons.add_circle_outline,
        title: '오더 등록',
        subtitle: _listing!['createdat'] != null
            ? _dateFmt.format(DateTime.parse(_listing!['createdat']))
            : '-',
        color: const Color(0xFF0B2545),
        isCompleted: true,
        detail: '${_ownerInfo?['businessname'] ?? _ownerInfo?['name'] ?? '사업자'} 님이 오더를 등록했습니다.',
      ),
      _TimelineStep(
        icon: Icons.gavel_outlined,
        title: '낙찰',
        subtitle: claimedAt != null
            ? _dateFmt.format(DateTime.parse(claimedAt))
            : '입찰 대기 중',
        color: Colors.orange,
        isCompleted: _isStatusAfter(status, 'assigned'),
        isActive: status == 'created' || status == 'open',
        detail: _winnerInfo != null
            ? '${_winnerInfo!['businessname'] ?? _winnerInfo!['name'] ?? '사업자'} 님이 낙찰받았습니다.${_winnerBid?['bid_amount'] != null ? '\n입찰 금액: ₩${_fmt.format(_winnerBid!['bid_amount'])}' : ''}'
            : '아직 낙찰된 사업자가 없습니다.',
      ),
      _TimelineStep(
        icon: Icons.construction_outlined,
        title: '진행 중',
        subtitle: _isStatusAfter(status, 'in_progress') ? '작업 진행 중' : '-',
        color: Colors.blue,
        isCompleted: _isStatusAfter(status, 'awaiting_confirmation'),
        isActive: status == 'assigned' || status == 'in_progress',
        detail: status == 'assigned' || status == 'in_progress'
            ? '${_winnerInfo?['businessname'] ?? _winnerInfo?['name'] ?? '사업자'} 님이 작업을 진행하고 있습니다.'
            : _isStatusAfter(status, 'awaiting_confirmation') ? '작업이 완료되었습니다.' : '아직 시작되지 않았습니다.',
      ),
      _TimelineStep(
        icon: Icons.check_circle_outline,
        title: '완료',
        subtitle: status == 'completed' || status == 'awaiting_confirmation'
            ? (updatedAt != null ? _dateFmt.format(DateTime.parse(updatedAt)) : '완료됨')
            : '-',
        color: Colors.green,
        isCompleted: status == 'completed' || status == 'awaiting_confirmation',
        isActive: status == 'awaiting_confirmation',
        detail: status == 'completed'
            ? '오더가 완료 확인되었습니다.'
            : status == 'awaiting_confirmation'
                ? '완료 확인을 기다리고 있습니다.'
                : '아직 완료되지 않았습니다.',
      ),
      _TimelineStep(
        icon: Icons.star_outline,
        title: '후기',
        subtitle: _review != null
            ? _dateFmt.format(DateTime.parse(_review!['created_at']))
            : '-',
        color: Colors.amber,
        isCompleted: _review != null,
        isActive: (status == 'completed') && _review == null,
        detail: _review != null
            ? '★ ${_review!['rating'] ?? '-'}  "${_review!['comment'] ?? ''}"'
            : '아직 후기가 작성되지 않았습니다.',
        actionWidget: _review == null && status == 'completed' && _winnerInfo != null
            ? TextButton.icon(
                onPressed: () => _navigateToReview(),
                icon: const Icon(Icons.rate_review_outlined, size: 16),
                label: const Text('후기 작성'),
                style: TextButton.styleFrom(foregroundColor: Colors.amber[700]),
              )
            : null,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('오더 진행 현황', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0B2545))),
          const SizedBox(height: 20),
          ...steps.asMap().entries.map((entry) {
            final i = entry.key;
            final step = entry.value;
            return _buildTimelineItem(step, isLast: i == steps.length - 1);
          }),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(_TimelineStep step, {required bool isLast}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 왼쪽: 아이콘 + 연결선
          Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: step.isCompleted
                      ? step.color
                      : step.isActive
                          ? step.color.withValues(alpha: 0.15)
                          : Colors.grey[100],
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: step.isCompleted || step.isActive ? step.color : Colors.grey[300]!,
                    width: 2,
                  ),
                ),
                child: Icon(
                  step.isCompleted ? Icons.check : step.icon,
                  size: 20,
                  color: step.isCompleted
                      ? Colors.white
                      : step.isActive
                          ? step.color
                          : Colors.grey[400],
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: step.isCompleted ? step.color.withValues(alpha: 0.3) : Colors.grey[200],
                    margin: const EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          // 오른쪽: 내용
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        step.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: step.isCompleted || step.isActive ? Colors.black87 : Colors.grey[400],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (step.isActive)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: step.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '현재 단계',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: step.color),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    step.subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    step.detail,
                    style: TextStyle(
                      fontSize: 13,
                      color: step.isCompleted || step.isActive ? Colors.grey[700] : Colors.grey[400],
                      height: 1.5,
                    ),
                  ),
                  if (step.actionWidget != null) step.actionWidget!,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('참여자 정보', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0B2545))),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildPersonCard('오더 등록자', _ownerInfo, Icons.person_outline, const Color(0xFF0B2545))),
              const SizedBox(width: 12),
              Expanded(child: _buildPersonCard('낙찰 사업자', _winnerInfo, Icons.business_center_outlined, Colors.orange)),
            ],
          ),
          if (_chatRooms.isNotEmpty) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _openChat(),
              icon: const Icon(Icons.chat_outlined, size: 18),
              label: const Text('채팅 보기'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0B2545),
                side: const BorderSide(color: Color(0xFF0B2545)),
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPersonCard(String role, Map<String, dynamic>? info, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(role, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            info?['businessname'] ?? info?['name'] ?? '정보 없음',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          if (info?['phonenumber'] != null) ...[
            const SizedBox(height: 4),
            Text(info!['phonenumber'], style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ],
      ),
    );
  }

  Widget _buildReviewCard() {
    final review = _review!;
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final comment = review['comment'] as String?;
    final tags = review['tags'] as List<dynamic>?;
    final createdAt = review['created_at'] != null
        ? _dateFmt.format(DateTime.parse(review['created_at']))
        : '-';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.amber[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.star_rounded, color: Colors.amber, size: 20),
              const SizedBox(width: 8),
              const Text('완료 후기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(createdAt, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(5, (i) => Icon(
              i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
              color: Colors.amber,
              size: 24,
            )),
          ),
          if (tags != null && tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: tags.map((t) => Chip(
                label: Text(t.toString(), style: const TextStyle(fontSize: 12)),
                backgroundColor: Colors.amber[100],
                visualDensity: VisualDensity.compact,
              )).toList(),
            ),
          ],
          if (comment != null && comment.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(comment, style: const TextStyle(fontSize: 14, height: 1.6)),
            ),
          ],
        ],
      ),
    );
  }

  void _navigateToReview() async {
    if (_winnerInfo == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderReviewScreen(
          listingId: widget.listingId,
          jobId: _listing?['jobid']?.toString() ?? '',
          revieweeId: _listing!['claimed_by'],
          revieweeName: _winnerInfo!['businessname'] ?? _winnerInfo!['name'] ?? '사업자',
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

  bool _isStatusAfter(String current, String check) {
    const order = ['created', 'open', 'assigned', 'in_progress', 'awaiting_confirmation', 'completed'];
    final ci = order.indexOf(current);
    final ci2 = order.indexOf(check);
    if (ci < 0 || ci2 < 0) return false;
    return ci >= ci2;
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'created':
      case 'open':
        return Colors.orange;
      case 'assigned':
      case 'in_progress':
        return Colors.blue;
      case 'awaiting_confirmation':
        return Colors.purple;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'created': return '입찰 대기';
      case 'open': return '공개됨';
      case 'assigned': return '낙찰됨';
      case 'in_progress': return '진행 중';
      case 'awaiting_confirmation': return '완료 확인 대기';
      case 'completed': return '완료';
      case 'cancelled': return '취소됨';
      default: return status;
    }
  }
}

class _TimelineStep {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool isCompleted;
  final bool isActive;
  final String detail;
  final Widget? actionWidget;

  const _TimelineStep({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.isCompleted,
    this.isActive = false,
    required this.detail,
    this.actionWidget,
  });
}
