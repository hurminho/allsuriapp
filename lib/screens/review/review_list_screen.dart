import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/review_service.dart';
import '../../models/business_review.dart';
import '../../widgets/star_rating.dart';

class ReviewListScreen extends StatefulWidget {
  final String businessId;
  const ReviewListScreen({super.key, required this.businessId});

  @override
  State<ReviewListScreen> createState() => _ReviewListScreenState();
}

class _ReviewListScreenState extends State<ReviewListScreen> {
  bool _loading = false;
  List<BusinessReview> _reviews = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final svc = Provider.of<ReviewService>(context, listen: false);
      final rows = await svc.getBusinessReviews(widget.businessId);
      setState(() => _reviews = rows);
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('후기')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : _reviews.isEmpty
                ? const Center(child: Text('아직 후기가 없습니다.'))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemBuilder: (_, i) => _buildTile(_reviews[i]),
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemCount: _reviews.length,
                  ),
      ),
    );
  }

  Widget _buildTile(BusinessReview r) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CupertinoColors.separator),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StarRating(rating: (r.rating ?? 0).toDouble(), size: 18),
          const SizedBox(height: 6),
          if ((r.title ?? '').isNotEmpty) Text(r.title!),
          const SizedBox(height: 6),
          Text(r.content ?? ''),
        ],
      ),
    );
  }
}


