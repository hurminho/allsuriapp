import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/job_service.dart';
import '../../services/payment_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/business_theme.dart';
import '../../widgets/business/business_status_badge.dart';

class AcceptTransferScreen extends StatefulWidget {
  final String jobId;
  const AcceptTransferScreen({super.key, required this.jobId});

  @override
  State<AcceptTransferScreen> createState() => _AcceptTransferScreenState();
}

class _AcceptTransferScreenState extends State<AcceptTransferScreen> {
  final TextEditingController _awardedAmountController = TextEditingController();
  bool _processing = false;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: BusinessTheme.theme(Theme.of(context)),
      child: Scaffold(
      backgroundColor: BusinessTheme.background,
      appBar: AppBar(title: const Text('이관 수락 및 결제')),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: Supabase.instance.client
            .from('jobs')
            .select('id, title, description, owner_business_id, transfer_to_business_id')
            .eq('id', widget.jobId)
            .maybeSingle(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final data = snapshot.data;
          if (data == null) return const Center(child: Text('공사 정보를 불러올 수 없습니다'));
          final title = data['title']?.toString() ?? '공사';
          final desc = data['description']?.toString() ?? '';
          final ownerId = data['owner_business_id']?.toString() ?? '';
          final transferTo = data['transfer_to_business_id']?.toString() ?? '';
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BusinessStatusBadge(label: '이관 대기', color: BusinessTheme.warning),
                const SizedBox(height: 12),
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(desc, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 24),
                TextField(
                  controller: _awardedAmountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '낙찰 금액',
                    prefixText: '₩ ',
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _processing
                        ? null
                        : () async {
                            final assigneeId = context.read<AuthService>().currentUser?.id;
                            if (assigneeId == null) return;
                            final awarded = double.tryParse(_awardedAmountController.text.replaceAll(',', ''));
                            if (awarded == null) return;
                            setState(() => _processing = true);
                            try {
                              final ok = await context.read<PaymentService>().chargeTransferFee(
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
                              await context.read<PaymentService>().notifyB2bPlatformFee(
                                    assigneeBusinessId: assigneeId,
                                    awardedAmount: awarded,
                                  );
                              if (!mounted) return;
                              Navigator.pop(context);
                            } finally {
                              if (mounted) setState(() => _processing = false);
                            }
                          },
                    child: _processing
                        ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('즉시 결제 후 수락'),
                  ),
                )
              ],
            ),
          );
        },
      ),
    ));
  }
}


