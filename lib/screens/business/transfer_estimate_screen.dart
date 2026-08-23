import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/estimate.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../../services/estimate_service.dart';
import '../../widgets/business/business_app_shell.dart';
import '../../widgets/business/business_empty_state.dart';
import '../../widgets/business/business_primary_button.dart';
import '../../widgets/business/business_section_header.dart';
import '../../widgets/business/business_status_chip.dart';
import '../../widgets/business/business_tokens.dart';

class TransferEstimateScreen extends StatefulWidget {
  final Estimate estimate;

  const TransferEstimateScreen({
    super.key,
    required this.estimate,
  });

  @override
  State<TransferEstimateScreen> createState() => _TransferEstimateScreenState();
}

class _TransferEstimateScreenState extends State<TransferEstimateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  final _amountFormat = NumberFormat('#,###', 'ko_KR');
  final _dateFormat = DateFormat('yyyy.MM.dd', 'ko_KR');

  bool _isSubmitting = false;
  bool _isLoadingBusinesses = true;
  String? _loadError;
  List<Map<String, dynamic>> _businesses = [];
  String? _selectedBusinessId;
  String? _selectedBusinessName;

  @override
  void initState() {
    super.initState();
    _loadBusinesses();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadBusinesses() async {
    setState(() {
      _isLoadingBusinesses = true;
      _loadError = null;
    });
    try {
      final currentUserId =
          Provider.of<AuthService>(context, listen: false).currentUser?.id;
      if (currentUserId == null || currentUserId.isEmpty) {
        throw Exception('로그인이 필요합니다');
      }

      final response = await Supabase.instance.client
          .from('users')
          .select('id, businessname, name, phonenumber')
          .eq('role', 'business')
          .neq('id', currentUserId);

      if (!mounted) return;
      setState(() {
        _businesses = List<Map<String, dynamic>>.from(response);
        _isLoadingBusinesses = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingBusinesses = false;
        _loadError = '업체 목록을 불러오지 못했습니다';
      });
    }
  }

  Future<void> _transferEstimate() async {
    if (_selectedBusinessId == null) {
      _showError('이관할 사업자를 선택해주세요');
      return;
    }

    setState(() => _isSubmitting = true);

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (loadingContext) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('$_selectedBusinessName님에게\n견적을 이관하고 있습니다...'),
            ],
          ),
        ),
      );
    }

    try {
      final estimateService =
          Provider.of<EstimateService>(context, listen: false);
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUserId = authService.currentUser?.id ?? '';

      await estimateService.transferEstimate(
        estimateId: widget.estimate.id,
        newBusinessId: _selectedBusinessId!,
        newBusinessName: _selectedBusinessName ?? '',
        reason: _reasonController.text.trim(),
        transferredBy: currentUserId,
      );

      try {
        final roomId = 'transfer_${widget.estimate.id}';
        await ChatService().createChatRoom(
          roomId,
          currentUserId,
          _selectedBusinessId!,
          estimateId: widget.estimate.id,
        );
      } catch (_) {
        // Chat creation remains best-effort after a successful transfer.
      }

      if (mounted) {
        Navigator.pop(context);
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('견적 이관 완료'),
            content: Text(
              '$_selectedBusinessName님에게 견적이 이관되었습니다.\n'
              '협업 채팅방이 자동으로 생성되었습니다.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
                child: const Text('확인'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showError('견적 이관 중 오류가 발생했습니다: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('오류'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _showBusinessPicker() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BusinessTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(BusinessTokens.cardRadius),
        ),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.68,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: BusinessSectionHeader(
                    title: '이관 업체 선택',
                    subtitle: '견적을 이어서 진행할 업체를 선택하세요',
                  ),
                ),
                const Divider(height: 1, color: BusinessTokens.border),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(BusinessTokens.space16),
                    itemCount: _businesses.length,
                    separatorBuilder: (_, __) => const SizedBox(
                      height: BusinessTokens.space8,
                    ),
                    itemBuilder: (context, index) {
                      final business = _businesses[index];
                      final id = business['id']?.toString() ?? '';
                      final name = business['businessname']?.toString() ??
                          business['name']?.toString() ??
                          '사업자';
                      final phone = business['phonenumber']?.toString() ?? '';
                      final selected = id == _selectedBusinessId;
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(
                            BusinessTokens.controlRadius,
                          ),
                          onTap: () {
                            setState(() {
                              _selectedBusinessId = id;
                              _selectedBusinessName = name;
                            });
                            Navigator.pop(sheetContext);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(
                              BusinessTokens.space12,
                            ),
                            decoration: BusinessTokens.card(
                              color: selected
                                  ? BusinessTokens.blueLight
                                  : BusinessTokens.surface,
                              borderColor: selected
                                  ? BusinessTokens.blue
                                  : BusinessTokens.border,
                              radius: BusinessTokens.controlRadius,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  selected
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_off,
                                  color: selected
                                      ? BusinessTokens.blue
                                      : BusinessTokens.mutedText,
                                ),
                                const SizedBox(
                                  width: BusinessTokens.space12,
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: BusinessTokens.body.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      if (phone.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          phone,
                                          style: BusinessTokens.caption,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BusinessAppShell(
      title: '견적 이관',
      body: _isLoadingBusinesses
          ? const BusinessListSkeleton(itemCount: 4)
          : _loadError != null
              ? BusinessEmptyState(
                  icon: Icons.refresh_rounded,
                  title: _loadError!,
                  subtitle: '네트워크 상태를 확인한 뒤 다시 시도해 주세요.',
                  actionLabel: '다시 시도',
                  onAction: _loadBusinesses,
                )
              : _businesses.isEmpty
                  ? BusinessEmptyState(
                      icon: Icons.business_outlined,
                      title: '이관할 수 있는 업체가 없습니다',
                      subtitle: '업체 목록을 새로고침해 다시 확인해 주세요.',
                      actionLabel: '새로고침',
                      onAction: _loadBusinesses,
                    )
                  : SafeArea(
                      child: Form(
                        key: _formKey,
                        child: ListView(
                          padding: const EdgeInsets.all(
                            BusinessTokens.pagePadding,
                          ),
                          children: [
                            _buildAssignmentSummary(),
                            const SizedBox(
                              height: BusinessTokens.space24,
                            ),
                            const BusinessSectionHeader(
                              title: '업체 배정',
                              subtitle: '견적을 이어서 진행할 업체를 지정하세요',
                            ),
                            const SizedBox(
                              height: BusinessTokens.space12,
                            ),
                            OutlinedButton(
                              onPressed: _showBusinessPicker,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 52),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: BusinessTokens.space16,
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.business_outlined),
                                  const SizedBox(
                                    width: BusinessTokens.space12,
                                  ),
                                  Expanded(
                                    child: Text(
                                      _selectedBusinessName ?? '이관 업체를 선택해 주세요',
                                      textAlign: TextAlign.left,
                                    ),
                                  ),
                                  const Icon(
                                    Icons.expand_more_rounded,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(
                              height: BusinessTokens.space16,
                            ),
                            TextField(
                              controller: _reasonController,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: '이관 사유',
                                hintText: '필요한 경우 사유를 입력해 주세요',
                                alignLabelWithHint: true,
                              ),
                            ),
                            const SizedBox(
                              height: BusinessTokens.space16,
                            ),
                            Container(
                              padding: const EdgeInsets.all(
                                BusinessTokens.space12,
                              ),
                              decoration: BusinessTokens.card(
                                color: BusinessTokens.blueLight,
                                borderColor: BusinessTokens.blue,
                                radius: BusinessTokens.controlRadius,
                              ),
                              child: const Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.info_outline_rounded,
                                    size: 18,
                                    color: BusinessTokens.blue,
                                  ),
                                  SizedBox(
                                    width: BusinessTokens.space8,
                                  ),
                                  Expanded(
                                    child: Text(
                                      '이관 후 선택한 업체가 견적을 이어서 처리하며, '
                                      '관련 안내가 자동으로 전달됩니다.',
                                      style: BusinessTokens.caption,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(
                              height: BusinessTokens.space24,
                            ),
                            BusinessPrimaryButton(
                              label: '견적 이관 요청',
                              icon: Icons.send_outlined,
                              loading: _isSubmitting,
                              onPressed: _selectedBusinessId == null
                                  ? null
                                  : _transferEstimate,
                            ),
                          ],
                        ),
                      ),
                    ),
    );
  }

  Widget _buildAssignmentSummary() {
    return Container(
      padding: const EdgeInsets.all(BusinessTokens.space16),
      decoration: BusinessTokens.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('협업 견적', style: BusinessTokens.caption),
              ),
              BusinessStatusChip.forEstimate(widget.estimate.status),
            ],
          ),
          const SizedBox(height: BusinessTokens.space12),
          Text(
            widget.estimate.customerName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: BusinessTokens.title,
          ),
          const SizedBox(height: BusinessTokens.space16),
          const Divider(height: 1, color: BusinessTokens.border),
          const SizedBox(height: BusinessTokens.space12),
          _buildInfoRow(
            Icons.calendar_today_outlined,
            '방문 일정',
            _dateFormat.format(widget.estimate.visitDate),
          ),
          const SizedBox(height: BusinessTokens.space12),
          _buildInfoRow(
            Icons.payments_outlined,
            '견적 금액',
            '${_amountFormat.format(widget.estimate.amount)}원',
          ),
          const SizedBox(height: BusinessTokens.space12),
          const _SummaryInfoRow(
            icon: Icons.privacy_tip_outlined,
            label: '연락 안내',
            value: '고객 연락은 기존 견적 절차에 따라 진행해 주세요.',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return _SummaryInfoRow(icon: icon, label: label, value: value);
  }
}

class _SummaryInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SummaryInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
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
}
