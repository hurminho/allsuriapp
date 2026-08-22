import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import '../../services/api_service.dart';
import 'dart:io';
import '../../services/media_service.dart';

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final TextEditingController _questionCtrl = TextEditingController();
  bool _loading = false;
  final List<Map<String, dynamic>> _messages = []; // {role: 'assistant'|'user', text: String, time: DateTime}
  final ScrollController _scrollController = ScrollController();
  final List<File> _localImages = [];
  final MediaService _media = MediaService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('AI 도우미', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () {
                setState(() {
                  _messages.clear();
                  _localImages.clear();
                });
              },
              tooltip: '대화 초기화',
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFFfbc2eb).withOpacity(0.3),
                                const Color(0xFFa6c1ee).withOpacity(0.3),
                              ],
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.psychology_rounded,
                            size: 50,
                            color: Color(0xFF7B1FA2),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'AI 어시스턴트',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Text(
                            '현장 견적, 자재 추천, 시공 단계 등\n무엇이든 물어보세요',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                              height: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildSuggestionChip('욕실 배관 교체 비용은?'),
                            _buildSuggestionChip('타일 시공 단계'),
                            _buildSuggestionChip('방수 자재 추천'),
                          ],
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    reverse: true,
                    itemCount: _messages.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final msg = _messages[_messages.length - 1 - index];
                      final isUser = msg['role'] == 'user';
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                        children: [
                          if (!isUser) ...[
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFfbc2eb), Color(0xFFa6c1ee)],
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.auto_awesome_rounded, size: 18, color: Colors.white),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: isUser ? const Color(0xFF2E74B5) : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Text(
                                msg['text'] as String,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isUser ? Colors.white : Colors.black87,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ),
                          if (isUser) const SizedBox(width: 40),
                        ],
                      );
                    },
                  ),
          ),
          _buildModernInputBar(),
        ],
      ),
    );
  }

  Widget _buildSuggestionChip(String text) {
    return GestureDetector(
      onTap: () {
        _questionCtrl.text = text;
        _ask();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[700],
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildModernInputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Image picker button
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 22),
                onPressed: _loading ? null : _pickImage,
                tooltip: '이미지 추가',
                color: const Color(0xFF7B1FA2),
              ),
            ),
            const SizedBox(width: 8),
            // Input field
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TextField(
                  controller: _questionCtrl,
                  decoration: const InputDecoration(
                    hintText: '질문을 입력하세요...',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  maxLines: 4,
                  minLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _loading ? null : _ask(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Send button
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: _loading 
                    ? null 
                    : const LinearGradient(
                        colors: [Color(0xFFfbc2eb), Color(0xFFa6c1ee)],
                      ),
                color: _loading ? Colors.grey[300] : null,
                shape: BoxShape.circle,
                boxShadow: _loading ? [] : [
                  BoxShadow(
                    color: const Color(0xFF7B1FA2).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                      onPressed: _loading ? null : _ask,
                      padding: EdgeInsets.zero,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _ask() async {
    final q = _questionCtrl.text.trim();
    if (q.isEmpty && _localImages.isEmpty) return;
    setState(() {
      _loading = true;
      _messages.add({'role': 'user', 'text': q, 'time': DateTime.now()});
    });
    try {
      // Upload selected images to get public URLs
      final List<String> urls = [];
      for (final file in _localImages) {
        final url = await _media.uploadAiImage(file: file);
        if (url != null) urls.add(url);
      }

      final uri = Uri.parse('${ApiService.baseUrl}/ai/ask');
      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'question': q, 'images': urls}),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final answer = (data['answer']?.toString() ?? '').trim();
        setState(() {
          _messages.add({'role': 'assistant', 'text': answer.isEmpty ? '답변이 비어 있습니다.' : answer, 'time': DateTime.now()});
        });
      } else {
        String err = '오류: ${resp.statusCode}';
        try {
          final body = jsonDecode(resp.body) as Map<String, dynamic>;
          err += ' - ' + (body['message']?.toString() ?? '');
          if (body['details'] != null) err += '\n' + body['details'].toString();
        } catch (_) {
          err += ' ' + resp.body.substring(0, resp.body.length > 200 ? 200 : resp.body.length);
        }
        setState(() {
          _messages.add({'role': 'assistant', 'text': err, 'time': DateTime.now()});
        });
      }
    } catch (e) {
      setState(() {
        _messages.add({'role': 'assistant', 'text': '네트워크 오류: $e', 'time': DateTime.now()});
      });
    } finally {
      if (mounted) setState(() => _loading = false);
      setState(() => _localImages.clear());
    }
  }

  Future<void> _pickImage() async {
    final file = await _media.pickImageFromGallery();
    if (file == null) return;
    setState(() {
      _localImages.add(file);
    });
  }

}
