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
import '../services/marketplace_service.dart';
import '../services/media_service.dart';
import '../utils/business_verify_guard.dart';
import '../widgets/business/business_app_shell.dart';
import '../widgets/business/business_primary_button.dart';
import '../widgets/business/business_section_header.dart';
import '../widgets/business/business_status_chip.dart';
import '../widgets/business/business_tokens.dart';

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
  final _market = MarketplaceService();

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
      backgroundColor: BusinessTokens.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(BusinessTokens.cardRadius),
        ),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(BusinessTokens.space24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BusinessSectionHeader(
                  title: '입찰 제출 전 확인',
                  subtitle: '고객에게 전달될 내용을 마지막으로 확인해주세요.',
                ),
                const SizedBox(height: BusinessTokens.space24),
                _confirmationRow(
                  '입찰 금액',
                  '${_amountController.text.trim()}원',
                ),
                _confirmationRow(
                  '방문 요청일',
                  _formatDate(widget.order.visitDate),
                ),
                _confirmationRow(
                  '예상 소요',
                  '${_estimatedDaysController.text.trim()}일',
                ),
                const Divider(height: BusinessTokens.space24),
                const Text('작업 안내 메시지', style: BusinessTokens.sectionTitle),
                const SizedBox(height: BusinessTokens.space8),
                Text(
                  _descriptionController.text.trim(),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: BusinessTokens.body,
                ),
                const SizedBox(height: BusinessTokens.space24),
                BusinessPrimaryButton(
                  label: '입찰 제출',
                  onPressed: () => Navigator.pop(ctx, true),
                ),
                const SizedBox(height: BusinessTokens.space8),
                BusinessPrimaryButton(
                  label: '수정하기',
                  secondary: true,
                  onPressed: () => Navigator.pop(ctx, false),
                ),
              ],
            ),
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

    final canProceed =
        await BusinessVerifyGuard.ensure(context, action: '견적서 등록');
    if (!canProceed) return;

    setState(() => _isSubmitting = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final estimateService =
          Provider.of<EstimateService>(context, listen: false);

      final user = authService.currentUser;
      if (user == null) {
        throw Exception('사용자 정보를 찾을 수 없습니다.');
      }

      final parsedAmount =
          double.parse(_amountController.text.trim().replaceAll(',', ''));
      final estimatedDays = int.parse(_estimatedDaysController.text.trim());
      final description = _descriptionController.text.trim();

      // 웹에서 들어온 고객 오더는 marketplace_listings 미러가 있어 입찰을
      // order_bids 로 보내야 한다. 그래야 '내 입찰'·대시보드 '입찰 대기'와
      // 고객의 웹 조회 화면에 함께 나타난다. estimates 로만 쓰면 세 곳 모두
      // 조회 대상이 아니라 입찰이 사라진 것처럼 보인다.
      final listingId =
          await _market.findListingIdForWebOrder(widget.order.id ?? '');
      if (listingId != null) {
        await _market.claimListing(
          listingId,
          businessId: user.id,
          bidAmount: parsedAmount,
          estimatedDays: estimatedDays,
          message: description,
        );
        if (mounted) _showSubmitted();
        return;
      }

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
        description: description,
        estimatedDays: estimatedDays,
        createdAt: DateTime.now(),
        visitDate: widget.order.visitDate,
        status: Estimate.STATUS_PENDING,
        mediaUrls: _uploadedImageUrls.isNotEmpty ? _uploadedImageUrls : null,
      );

      await estimateService.createEstimate(estimate);

      if (mounted) _showSubmitted();
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

  void _showSubmitted() {
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

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}.$month.$day';
  }

  Widget _confirmationRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: BusinessTokens.space12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(label, style: BusinessTokens.caption),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: BusinessTokens.body.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required String hint,
    String? suffixText,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      suffixText: suffixText,
      filled: true,
      fillColor: BusinessTokens.canvas,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BusinessTokens.controlRadius),
        borderSide: const BorderSide(color: BusinessTokens.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BusinessTokens.controlRadius),
        borderSide: const BorderSide(color: BusinessTokens.border),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: BusinessTokens.space16),
      padding: const EdgeInsets.all(BusinessTokens.space16),
      decoration: BusinessTokens.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BusinessSectionHeader(
            title: title,
            subtitle: subtitle,
          ),
          const SizedBox(height: BusinessTokens.space16),
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
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(BusinessTokens.pagePadding),
          child: Column(
            children: [
              _sectionCard(
                title: '고객 요청',
                subtitle: '요청 내용과 방문 일정을 확인해주세요.',
                children: [
                  Wrap(
                    spacing: BusinessTokens.space8,
                    runSpacing: BusinessTokens.space8,
                    children: [
                      if (order.equipmentType.isNotEmpty)
                        BusinessStatusChip(
                          label: order.equipmentType,
                          tone: BusinessStatusTone.info,
                        ),
                      if (order.images.isNotEmpty)
                        const BusinessStatusChip(
                          label: '사진 있음',
                          icon: Icons.photo_outlined,
                        ),
                    ],
                  ),
                  if (order.title.isNotEmpty) ...[
                    const SizedBox(height: BusinessTokens.space12),
                    Text(order.title, style: BusinessTokens.sectionTitle),
                  ],
                  if (order.description.isNotEmpty) ...[
                    const SizedBox(height: BusinessTokens.space8),
                    Text(order.description, style: BusinessTokens.body),
                  ],
                  const SizedBox(height: BusinessTokens.space16),
                  _requestMeta(
                    Icons.calendar_today_outlined,
                    '방문 요청일',
                    _formatDate(order.visitDate),
                  ),
                  if (order.address.isNotEmpty) ...[
                    const SizedBox(height: BusinessTokens.space8),
                    _requestMeta(
                      Icons.location_on_outlined,
                      '작업 주소',
                      order.address,
                    ),
                  ],
                ],
              ),
              if (order.images.isNotEmpty)
                _sectionCard(
                  title: '현장 사진 및 증상',
                  subtitle:
                      order.description.isNotEmpty ? order.description : null,
                  children: [
                    SizedBox(
                      height: 96,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: order.images.length,
                        separatorBuilder: (_, __) => const SizedBox(
                          width: BusinessTokens.space8,
                        ),
                        itemBuilder: (_, i) => ClipRRect(
                          borderRadius: BorderRadius.circular(
                            BusinessTokens.controlRadius,
                          ),
                          child: Image.network(
                            order.images[i],
                            width: 96,
                            height: 96,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 96,
                              height: 96,
                              color: BusinessTokens.blueLight,
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.broken_image_outlined,
                                color: BusinessTokens.mutedText,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              if (order.estimatedPrice > 0)
                _sectionCard(
                  title: '고객 요청 참고 금액',
                  children: [
                    Text(
                      _formatWon(order.estimatedPrice),
                      style: BusinessTokens.title.copyWith(
                        color: BusinessTokens.blue,
                      ),
                    ),
                    const SizedBox(height: BusinessTokens.space4),
                    const Text(
                      '고객 요청에 포함된 참고 금액입니다.',
                      style: BusinessTokens.caption,
                    ),
                  ],
                ),
              _sectionCard(
                title: '입찰 금액',
                subtitle: '고객에게 제안할 최종 금액을 입력해주세요.',
                children: [
                  TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9,]')),
                      _ThousandsSeparatorInputFormatter(),
                    ],
                    onChanged: (v) {
                      final parsed =
                          double.tryParse(v.replaceAll(',', '')) ?? 0.0;
                      setState(() => _amountValue = parsed);
                    },
                    decoration: _fieldDecoration(
                      label: '입찰 금액',
                      hint: '금액 입력',
                      suffixText: '원',
                    ),
                  ),
                  const SizedBox(height: BusinessTokens.space8),
                  _BidAmountPreview(amount: _amountValue),
                ],
              ),
              _sectionCard(
                title: '방문 및 작업 기간',
                subtitle: '기존 방문 요청일과 예상 소요일을 확인해주세요.',
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(BusinessTokens.space12),
                    decoration: BusinessTokens.card(
                      color: BusinessTokens.canvas,
                      radius: BusinessTokens.controlRadius,
                    ),
                    child: _requestMeta(
                      Icons.event_available_outlined,
                      '방문 요청일',
                      _formatDate(order.visitDate),
                    ),
                  ),
                  const SizedBox(height: BusinessTokens.space12),
                  TextField(
                    controller: _estimatedDaysController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: _fieldDecoration(
                      label: '예상 소요일',
                      hint: '예상 작업 기간 입력',
                      suffixText: '일',
                    ),
                  ),
                ],
              ),
              _sectionCard(
                title: '작업 안내 메시지',
                subtitle: '아래 한 칸에 작업 범위, 제외 항목, AS 조건과 고객 메시지를 함께 작성해주세요.',
                children: [
                  TextField(
                    controller: _descriptionController,
                    minLines: 5,
                    maxLines: 8,
                    decoration: _fieldDecoration(
                      label: '작업 범위 · 제외 항목 · AS · 고객 메시지',
                      hint: '고객에게 전달할 작업 내용을 입력하세요.',
                    ),
                  ),
                ],
              ),
              _sectionCard(
                title: '입찰 사진',
                subtitle: '필요한 경우 작업 설명 사진을 첨부할 수 있습니다.',
                children: [
                  if (_uploadedImageUrls.isNotEmpty ||
                      _selectedImages.isNotEmpty) ...[
                    SizedBox(
                      height: 88,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (var index = 0;
                              index < _uploadedImageUrls.length;
                              index++)
                            Padding(
                              padding: const EdgeInsets.only(
                                right: BusinessTokens.space8,
                              ),
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      BusinessTokens.controlRadius,
                                    ),
                                    child: Image.network(
                                      _uploadedImageUrls[index],
                                      width: 88,
                                      height: 88,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: InkWell(
                                      onTap: () => _removeImage(index),
                                      borderRadius: BorderRadius.circular(12),
                                      child: const CircleAvatar(
                                        radius: 11,
                                        backgroundColor: BusinessTokens.danger,
                                        child: Icon(
                                          Icons.close,
                                          size: 13,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          for (final image in _selectedImages)
                            Padding(
                              padding: const EdgeInsets.only(
                                right: BusinessTokens.space8,
                              ),
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      BusinessTokens.controlRadius,
                                    ),
                                    child: Image.file(
                                      image,
                                      width: 88,
                                      height: 88,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  const Positioned(
                                    left: 4,
                                    bottom: 4,
                                    child: BusinessStatusChip(
                                      label: '업로드 전',
                                      tone: BusinessStatusTone.warning,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: BusinessTokens.space12),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isUploadingImages
                              ? null
                              : _showImageSourceOptions,
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: const Text('사진 선택'),
                        ),
                      ),
                      const SizedBox(width: BusinessTokens.space8),
                      Expanded(
                        child: FilledButton(
                          onPressed:
                              (_selectedImages.isEmpty || _isUploadingImages)
                                  ? null
                                  : _uploadImages,
                          child: _isUploadingImages
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text('업로드 (${_selectedImages.length})'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
          BusinessTokens.pagePadding,
          BusinessTokens.space12,
          BusinessTokens.pagePadding,
          BusinessTokens.space12 + MediaQuery.paddingOf(context).bottom,
        ),
        decoration: const BoxDecoration(
          color: BusinessTokens.surface,
          border: Border(
            top: BorderSide(color: BusinessTokens.border),
          ),
        ),
        child: BusinessPrimaryButton(
          label: '입찰 제출',
          loading: _isSubmitting,
          onPressed: _isSubmitting ? null : _confirmAndSubmit,
        ),
      ),
    );
  }

  Widget _requestMeta(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: BusinessTokens.mutedText),
        const SizedBox(width: BusinessTokens.space8),
        SizedBox(
          width: 76,
          child: Text(label, style: BusinessTokens.caption),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: BusinessTokens.body.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  String _formatWon(double amount) {
    final formatted = amount.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (match) => ',',
        );
    return '$formatted원';
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

class _BidAmountPreview extends StatelessWidget {
  final double amount;
  const _BidAmountPreview({required this.amount});

  String _format(double v) {
    final s = v.toStringAsFixed(0);
    return s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.receipt_long_outlined,
          size: 16,
          color: BusinessTokens.mutedText,
        ),
        const SizedBox(width: BusinessTokens.space8),
        Expanded(
          child: Text(
            amount > 0 ? '제출 금액 ${_format(amount)}원' : '제출할 실제 금액을 입력해주세요.',
            style: BusinessTokens.caption.copyWith(
              color:
                  amount > 0 ? BusinessTokens.blue : BusinessTokens.mutedText,
              fontWeight: amount > 0 ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
