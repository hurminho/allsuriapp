import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/community_service.dart';
import '../../services/auth_service.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('새 글 작성')),
      body: SafeArea(
        child: DefaultTextStyle(
          style: const TextStyle(fontFamily: 'Arial', fontSize: 15, color: CupertinoColors.black),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                CupertinoTextField(
                  controller: _titleCtrl,
                  placeholder: '제목',
                  style: const TextStyle(fontFamily: 'Arial', fontSize: 15, color: CupertinoColors.black),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: CupertinoTextField(
                    controller: _contentCtrl,
                    placeholder: '내용을 입력하세요\n예) 현장에 가 보니 이전 작업이 아니라 배관 설계부터 다시 해야 할 것 같습니다. 적정 견적 알려주세요!',
                    maxLines: 3,
                    expands: false,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(fontFamily: 'Arial', fontSize: 15, color: CupertinoColors.black),
                  ),
                ),
                const SizedBox(height: 12),
                CupertinoTextField(
                  controller: _tagsCtrl,
                  placeholder: '태그 (쉼표로 구분, 선택)',
                  style: const TextStyle(fontFamily: 'Arial', fontSize: 15, color: CupertinoColors.black),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton.filled(
                    onPressed: _saving ? null : _submit,
                    child: _saving
                        ? const CupertinoActivityIndicator()
                        : const Text('등록', style: TextStyle(fontFamily: 'Arial', fontSize: 15, color: CupertinoColors.black)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    if (title.isEmpty || content.isEmpty) return;

    setState(() => _saving = true);
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final svc = Provider.of<CommunityService>(context, listen: false);
      final userId = auth.currentUser?.id ?? '';
      final tags = _tagsCtrl.text.trim().isEmpty
          ? <String>[]
          : _tagsCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      final created = await svc.createPost(authorId: userId, title: title, content: content, tags: tags);
      if (!mounted) return;
      Navigator.pop(context, created);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
