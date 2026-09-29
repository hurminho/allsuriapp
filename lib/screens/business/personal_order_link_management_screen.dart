import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../models/personal_order_link.dart';
import '../../providers/user_provider.dart';
import '../../services/personal_order_link_service.dart';
import '../../widgets/business/business_app_shell.dart';
import '../../widgets/business/business_tokens.dart';
import '../../widgets/business/business_primary_button.dart';
import '../../config.dart';
import '../../utils/app_logger.dart';
import '../../utils/personal_order_link_nav.dart';
import 'edit_personal_order_link_screen.dart';

/// 개인 오더 링크 관리 화면
class PersonalOrderLinkManagementScreen extends StatefulWidget {
  const PersonalOrderLinkManagementScreen({super.key});

  @override
  State<PersonalOrderLinkManagementScreen> createState() =>
      _PersonalOrderLinkManagementScreenState();
}

class _PersonalOrderLinkManagementScreenState
    extends State<PersonalOrderLinkManagementScreen> {
  PersonalOrderLink? _link;
  PersonalOrderLinkStats? _stats;
  bool _isLoading = true;
  String? _error;

  final String _baseUrl = AppConfig.publicWebBaseUrl;

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
      final link = await service.getMyPersonalOrderLink();

      if (link != null) {
        // 통계 로드 (최근 30일)
        final since = DateTime.now().subtract(const Duration(days: 30));
        final stats = await service.getStats(link.id, since);

        setState(() {
          _link = link;
          _stats = stats;
        });
      } else {
        setState(() {
          _link = null;
          _stats = null;
        });
      }
    } catch (e, stack) {
      AppLog.error('PersonalOrderLinkManagement', e,
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
    return BusinessAppShell(
      title: '개인 오더 링크',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorView()
              : _link == null
                  ? _buildNoLinkView()
                  : _buildLinkView(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline,
                size: 64, color: BusinessTokens.danger),
            const SizedBox(height: 16),
            Text(_error ?? '오류가 발생했습니다',
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 24),
            BusinessPrimaryButton(
              label: '다시 시도',
              onPressed: _loadLink,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoLinkView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: BusinessTokens.blueLight,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.link,
                  size: 48, color: BusinessTokens.blue),
            ),
            const SizedBox(height: 32),
            const Text(
              '나만의 견적 접수 링크를\n만들어 보세요',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              '단골 고객, 부동산, 관리소장님에게 공유하면\n사장님에게만 직접 견적 요청이 들어옵니다.',
              style: TextStyle(
                  fontSize: 14, color: BusinessTokens.mutedText, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: BusinessPrimaryButton(
                label: _isCreatingLink ? '링크 생성 중...' : '개인 링크 만들기',
                onPressed: _isCreatingLink ? null : _createLinkQuick,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isCreatingLink = false;

  /// 빠른 링크 생성 - 사용자 정보를 기반으로 자동 생성
  Future<void> _createLinkQuick() async {
    setState(() {
      _isCreatingLink = true;
    });

    try {
      final service = Provider.of<PersonalOrderLinkService>(context, listen: false);
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.currentUser;

      if (user == null) {
        throw Exception('로그인이 필요합니다');
      }

      // 사용자 정보 기반으로 기본값 설정
      final displayName = user.businessName ?? user.name;
      final slug = service.generateSuggestedSlug(displayName);

      await service.createPersonalOrderLink(
        slug: slug,
        displayName: displayName,
        supportedCategories: user.specialties.isNotEmpty ? user.specialties : null,
        serviceRegions: user.serviceAreas.isNotEmpty ? user.serviceAreas : null,
      );

      // 생성 후 링크 다시 로드
      await _loadLink();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('개인 링크가 생성되었습니다!'),
              ],
            ),
            backgroundColor: BusinessTokens.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e, stack) {
      AppLog.error('PersonalOrderLinkManagement', e,
          stack: stack, message: '빠른 링크 생성 실패');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('링크 생성에 실패했습니다: ${e.toString()}'),
            backgroundColor: BusinessTokens.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingLink = false;
        });
      }
    }
  }

  Widget _buildLinkView() {
    if (_link == null) return const SizedBox();

    final linkUrl = _link!.getPublicUrl(_baseUrl);

    return RefreshIndicator(
      onRefresh: _loadLink,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 링크 정보 카드
            _buildLinkCard(linkUrl),
            const SizedBox(height: 16),

            // 액션 버튼들
            _buildActionButtons(linkUrl),
            const SizedBox(height: 24),

            // 통계 카드
            if (_stats != null) _buildStatsCard(),

            const SizedBox(height: 24),

            // 관리 버튼들
            _buildManagementButtons(),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildLinkCard(String linkUrl) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BusinessTokens.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 프로필 이미지 또는 기본 아이콘
              CircleAvatar(
                radius: 28,
                backgroundColor: BusinessTokens.blueLight,
                backgroundImage: _link!.profileImageUrl != null
                    ? NetworkImage(_link!.profileImageUrl!)
                    : null,
                child: _link!.profileImageUrl == null
                    ? Icon(Icons.person, size: 28, color: BusinessTokens.blue)
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _link!.displayName ?? '내 링크',
                      style: BusinessTokens.title,
                    ),
                    if (_link!.headline != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _link!.headline!,
                        style: BusinessTokens.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              _buildStatusChip(_link!.status),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 20),
          Text(
            '내 개인 오더 링크',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: BusinessTokens.mutedText,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: BusinessTokens.canvas,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: BusinessTokens.border),
            ),
            child: Row(
              children: [
                Icon(Icons.link, size: 18, color: BusinessTokens.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    linkUrl,
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(String linkUrl) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                icon: Icons.copy,
                label: '복사',
                onPressed: () => _copyLink(linkUrl),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ActionButton(
                icon: Icons.share,
                label: '공유',
                onPressed: () => _shareLink(linkUrl),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ActionButton(
                icon: Icons.qr_code,
                label: 'QR',
                onPressed: () => _showQRCode(linkUrl),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                icon: Icons.visibility_outlined,
                label: '미리보기',
                onPressed: () =>
                    openPersonalOrderLinkPublicPage(context, _link!.slug),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ActionButton(
                icon: Icons.edit,
                label: '수정',
                onPressed: _navigateToEditLink,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusChip(PersonalOrderLinkStatus status) {
    Color color;
    Color bgColor;
    switch (status) {
      case PersonalOrderLinkStatus.active:
        color = BusinessTokens.success;
        bgColor = BusinessTokens.success.withValues(alpha: 0.1);
        break;
      case PersonalOrderLinkStatus.paused:
        color = BusinessTokens.warning;
        bgColor = BusinessTokens.warning.withValues(alpha: 0.1);
        break;
      case PersonalOrderLinkStatus.revoked:
      case PersonalOrderLinkStatus.suspended:
        color = BusinessTokens.danger;
        bgColor = BusinessTokens.danger.withValues(alpha: 0.1);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.displayName,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildStatsCard() {
    if (_stats == null) return const SizedBox();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BusinessTokens.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart, size: 20, color: BusinessTokens.blue),
              const SizedBox(width: 8),
              Text(
                '최근 30일 통계',
                style: BusinessTokens.sectionTitle,
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_stats!.pageViews == 0 &&
              _stats!.quoteStarts == 0 &&
              _stats!.quoteSubmissions == 0) ...[
            _buildEmptyStats(),
          ] else ...[
            _buildStatGrid(),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyStats() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.show_chart,
              size: 48, color: BusinessTokens.mutedText.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(
            '아직 링크를 통한 요청이 없습니다',
            style: TextStyle(
              fontSize: 14,
              color: BusinessTokens.mutedText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '카카오톡 프로필, 명함, 블로그에\n링크를 공유해 보세요.',
            style: TextStyle(
              fontSize: 12,
              color: BusinessTokens.mutedText.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStatGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildStatItem('링크 방문', _stats!.pageViews.toString(), Icons.visibility)),
            const SizedBox(width: 12),
            Expanded(child: _buildStatItem('요청 시작', _stats!.quoteStarts.toString(), Icons.edit_note)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildStatItem('요청 완료', _stats!.quoteSubmissions.toString(), Icons.check_circle_outline)),
            const SizedBox(width: 12),
            Expanded(child: _buildStatItem('응답 대기', _stats!.pendingOrders.toString(), Icons.hourglass_empty,
                color: _stats!.pendingOrders > 0 ? BusinessTokens.warning : null)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildStatItem('응답률', '${_stats!.responseRate.toStringAsFixed(0)}%', Icons.speed)),
            const SizedBox(width: 12),
            Expanded(child: _buildStatItem('완료 오더', _stats!.completedOrders.toString(), Icons.done_all,
                color: _stats!.completedOrders > 0 ? BusinessTokens.success : null)),
          ],
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, {Color? color}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BusinessTokens.canvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BusinessTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color ?? BusinessTokens.mutedText),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: BusinessTokens.mutedText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color ?? BusinessTokens.text,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManagementButtons() {
    return Column(
      children: [
        if (_link!.status == PersonalOrderLinkStatus.active)
          _ManagementButton(
            icon: Icons.pause_circle_outline,
            label: '링크 일시정지',
            description: '일시정지 중에는 새로운 견적 요청을 받을 수 없습니다',
            color: BusinessTokens.warning,
            onPressed: _pauseLink,
          )
        else if (_link!.status == PersonalOrderLinkStatus.paused)
          _ManagementButton(
            icon: Icons.play_circle_outline,
            label: '링크 재개',
            description: '다시 견적 요청을 받을 수 있습니다',
            color: BusinessTokens.success,
            onPressed: _resumeLink,
          ),
        const SizedBox(height: 12),
        _ManagementButton(
          icon: Icons.delete_outline,
          label: '링크 폐기',
          description: '폐기된 링크는 복구할 수 없습니다',
          color: BusinessTokens.danger,
          onPressed: _revokeLink,
        ),
      ],
    );
  }

  Future<void> _copyLink(String url) async {
    await Clipboard.setData(ClipboardData(text: url));

    // 공유 통계 업데이트
    final service =
        Provider.of<PersonalOrderLinkService>(context, listen: false);
    if (_link != null) {
      await service.updateLastShared(_link!.id);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('링크가 복사되었습니다'),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: BusinessTokens.success,
        ),
      );
    }
  }

  Future<void> _shareLink(String url) async {
    final message = '''우리 동네 설비·수리 문의는 여기서 바로 접수하세요.
사진과 증상을 남겨주시면 확인 후 견적을 드릴게요.

$url''';

    try {
      // iOS에서 공유 시트 위치 지정 (iPad 호환성)
      final box = context.findRenderObject() as RenderBox?;
      final sharePositionOrigin = box != null
          ? Rect.fromLTWH(
              box.localToGlobal(Offset.zero).dx,
              box.localToGlobal(Offset.zero).dy,
              box.size.width,
              box.size.height / 2,
            )
          : null;

      await Share.share(
        message,
        subject: '올수리 - 수리 견적 요청',
        sharePositionOrigin: sharePositionOrigin,
      );

      // 공유 통계 업데이트
      final service =
          Provider.of<PersonalOrderLinkService>(context, listen: false);
      if (_link != null) {
        await service.updateLastShared(_link!.id);
      }
    } catch (e) {
      AppLog.error('PersonalOrderLinkManagement', e, message: '공유 실패');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('공유에 실패했습니다: $e'),
            backgroundColor: BusinessTokens.danger,
          ),
        );
      }
    }
  }

  void _showQRCode(String url) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: BusinessTokens.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'QR 코드',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '명함이나 매장에 붙여서 사용하세요',
              style: TextStyle(fontSize: 14, color: BusinessTokens.mutedText),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: BusinessTokens.border),
              ),
              child: QrImageView(
                data: url,
                version: QrVersions.auto,
                size: 200,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('닫기'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToEditLink() {
    if (_link == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditPersonalOrderLinkScreen(link: _link!),
      ),
    ).then((_) => _loadLink());
  }

  Future<void> _pauseLink() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('링크 일시정지'),
        content: const Text('링크를 일시정지하시겠습니까?\n\n'
            '일시정지 중에는 새로운 견적 요청을 받을 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: BusinessTokens.warning,
            ),
            child: const Text('일시정지'),
          ),
        ],
      ),
    );

    if (confirmed == true && _link != null) {
      try {
        final service =
            Provider.of<PersonalOrderLinkService>(context, listen: false);
        await service.updateLinkStatus(
            _link!.id, PersonalOrderLinkStatus.paused);
        await _loadLink();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('링크가 일시정지되었습니다')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('링크 일시정지에 실패했습니다')),
          );
        }
      }
    }
  }

  Future<void> _resumeLink() async {
    try {
      final service =
          Provider.of<PersonalOrderLinkService>(context, listen: false);
      await service.updateLinkStatus(_link!.id, PersonalOrderLinkStatus.active);
      await _loadLink();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('링크가 재개되었습니다')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('링크 재개에 실패했습니다')),
        );
      }
    }
  }

  Future<void> _revokeLink() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('링크 폐기'),
        content: const Text('링크를 폐기하시겠습니까?\n\n'
            '⚠️ 폐기된 링크는 복구할 수 없습니다.\n'
            '새로운 링크를 만들어야 합니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: BusinessTokens.danger,
            ),
            child: const Text('폐기'),
          ),
        ],
      ),
    );

    if (confirmed == true && _link != null) {
      try {
        final service =
            Provider.of<PersonalOrderLinkService>(context, listen: false);
        await service.updateLinkStatus(
            _link!.id, PersonalOrderLinkStatus.revoked);
        await _loadLink();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('링크가 폐기되었습니다')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('링크 폐기에 실패했습니다')),
          );
        }
      }
    }
  }
}

// 액션 버튼 위젯
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: BusinessTokens.border),
          ),
          child: Column(
            children: [
              Icon(icon, size: 22, color: BusinessTokens.blue),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: BusinessTokens.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 관리 버튼 위젯
class _ManagementButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final VoidCallback onPressed;

  const _ManagementButton({
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 22, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12,
                        color: BusinessTokens.mutedText,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
