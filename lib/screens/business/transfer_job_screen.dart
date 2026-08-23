import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../../services/job_service.dart';
import '../../widgets/business/business_app_shell.dart';
import '../../widgets/business/business_empty_state.dart';
import '../../widgets/business/business_primary_button.dart';
import '../../widgets/business/business_section_header.dart';
import '../../widgets/business/business_status_chip.dart';
import '../../widgets/business/business_tokens.dart';

class TransferJobScreen extends StatefulWidget {
  final String jobId;

  const TransferJobScreen({super.key, required this.jobId});

  @override
  State<TransferJobScreen> createState() => _TransferJobScreenState();
}

class _TransferJobScreenState extends State<TransferJobScreen> {
  String? _selectedBusinessId;
  String? _selectedBusinessName;
  bool _submitting = false;
  String _searchText = '';

  Timer? _debounce;
  Future<List<Map<String, dynamic>>>? _searchFuture;

  @override
  void initState() {
    super.initState();
    _searchFuture = _searchBusinesses('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String text) {
    _searchText = text;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _retrySearch();
    });
  }

  void _retrySearch() {
    setState(() {
      _searchFuture = _searchBusinesses(_searchText);
    });
  }

  @override
  Widget build(BuildContext context) {
    return BusinessAppShell(
      title: '협업 일감 이관',
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: _buildAssignmentSummary(),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const BusinessSectionHeader(
                            title: '업체 배정',
                            subtitle: '이관 받을 업체를 검색해 선택하세요',
                          ),
                          const SizedBox(height: BusinessTokens.space12),
                          TextField(
                            decoration: const InputDecoration(
                              hintText: '상호명 또는 전화번호 검색',
                              prefixIcon: Icon(Icons.search_rounded),
                            ),
                            textInputAction: TextInputAction.search,
                            onChanged: _onSearchChanged,
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    sliver: SliverToBoxAdapter(
                      child: SizedBox(
                        height: 360,
                        child: FutureBuilder<List<Map<String, dynamic>>>(
                          future: _searchFuture,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const BusinessListSkeleton(itemCount: 3);
                            }
                            if (snapshot.hasError) {
                              return BusinessEmptyState(
                                icon: Icons.refresh_rounded,
                                title: '업체 목록을 불러오지 못했습니다',
                                subtitle: '네트워크 상태를 확인해 주세요.',
                                actionLabel: '다시 시도',
                                onAction: _retrySearch,
                              );
                            }
                            final rows =
                                snapshot.data ?? <Map<String, dynamic>>[];
                            if (rows.isEmpty) {
                              return const BusinessEmptyState(
                                icon: Icons.person_search_outlined,
                                title: '검색된 업체가 없습니다',
                                subtitle: '검색어를 바꾸어 다시 확인해 주세요.',
                              );
                            }
                            return ListView.separated(
                              padding: EdgeInsets.zero,
                              itemCount: rows.length,
                              separatorBuilder: (_, __) => const SizedBox(
                                height: BusinessTokens.space8,
                              ),
                              itemBuilder: (context, index) {
                                final data = rows[index];
                                final businessId = data['id'] as String;
                                final name = (data['businessName'] ??
                                        data['name'] ??
                                        '사업자')
                                    .toString();
                                final phone = (data['phoneNumber'] ??
                                        data['phonenumber'] ??
                                        '')
                                    .toString();
                                final selected =
                                    businessId == _selectedBusinessId;
                                return Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(
                                      BusinessTokens.controlRadius,
                                    ),
                                    onTap: () {
                                      setState(() {
                                        _selectedBusinessId = businessId;
                                        _selectedBusinessName = name;
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: BusinessTokens.space12,
                                        vertical: BusinessTokens.space8,
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
                                                  style: BusinessTokens.body
                                                      .copyWith(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                                if (phone.isNotEmpty) ...[
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    phone,
                                                    style:
                                                        BusinessTokens.caption,
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
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(
                BusinessTokens.space16,
                BusinessTokens.space8,
                BusinessTokens.space16,
                BusinessTokens.space8 + MediaQuery.of(context).padding.bottom,
              ),
              decoration: const BoxDecoration(
                color: BusinessTokens.surface,
                border: Border(
                  top: BorderSide(color: BusinessTokens.border),
                ),
              ),
              child: BusinessPrimaryButton(
                label: '협업 일감 이관 요청',
                icon: Icons.send_outlined,
                loading: _submitting,
                onPressed: _selectedBusinessId == null ? null : _submitTransfer,
              ),
            ),
          ],
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
                child: Text('이관 대상', style: BusinessTokens.caption),
              ),
              BusinessStatusChip(
                label: _selectedBusinessId == null ? '업체 선택 필요' : '업체 선택 완료',
                tone: _selectedBusinessId == null
                    ? BusinessStatusTone.warning
                    : BusinessStatusTone.info,
              ),
            ],
          ),
          const SizedBox(height: BusinessTokens.space12),
          Text(
            _selectedBusinessName ?? '협업 일감 이관',
            style: BusinessTokens.title,
          ),
          const SizedBox(height: BusinessTokens.space16),
          const Divider(height: 1, color: BusinessTokens.border),
          const SizedBox(height: BusinessTokens.space12),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.privacy_tip_outlined,
                size: 18,
                color: BusinessTokens.blue,
              ),
              SizedBox(width: BusinessTokens.space8),
              Expanded(
                child: Text(
                  '연락은 이관 수락 후 협업 채팅에서 진행해 주세요.',
                  style: BusinessTokens.caption,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _submitTransfer() async {
    setState(() => _submitting = true);
    try {
      final me = context.read<AuthService>().currentUser;
      if (me == null || me.id.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('로그인이 필요합니다.')),
          );
        }
        return;
      }

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const AlertDialog(
            content: SizedBox(
              width: 200,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('협업 일감을 이관하고 있습니다...'),
                ],
              ),
            ),
          ),
        );
      }

      await context.read<JobService>().requestTransfer(
            jobId: widget.jobId,
            transferToBusinessId: _selectedBusinessId!,
            requesterBusinessId: me.id,
          );

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

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
              child: Lottie.asset(
                'assets/lottie/check.json',
                repeat: false,
              ),
            ),
          );
        },
      );
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이관 요청을 보냈습니다.')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
        final message = e is StateError ? e.message : '이관 요청에 실패했습니다: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<List<Map<String, dynamic>>> _searchBusinesses(String queryText) async {
    final sb = Supabase.instance.client;
    var query = sb
        .from('users')
        .select('id, name, businessName, phoneNumber, phonenumber')
        .eq('role', 'business');
    if (queryText.trim().isNotEmpty) {
      final like = '%${queryText.trim()}%';
      query = query.or(
        'businessName.ilike.$like,name.ilike.$like,'
        'phoneNumber.ilike.$like,phonenumber.ilike.$like',
      );
    }
    final rows = await query.limit(50);
    return rows
        .map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row))
        .toList();
  }
}
