import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:lottie/lottie.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../../services/job_service.dart';
import '../../services/chat_service.dart'; // 추가
import '../../services/api_service.dart';
import '../../models/job.dart';
import '../../widgets/business/business_app_shell.dart';
import '../../widgets/business/business_empty_state.dart';
import '../../widgets/business/business_filter_chip.dart';
import '../../widgets/business/business_primary_button.dart';
import '../../widgets/business/business_section_header.dart';
import '../../widgets/business/business_status_chip.dart';
import '../../widgets/business/business_tokens.dart';
import '../../widgets/modern_order_card.dart';
import 'order_bidders_screen.dart';
import 'order_review_screen.dart';
import 'job_cancel_reason_screen.dart';
import '../chat_screen.dart'; // 추가

class JobManagementScreen extends StatefulWidget {
  final String? highlightedJobId; // 포커싱할 공사 ID
  final String? initialFilter; // 초기 필터 ('in_progress', 'completed')
  final bool embedded;
  final bool hideFilters;

  const JobManagementScreen({
    super.key,
    this.highlightedJobId,
    this.initialFilter,
    this.embedded = false,
    this.hideFilters = false,
  });

  @override
  State<JobManagementScreen> createState() => _JobManagementScreenState();
}

class _JobManagementScreenState extends State<JobManagementScreen> {
  List<Job> _combinedJobs = [];
  List<Job> _completedJobs = []; // 완료된 공사 (awaiting_confirmation + completed)
  bool _isLoading = true;
  String? _loadError;
  late String _filter; // in_progress | completed (내가 가져간 공사만)
  Map<String, Map<String, dynamic>> _listingByJobId = {};
  bool _isCompleting = false; // 공사 완료 중 플래그
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter ?? 'in_progress';
    _loadJobs();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  static const _listingOnlyPrefix = 'listing:';

  String _listingOnlyJobId(String listingId) => '$_listingOnlyPrefix$listingId';

  bool _isListingOnlyJobId(String? jobId) =>
      jobId != null && jobId.startsWith(_listingOnlyPrefix);

  String? _listingIdFromJobId(String? jobId) {
    if (jobId == null) return null;
    if (_isListingOnlyJobId(jobId)) {
      return jobId.substring(_listingOnlyPrefix.length);
    }
    return _listingByJobId[jobId]?['id']?.toString();
  }

  Map<String, dynamic>? _listingForJob(Job job) {
    if (job.id != null) {
      final byJobId = _listingByJobId[job.id];
      if (byJobId != null) return byJobId;
    }
    final listingId = _listingIdFromJobId(job.id);
    if (listingId != null) {
      return _listingByJobId[_listingOnlyJobId(listingId)] ??
          _listingByJobId[listingId];
    }
    return null;
  }

  bool _isAssignee(Job job, String userId, Map<String, dynamic>? listing) {
    if (job.assignedBusinessId == userId) return true;
    if (listing == null) return false;
    final selected = listing['selected_bidder_id']?.toString();
    final claimed = listing['claimed_by']?.toString();
    return selected == userId || claimed == userId;
  }

  String _jobStatusFromListing(String? listingStatus,
      {String fallback = 'assigned'}) {
    switch (listingStatus) {
      case 'assigned':
      case 'in_progress':
      case 'awaiting_confirmation':
      case 'completed':
      case 'cancelled':
        return listingStatus!;
      default:
        return fallback;
    }
  }

  Job _jobFromListing(
    Map<String, dynamic> listing,
    String assigneeId, {
    required String storageJobId,
    Job? existingJob,
  }) {
    final budgetRaw = listing['budget_amount'] ?? listing['estimate_amount'];
    final createdRaw = listing['createdat'] ?? listing['createdAt'];

    return Job(
      id: storageJobId,
      title: listing['title']?.toString() ?? existingJob?.title ?? '협업 일감',
      description:
          listing['description']?.toString() ?? existingJob?.description ?? '',
      ownerBusinessId: listing['posted_by']?.toString() ??
          existingJob?.ownerBusinessId ??
          '',
      assignedBusinessId: assigneeId,
      budgetAmount: budgetRaw != null
          ? (budgetRaw as num).toDouble()
          : existingJob?.budgetAmount,
      status: _jobStatusFromListing(
        listing['status']?.toString(),
        fallback: existingJob?.status ?? 'assigned',
      ),
      location: listing['region']?.toString() ?? existingJob?.location,
      category: listing['category']?.toString() ?? existingJob?.category,
      mediaUrls: existingJob?.mediaUrls,
      createdAt: DateTime.tryParse(createdRaw?.toString() ?? '') ??
          existingJob?.createdAt ??
          DateTime.now(),
      updatedAt: existingJob?.updatedAt,
    );
  }

