import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/job_service.dart';
import '../../services/payment_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/business/business_app_shell.dart';
import '../../widgets/business/business_primary_button.dart';
import '../../widgets/business/business_section_header.dart';
import '../../widgets/business/business_status_chip.dart';
import '../../widgets/business/business_tokens.dart';

class AcceptTransferScreen extends StatefulWidget {
  final String jobId;
  const AcceptTransferScreen({super.key, required this.jobId});

  @override
  State<AcceptTransferScreen> createState() => _AcceptTransferScreenState();
}

class _AcceptTransferScreenState extends State<AcceptTransferScreen> {
  final TextEditingController _awardedAmountController =
      TextEditingController();
  bool _processing = false;

  @override
  Widget build(BuildContext context) {
    return BusinessAppShell(
      title: '협업 이관 수락',
      body: FutureBuilder<Map<String, dynamic>?>(
        future: Supabase.instance.client
            .from('jobs')
            .select(
                'id, title, description, owner_business_id, transfer_to_business_id')
            .eq('id', widget.jobId)
            .maybeSingle(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data;
          if (data == null) {
            return const Center(child: Text('협업 일감 정보를 불러올 수 없습니다'));
          }
          final title = data['title']?.toString() ?? '공사';
          final desc = data['description']?.toString() ?? '';
          final ownerId = data['owner_business_id']?.toString() ?? '';
          final transferTo = data['transfer_to_business_id']?.toString() ?? '';
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(BusinessTokens.pagePadding),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BusinessTokens.card(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const BusinessStatusChip(
                            label: '이관 수락 대기',
                            tone: BusinessStatusTone.warning,
                          ),
                          const SizedBox(height: 14),
                          Text(title, style: BusinessTokens.title),
                          if (desc.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(desc, style: BusinessTokens.body),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BusinessTokens.card(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const BusinessSectionHeader(
                            title: '협업 배정 금액',
                            subtitle: '수락할 공사의 최종 배정 금액을 입력하세요',
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _awardedAmountController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '배정 금액',
                              hintText: '금액 입력',
                              prefixText: '₩ ',
                              suffixText: '원',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BusinessTokens.card(
                        color: BusinessTokens.blueLight,
                        borderColor: BusinessTokens.blueLight,
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 20,
                            color: BusinessTokens.blue,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '결제가 완료되면 협업 일감이 배정되고 수락 처리가 진행됩니다.',
                              style: BusinessTokens.body,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  decoration: const BoxDecoration(
                    color: BusinessTokens.surface,
                    border: Border(
                      top: BorderSide(color: BusinessTokens.border),
                    ),
                  ),
                  child: BusinessPrimaryButton(
                    label: '결제 후 협업 수락',
                    icon: Icons.check_circle_outline_rounded,
                    loading: _processing,
                    onPressed: _processing
                        ? null
                        : () async {
                            final assigneeId =
                                context.read<AuthService>().currentUser?.id;
                            if (assigneeId == null) return;
                            final awarded = double.tryParse(
                                _awardedAmountController.text
                                    .replaceAll(',', ''));
                            if (awarded == null) return;
                            setState(() => _processing = true);
                            try {
                              final ok = await context
                                  .read<PaymentService>()
                                  .chargeTransferFee(
                                    payerBusinessId: assigneeId,
                                    payeeBusinessId: ownerId,
                                    awardedAmount: awarded,
                                  );
                              if (!ok) return;
                              await context.read<JobService>().acceptTransfer(
                                    jobId: widget.jobId,
                                    assigneeBusinessId: assigneeId,
                                    awardedAmount: awarded,
                                  );
                              // B2B 플랫폼 3% 정산 가상 알림
                              await context
                                  .read<PaymentService>()
                                  .notifyB2bPlatformFee(
                                    assigneeBusinessId: assigneeId,
                                    awardedAmount: awarded,
                                  );
                              if (!mounted) return;
                              Navigator.pop(context);
                            } finally {
                              if (mounted) setState(() => _processing = false);
                            }
                          },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
