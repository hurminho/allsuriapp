import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:lottie/lottie.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../widgets/shimmer_widgets.dart';
import '../../services/auth_service.dart';
import '../../services/job_service.dart';
import '../../services/chat_service.dart'; // 추가
import '../../models/job.dart';
import '../../widgets/interactive_card.dart';
import '../../widgets/modern_order_card.dart';
import '../../widgets/modern_button.dart';
import '../../config/app_constants.dart';
import 'order_bidders_screen.dart';
import 'order_review_screen.dart';
import '../../services/api_service.dart';
import '../chat_screen.dart'; // 추가

class JobManagementScreen extends StatefulWidget {
  final String? highlightedJobId; // 포커싱할 공사 ID
  final String? initialFilter; // 초기 필터 ('in_progress', 'completed')
  
  const JobManagementScreen({
    super.key, 
    this.highlightedJobId,
    this.initialFilter,
  });

  @override
  State<JobManagementScreen> createState() => _JobManagementScreenState();
}

class _JobManagementScreenState extends State<JobManagementScreen> {
  List<Job> _combinedJobs = [];
  List<Job> _completedJobs = []; // 완료된 공사 (awaiting_confirmation + completed)
  bool _isLoading = true;
  late String _filter; // in_progress | completed (내가 가져간 공사만)
  Map<String, Map<String, dynamic>> _listingByJobId = {};
  bool _isCompleting = false; // 공사 완료 중 플래그
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 초기 필터 설정
    _filter = widget.initialFilter ?? 'in_progress';
    _loadJobs();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadJobs() async {
    setState(() => _isLoading = true);
    
    try {
      final authService = context.read<AuthService>();
      final jobService = context.read<JobService>();
      final currentUserId = authService.currentUser?.id;
      
      if (currentUserId == null) return;

      final allJobs = await jobService.getJobs();
      print('🔍 [JobManagement] 전체 공사: ${allJobs.length}개');
      
      // 내가 가져간 공사만 필터링 (assignedBusinessId == currentUserId)
      final myJobs = allJobs.where((job) {
        return job.assignedBusinessId == currentUserId;
      }).toList();
      
      // 완료된 공사 (awaiting_confirmation + completed)
      _completedJobs = myJobs.where((job) {
        return job.status == 'completed' || job.status == 'awaiting_confirmation';
      }).toList();
      
      // 진행 중인 공사 (완료 제외)
      final related = myJobs.where((job) {
        final isNotCompleted = job.status != 'completed' && job.status != 'awaiting_confirmation';
        
        if (!isNotCompleted) {
          print('   완료됨 필터로 이동: ${job.title} (status: ${job.status})');
        }
        
        return isNotCompleted;
      }).toList();
      
      final Map<String, Job> byId = {};
      for (final j in related) {
        final id = j.id ?? UniqueKey().toString();
        byId[id] = j;
      }
      _combinedJobs = byId.values.toList();
      
      print('🔍 [JobManagement] 진행중 공사: ${_combinedJobs.length}개, 완료된 공사: ${_completedJobs.length}개');

      // fetch marketplace listings for all related jobs (내가 올린 것 + 받은 것)
      final jobIds = _combinedJobs
          .map((job) => job.id)
          .whereType<String>()
          .toList();

      print('🔍 [JobManagement] jobIds: $jobIds');

      if (jobIds.isNotEmpty) {
        final api = ApiService();
        final Map<String, Map<String, dynamic>> tempMap = {};

        const chunkSize = 25;
        final List<List<String>> chunks = [
          for (var i = 0; i < jobIds.length; i += chunkSize)
            jobIds.sublist(i, i + chunkSize > jobIds.length ? jobIds.length : i + chunkSize),
        ];

        final responses = await Future.wait(chunks.map((chunk) async {
          final jobIdsParam = chunk.join(',');
          try {
            final response = await api.get('/market/listings?jobIds=$jobIdsParam&limit=${chunk.length}');
            if (response['success'] == true) {
              return List<Map<String, dynamic>>.from(response['data'] ?? []);
            } else {
              print('⚠️ [JobManagement] listing API 실패 (chunk=$chunk): ${response['error']}');
              return <Map<String, dynamic>>[];
            }
          } catch (e) {
            print('⚠️ [JobManagement] listing 조회 실패 (chunk=$chunk): $e');
            return <Map<String, dynamic>>[];
          }
        }));

        for (final list in responses) {
          for (final listing in list) {
            final jobId = listing['jobid']?.toString();
            if (jobId != null) {
              tempMap[jobId] = Map<String, dynamic>.from(listing);
            }
          }
        }

        _listingByJobId = tempMap;

        print('🔍 [JobManagement] 조회된 listings: ${_listingByJobId.length}개');
        if (_listingByJobId.isNotEmpty) {
          print('   첫 번째 listing: ${_listingByJobId.values.first}');
        }
        
        print('✅ [JobManagement] ${_listingByJobId.length}개 listing 매핑 완료');
        print('   매핑된 jobIds: ${_listingByJobId.keys.toList()}');
      } else {
        _listingByJobId = {};
        print('⚠️ [JobManagement] jobIds가 비어있음');
      }
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('공사 목록을 불러오는데 실패했습니다: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        
        // 🎯 포커싱: highlightedJobId가 있으면 해당 공사로 스크롤
        if (widget.highlightedJobId != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToHighlightedJob();
          });
        }
      }
    }
  }

  void _scrollToHighlightedJob() {
    if (widget.highlightedJobId == null || !mounted) return;

    // 약간의 지연을 두어 ListView가 완전히 빌드된 후 스크롤
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted || !_scrollController.hasClients) return;
      
      final filteredJobs = _filteredByBadge(_combinedJobs, context.read<AuthService>().currentUser?.id ?? '');
      final index = filteredJobs.indexWhere((job) => job.id == widget.highlightedJobId);

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
        
        print('✅ [JobManagement] ${widget.highlightedJobId} 공사로 스크롤 (index: $index, offset: $targetOffset)');
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          '내 공사 관리',
          style: TextStyle(
            color: Color(0xFF1E3A8A),
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Color(0xFF1E3A8A)),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF1E3A8A)),
            onPressed: _loadJobs,
            tooltip: '새로고침',
          ),
        ],
      ),
      body: _isLoading
          ? const ShimmerList(itemCount: 6, itemHeight: 120)
          : Column(
              children: [
                _buildModernFilterChips(),
                Expanded(
                  child: _ModernJobsList(
                    jobs: _filteredByBadge(_combinedJobs, context.read<AuthService>().currentUser?.id ?? ''),
                    currentUserId: context.read<AuthService>().currentUser?.id ?? '',
                    listingsByJobId: _listingByJobId,
                    onViewBidders: _openBidderList,
                    onCompleteJob: _completeJob,
                    onCancelJob: _cancelJob, // 추가
                    onReview: _openReviewScreen,
                    scrollController: _scrollController,
                    highlightedJobId: widget.highlightedJobId,
                  ),
                ),
              ],
            ),
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
          child: SizedBox(width: 140, height: 140, child: Lottie.asset('assets/lottie/check.json', repeat: false)),
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
    final me = context.read<AuthService>().currentUser?.id ?? '';
    
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '필터',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildModernChip('진행 중', 'in_progress', Icons.construction_outlined, _combinedJobs.length),
                const SizedBox(width: 10),
                _buildModernChip('완료됨', 'completed', Icons.check_circle_outline, _completedJobs.length),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernChip(String label, String value, IconData icon, int count) {
    final isSelected = _filter == value;
    final color = const Color(0xFF1E3A8A); // Navy for professional style
    
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
                  color: isSelected ? Colors.white.withOpacity(0.3) : color.withOpacity(0.15),
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
    final listing = _listingByJobId[job.id];
    if (listing == null) return;
    
    final listingId = listing['id']?.toString() ?? '';
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('공사 취소'),
        content: Text('[${job.title}] 공사를 취소하시겠습니까?\n취소 시 오더 소유자에게 알림이 전송됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('아니오', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('취소하기', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      final jobService = context.read<JobService>();
      await jobService.cancelJobByAssignee(job.id!, listingId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('공사가 취소되었습니다.'), backgroundColor: Colors.orange),
        );
        await _loadJobs(); // 목록 새로고침
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
        title: const Text('공사 완료'),
        content: const Text('이 공사를 완료하시겠습니까?\n완료 후 원 사업자가 확인하고 리뷰를 남길 수 있습니다.'),
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
      
      // marketplace_listings 찾기 (job.id로 직접 조회)
      String? listingId = _listingByJobId[job.id]?['id']?.toString();
      
      if (listingId == null && job.id != null) {
        // 직접 조회
        print('   listingId 없음, 직접 조회 시도 (jobid=${job.id})');
        final listings = await Supabase.instance.client
            .from('marketplace_listings')
            .select('id, jobid, claimed_by')
            .eq('jobid', job.id!)
            .eq('claimed_by', currentUserId); // 내가 가져간 것만
        
        print('   직접 조회 결과: ${listings.length}개');
        if (listings.isNotEmpty) {
          listingId = listings.first['id']?.toString();
          print('   직접 조회로 listingId 찾음: $listingId');
        } else {
          print('   ❌ 직접 조회 실패 - claimed_by로 조회해도 없음');
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
          print('   ⚠️ marketplace_listings UPDATE 실패 (RLS 차단?)');
        } else {
          print('   ✅ marketplace_listings 업데이트 성공: ${updateResult.first['status']}');
        }

        // 오더 소유자(생성자)에게 후기/평점 작성 push 알림
        final ownerId = job.ownerBusinessId;
        print('   알림 전송 중: $ownerId');
        if (ownerId != null && ownerId.isNotEmpty) {
          await Supabase.instance.client.from('notifications').insert({
            'userid': ownerId,
            'title': '후기/평점 작성 안내',
            'body': '${job.title} 공사가 완료되었습니다. 후기와 평점을 작성해 주세요.',
            'type': 'review_request',
            if (listingId != null) 'listingid': listingId,
            if (job.id != null) 'jobid': job.id,
            'isread': false,
            'createdat': DateTime.now().toIso8601String(),
          });
        } else {
          print('⚠️ [JobManagement] ownerId 없어 알림을 건너뜀');
        }

        print('✅ [JobManagement] 공사 완료 처리 완료 (awaiting_confirmation)');
        if (mounted && job.id != null) {
          setState(() {
            final idx = _combinedJobs.indexWhere((j) => j.id == job.id);
            if (idx != -1) {
              _combinedJobs[idx] = _combinedJobs[idx].copyWith(status: 'awaiting_confirmation');
            }
            if (_listingByJobId.containsKey(job.id)) {
              _listingByJobId[job.id]!['status'] = 'awaiting_confirmation';
            }
          });
        }
      } else {
        print('⚠️ [JobManagement] listingId를 찾을 수 없음');
      }

      // jobs 테이블도 업데이트
      if (job.id != null) {
        print('   jobs 테이블 업데이트 중');
        final jobUpdateResult = await Supabase.instance.client
            .from('jobs')
            .update({
              'status': 'awaiting_confirmation',
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', job.id!)
            .select();
        
        print('   jobs 업데이트 결과: ${jobUpdateResult.length}개 행');
        if (jobUpdateResult.isEmpty) {
          print('   ⚠️ jobs UPDATE 실패 (RLS 차단?)');
        } else {
          print('   ✅ jobs 업데이트 성공: ${jobUpdateResult.first['status']}');
        }
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
      }
    } finally {
      if (mounted) {
        setState(() => _isCompleting = false);
      }
    }
  }

  Future<void> _openReviewScreen(Job job) async {
    final listing = _listingByJobId[job.id];
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
            jobId: job.id ?? '',
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
        final isHighlighted = highlightedJobId != null && job.id == highlightedJobId;
        final listing = job.id != null ? listingsByJobId[job.id] : null;
        final badge = _badgeFor(job, currentUserId, listing);
        final listingId = listing != null ? listing['id']?.toString() : null;
        final listingTitle = listing != null ? (listing['title']?.toString() ?? job.title) : job.title;
        final bidCount = listing != null
            ? (listing['bid_count'] is int
                ? listing['bid_count'] as int
                : int.tryParse(listing['bid_count']?.toString() ?? '0') ?? 0)
            : 0;
        final canViewBidders = job.ownerBusinessId == currentUserId && listingId != null;
        
        // 액션 버튼 빌드
        Widget? actionButton;
        if (canViewBidders) {
          actionButton = SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A8A),
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
        } else if (job.assignedBusinessId == currentUserId && 
                   (job.status == 'assigned' || job.status == 'in_progress' || job.status == 'awaiting_confirmation')) {
          final canComplete = (job.status == 'assigned' || job.status == 'in_progress');
          print('🔍 [BuildButton] jobId=${job.id}, status=${job.status}, canComplete=$canComplete');
          
          actionButton = Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: job.status == 'awaiting_confirmation' 
                        ? Colors.grey[400] 
                        : const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  icon: Icon(job.status == 'awaiting_confirmation' ? Icons.check_circle : Icons.check_circle_outline, size: 18),
                  label: Text(
                    job.status == 'awaiting_confirmation' ? '확인 대기 중' : '공사 완료',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
        if (listingId != null && (job.status == 'in_progress' || job.status == 'completed' || job.status == 'awaiting_confirmation' || job.status == 'assigned')) {
          return Stack(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 800),
                decoration: BoxDecoration(
                  border: isHighlighted ? Border.all(color: const Color(0xFF1E3A8A), width: 3) : null,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: isHighlighted ? [
                    BoxShadow(
                      color: const Color(0xFF1E3A8A).withOpacity(0.3),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ] : null,
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
                  onTap: () async => await _showJobDetail(context, job, listing),
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E3A8A),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(14),
                        bottomRight: Radius.circular(14),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline, color: Colors.white, size: 14),
                        SizedBox(width: 6),
                        Text(
                          '우측 채팅 버튼을 눌러 발주자와 대화를 시작하세요',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
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
                  color: isHighlighted ? const Color(0xFF1E3A8A) : null,
                  child: InkWell(
                    onTap: () async {
                      // 채팅방 이동 로직
                      try {
                        final chatService = ChatService();
                        final authService = Provider.of<AuthService>(context, listen: false);
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
                          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
                          : const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isHighlighted
                            ? const Color(0xFFFF6B35) // 강조: 주황색
                            : const Color(0xFF1E3A8A),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: isHighlighted
                            ? [BoxShadow(color: const Color(0xFFFF6B35).withOpacity(0.5), blurRadius: 8, spreadRadius: 2)]
                            : null,
                      ),
                      child: isHighlighted
                          ? const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.chat_bubble_outline, color: Colors.white, size: 18),
                                SizedBox(width: 4),
                                Text('채팅하기', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                              ],
                            )
                          : const Icon(Icons.chat_bubble_outline, color: Colors.white, size: 20),
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
            border: isHighlighted ? Border.all(color: const Color(0xFF1E3A8A), width: 3) : null,
            borderRadius: BorderRadius.circular(16),
            boxShadow: isHighlighted ? [
              BoxShadow(
                color: const Color(0xFF1E3A8A).withOpacity(0.3),
                blurRadius: 12,
                spreadRadius: 2,
              ),
            ] : null,
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

  static Future<void> _showJobDetail(BuildContext context, Job job, Map<String, dynamic>? listing) async {
    // ── 웹 고객 낙찰 여부 파싱 ──────────────────────────────────────
    String desc = job.description;
    print('🔍 [_showJobDetail] job.title=${job.title}, desc="${desc.length > 60 ? desc.substring(0, 60) : desc}"');

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
    String webCustomerContact = '';  // "이름 / 전화번호"
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
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0EA5E9).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                '🌐 웹 고객 낙찰',
                                style: TextStyle(fontSize: 11, color: Color(0xFF0369A1), fontWeight: FontWeight.w600),
                              ),
                            ),
                          Text(
                            job.title,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
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

                // 공사 진행 현황 타임라인
                _buildTimeline(job.status),
                const SizedBox(height: 20),
                const Divider(height: 1),
                const SizedBox(height: 16),

                // ── 웹 고객 연락처 (웹 낙찰일 때만) ──────────────────────
                if (isWebOrder) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
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
                            Icon(Icons.person_pin_circle, color: Colors.white, size: 18),
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
                              Clipboard.setData(ClipboardData(text: webCustomerContact));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('연락처가 클립보드에 복사됐습니다'), duration: Duration(seconds: 2)),
                              );
                            },
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.phone_outlined, color: Colors.white70, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      webCustomerContact,
                                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  const Icon(Icons.copy_outlined, color: Colors.white54, size: 16),
                                ],
                              ),
                            ),
                          ),
                        ],
                        if (webCustomerAddress.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: webCustomerAddress));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('주소가 클립보드에 복사됐습니다'), duration: Duration(seconds: 2)),
                              );
                            },
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.location_on_outlined, color: Colors.white70, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      webCustomerAddress,
                                      style: const TextStyle(color: Colors.white, fontSize: 14),
                                    ),
                                  ),
                                  const Icon(Icons.copy_outlined, color: Colors.white54, size: 16),
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
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87),
                ),
                const SizedBox(height: 8),
                Text(
                  isWebOrder && webOriginalRequest.isNotEmpty
                      ? webOriginalRequest
                      : desc,
                  style: TextStyle(fontSize: 14, color: Colors.grey[700], height: 1.5),
                ),
                const SizedBox(height: 16),
                
                // Details
                _buildDetailRow(Icons.location_on_outlined, '위치', job.location ?? '미정'),
                const SizedBox(height: 8),
                _buildDetailRow(Icons.category_outlined, '카테고리', job.category ?? '일반'),
                const SizedBox(height: 8),
                if (job.budgetAmount != null)
                  _buildDetailRow(Icons.attach_money, '예산', '₩${job.budgetAmount!.toStringAsFixed(0)}'),
                const SizedBox(height: 8),
                if (job.commissionRate != null)
                  _buildDetailRow(Icons.percent, '수수료율', '${job.commissionRate!.toStringAsFixed(1)}%'),
                const SizedBox(height: 8),
                if (job.commissionAmount != null)
                  _buildDetailRow(Icons.money_off, '수수료', '₩${job.commissionAmount!.toStringAsFixed(0)}'),
                
                // Listing info
                if (listing != null) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  const Text(
                    '오더 정보',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87),
                  ),
                  const SizedBox(height: 8),
                  _buildDetailRow(Icons.info_outline, '오더 상태', listing['status']?.toString() ?? '알 수 없음'),
                  const SizedBox(height: 8),
                  if (listing['bid_count'] != null)
                    _buildDetailRow(Icons.people_outline, '입찰 수', '${listing['bid_count']}명'),
                ],
                
                const SizedBox(height: 24),
                
                // Close button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1976D2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('닫기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
  static Widget _buildTimeline(String status) {
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
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            const Text('공사 현황', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54)),
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
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        color: i <= current ? const Color(0xFF1E3A8A) : Colors.grey[200],
                        shape: BoxShape.circle,
                        boxShadow: i == current
                            ? [BoxShadow(color: const Color(0xFF1E3A8A).withOpacity(0.35), blurRadius: 8, spreadRadius: 1)]
                            : null,
                      ),
                      child: Center(
                        child: i < current
                            ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                            : Text(
                                '${i + 1}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: i == current ? Colors.white : Colors.grey[400],
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
                        fontWeight: i == current ? FontWeight.bold : FontWeight.normal,
                        color: i <= current ? const Color(0xFF1E3A8A) : Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),
              if (i < steps.length - 1)
                Container(
                  height: 2, width: 14,
                  margin: const EdgeInsets.only(bottom: 30),
                  color: i < current ? const Color(0xFF1E3A8A) : Colors.grey[300],
                ),
            ],
          ],
        ),
      ],
    );
  }

  static int _statusToStep(String status) {
    switch (status) {
      case 'assigned':              return 0;
      case 'in_progress':           return 1;
      case 'awaiting_confirmation': return 2;
      case 'completed':             return 3;
      default:                      return 0;
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
        return '생성됨';
      case 'pending_transfer':
        return '이전 대기';
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

  static _Badge _badgeFor(Job job, String me, Map<String, dynamic>? listing) {
    // ✅ 입찰 대기 상태 확인 (내가 입찰한 오더)
    if (listing != null) {
      final claimedBy = listing['claimed_by']?.toString();
      final selectedBidderId = listing['selected_bidder_id']?.toString();
      final listingStatus = listing['status']?.toString();
      
      // 내가 입찰했지만 아직 낙찰되지 않은 상태
      if (claimedBy == me && selectedBidderId == null && listingStatus != 'assigned') {
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