  Future<List<Map<String, dynamic>>> _fetchMyAssignedListings(
      String userId) async {
    final rows = await Supabase.instance.client
        .from('marketplace_listings')
        .select('*')
        .or('claimed_by.eq.$userId,selected_bidder_id.eq.$userId')
        .inFilter('status',
            ['assigned', 'in_progress', 'awaiting_confirmation', 'completed']);

    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> _loadJobs() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final authService = context.read<AuthService>();
      final jobService = context.read<JobService>();
      final currentUserId = authService.currentUser?.id;

      if (currentUserId == null) {
        if (mounted) setState(() => _loadError = '로그인이 필요합니다');
        return;
      }

      final allJobs = await jobService.getJobs();
      final assignedListings = await _fetchMyAssignedListings(currentUserId);
      print(
          '🔍 [JobManagement] jobs=${allJobs.length}, 내 낙찰 listings=${assignedListings.length}');

      final jobsById = {
        for (final job in allJobs)
          if (job.id != null) job.id!: job,
      };

      final Map<String, Job> mergedByKey = {};
      final Map<String, Map<String, dynamic>> tempListingByJobId = {};

      void registerJobListing(Job job, Map<String, dynamic> listing) {
        final listingId = listing['id']?.toString();
        final realJobId = listing['jobid']?.toString();

        mergedByKey[job.id ?? listingId ?? UniqueKey().toString()] = job;

        if (realJobId != null) {
          tempListingByJobId[realJobId] = listing;
        }
        if (listingId != null) {
          tempListingByJobId[_listingOnlyJobId(listingId)] = listing;
        }
        if (job.id != null) {
          tempListingByJobId[job.id!] = listing;
        }
      }

      // 1) marketplace_listings 기준 — 낙찰/클레임된 오더 (jobs.assigned_business_id 미동기화 대비)
      for (final listing in assignedListings) {
        final listingId = listing['id']?.toString();
        if (listingId == null) continue;

        final realJobId = listing['jobid']?.toString();
        final existingJob = realJobId != null ? jobsById[realJobId] : null;
        final storageJobId = realJobId ?? _listingOnlyJobId(listingId);

        final job = existingJob != null
            ? existingJob.copyWith(
                assignedBusinessId: currentUserId,
                status: _jobStatusFromListing(
                  listing['status']?.toString(),
                  fallback: existingJob.status,
                ),
              )
            : _jobFromListing(
                listing,
                currentUserId,
                storageJobId: storageJobId,
              );

        registerJobListing(job, listing);
      }

      // 2) jobs.assigned_business_id 기준 — listing 조회에 누락된 공사 보완
      for (final job
          in allJobs.where((j) => j.assignedBusinessId == currentUserId)) {
        if (job.id != null && mergedByKey.containsKey(job.id)) continue;
        mergedByKey[job.id ?? UniqueKey().toString()] = job;
      }

      final myJobs = mergedByKey.values.toList();

      _completedJobs = myJobs.where((job) {
        final listing = _listingForJobFromMaps(job, tempListingByJobId);
        final listingStatus = listing?['status']?.toString();
        return job.status == 'completed' ||
            job.status == 'awaiting_confirmation' ||
            job.status == 'cancelled' ||
            listingStatus == 'completed' ||
            listingStatus == 'awaiting_confirmation' ||
            listingStatus == 'cancelled';
      }).toList();

      _combinedJobs = myJobs.where((job) {
        final listing = _listingForJobFromMaps(job, tempListingByJobId);
        final listingStatus = listing?['status']?.toString();
        final isDone = job.status == 'completed' ||
            job.status == 'awaiting_confirmation' ||
            job.status == 'cancelled' ||
            listingStatus == 'completed' ||
            listingStatus == 'awaiting_confirmation' ||
            listingStatus == 'cancelled';
        return !isDone;
      }).toList();

      _listingByJobId = tempListingByJobId;

      print(
          '🔍 [JobManagement] 진행중 공사: ${_combinedJobs.length}개, 완료된 공사: ${_completedJobs.length}개');
      print('   listing 매핑: ${_listingByJobId.length}개');
    } catch (e) {
      print('❌ [JobManagement] 공사 로드 실패: $e');
      if (mounted) {
        setState(() => _loadError = '협업 일감을 불러오지 못했습니다');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('공사 목록을 불러오는데 실패했습니다: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);

        if (widget.highlightedJobId != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToHighlightedJob();
          });
        }
      }
    }
  }

  Map<String, dynamic>? _listingForJobFromMaps(
    Job job,
    Map<String, Map<String, dynamic>> listingMap,
  ) {
    if (job.id != null) {
      final direct = listingMap[job.id];
      if (direct != null) return direct;
    }
    final listingId = _listingIdFromJobId(job.id);
    if (listingId != null) {
      return listingMap[_listingOnlyJobId(listingId)] ?? listingMap[listingId];
    }
    return null;
  }

  void _scrollToHighlightedJob() {
    if (widget.highlightedJobId == null || !mounted) return;

    // 약간의 지연을 두어 ListView가 완전히 빌드된 후 스크롤
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted || !_scrollController.hasClients) return;

      final filteredJobs = _filteredByBadge(
          _combinedJobs, context.read<AuthService>().currentUser?.id ?? '');
      final highlightId = widget.highlightedJobId;
      final index = filteredJobs.indexWhere((job) {
        if (job.id == highlightId) return true;
        final listing = _listingForJob(job);
        return listing?['id']?.toString() == highlightId;
      });

      print('🔍 [_scrollToHighlightedJob] 찾는 중...');
      print('   highlightedJobId: ${widget.highlightedJobId}');
      print('   filteredJobs 개수: ${filteredJobs.length}');
      print('   찾은 index: $index');

      if (index != -1) {
        // 대략적인 아이템 높이 (카드 높이 + spacing)
        const double itemHeight = 220.0;
        final double offset = index * itemHeight;
        final double maxScroll = _scrollController.position.maxScrollExtent;

        // 스크롤 범위를 초과하지 않도록 제한
        final double targetOffset = offset > maxScroll ? maxScroll : offset;

        _scrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOutCubic,
        );

        print(
            '✅ [JobManagement] ${widget.highlightedJobId} 공사로 스크롤 (index: $index, offset: $targetOffset)');
      } else {
        print('⚠️ [JobManagement] highlightedJobId를 찾을 수 없음');
        if (filteredJobs.isNotEmpty) {
          print('   첫 번째 공사 ID: ${filteredJobs.first.id}');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final body = _isLoading
        ? const BusinessListSkeleton()
        : _loadError != null
            ? BusinessEmptyState(
                icon: Icons.refresh_rounded,
                title: _loadError!,
                subtitle: '네트워크 상태를 확인한 뒤 다시 시도해 주세요.',
                actionLabel: '다시 시도',
                onAction: _loadJobs,
              )
            : Column(
                children: [
                  if (!widget.hideFilters) _buildModernFilterChips(),
                  Expanded(
                    child: _ModernJobsList(
                      jobs: _filteredByBadge(
                        _combinedJobs,
                        context.read<AuthService>().currentUser?.id ?? '',
                      ),
                      currentUserId:
                          context.read<AuthService>().currentUser?.id ?? '',
                      listingsByJobId: _listingByJobId,
                      onViewBidders: _openBidderList,
                      onCompleteJob: _completeJob,
                      onCancelJob: _cancelJob,
                      onReview: _openReviewScreen,
                      scrollController: _scrollController,
                      highlightedJobId: widget.highlightedJobId,
                    ),
                  ),
                ],
              );
    if (widget.embedded) return body;
    return BusinessAppShell(
      title: '진행 관리',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loadJobs,
          tooltip: '새로고침',
        ),
      ],
      body: body,
    );
  }

  void _showCheck() {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'check',
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) {
        return Center(
          child: SizedBox(
              width: 140,
              height: 140,
              child: Lottie.asset('assets/lottie/check.json', repeat: false)),
        );
      },
    );
    Future.delayed(const Duration(milliseconds: 900), () {
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    });
  }

  Widget _buildModernFilterChips() {
    return Container(
      width: double.infinity,
      color: BusinessTokens.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BusinessSectionHeader(
            title: '오더',
            subtitle: '배정된 작업의 현재 단계와 다음 할 일을 확인하세요',
          ),
          const SizedBox(height: BusinessTokens.space12),
          Row(
            children: [
              BusinessFilterChip(
                label: '작업 진행',
                selected: _filter == 'in_progress',
                count: _combinedJobs.length,
                onTap: () => setState(() => _filter = 'in_progress'),
              ),
              const SizedBox(width: BusinessTokens.space8),
              BusinessFilterChip(
                label: '완료',
                selected: _filter == 'completed',
                count: _completedJobs.length,
                onTap: () => setState(() => _filter = 'completed'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModernChip(
      String label, String value, IconData icon, int count) {
    final isSelected = _filter == value;
    final color = const Color(0xFF0B2545); // Navy for professional style

    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey[300]!,
            width: 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Colors.white : color,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? Colors.white : Colors.grey[700],
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withOpacity(0.3)
                      : color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : color,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Job> _filteredByBadge(List<Job> jobs, String me) {
    if (_filter == 'completed') return _completedJobs; // 완료된 공사 별도 처리
    // 기본적으로 진행 중인 공사만 표시 (내가 가져간 공사)
    return jobs;
  }

  void _openBidderList(String listingId, String orderTitle) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => OrderBiddersScreen(
          listingId: listingId,
          orderTitle: orderTitle,
        ),
      ),
    );

    // 입찰자가 선택되었으면 목록 새로고침
    if (result == true) {
      print('🔄 [JobManagement] 입찰자 선택 완료, 목록 새로고침');
      await _loadJobs();
    }
  }

  /// 공사 취소 처리
  Future<void> _cancelJob(Job job) async {
    final listing = _listingForJob(job);
    if (listing == null) return;

    final listingId = listing['id']?.toString() ?? '';
    if (listingId.isEmpty) return;

    final reason = await Navigator.push<JobCancelReason>(
      context,
      MaterialPageRoute(
        builder: (_) => JobCancelReasonScreen(jobTitle: job.title),
      ),
    );
    if (reason == null || !mounted) return;

    setState(() => _isLoading = true);

    try {
      final jobService = context.read<JobService>();
      final rawJobId = job.id ?? '';
      await jobService.cancelJobByAssignee(
        rawJobId,
        listingId,
        reasonCategory: reason.category,
        reasonDetail: reason.detail,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('공사가 취소되었습니다.'), backgroundColor: Colors.orange),
        );
        await _loadJobs();
      }
    } catch (e) {
      print('❌ [JobManagement] 공사 취소 에러: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('취소 실패: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _completeJob(Job job) async {
    print('🔘 [_completeJob] 공사 완료 버튼 클릭!');
    print('   jobId: ${job.id}');
    print('   job.status: ${job.status}');
    print('   job.title: ${job.title}');

    // 중복 실행 방지
    if (_isCompleting) {
      print('⚠️ [_completeJob] 이미 완료 작업 진행 중, 무시');
      return;
    }

    // 완료 확인 다이얼로그
    print('🔘 [_completeJob] 확인 다이얼로그 표시');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('작업 완료'),
        content: const Text(
          '작업 완료를 알리시겠습니까?\n'
          '완료 후 요청 업체가 확인하고 리뷰를 남길 수 있습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('완료하기'),
          ),
        ],
      ),
    );

    print('🔘 [_completeJob] 사용자 확인 결과: $confirmed');
    if (confirmed != true) return;

    setState(() => _isCompleting = true);

    try {
      // 로딩 표시
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(child: CircularProgressIndicator()),
        );
      }

      final authService = context.read<AuthService>();
      final currentUserId = authService.currentUser?.id;

      if (currentUserId == null) throw Exception('로그인이 필요합니다');

      print('🔄 [JobManagement] 공사 완료 처리 시작: jobId=${job.id}');
      print('   listingByJobId: ${_listingByJobId.keys.toList()}');

      final listing = _listingForJob(job);
      String? listingId =
          listing?['id']?.toString() ?? _listingIdFromJobId(job.id);
      late final String? realJobId;
      if (_isListingOnlyJobId(job.id)) {
        realJobId = listing == null ? null : listing['jobid']?.toString();
      } else {
        realJobId = job.id;
      }

      if (listingId == null &&
          realJobId != null &&
          !_isListingOnlyJobId(realJobId)) {
        print('   listingId 없음, 직접 조회 시도 (jobid=$realJobId)');
        final listings = await Supabase.instance.client
            .from('marketplace_listings')
            .select('id, jobid, claimed_by, selected_bidder_id')
            .eq('jobid', realJobId)
            .or('claimed_by.eq.$currentUserId,selected_bidder_id.eq.$currentUserId');

        print('   직접 조회 결과: ${listings.length}개');
        if (listings.isNotEmpty) {
          listingId = listings.first['id']?.toString();
          print('   직접 조회로 listingId 찾음: $listingId');
        }
      }

      if (listingId != null) {
        print('   marketplace_listings 업데이트 중: $listingId');
        // ✅ status를 'awaiting_confirmation'으로 변경 (원 사업자 확인 대기)
        final updateResult = await Supabase.instance.client
            .from('marketplace_listings')
            .update({
              'status': 'awaiting_confirmation',
              'completed_at': DateTime.now().toIso8601String(),
              'completed_by': currentUserId,
              'updatedat': DateTime.now().toIso8601String(),
            })
            .eq('id', listingId)
            .select();

        print('   marketplace_listings 업데이트 결과: ${updateResult.length}개 행');
        if (updateResult.isEmpty) {
          // 0행 = RLS 차단 또는 대상 없음. 완료로 표시하면 유령 성공이 됩니다.
          throw Exception('공사 상태를 변경할 권한이 없거나 대상을 찾을 수 없습니다.');
        }
        print(
            '   ✅ marketplace_listings 업데이트 성공: ${updateResult.first['status']}');

        // 오더 소유자(생성자)에게 후기/평점 작성 push 알림
        // (웹 고객 낙찰 건은 owner_business_id == 낙찰 사업자 본인이므로 자기 자신에게는 보내지 않음)
        final ownerId = job.ownerBusinessId;
        print('   알림 전송 중: $ownerId');
        if (ownerId != null && ownerId.isNotEmpty && ownerId != currentUserId) {
          await Supabase.instance.client.from('notifications').insert({
            'userid': ownerId,
            'title': '후기/평점 작성 안내',
            'body': '${job.title} 공사가 완료되었습니다. 후기와 평점을 작성해 주세요.',
            'type': 'review_request',
            if (listingId != null) 'listingid': listingId,
            if (realJobId != null && !_isListingOnlyJobId(realJobId))
              'jobid': realJobId,
            'isread': false,
            'createdat': DateTime.now().toIso8601String(),
          });
        } else {
          print('⚠️ [JobManagement] ownerId 없거나 본인이라 알림을 건너뜀');
        }

        // 웹 고객이 낙찰한 공사라면, 고객에게 공사 완료·평점 요청 문자 발송
        // (최종 완료 처리는 고객이 웹에서 직접 확인해야 확정됨)
        if (realJobId != null && !_isListingOnlyJobId(realJobId)) {
          try {
            final jobRow = await Supabase.instance.client
                .from('jobs')
                .select('web_order_id')
                .eq('id', realJobId)
                .maybeSingle();
            final webOrderId = jobRow?['web_order_id']?.toString();
            if (webOrderId != null && webOrderId.isNotEmpty && mounted) {
              // 실패해도 완료 처리 자체는 계속 진행 (알림 발송은 best-effort)
              // ignore: use_build_context_synchronously
              await context
                  .read<ApiService>()
                  .post('/customer/order/$webOrderId/notify-work-done', {});
            }
          } catch (e) {
            print('⚠️ [JobManagement] 웹 오더 완료유도 알림 발송 실패 (무시): $e');
          }
        }

        // 로컬 상태는 아래 _loadJobs()로 서버 기준으로 다시 맞춥니다.
        // (여기서 미리 바꾸면 뒤따르는 jobs UPDATE가 실패해도 완료로 보임)
        print('✅ [JobManagement] 공사 완료 처리 완료 (awaiting_confirmation)');
      } else {
        throw Exception('완료 처리할 협업 일감을 찾을 수 없습니다.');
      }

      // jobs 테이블도 업데이트 (실제 job이 연결된 경우만)
      if (realJobId != null &&
          realJobId.isNotEmpty &&
          !_isListingOnlyJobId(realJobId)) {
        print('   jobs 테이블 업데이트 중');
        final jobUpdateResult = await Supabase.instance.client
            .from('jobs')
            .update({
              'status': 'awaiting_confirmation',
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', realJobId)
            .select();

        print('   jobs 업데이트 결과: ${jobUpdateResult.length}개 행');
        if (jobUpdateResult.isEmpty) {
          throw Exception('공사(jobs) 상태를 변경할 권한이 없거나 대상을 찾을 수 없습니다.');
        }
        print('   ✅ jobs 업데이트 성공: ${jobUpdateResult.first['status']}');
      }

      if (mounted) {
        Navigator.pop(context); // 로딩 닫기

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('공사 완료 요청이 전송되었습니다!\n원 사업자의 확인을 기다리고 있어요'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );

        await _loadJobs(); // 목록 새로고침
      }
    } catch (e) {
      print('❌ [JobManagement] 공사 완료 실패: $e');

      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop(); // 로딩 닫기

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('공사 완료 처리 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );

        // 중간까지 성공한 변경이 있을 수 있으므로 서버 상태로 재동기화
        await _loadJobs();
      }
    } finally {
      if (mounted) {
        setState(() => _isCompleting = false);
      }
    }
  }

  Future<void> _openReviewScreen(Job job) async {
    final listing = _listingForJob(job);
    if (listing == null) return;

    final listingId = listing['id']?.toString() ?? '';
    final revieweeId = job.assignedBusinessId ?? '';

    if (listingId.isEmpty || revieweeId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('리뷰를 작성할 수 없습니다')),
      );
      return;
    }

    // 리뷰 대상 사업자 이름 가져오기
    try {
      final user = await Supabase.instance.client
          .from('users')
          .select('businessname, name')
          .eq('id', revieweeId)
          .maybeSingle();

      final revieweeName = user?['businessname'] ?? user?['name'] ?? '사업자';

      if (!mounted) return;

      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => OrderReviewScreen(
            listingId: listingId,
            jobId: _isListingOnlyJobId(job.id) ? null : job.id,
            revieweeId: revieweeId,
            revieweeName: revieweeName,
            orderTitle: job.title,
          ),
        ),
      );

      if (result == true) {
        await _loadJobs();
      }
    } catch (e) {
      print('❌ [JobManagement] 리뷰 화면 열기 실패: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('리뷰 화면을 열 수 없습니다')),
      );
    }
  }
}

