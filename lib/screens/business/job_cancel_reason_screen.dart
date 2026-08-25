import 'package:flutter/material.dart';

import '../../widgets/business/business_app_shell.dart';
import '../../widgets/business/business_primary_button.dart';
import '../../widgets/business/business_tokens.dart';

class JobCancelReason {
  final String category;
  final String detail;

  const JobCancelReason({required this.category, required this.detail});
}

/// 공사 취소 전 사유를 카테고리 + 상세로 받는 화면.
class JobCancelReasonScreen extends StatefulWidget {
  final String jobTitle;

  const JobCancelReasonScreen({super.key, required this.jobTitle});

  static const categories = [
    '일정 조율 불가',
    '현장 여건이 다름',
    '자재·인력 부족',
    '고객 요청으로 중단',
    '견적 조건 변경',
    '중복·오배정',
    '기타',
  ];

  @override
  State<JobCancelReasonScreen> createState() => _JobCancelReasonScreenState();
}

class _JobCancelReasonScreenState extends State<JobCancelReasonScreen> {
  String? _category;
  final _detailController = TextEditingController();

  @override
  void dispose() {
    _detailController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _category != null && _detailController.text.trim().length >= 2;

  void _submit() {
    if (!_canSubmit) return;
    Navigator.pop(
      context,
      JobCancelReason(
        category: _category!,
        detail: _detailController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BusinessAppShell(
      title: '공사 취소',
      body: ListView(
        padding: const EdgeInsets.all(BusinessTokens.pagePadding),
        children: [
          Text(
            widget.jobTitle,
            style: BusinessTokens.sectionTitle,
          ),
          const SizedBox(height: 8),
          const Text(
            '취소 사유를 선택한 뒤, 아래에 자세한 내용을 적어 주세요. 상대 사업자·고객에게 전달됩니다.',
            style: BusinessTokens.caption,
          ),
          const SizedBox(height: 20),
          const Text('사유 선택', style: BusinessTokens.body),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in JobCancelReasonScreen.categories)
                ChoiceChip(
                  label: Text(item),
                  selected: _category == item,
                  selectedColor: BusinessTokens.blueLight,
                  labelStyle: TextStyle(
                    color: _category == item
                        ? BusinessTokens.blue
                        : BusinessTokens.text,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (_) => setState(() => _category = item),
                ),
            ],
          ),
          const SizedBox(height: 24),
          const Text('자세한 사유', style: BusinessTokens.body),
          const SizedBox(height: 8),
          TextField(
            controller: _detailController,
            minLines: 4,
            maxLines: 8,
            maxLength: 500,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '예: 방문 일정을 맞출 수 없어 진행이 어렵습니다.',
              filled: true,
              fillColor: BusinessTokens.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: BusinessTokens.border),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: BusinessPrimaryButton(
            label: '이 사유로 취소하기',
            icon: Icons.cancel_outlined,
            onPressed: _canSubmit ? _submit : null,
          ),
        ),
      ),
    );
  }
}
