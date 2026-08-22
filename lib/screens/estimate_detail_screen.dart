import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/estimate.dart';
import '../models/order.dart';
import '../services/estimate_service.dart';
import '../services/order_service.dart';
import '../services/payment_service.dart';
import '../services/chat_service.dart';
import 'chat/chat_list_page.dart';

class EstimateDetailScreen extends StatefulWidget {
  final Order order;
  final Estimate estimate;

  const EstimateDetailScreen({super.key, required this.order, required this.estimate});

  @override
  State<EstimateDetailScreen> createState() => _EstimateDetailScreenState();
}

class _EstimateDetailScreenState extends State<EstimateDetailScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final e = widget.estimate;
    final isAwarded = order.isAwarded && order.awardedEstimateId == e.id;

    return Scaffold(
      appBar: AppBar(title: const Text('견적 상세')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionCard(children: [
              const Text('견적 금액', style: TextStyle(fontSize: 12, color: CupertinoColors.secondaryLabel)),
              const SizedBox(height: 6),
              Text('₩${_format(e.amount)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
            ]),
            const SizedBox(height: 12),
            _sectionCard(children: [
              const Text('사업자 정보', style: TextStyle(fontSize: 12, color: CupertinoColors.secondaryLabel)),
              const SizedBox(height: 6),
              Text(e.businessName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                isAwarded ? '연락처: ${e.businessPhone}' : '연락처: 낙찰 후 공개',
                style: const TextStyle(fontSize: 14, color: CupertinoColors.secondaryLabel),
              ),
            ]),
            const SizedBox(height: 12),
            _sectionCard(children: [
              const Text('상세 설명', style: TextStyle(fontSize: 12, color: CupertinoColors.secondaryLabel)),
              const SizedBox(height: 6),
              Text(e.description),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(CupertinoIcons.time, size: 18, color: CupertinoColors.systemGrey),
                  const SizedBox(width: 6),
                  Text('예상 소요일 ${e.estimatedDays}일', style: const TextStyle(color: CupertinoColors.secondaryLabel)),
                ],
              ),
              const SizedBox(height: 12),
              // 고객 개인정보 비표시 가이드
              const Text('고객 정보는 낙찰 후에만 제공됩니다.',
                  style: TextStyle(fontSize: 12, color: CupertinoColors.secondaryLabel))
            ]),
            const SizedBox(height: 24),
            if (!order.isAwarded) ...[
              Row(
                children: [
                  Expanded(
                    child: CupertinoButton(
                      onPressed: _busy ? null : () => _reject(order, e),
                      child: const Text('거절', style: TextStyle(color: CupertinoColors.systemRed)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CupertinoButton.filled(
                      onPressed: _busy ? null : () => _award(order, e),
                      child: _busy ? const CupertinoActivityIndicator() : const Text('선택'),
                    ),
                  ),
                ],
              ),
            ] else ...[
              CupertinoButton(
                onPressed: () {
                  Navigator.push(context, CupertinoPageRoute(builder: (_) => const ChatListPage()));
                },
                child: const Text('채팅 열기'),
              ),
            ]
          ],
        ),
      ),
    );
  }

  Future<void> _award(Order order, Estimate estimate) async {
    setState(() => _busy = true);
    try {
      final orderService = context.read<OrderService>();
      final estimateService = context.read<EstimateService>();
      final paymentService = context.read<PaymentService>();
      final updatedOrder = order.copyWith(
        isAwarded: true,
        awardedAt: DateTime.now(),
        awardedEstimateId: estimate.id,
      );
      await orderService.updateOrder(updatedOrder);
      await estimateService.awardEstimate(estimate.id);
      await paymentService.notifyB2cAwardFee(
        businessId: estimate.businessId,
        awardedAmount: estimate.amount,
      );
      await ChatService().activateChatRoom(estimate.id, estimate.businessId);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(Order order, Estimate estimate) async {
    setState(() => _busy = true);
    try {
      final orderService = context.read<OrderService>();
      final estimateService = context.read<EstimateService>();
      final updatedOrder = order.copyWith(isAwarded: false, awardedAt: null, awardedEstimateId: null);
      await orderService.updateOrder(updatedOrder);
      await estimateService.rejectEstimate(estimate.id);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _sectionCard({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CupertinoColors.separator),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  String _format(double v) {
    final s = v.toStringAsFixed(0);
    return s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  }
}

// 수수료 배지 제거됨: 낙찰 시 플랫폼이 견적가 5%를 별도 징수