class _ModernJobsList extends StatelessWidget {
  final List<Job> jobs;
  final String currentUserId;
  final Map<String, Map<String, dynamic>> listingsByJobId;
  final void Function(String listingId, String orderTitle) onViewBidders;
  final Future<void> Function(Job job) onCompleteJob;
  final Future<void> Function(Job job) onCancelJob; // 추가
  final Future<void> Function(Job job) onReview;
  final ScrollController? scrollController;
  final String? highlightedJobId;

  const _ModernJobsList({
    required this.jobs,
    required this.currentUserId,
    required this.listingsByJobId,
    required this.onViewBidders,
    required this.onCompleteJob,
    required this.onCancelJob, // 추가
    required this.onReview,
    this.scrollController,
    this.highlightedJobId,
  });

  @override
  Widget build(BuildContext context) {
    return _buildCollaborationList(context);
  }

  // ignore: unused_element
  Widget _buildCollaborationListDraft(BuildContext context) {
    if (jobs.isEmpty) {
      return const BusinessEmptyState(
        icon: Icons.work_outline_rounded,
        title: '진행 중인 협업 일감이 없습니다',
        subtitle: '배정되거나 수주한 공사가 생기면 여기에 표시됩니다.',
      );
    }

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: jobs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final job = jobs[index];
        final listing = job.id == null ? null : listingsByJobId[job.id];
        final listingStatus = listing?['status']?.toString();
        final status = listingStatus ?? job.status;
        final listingId = listing?['id']?.toString();
        final listingTitle = listing?['title']?.toString() ?? job.title;
        final bidCount = listing == null
            ? 0
            : (listing['bid_count'] is int
                ? listing['bid_count'] as int
                : int.tryParse(listing['bid_count']?.toString() ?? '0') ?? 0);
        final isOwner = job.ownerBusinessId == currentUserId;
        final isAssignee = job.assignedBusinessId == currentUserId ||
            listing?['selected_bidder_id']?.toString() == currentUserId ||
            listing?['claimed_by']?.toString() == currentUserId;
        final isHighlighted = highlightedJobId != null &&
            (job.id == highlightedJobId || listingId == highlightedJobId);
        final amount = job.awardedAmount ?? job.budgetAmount;

        Widget? primaryAction;
        Widget? secondaryAction;
        if (isOwner && listingId != null && status != 'completed') {
          primaryAction = BusinessPrimaryButton(
            label: bidCount > 0 ? '참여 사업자 $bidCount명 비교' : '참여 현황 확인',
            icon: Icons.people_outline_rounded,
            onPressed: () => onViewBidders(listingId, listingTitle),
          );
        } else if (isAssignee &&
            (status == 'assigned' ||
                status == 'in_progress' ||
                status == 'awaiting_confirmation')) {
          final awaiting = status == 'awaiting_confirmation';
          primaryAction = BusinessPrimaryButton(
            label: awaiting ? '완료 확인 대기' : '작업 완료 처리',
            icon: awaiting
                ? Icons.hourglass_top_rounded
                : Icons.check_circle_outline_rounded,
            onPressed: awaiting ? null : () => onCompleteJob(job),
          );
          if (!awaiting) {
            secondaryAction = TextButton(
              onPressed: () => onCancelJob(job),
              style: TextButton.styleFrom(
                foregroundColor: BusinessTokens.danger,
              ),
              child: const Text('공사 취소'),
            );
          }
        } else if (isOwner && status == 'completed') {
          primaryAction = BusinessPrimaryButton(
            label: '후기 작성',
            icon: Icons.star_outline_rounded,
            onPressed: () => onReview(job),
          );
        }

        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          decoration: BusinessTokens.card(
            borderColor:
                isHighlighted ? BusinessTokens.blue : BusinessTokens.border,
          ),
          child: InkWell(
            onTap: () => _showJobDetail(context, job, listing),
            borderRadius: BorderRadius.circular(BusinessTokens.cardRadius),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            BusinessStatusChip.forJob(status),
                            const SizedBox(height: 10),
                            Text(
                              job.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: BusinessTokens.sectionTitle,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: BusinessTokens.mutedText,
                      ),
                    ],
                  ),
                  if (job.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      job.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: BusinessTokens.caption,
                    ),
                  ],
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 14,
                    runSpacing: 8,
                    children: [
                      if ((job.category ?? '').isNotEmpty)
                        _compactMeta(Icons.category_outlined, job.category!),
                      if ((job.location ?? '').isNotEmpty)
                        _compactMeta(Icons.place_outlined, job.location!),
                      if (amount != null && amount > 0)
                        _compactMeta(
                          Icons.payments_outlined,
                          _formatWon(amount),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _compactTimeline(status),
                  if (primaryAction != null) ...[
                    const SizedBox(height: 16),
                    primaryAction,
                  ],
                  if (secondaryAction != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: secondaryAction,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _compactMeta(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: BusinessTokens.mutedText),
        const SizedBox(width: 5),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 190),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: BusinessTokens.caption,
          ),
        ),
      ],
    );
  }

  Widget _compactTimeline(String status) {
    const labels = ['업체 배정', '일정 확정', '작업 진행', '완료 확인'];
    final current = switch (status) {
      'created' || 'open' => 0,
      'assigned' => 1,
      'in_progress' => 2,
      'awaiting_confirmation' || 'completed' => 3,
      _ => 0,
    };
    final completed = status == 'completed';

    return Row(
      children: List.generate(labels.length, (index) {
        final done = completed || index < current;
        final active = !completed && index == current;
        final color =
            done || active ? BusinessTokens.blue : BusinessTokens.border;
        return Expanded(
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: done
                      ? BusinessTokens.blue
                      : active
                          ? BusinessTokens.blueLight
                          : BusinessTokens.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 1.5),
                ),
                alignment: Alignment.center,
                child: done
                    ? const Icon(Icons.check_rounded,
                        size: 14, color: Colors.white)
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: active
                              ? BusinessTokens.blue
                              : BusinessTokens.mutedText,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
              if (index < labels.length - 1)
                Expanded(
                  child: Container(
                    height: 1.5,
                    color: done ? BusinessTokens.blue : BusinessTokens.border,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  String _formatWon(num amount) {
    final raw = amount.round().toString();
    final formatted = raw.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '$formatted원';
  }

  Widget buildLegacy(BuildContext context) {
    if (jobs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.yellow[50],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.construction_outlined,
                size: 50,
                color: Colors.yellow[700],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '공사가 없습니다',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Call 공사를 잡거나 새로 등록해보세요',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: jobs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final job = jobs[index];
        final isHighlighted = highlightedJobId != null &&
            (job.id == highlightedJobId ||
                (listingsByJobId[job.id ?? '']?['id']?.toString() ==
                    highlightedJobId));
        final listing = job.id != null ? listingsByJobId[job.id] : null;
        final listingStatus = listing?['status']?.toString();
        final effectiveStatus = listingStatus ?? job.status;
        final badge = _badgeFor(job, currentUserId, listing);
        final listingId = listing != null ? listing['id']?.toString() : null;
        final listingTitle = listing != null
            ? (listing['title']?.toString() ?? job.title)
            : job.title;
        final bidCount = listing != null
            ? (listing['bid_count'] is int
                ? listing['bid_count'] as int
                : int.tryParse(listing['bid_count']?.toString() ?? '0') ?? 0)
            : 0;
        final canViewBidders =
            job.ownerBusinessId == currentUserId && listingId != null;
        final isAssignee = job.assignedBusinessId == currentUserId ||
            listing?['selected_bidder_id']?.toString() == currentUserId ||
            listing?['claimed_by']?.toString() == currentUserId;

        // 액션 버튼 빌드
        Widget? actionButton;
        if (canViewBidders) {
          actionButton = SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0B2545),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              icon: const Icon(Icons.people_outline),
              label: Text(
                '입찰자 보기 ($bidCount명)',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: () => onViewBidders(listingId!, listingTitle),
            ),
          );
        } else if (isAssignee &&
            (effectiveStatus == 'assigned' ||
                effectiveStatus == 'in_progress' ||
                effectiveStatus == 'awaiting_confirmation' ||
                job.status == 'assigned' ||
                job.status == 'in_progress' ||
                job.status == 'awaiting_confirmation')) {
          final canComplete = effectiveStatus == 'assigned' ||
              effectiveStatus == 'in_progress' ||
              job.status == 'assigned' ||
              job.status == 'in_progress';
          print(
              '🔍 [BuildButton] jobId=${job.id}, status=$effectiveStatus, canComplete=$canComplete');

          actionButton = Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        effectiveStatus == 'awaiting_confirmation' ||
                                job.status == 'awaiting_confirmation'
                            ? Colors.grey[400]
                            : const Color(0xFF1F8A70),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  icon: Icon(
                    effectiveStatus == 'awaiting_confirmation' ||
                            job.status == 'awaiting_confirmation'
                        ? Icons.check_circle
                        : Icons.check_circle_outline,
                    size: 18,
                  ),
                  label: Text(
                    effectiveStatus == 'awaiting_confirmation' ||
                            job.status == 'awaiting_confirmation'
                        ? '확인 대기 중'
                        : '공사 완료',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  onPressed: canComplete ? () => onCompleteJob(job) : null,
                ),
              ),
              if (canComplete) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text(
                      '공사 취소',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    onPressed: () => onCancelJob(job),
                  ),
                ),
              ],
            ],
          );
        } else if (job.ownerBusinessId == currentUserId &&
            job.status == 'completed' &&
            listing != null &&
            listing['status'] == 'completed') {
          actionButton = SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              icon: const Icon(Icons.star_outline),
              label: const Text(
                '리뷰 작성',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: () => onReview(job),
            ),
          );
        }

        // 커스텀 배지는 표시하지 않음 (견적 금액으로 대체)
        final badges = <Widget>[];

        // 채팅방 바로가기 버튼 (진행 중 또는 완료된 공사일 때)
        if (listingId != null &&
            (job.status == 'in_progress' ||
                job.status == 'completed' ||
                job.status == 'awaiting_confirmation' ||
                job.status == 'assigned')) {
          return Stack(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 800),
                decoration: BoxDecoration(
                  border: isHighlighted
                      ? Border.all(color: const Color(0xFF0B2545), width: 3)
                      : null,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: isHighlighted
                      ? [
                          BoxShadow(
                            color: const Color(0xFF0B2545).withOpacity(0.3),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: ModernOrderCard(
                  orderId: job.id,
                  title: job.title,
                  description: job.description,
                  category: job.category,
                  region: job.location,
                  budget: job.awardedAmount ?? job.budgetAmount, // 낙찰 금액 우선 표시
                  status: job.status,
                  bidCount: bidCount > 0 ? bidCount : null,
                  onTap: () async =>
                      await _showJobDetail(context, job, listing),
                  actionButton: actionButton,
                  badges: badges,
                  customBudgetLabel: job.awardedAmount != null ? '견적 금액' : null,
                ),
              ),
              // 낙찰 알림에서 진입 시 채팅 버튼 안내 배너
              if (isHighlighted)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B2545),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(14),
                        bottomRight: Radius.circular(14),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline,
                            color: Colors.white, size: 14),
                        SizedBox(width: 6),
                        Text(
                          '우측 채팅 버튼을 눌러 발주자와 대화를 시작하세요',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
              Positioned(
                top: 66,
                right: 16,
                child: Material(
                  elevation: isHighlighted ? 6 : 2,
                  borderRadius: BorderRadius.circular(20),
                  color: isHighlighted ? const Color(0xFF0B2545) : null,
                  child: InkWell(
                    onTap: () async {
                      // 채팅방 이동 로직
                      try {
                        final chatService = ChatService();
                        final authService =
                            Provider.of<AuthService>(context, listen: false);
                        final currentUserId = authService.currentUser?.id;

                        if (currentUserId == null) return;

                        // 상대방 ID 확인 (오더 소유자)
                        final targetUserId = job.ownerBusinessId;

                        if (targetUserId == null) return;

                        // 채팅방 생성/조회
                        final chatRoomId = await chatService.ensureChatRoom(
                          customerId: targetUserId, // 오더 소유자
                          businessId: currentUserId, // 나 (낙찰받은 사업자)
                          listingId: listingId,
                          title: listingTitle,
                        );

                        // 채팅 화면으로 이동
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              chatRoomId: chatRoomId,
                              chatRoomTitle: listingTitle,
                            ),
                          ),
                        );
                      } catch (e) {
                        print('❌ 채팅방 이동 실패: $e');
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('채팅방을 열 수 없습니다.')),
                        );
                      }
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: isHighlighted
                          ? const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10)
                          : const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isHighlighted
                            ? const Color(0xFFFF6B35) // 강조: 주황색
                            : const Color(0xFF0B2545),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: isHighlighted
                            ? [
                                BoxShadow(
                                    color: const Color(0xFFFF6B35)
                                        .withOpacity(0.5),
                                    blurRadius: 8,
                                    spreadRadius: 2)
                              ]
                            : null,
                      ),
                      child: isHighlighted
                          ? const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.chat_bubble_outline,
                                    color: Colors.white, size: 18),
                                SizedBox(width: 4),
                                Text('채팅하기',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold)),
                              ],
                            )
                          : const Icon(Icons.chat_bubble_outline,
                              color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        return AnimatedContainer(
          duration: const Duration(milliseconds: 800),
          decoration: BoxDecoration(
            border: isHighlighted
                ? Border.all(color: const Color(0xFF0B2545), width: 3)
                : null,
            borderRadius: BorderRadius.circular(16),
            boxShadow: isHighlighted
                ? [
                    BoxShadow(
                      color: const Color(0xFF0B2545).withOpacity(0.3),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: ModernOrderCard(
            orderId: job.id,
            title: job.title,
            description: job.description,
            category: job.category,
            region: job.location,
            budget: job.awardedAmount ?? job.budgetAmount, // 낙찰 금액 우선 표시
            status: job.status,
            customBudgetLabel: job.awardedAmount != null ? '견적 금액' : null,
            bidCount: bidCount > 0 ? bidCount : null,
            onTap: () async => await _showJobDetail(context, job, listing),
            actionButton: actionButton,
            badges: badges,
          ),
        );
      },
    );
  }

  static final _wonFormat = NumberFormat('#,###', 'ko_KR');
  static final _dateFormat = DateFormat('yyyy.MM.dd', 'ko_KR');

  Widget _buildCollaborationList(BuildContext context) {
    if (jobs.isEmpty) {
      return const BusinessEmptyState(
        icon: Icons.assignment_outlined,
        title: '해당 상태의 협업 일감이 없습니다',
        subtitle: '다른 상태를 선택하거나 새로고침해 주세요.',
      );
    }

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.all(BusinessTokens.space16),
      itemCount: jobs.length,
      separatorBuilder: (_, __) =>
          const SizedBox(height: BusinessTokens.space12),
      itemBuilder: (context, index) {
        final job = jobs[index];
        final listing = job.id != null ? listingsByJobId[job.id] : null;
        final listingStatus = listing?['status']?.toString();
        final effectiveStatus = listingStatus ?? job.status;
        final listingId = listing?['id']?.toString();
        final listingTitle = listing?['title']?.toString() ?? job.title;
        final bidCount = listing?['bid_count'] is int
            ? listing!['bid_count'] as int
            : int.tryParse(listing?['bid_count']?.toString() ?? '0') ?? 0;
        final canViewBidders =
            job.ownerBusinessId == currentUserId && listingId != null;
        final isAssignee = job.assignedBusinessId == currentUserId ||
            listing?['selected_bidder_id']?.toString() == currentUserId ||
            listing?['claimed_by']?.toString() == currentUserId;
        final canComplete = isAssignee &&
            (effectiveStatus == 'assigned' ||
                effectiveStatus == 'in_progress' ||
                job.status == 'assigned' ||
                job.status == 'in_progress');
        final isAwaiting = effectiveStatus == 'awaiting_confirmation' ||
            job.status == 'awaiting_confirmation';
        final canReview = job.ownerBusinessId == currentUserId &&
            job.status == 'completed' &&
            listing != null &&
            listing['status'] == 'completed';
        final canChat = listingId != null &&
            (job.status == 'in_progress' ||
                job.status == 'completed' ||
                job.status == 'awaiting_confirmation' ||
                job.status == 'assigned');
        final isHighlighted = highlightedJobId != null &&
            (job.id == highlightedJobId ||
                listing?['id']?.toString() == highlightedJobId);

        Widget primaryAction;
        var primaryOpensDetail = false;
        if (canViewBidders) {
          primaryAction = BusinessPrimaryButton(
            label: '업체 배정하기 ($bidCount명)',
            icon: Icons.people_outline,
            onPressed: () => onViewBidders(listingId, listingTitle),
          );
        } else if (canComplete) {
          primaryAction = BusinessPrimaryButton(
            label: '작업 완료 알리기',
            icon: Icons.task_alt_rounded,
            onPressed: () => onCompleteJob(job),
          );
        } else if (isAwaiting) {
          primaryAction = const BusinessPrimaryButton(
            label: '완료 확인 대기',
            icon: Icons.hourglass_top_rounded,
          );
        } else if (canReview) {
          primaryAction = BusinessPrimaryButton(
            label: '후기 작성',
            icon: Icons.star_outline_rounded,
            onPressed: () => onReview(job),
          );
        } else {
          primaryOpensDetail = true;
          primaryAction = BusinessPrimaryButton(
            label: '진행 상세 보기',
            icon: Icons.chevron_right_rounded,
            secondary: true,
            onPressed: () => _showJobDetail(context, job, listing),
          );
        }

        final amount = job.awardedAmount ?? job.budgetAmount;
        final location = job.location?.trim();
        final infoRows = <Widget>[
          _buildCurrentInfoRow(
            Icons.calendar_today_outlined,
            '등록 일자',
            _dateFormat.format(job.createdAt),
          ),
          if (location != null && location.isNotEmpty)
            _buildCurrentInfoRow(
              Icons.location_on_outlined,
              '작업 위치',
              location,
            ),
          if (amount != null)
            _buildCurrentInfoRow(
              Icons.payments_outlined,
              job.awardedAmount != null ? '확정 금액' : '예상 금액',
              '${_wonFormat.format(amount)}원',
            ),
          _buildCurrentInfoRow(
            Icons.privacy_tip_outlined,
            '연락 안내',
            canChat ? '배정 이후 연락은 협업 채팅을 이용해 주세요.' : '연락처는 업체 배정 후 확인할 수 있습니다.',
          ),
        ];

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.all(BusinessTokens.space16),
          decoration: BusinessTokens.card(
            borderColor:
                isHighlighted ? BusinessTokens.blue : BusinessTokens.border,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      isHighlighted ? '확인할 협업 일감' : '협업 일감',
                      style: BusinessTokens.caption,
                    ),
                  ),
                  _statusChip(effectiveStatus),
                ],
              ),
              const SizedBox(height: BusinessTokens.space12),
              Text(
                job.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: BusinessTokens.title,
              ),
              const SizedBox(height: BusinessTokens.space16),
              if (effectiveStatus != 'cancelled') ...[
                _buildTimeline(effectiveStatus),
                const SizedBox(height: BusinessTokens.space16),
              ],
              const Divider(height: 1, color: BusinessTokens.border),
              const SizedBox(height: BusinessTokens.space12),
              const BusinessSectionHeader(title: '현재 정보'),
              const SizedBox(height: BusinessTokens.space12),
              for (var infoIndex = 0;
                  infoIndex < infoRows.length;
                  infoIndex++) ...[
                if (infoIndex > 0)
                  const SizedBox(height: BusinessTokens.space12),
                infoRows[infoIndex],
              ],
              const SizedBox(height: BusinessTokens.space16),
              primaryAction,
              if (canChat) ...[
                const SizedBox(height: BusinessTokens.space8),
                BusinessPrimaryButton(
                  label: '협업 채팅',
                  icon: Icons.chat_bubble_outline_rounded,
                  secondary: true,
                  onPressed: () => _openCollaborationChat(
                    context,
                    job,
                    listingId,
                    listingTitle,
                  ),
                ),
              ],
              if (!primaryOpensDetail || canComplete) ...[
                const SizedBox(height: BusinessTokens.space8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!primaryOpensDetail)
                      TextButton(
                        onPressed: () => _showJobDetail(context, job, listing),
                        child: const Text('진행 정보 보기'),
                      ),
                    if (!primaryOpensDetail && canComplete)
                      const SizedBox(width: BusinessTokens.space8),
                    if (canComplete)
                      TextButton(
                        onPressed: () => onCancelJob(job),
                        style: TextButton.styleFrom(
                          foregroundColor: BusinessTokens.danger,
                        ),
                        child: const Text('작업 취소'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  static Widget _buildCurrentInfoRow(
    IconData icon,
    String label,
    String value,
  ) {
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

  static Future<void> _openCollaborationChat(
    BuildContext context,
    Job job,
    String? listingId,
    String listingTitle,
  ) async {
    try {
      if (listingId == null) return;
      final chatService = ChatService();
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUserId = authService.currentUser?.id;
      if (currentUserId == null) return;

      final targetUserId = job.ownerBusinessId;
      final chatRoomId = await chatService.ensureChatRoom(
        customerId: targetUserId,
        businessId: currentUserId,
        listingId: listingId,
        title: listingTitle,
      );

      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatRoomId: chatRoomId,
            chatRoomTitle: listingTitle,
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('채팅방을 열 수 없습니다.')),
      );
    }
  }

  static Future<void> _showJobDetail(
      BuildContext context, Job job, Map<String, dynamic>? listing) async {
    // ── 웹 고객 낙찰 여부 파싱 ──────────────────────────────────────
    String desc = job.description;
    print(
        '🔍 [_showJobDetail] job.title=${job.title}, desc="${desc.length > 60 ? desc.substring(0, 60) : desc}"');

    // description이 없거나 [웹 고객 낙찰]이 없으면 DB에서 직접 조회
    if (!desc.contains('[웹 고객 낙찰]') && job.id != null) {
      try {
        final data = await Supabase.instance.client
            .from('jobs')
            .select('description')
            .eq('id', job.id!)
            .maybeSingle();
        if (data != null && (data['description'] ?? '').contains('[웹 고객 낙찰]')) {
          desc = data['description'] as String;
          print('✅ [_showJobDetail] DB에서 description 로드 성공');
        }
      } catch (e) {
        print('⚠️ [_showJobDetail] DB description 조회 실패: $e');
      }
    }

    final isWebOrder = desc.contains('[웹 고객 낙찰]');
    String webCustomerContact = ''; // "이름 / 전화번호"
    String webCustomerAddress = '';
    String webOriginalRequest = '';

    if (isWebOrder) {
      for (final line in desc.split('\n')) {
        final t = line.trim();
        if (t.startsWith('📞 고객:')) {
          webCustomerContact = t.replaceFirst('📞 고객:', '').trim();
        } else if (t.startsWith('📍 주소:')) {
          webCustomerAddress = t.replaceFirst('📍 주소:', '').trim();
        } else if (t.startsWith('요청:')) {
          webOriginalRequest = t.replaceFirst('요청:', '').trim();
        }
      }
    }

    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isWebOrder)
                            Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color:
                                    const Color(0xFF0EA5E9).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                '웹 고객 배정',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF0369A1),
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          Text(
                            job.title,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (job.status != 'cancelled') ...[
                  _buildTimeline(job.status),
                  const SizedBox(height: 20),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                ],

                // ── 웹 고객 연락처 (웹 낙찰일 때만) ──────────────────────
                if (isWebOrder) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0B2545), Color(0xFF2563EB)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.person_pin_circle,
                                color: Colors.white, size: 18),
                            SizedBox(width: 6),
                            Text(
                              '고객 연락처',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        if (webCustomerContact.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(
                                  ClipboardData(text: webCustomerContact));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('연락처가 클립보드에 복사됐습니다'),
                                    duration: Duration(seconds: 2)),
                              );
                            },
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.phone_outlined,
                                      color: Colors.white70, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      webCustomerContact,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  const Icon(Icons.copy_outlined,
                                      color: Colors.white54, size: 16),
                                ],
                              ),
                            ),
                          ),
                        ],
                        if (webCustomerAddress.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(
                                  ClipboardData(text: webCustomerAddress));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('주소가 클립보드에 복사됐습니다'),
                                    duration: Duration(seconds: 2)),
                              );
                            },
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.location_on_outlined,
                                      color: Colors.white70, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      webCustomerAddress,
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 14),
                                    ),
                                  ),
                                  const Icon(Icons.copy_outlined,
                                      color: Colors.white54, size: 16),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Description
                const Text(
                  '설명',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87),
                ),
                const SizedBox(height: 8),
                Text(
                  isWebOrder && webOriginalRequest.isNotEmpty
                      ? webOriginalRequest
                      : desc,
                  style: TextStyle(
                      fontSize: 14, color: Colors.grey[700], height: 1.5),
                ),
                const SizedBox(height: 16),

                // Details
                if (job.location != null && job.location!.trim().isNotEmpty)
                  _buildDetailRow(
                    Icons.location_on_outlined,
                    '작업 위치',
                    job.location!,
                  ),
                if (job.location != null && job.location!.trim().isNotEmpty)
                  const SizedBox(height: 8),
                if (job.budgetAmount != null)
                  _buildDetailRow(
                    Icons.payments_outlined,
                    '예상 금액',
                    '${_wonFormat.format(job.budgetAmount)}원',
                  ),
                if (job.budgetAmount != null) const SizedBox(height: 8),
                _buildDetailRow(
                  Icons.privacy_tip_outlined,
                  '연락 안내',
                  '배정 이후 연락은 협업 채팅을 이용해 주세요.',
                ),

                // Listing info
                if (listing != null) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  const Text(
                    '배정 정보',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87),
                  ),
                  const SizedBox(height: 8),
                  _buildDetailRow(
                    Icons.info_outline,
                    '진행 상태',
                    _getStatusText(
                      listing['status']?.toString() ?? job.status,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (listing['bid_count'] != null)
                    _buildDetailRow(Icons.people_outline, '입찰 수',
                        '${listing['bid_count']}명'),
                ],

                const SizedBox(height: 24),

                // Close button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E74B5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('닫기',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 공사 진행 현황 타임라인 ───────────────────────────────────────────
  static Widget _statusChip(String status) {
    switch (status) {
      case 'created':
      case 'open':
        return const BusinessStatusChip(
          label: '업체 배정',
          tone: BusinessStatusTone.info,
        );
      case 'pending_transfer':
        return const BusinessStatusChip(
          label: '업체 배정 대기',
          tone: BusinessStatusTone.warning,
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

  static Widget _buildTimeline(String status) {
    const labels = ['업체 배정', '일정 확정', '작업 진행', '완료 확인'];
    final current = _statusToStep(status);
    final fullyCompleted = status == 'completed';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BusinessSectionHeader(
          title: '진행 관리',
          subtitle: '현재 상태에 맞춰 협업 단계를 표시합니다',
        ),
        const SizedBox(height: BusinessTokens.space16),
        for (var index = 0; index < labels.length; index++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 30,
                  child: Column(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: index < current || fullyCompleted
                              ? BusinessTokens.blue
                              : index == current
                                  ? BusinessTokens.blueLight
                                  : BusinessTokens.surface,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: index <= current || fullyCompleted
                                ? BusinessTokens.blue
                                : BusinessTokens.border,
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          index < current || fullyCompleted
                              ? Icons.check_rounded
                              : index == current
                                  ? Icons.circle
                                  : Icons.circle_outlined,
                          size: index == current ? 9 : 16,
                          color: index < current || fullyCompleted
                              ? Colors.white
                              : index == current
                                  ? BusinessTokens.blue
                                  : BusinessTokens.border,
                        ),
                      ),
                      if (index < labels.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            color: index < current || fullyCompleted
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
                    padding: const EdgeInsets.only(
                      top: 3,
                      bottom: BusinessTokens.space16,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            labels[index],
                            style: BusinessTokens.body.copyWith(
                              fontWeight: index == current
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: index <= current || fullyCompleted
                                  ? BusinessTokens.text
                                  : BusinessTokens.mutedText,
                            ),
                          ),
                        ),
                        if (index == current && !fullyCompleted)
                          const BusinessStatusChip(
                            label: '현재 단계',
                            tone: BusinessStatusTone.info,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ignore: unused_element
  static Widget buildLegacyTimeline(String status) {
    const steps = ['낙찰\n확정', '공사\n진행', '완료\n확인', '완료'];
    final current = _statusToStep(status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _getStatusColor(status),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _getStatusText(status),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            const Text('공사 현황',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            for (int i = 0; i < steps.length; i++) ...[
              Expanded(
                child: Column(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: i <= current
                            ? const Color(0xFF0B2545)
                            : Colors.grey[200],
                        shape: BoxShape.circle,
                        boxShadow: i == current
                            ? [
                                BoxShadow(
                                    color: const Color(0xFF0B2545)
                                        .withOpacity(0.35),
                                    blurRadius: 8,
                                    spreadRadius: 1)
                              ]
                            : null,
                      ),
                      child: Center(
                        child: i < current
                            ? const Icon(Icons.check_rounded,
                                color: Colors.white, size: 20)
                            : Text(
                                '${i + 1}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: i == current
                                      ? Colors.white
                                      : Colors.grey[400],
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      steps[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.3,
                        fontWeight:
                            i == current ? FontWeight.bold : FontWeight.normal,
                        color: i <= current
                            ? const Color(0xFF0B2545)
                            : Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),
              if (i < steps.length - 1)
                Container(
                  height: 2,
                  width: 14,
                  margin: const EdgeInsets.only(bottom: 30),
                  color:
                      i < current ? const Color(0xFF0B2545) : Colors.grey[300],
                ),
            ],
          ],
        ),
      ],
    );
  }

  static int _statusToStep(String status) {
    switch (status) {
      case 'assigned':
        return 1;
      case 'in_progress':
        return 2;
      case 'awaiting_confirmation':
      case 'completed':
        return 3;
      case 'created':
      case 'pending_transfer':
      case 'cancelled':
      default:
        return 0;
    }
  }

  static Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
            ),
          ),
        ),
      ],
    );
  }

  static Color _getStatusColor(String status) {
    switch (status) {
      case 'created':
        return Colors.blue;
      case 'pending_transfer':
        return Colors.orange;
      case 'assigned':
      case 'in_progress':
        return Colors.green;
      case 'awaiting_confirmation':
        return Colors.purple;
      case 'completed':
        return Colors.teal;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  static String _getStatusText(String status) {
    switch (status) {
      case 'created':
        return '업체 배정';
      case 'pending_transfer':
        return '업체 배정 대기';
      case 'assigned':
        return '일정 확정';
      case 'in_progress':
        return '작업 진행';
      case 'awaiting_confirmation':
        return '완료 확인';
      case 'completed':
        return '완료';
      case 'cancelled':
        return '취소됨';
      default:
        return status;
    }
  }

  static _Badge _badgeFor(Job job, String me, Map<String, dynamic>? listing) {
    // ✅ 입찰 대기 상태 확인 (내가 입찰한 오더)
    if (listing != null) {
      final claimedBy = listing['claimed_by']?.toString();
      final selectedBidderId = listing['selected_bidder_id']?.toString();
      final listingStatus = listing['status']?.toString();

      // 내가 입찰했지만 아직 낙찰되지 않은 상태
      if (claimedBy == me &&
          selectedBidderId == null &&
          listingStatus != 'assigned') {
        return _Badge('낙찰 대기중', Colors.orange, Icons.schedule);
      }

      // 완료 확인 대기 중 상태
      if (listingStatus == 'awaiting_confirmation') {
        return _Badge('원 사업자 확인 대기중', Colors.purple, Icons.hourglass_empty);
      }
    }

    // 모든 공사는 내가 가져간 공사이므로 배지 통일
    return _Badge('진행 중', Colors.green, Icons.construction_outlined);
  }
}

class _Badge {
  final String label;
  final Color color;
  final IconData icon;

  const _Badge(this.label, this.color, this.icon);
}
