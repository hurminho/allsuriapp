import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/estimate.dart';
import '../models/order.dart';
import '../services/estimate_service.dart';
import '../services/auth_service.dart';
import '../services/media_service.dart';
import '../utils/business_verify_guard.dart';
import '../theme/business_theme.dart';
import '../widgets/business/business_app_shell.dart';
import '../widgets/business/business_primary_button.dart';
import '../widgets/business/business_status_badge.dart';

class CreateEstimateScreen extends StatefulWidget {
  final Order order;
  
  const CreateEstimateScreen({
    super.key,
    required this.order,
  });

  @override
  State<CreateEstimateScreen> createState() => _CreateEstimateScreenState();
}

class _CreateEstimateScreenState extends State<CreateEstimateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _estimatedDaysController = TextEditingController();
  bool _isSubmitting = false;
  double _amountValue = 0.0;
  List<File> _selectedImages = [];
  List<String> _uploadedImageUrls = [];
  bool _isUploadingImages = false;
  final _imagePicker = ImagePicker();
  final _mediaService = MediaService();

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _estimatedDaysController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    try {
      final List<XFile> images = await _imagePicker.pickMultiImage(
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );

      if (images.isNotEmpty) {
        setState(() {
          _selectedImages.addAll(images.map((img) => File(img.path)));
        });
      }
    } catch (e) {
      _showError('사진 선택 실패: $e');
    }
  }

  Future<void> _pickImageFromCamera() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _selectedImages.add(File(image.path));
        });
      }
    } catch (e) {
      _showError('카메라 접근 실패: $e');
    }
  }

  void _showImageSourceOptions() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        title: const Text('사진 첨부'),
        message: const Text('사진을 어떻게 추가하시겠어요?'),
        actions: <CupertinoActionSheetAction>[
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _pickImageFromCamera();
            },
            child: const Text('카메라로 찍기'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _pickImages();
            },
            child: const Text('앨범에서 선택'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () {
            Navigator.pop(context);
          },
          isDefaultAction: true,
          child: const Text('취소'),
        ),
      ),
    );
  }

  Future<void> _uploadImages() async {
    if (_selectedImages.isEmpty) return;

    setState(() => _isUploadingImages = true);

    final pending = List<File>.from(_selectedImages);
    final urls = <String>[];
    final failed = <File>[];
    String? lastError;

    for (final image in pending) {
      try {
        final url = await _mediaService.uploadEstimateImage(file: image);
        urls.add(url);
      } catch (e) {
        debugPrint('❌ [uploadImages] 사진 업로드 실패: $e');
        lastError = e.toString();
        failed.add(image);
      }
    }

    if (!mounted) return;

    setState(() {
      _uploadedImageUrls.addAll(urls);
      _selectedImages
        ..clear()
        ..addAll(failed);
    });

    if (urls.isNotEmpty && failed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${urls.length}개 사진이 업로드되었습니다')),
      );
    } else if (urls.isNotEmpty && failed.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${urls.length}개 완료, ${failed.length}개 실패: $lastError'),
          backgroundColor: Colors.orange,
        ),
      );
    } else {
      _showError('사진 업로드 실패: ${lastError ?? "알 수 없는 오류"}');
    }

    if (mounted) setState(() => _isUploadingImages = false);
  }

  void _removeImage(int index) {
    setState(() => _uploadedImageUrls.removeAt(index));
  }

  Future<void> _confirmAndSubmit() async {
    if (_amountController.text.trim().isEmpty) {
      _showError('견적 금액을 입력해주세요');
      return;
    }
    if (_descriptionController.text.trim().isEmpty) {
      _showError('견적 설명을 입력해주세요');
      return;
    }
    if (_estimatedDaysController.text.trim().isEmpty) {
      _showError('예상 소요일을 입력해주세요');
      return;
    }
    if (_selectedImages.isNotEmpty) {
      _showError('모든 사진을 먼저 업로드해주세요');
      return;
    }

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: BusinessTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).padding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '입찰 제출 전 확인',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: BusinessTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              Text('금액  ${_amountController.text}원'),
              Text('방문 일정  ${widget.order.visitDate.toString().split(' ').first}'),
              Text('예상 소요  ${_estimatedDaysController.text.trim()}일'),
              const SizedBox(height: 8),
              const Text(
                'AS 조건은 아래 메시지에 포함된 내용으로 고객에게 전달됩니다.',
                style: TextStyle(fontSize: 12, color: BusinessTheme.textMuted),
              ),
              const SizedBox(height: 8),
              Text(
                _descriptionController.text.trim(),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: BusinessTheme.textMuted),
              ),
              const SizedBox(height: 20),
              BusinessPrimaryButton(
                label: '입찰 제출',
                onPressed: () => Navigator.pop(ctx, true),
              ),
              const SizedBox(height: 8),
              BusinessPrimaryButton(
                label: '수정하기',
                secondary: true,
                onPressed: () => Navigator.pop(ctx, false),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed == true) {
      await _submitEstimate();
    }
  }

  Future<void> _submitEstimate() async {
    if (_amountController.text.trim().isEmpty) {
      _showError('견적 금액을 입력해주세요');
      return;
    }
    if (_descriptionController.text.trim().isEmpty) {
      _showError('견적 설명을 입력해주세요');
      return;
    }
    if (_estimatedDaysController.text.trim().isEmpty) {
      _showError('예상 소요일을 입력해주세요');
      return;
    }

    if (_selectedImages.isNotEmpty) {
      _showError('모든 사진을 먼저 업로드해주세요');
      return;
    }

    final canProceed = await BusinessVerifyGuard.ensure(context, action: '견적서 등록');
    if (!canProceed) return;

    setState(() => _isSubmitting = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final estimateService = Provider.of<EstimateService>(context, listen: false);
      
      final user = authService.currentUser;
      if (user == null) {
        throw Exception('사용자 정보를 찾을 수 없습니다.');
      }

      final parsedAmount = double.parse(_amountController.text.trim().replaceAll(',', ''));

      final customerId = widget.order.customerId ?? '';
      final estimate = Estimate(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        orderId: widget.order.id ?? '',
        customerId: customerId,
        customerName: widget.order.customerName,
        businessId: user.id,
        businessName: user.name,
        businessPhone: user.phoneNumber ?? '',
        equipmentType: widget.order.equipmentType,
        amount: parsedAmount,
        description: _descriptionController.text.trim(),
        estimatedDays: int.parse(_estimatedDaysController.text.trim()),
        createdAt: DateTime.now(),
        visitDate: widget.order.visitDate,
        status: Estimate.STATUS_PENDING,
        mediaUrls: _uploadedImageUrls.isNotEmpty ? _uploadedImageUrls : null,
      );

      await estimateService.createEstimate(estimate);
      
      if (mounted) {
        showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('견적 제출 완료'),
            content: const Text('견적이 성공적으로 제출되었습니다!'),
            actions: [
              CupertinoDialogAction(
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
        _showError('견적 제출 중 오류가 발생했습니다: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showError(String message) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('오류'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BusinessTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: BusinessTheme.navy,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    return BusinessAppShell(
      title: '입찰 제출',
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    _sectionCard(
                      title: '고객 요청 요약',
                      children: [
                        Text(order.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          children: [
                            BusinessStatusBadge(label: order.equipmentType, color: BusinessTheme.blue),
                            if (order.images.isNotEmpty)
                              const BusinessStatusBadge(label: '사진 있음', color: BusinessTheme.navy),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(order.description, style: const TextStyle(color: BusinessTheme.textMuted)),
                        const SizedBox(height: 8),
                        Text('지역  ${BusinessTheme.regionFromAddress(order.address)}'),
                        Text('방문 요청일  ${order.visitDate.toString().split(' ').first}'),
                      ],
                    ),
                    if (order.images.isNotEmpty)
                      _sectionCard(
                        title: '사진 및 증상',
                        children: [
                          SizedBox(
                            height: 88,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: order.images.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 8),
                              itemBuilder: (_, i) => ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(order.images[i], width: 88, height: 88, fit: BoxFit.cover),
                              ),
                            ),
                          ),
                        ],
                      ),
                    if (order.estimatedPrice > 0)
                      _sectionCard(
                        title: 'AI 참고 가격 범위',
                        children: [
                          Text(
                            BusinessTheme.formatWon(order.estimatedPrice),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: BusinessTheme.blue,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            '참고 금액이며, 실제 견적과 다를 수 있습니다.',
                            style: TextStyle(fontSize: 12, color: BusinessTheme.textMuted),
                          ),
                        ],
                      ),
                    _sectionCard(
                      title: '견적 금액',
                      children: [
                        TextField(
                          controller: _amountController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9,]')),
                            _ThousandsSeparatorInputFormatter(),
                          ],
                          onChanged: (v) {
                            final parsed = double.tryParse(v.replaceAll(',', '')) ?? 0.0;
                            setState(() => _amountValue = parsed);
                          },
                          decoration: const InputDecoration(
                            hintText: '견적 금액 (원)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _EstimateFeePreview(amount: _amountValue),
                      ],
                    ),
                    _sectionCard(
                      title: '방문 가능 일정',
                      children: [
                        Text('고객 요청일: ${order.visitDate.toString().split(' ').first}'),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _estimatedDaysController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            hintText: '예상 소요일 (일)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                    _sectionCard(
                      title: '작업 범위 · 제외 항목 · AS · 메시지',
                      children: [
                        TextField(
                          controller: _descriptionController,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            hintText: '작업 범위, 제외 항목, AS 조건, 고객에게 보낼 메시지를 입력하세요',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                    _sectionCard(
                      title: '사진 첨부 (선택)',
                      children: [
                        if (_uploadedImageUrls.isNotEmpty)
                          SizedBox(
                            height: 88,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _uploadedImageUrls.length,
                              itemBuilder: (context, index) {
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(_uploadedImageUrls[index], width: 88, height: 88, fit: BoxFit.cover),
                                      ),
                                      Positioned(
                                        right: 0,
                                        child: GestureDetector(
                                          onTap: () => _removeImage(index),
                                          child: const CircleAvatar(
                                            radius: 10,
                                            backgroundColor: BusinessTheme.danger,
                                            child: Icon(Icons.close, size: 12, color: Colors.white),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _isUploadingImages ? null : _showImageSourceOptions,
                                child: const Text('사진 선택'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton(
                                onPressed: (_selectedImages.isEmpty || _isUploadingImages) ? null : _uploadImages,
                                child: _isUploadingImages
                                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : Text('업로드 (${_selectedImages.length})'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 72),
                  ],
                ),
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
            decoration: const BoxDecoration(
              color: BusinessTheme.surface,
              border: Border(top: BorderSide(color: BusinessTheme.border)),
            ),
            child: BusinessPrimaryButton(
              label: '입찰 제출',
              loading: _isSubmitting,
              onPressed: _isSubmitting ? null : _confirmAndSubmit,
            ),
          ),
        ],
      ),
    );
  }
}


class _ThousandsSeparatorInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }
    final text = newValue.text.replaceAll(',', '');
    final number = int.tryParse(text);
    if (number == null) {
      return oldValue;
    }
    final formatted = number.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _EstimateFeePreview extends StatelessWidget {
  final double amount;
  const _EstimateFeePreview({required this.amount});

  String _format(double v) {
    final s = v.toStringAsFixed(0);
    return s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  }

  @override
  Widget build(BuildContext context) {
    final platform5 = amount * 0.05;
    final b2b5 = amount * 0.05;
    final platform3 = amount * 0.03;

    return Row(
      children: [
        _badge('B2C 5%', _format(platform5), CupertinoColors.systemBlue),
        const SizedBox(width: 8),
        _badge('B2B 5%', _format(b2b5), CupertinoColors.systemGreen),
        const SizedBox(width: 8),
        _badge('B2B 3%', _format(platform3), CupertinoColors.systemPurple),
      ],
    );
  }

  Widget _badge(String label, String amountStr, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          const SizedBox(width: 6),
          Text('₩$amountStr', style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}
