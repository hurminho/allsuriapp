import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/personal_order_link.dart';
import '../../services/personal_order_link_service.dart';
import '../../widgets/business/business_tokens.dart';
import '../../utils/app_logger.dart';
import 'personal_link_quote_request_screen.dart';

/// 개인 오더 링크 공개 페이지 (소비자용 웹)
class PersonalOrderLinkPublicPage extends StatefulWidget {
  final String slug;

  const PersonalOrderLinkPublicPage({super.key, required this.slug});

  @override
  State<PersonalOrderLinkPublicPage> createState() =>
      _PersonalOrderLinkPublicPageState();
}

class _PersonalOrderLinkPublicPageState
    extends State<PersonalOrderLinkPublicPage> {
  PersonalOrderLink? _link;
  bool _isLoading = true;
  String? _error;

  // 사업자 추가 정보 (DB에서 조회)
  double? _avgRating;
  int? _reviewCount;

  @override
  void initState() {
    super.initState();
    _loadLink();
  }

  Future<void> _loadLink() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final service =
          Provider.of<PersonalOrderLinkService>(context, listen: false);
      final link = await service.getPublicLinkBySlug(widget.slug);

      if (link == null) {
        setState(() {
          _error = '링크를 찾을 수 없습니다';
        });
        return;
      }

      // 링크 상태 확인
      if (link.status != PersonalOrderLinkStatus.active) {
        setState(() {
          _error = 'paused';
          _link = link;
        });
        return;
      }

      // 페이지 방문 이벤트 기록
      await service.trackEvent(
        personalOrderLinkId: link.id,
        eventType: PersonalOrderLinkEventType.pageView,
      );

      setState(() {
        _link = link;
      });
    } catch (e, stack) {
      AppLog.error('PersonalOrderLinkPublicPage', e,
          stack: stack, message: '링크 로드 실패');
      setState(() {
        _error = '링크를 불러오는 중 오류가 발생했습니다';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorView()
              : _buildPublicPage(),
    );
  }

  Widget _buildErrorView() {
    if (_error == 'paused' && _link != null) {
      return _buildPausedView();
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline,
                size: 64, color: BusinessTokens.danger),
            const SizedBox(height: 16),
            Text(
              _error ?? '오류가 발생했습니다',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadLink,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPausedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: BusinessTokens.warning.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.pause_circle_outline,
                  size: 48, color: BusinessTokens.warning),
            ),
            const SizedBox(height: 24),
            const Text(
              '현재 새 견적 요청을\n받고 있지 않습니다',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            Text(
              '다른 검증된 업체에 비교 견적을 요청하시겠습니까?',
              style: TextStyle(fontSize: 14, color: BusinessTokens.mutedText),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _requestComparisonQuotes,
              child: const Text('다른 업체 비교 견적 요청하기'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPublicPage() {
    if (_link == null) return const SizedBox();

    return SingleChildScrollView(
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              _buildContractorProfile(),
              const SizedBox(height: 20),
              _buildTrustInfo(),
              const SizedBox(height: 20),
              _buildDirectAssignmentBanner(),
              const SizedBox(height: 24),
              _buildCTA(),
              const SizedBox(height: 40),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContractorProfile() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // 프로필 이미지
          if (_link!.profileImageUrl != null)
            CircleAvatar(
              radius: 50,
              backgroundImage: NetworkImage(_link!.profileImageUrl!),
            )
          else
            CircleAvatar(
              radius: 50,
              backgroundColor: BusinessTokens.blueLight,
              child: Icon(Icons.person,
                  size: 50, color: BusinessTokens.blue),
            ),
          const SizedBox(height: 20),

          // 이름
          Text(
            _link!.displayName ?? '사업자',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),

          // 한 줄 소개
          if (_link!.headline != null) ...[
            const SizedBox(height: 8),
            Text(
              _link!.headline!,
              style: TextStyle(
                fontSize: 16,
                color: BusinessTokens.mutedText,
              ),
              textAlign: TextAlign.center,
            ),
          ],

          const SizedBox(height: 24),

          // 활동 지역 & 전문 분야
          if (_link!.serviceRegions.isNotEmpty || _link!.supportedCategories.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: BusinessTokens.canvas,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  if (_link!.serviceRegions.isNotEmpty)
                    _buildInfoRow(
                      Icons.location_on,
                      '활동 지역',
                      _link!.serviceRegions.join(' · '),
                    ),
                  if (_link!.serviceRegions.isNotEmpty && _link!.supportedCategories.isNotEmpty)
                    const SizedBox(height: 12),
                  if (_link!.supportedCategories.isNotEmpty)
                    _buildInfoRow(
                      Icons.build,
                      '전문 분야',
                      _link!.supportedCategories.join(' / '),
                    ),
                ],
              ),
            ),

          // 상세 소개
          if (_link!.introduction != null) ...[
            const SizedBox(height: 20),
            Text(
              _link!.introduction!,
              style: const TextStyle(fontSize: 14, height: 1.6),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: BusinessTokens.blue),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: BusinessTokens.mutedText,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTrustInfo() {
    if (_link!.verificationStatus != VerificationStatus.verified) {
      return const SizedBox();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BusinessTokens.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: BusinessTokens.success.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.verified, color: BusinessTokens.success, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '올수리 인증 사업자',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: BusinessTokens.success,
                  ),
                ),
                if (_avgRating != null && _reviewCount != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '평점 ${_avgRating!.toStringAsFixed(1)} · 후기 $_reviewCount건',
                    style: TextStyle(
                      fontSize: 12,
                      color: BusinessTokens.mutedText,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectAssignmentBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            BusinessTokens.blue.withValues(alpha: 0.08),
            BusinessTokens.blue.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: BusinessTokens.blue.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: BusinessTokens.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.person_pin, color: BusinessTokens.blue, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: '이 페이지에서 접수한 요청은\n'),
                  TextSpan(
                    text: '${_link!.displayName ?? '사업자'}에게만',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const TextSpan(text: ' 직접 전달됩니다.'),
                ],
              ),
              style: TextStyle(
                fontSize: 14,
                color: BusinessTokens.blue,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCTA() {
    return ElevatedButton(
      onPressed: _startQuoteRequest,
      style: ElevatedButton.styleFrom(
        backgroundColor: BusinessTokens.blue,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        elevation: 0,
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.edit_note, size: 24),
          SizedBox(width: 8),
          Text(
            '무료 견적 요청하기',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        const Divider(),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '올수리',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: BusinessTokens.mutedText,
              ),
            ),
            Text(
              ' · 설비 수리 견적 플랫폼',
              style: TextStyle(
                fontSize: 12,
                color: BusinessTokens.mutedText,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _startQuoteRequest() {
    // 이벤트 기록
    final service =
        Provider.of<PersonalOrderLinkService>(context, listen: false);
    service.trackEvent(
      personalOrderLinkId: _link!.id,
      eventType: PersonalOrderLinkEventType.quoteStart,
    );

    // 견적 요청 화면으로 이동
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PersonalLinkQuoteRequestScreen(link: _link!),
      ),
    );
  }

  void _requestComparisonQuotes() {
    // TODO: 비교 견적 요청 (마켓플레이스로 전환)
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('비교 견적 요청 기능이 곧 구현됩니다')),
    );
  }
}
