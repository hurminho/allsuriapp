import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/review_service.dart';
import '../../services/auth_service.dart';
import '../../models/business_review.dart';
import '../../widgets/star_rating.dart';

class ReviewWriteScreen extends StatefulWidget {
  final String businessId;
  final String orderId;
  final String? estimateId;
  const ReviewWriteScreen({super.key, required this.businessId, required this.orderId, this.estimateId});

  @override
  State<ReviewWriteScreen> createState() => _ReviewWriteScreenState();
}

class _ReviewWriteScreenState extends State<ReviewWriteScreen> {
  double _rating = 5;
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('후기 작성')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('별점'),
              const SizedBox(height: 8),
              StarRatingInput(
                initial: _rating,
                onRated: (v) => _rating = v,
              ),
              const SizedBox(height: 16),
              CupertinoTextField(
                controller: _titleCtrl,
                placeholder: '제목 (선택)',
              ),
              const SizedBox(height: 12),
              Expanded(
                child: CupertinoTextField(
                  controller: _contentCtrl,
                  placeholder: '후기를 입력하세요',
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton.filled(
                  onPressed: _saving ? null : _submit,
                  child: _saving ? const CupertinoActivityIndicator() : const Text('등록'),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final svc = Provider.of<ReviewService>(context, listen: false);
      await svc.createReview(BusinessReview(
        id: '',
        businessId: widget.businessId,
        customerId: auth.currentUser?.id,
        orderId: widget.orderId,
        estimateId: widget.estimateId,
        rating: _rating.round(),
        title: _titleCtrl.text.trim(),
        content: _contentCtrl.text.trim(),
        isVerified: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}


