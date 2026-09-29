import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/personal_order_link.dart';
import '../../models/order.dart' as app_models;
import '../../services/personal_order_link_service.dart';
import '../../services/order_service.dart';
import '../../widgets/business/business_tokens.dart';
import '../../utils/app_logger.dart';

/// 개인 링크를 통한 견적 요청 화면
class PersonalLinkQuoteRequestScreen extends StatefulWidget {
  final PersonalOrderLink link;

  const PersonalLinkQuoteRequestScreen({super.key, required this.link});

  @override
  State<PersonalLinkQuoteRequestScreen> createState() =>
      _PersonalLinkQuoteRequestScreenState();
}

class _PersonalLinkQuoteRequestScreenState
    extends State<PersonalLinkQuoteRequestScreen> {
  final _formKey = GlobalKey<FormState>();

  // Step tracking
  int _currentStep = 0;

  // Step 1: 수리 종류
  String _selectedCategory = '';

  // Step 2: 증상과 사진
  final _symptomsController = TextEditingController();
  final List<String> _photos = [];

  // Step 3: 추가 정보
  final _addressController = TextEditingController();
  final _contactController = TextEditingController();
  DateTime? _visitDate;
  bool _isUrgent = false;
  String _housingType = '아파트';

  // 개인정보 동의
  bool _agreedToTerms = false;

  bool _isSubmitting = false;

  @override
  void dispose() {
    _symptomsController.dispose();
    _addressController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('견적 요청'),
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 진행 표시 (고정)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: _buildProgressIndicator(),
            ),
            // 내용 (스크롤)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 직접 배정 안내
                          _buildDirectAssignmentBanner(),
                          const SizedBox(height: 24),

                          // 현재 스텝 내용
                          if (_currentStep == 0) _buildStep1Category(),
                          if (_currentStep == 1) _buildStep2Symptoms(),
                          if (_currentStep == 2) _buildStep3AdditionalInfo(),
                          if (_currentStep == 3) _buildStep4Confirmation(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 네비게이션 버튼 (고정)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: _buildNavigationButtons(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Row(
      children: List.generate(4, (index) {
        final isCompleted = index < _currentStep;
        final isCurrent = index == _currentStep;

        return Expanded(
          child: Container(
            height: 4,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: isCompleted || isCurrent
                  ? BusinessTokens.blue
                  : BusinessTokens.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildDirectAssignmentBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BusinessTokens.blueLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.person_pin, color: BusinessTokens.blue, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${widget.link.displayName ?? '사업자'}에게만 직접 전달됩니다',
              style: TextStyle(
                fontSize: 13,
                color: BusinessTokens.blue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep1Category() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '어떤 수리가 필요하신가요?',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          '수리 종류를 선택해주세요',
          style: TextStyle(fontSize: 14, color: BusinessTokens.mutedText),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: app_models.Order.CATEGORIES.map((category) {
            final isSelected = _selectedCategory == category;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedCategory = category;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: isSelected ? BusinessTokens.blue : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? BusinessTokens.blue : BusinessTokens.border,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Text(
                  category,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : BusinessTokens.text,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildStep2Symptoms() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '어떤 문제가 있나요?',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          '증상을 자세히 설명해주시면 더 정확한 견적을 받을 수 있어요',
          style: TextStyle(fontSize: 14, color: BusinessTokens.mutedText),
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: _symptomsController,
          decoration: InputDecoration(
            hintText: '예: 화장실 천장에서 물이 떨어져요',
            hintStyle: TextStyle(color: BusinessTokens.mutedText),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: BusinessTokens.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: BusinessTokens.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: BusinessTokens.blue, width: 2),
            ),
            filled: true,
            fillColor: BusinessTokens.canvas,
          ),
          maxLines: 5,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return '증상을 입력해주세요';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _pickPhotos,
          icon: const Icon(Icons.camera_alt_outlined),
          label: Text(_photos.isEmpty ? '사진 추가 (선택)' : '사진 ${_photos.length}장 선택됨'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep3AdditionalInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '추가 정보',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          '정확한 견적을 위해 정보를 입력해주세요',
          style: TextStyle(fontSize: 14, color: BusinessTokens.mutedText),
        ),
        const SizedBox(height: 24),
        _buildInputField(
          controller: _addressController,
          label: '수리 위치',
          hint: '예: 서울시 강서구 화곡동',
          icon: Icons.location_on_outlined,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return '수리 위치를 입력해주세요';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        _buildInputField(
          controller: _contactController,
          label: '연락처',
          hint: '010-1234-5678',
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return '연락처를 입력해주세요';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        _buildDatePicker(),
        const SizedBox(height: 16),
        _buildHousingTypeSelector(),
        const SizedBox(height: 12),
        _buildUrgentSwitch(),
      ],
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(color: BusinessTokens.mutedText),
        prefixIcon: Icon(icon, color: BusinessTokens.mutedText),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: BusinessTokens.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: BusinessTokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: BusinessTokens.blue, width: 2),
        ),
        filled: true,
        fillColor: BusinessTokens.canvas,
      ),
      validator: validator,
    );
  }

  Widget _buildDatePicker() {
    return InkWell(
      onTap: _pickVisitDate,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: BusinessTokens.canvas,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: BusinessTokens.border),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, color: BusinessTokens.mutedText),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '희망 방문일',
                    style: TextStyle(
                      fontSize: 12,
                      color: BusinessTokens.mutedText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _visitDate == null
                        ? '날짜 선택 (선택사항)'
                        : '${_visitDate!.year}년 ${_visitDate!.month}월 ${_visitDate!.day}일',
                    style: TextStyle(
                      fontSize: 15,
                      color: _visitDate == null
                          ? BusinessTokens.mutedText
                          : BusinessTokens.text,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: BusinessTokens.mutedText),
          ],
        ),
      ),
    );
  }

  Widget _buildHousingTypeSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BusinessTokens.canvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BusinessTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '주택 유형',
            style: TextStyle(
              fontSize: 12,
              color: BusinessTokens.mutedText,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['아파트', '빌라', '단독주택', '오피스텔', '상가'].map((type) {
              final isSelected = _housingType == type;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _housingType = type;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? BusinessTokens.blue : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? BusinessTokens.blue : BusinessTokens.border,
                    ),
                  ),
                  child: Text(
                    type,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isSelected ? Colors.white : BusinessTokens.text,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildUrgentSwitch() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _isUrgent ? BusinessTokens.danger.withValues(alpha: 0.08) : BusinessTokens.canvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isUrgent ? BusinessTokens.danger.withValues(alpha: 0.3) : BusinessTokens.border,
        ),
      ),
      child: SwitchListTile(
        title: Row(
          children: [
            Icon(
              Icons.priority_high,
              size: 20,
              color: _isUrgent ? BusinessTokens.danger : BusinessTokens.mutedText,
            ),
            const SizedBox(width: 8),
            Text(
              '긴급 수리',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: _isUrgent ? BusinessTokens.danger : BusinessTokens.text,
              ),
            ),
          ],
        ),
        subtitle: Text(
          '빠른 방문이 필요한 경우 선택',
          style: TextStyle(
            fontSize: 12,
            color: BusinessTokens.mutedText,
          ),
        ),
        value: _isUrgent,
        onChanged: (value) {
          setState(() {
            _isUrgent = value;
          });
        },
        activeColor: BusinessTokens.danger,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildStep4Confirmation() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '견적 요청 확인',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          '입력한 내용을 확인해주세요',
          style: TextStyle(fontSize: 14, color: BusinessTokens.mutedText),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: BusinessTokens.canvas,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: BusinessTokens.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildConfirmationRow('사업자', widget.link.displayName ?? '', icon: Icons.person),
              _buildConfirmationDivider(),
              _buildConfirmationRow('수리 종류', _selectedCategory, icon: Icons.build),
              _buildConfirmationDivider(),
              _buildConfirmationRow('증상', _symptomsController.text, icon: Icons.description),
              _buildConfirmationDivider(),
              _buildConfirmationRow('위치', _addressController.text, icon: Icons.location_on),
              _buildConfirmationDivider(),
              _buildConfirmationRow('연락처', _contactController.text, icon: Icons.phone),
              if (_visitDate != null) ...[
                _buildConfirmationDivider(),
                _buildConfirmationRow(
                  '희망 방문일',
                  '${_visitDate!.year}년 ${_visitDate!.month}월 ${_visitDate!.day}일',
                  icon: Icons.calendar_today,
                ),
              ],
              if (_isUrgent) ...[
                _buildConfirmationDivider(),
                _buildConfirmationRow('긴급', '예', icon: Icons.priority_high, valueColor: BusinessTokens.danger),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        _buildPrivacyConsent(),
      ],
    );
  }

  Widget _buildConfirmationRow(String label, String value, {IconData? icon, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: BusinessTokens.mutedText),
            const SizedBox(width: 12),
          ],
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: BusinessTokens.mutedText,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: valueColor ?? BusinessTokens.text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmationDivider() {
    return Divider(color: BusinessTokens.border, height: 1);
  }

  Widget _buildPrivacyConsent() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BusinessTokens.yellow.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BusinessTokens.yellow.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.security, color: BusinessTokens.warning, size: 20),
              const SizedBox(width: 8),
              const Text(
                '개인정보 수집 및 제공 동의',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '입력한 연락처, 주소, 사진, 수리 요청 내용은 견적 응대를 위해 ${widget.link.displayName ?? '사업자'}와 올수리에 전달됩니다.',
            style: TextStyle(fontSize: 13, height: 1.5, color: BusinessTokens.text),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () {
              setState(() {
                _agreedToTerms = !_agreedToTerms;
              });
            },
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: _agreedToTerms ? BusinessTokens.blue : Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _agreedToTerms ? BusinessTokens.blue : BusinessTokens.border,
                      width: 2,
                    ),
                  ),
                  child: _agreedToTerms
                      ? const Icon(Icons.check, size: 18, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    '개인정보 수집 및 제공에 동의합니다',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationButtons() {
    return Row(
      children: [
        if (_currentStep > 0)
          Expanded(
            flex: 1,
            child: OutlinedButton(
              onPressed: () {
                setState(() {
                  _currentStep--;
                });
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('이전'),
            ),
          ),
        if (_currentStep > 0) const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _handleNext,
            style: ElevatedButton.styleFrom(
              backgroundColor: BusinessTokens.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              disabledBackgroundColor: BusinessTokens.blue.withValues(alpha: 0.5),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    _currentStep == 3
                        ? '견적 요청 보내기'
                        : '다음',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleNext() async {
    if (_currentStep == 0) {
      if (_selectedCategory.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('수리 종류를 선택해주세요')),
        );
        return;
      }
      setState(() {
        _currentStep++;
      });

      // 이벤트 기록
      final service =
          Provider.of<PersonalOrderLinkService>(context, listen: false);
      await service.trackEvent(
        personalOrderLinkId: widget.link.id,
        eventType: PersonalOrderLinkEventType.categorySelected,
      );
    } else if (_currentStep == 1) {
      if (_symptomsController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('증상을 입력해주세요')),
        );
        return;
      }
      setState(() {
        _currentStep++;
      });
    } else if (_currentStep == 2) {
      if (_addressController.text.trim().isEmpty ||
          _contactController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('필수 정보를 모두 입력해주세요')),
        );
        return;
      }
      setState(() {
        _currentStep++;
      });
    } else if (_currentStep == 3) {
      if (!_agreedToTerms) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('개인정보 수집 및 제공에 동의해주세요')),
        );
        return;
      }
      await _submitQuoteRequest();
    }
  }

  Future<void> _submitQuoteRequest() async {
    setState(() {
      _isSubmitting = true;
    });

    try {
      final orderService = Provider.of<OrderService>(context, listen: false);

      final order = app_models.Order(
        title: '$_selectedCategory 수리 요청',
        description: _symptomsController.text.trim(),
        address: _addressController.text.trim(),
        visitDate: _visitDate ?? DateTime.now().add(const Duration(days: 1)),
        status: app_models.Order.STATUS_PENDING,
        createdAt: DateTime.now(),
        images: _photos,
        category: _selectedCategory,
        customerName: '',
        customerPhone: _contactController.text.trim(),
        isAnonymous: true,
      );

      final createdOrder = await orderService.createPersonalLinkOrder(
        order: order,
        personalOrderLinkId: widget.link.id,
        contractorId: widget.link.contractorId,
      );

      // 이벤트 기록
      final polService =
          Provider.of<PersonalOrderLinkService>(context, listen: false);
      await polService.trackEvent(
        personalOrderLinkId: widget.link.id,
        eventType: PersonalOrderLinkEventType.quoteSubmitted,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) =>
                PersonalLinkQuoteRequestCompletionScreen(
              link: widget.link,
              orderId: createdOrder.id ?? '',
            ),
          ),
        );
      }
    } catch (e, stack) {
      AppLog.error('PersonalLinkQuoteRequest', e,
          stack: stack, message: '견적 요청 제출 실패');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('견적 요청에 실패했습니다. 다시 시도해주세요.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _pickPhotos() async {
    // TODO: 실제 이미지 피커 구현
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('사진 선택 기능이 곧 구현됩니다')),
    );
  }

  Future<void> _pickVisitDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );

    if (picked != null) {
      setState(() {
        _visitDate = picked;
      });
    }
  }
}

/// 견적 요청 완료 화면
class PersonalLinkQuoteRequestCompletionScreen extends StatelessWidget {
  final PersonalOrderLink link;
  final String orderId;

  const PersonalLinkQuoteRequestCompletionScreen({
    super.key,
    required this.link,
    required this.orderId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: BusinessTokens.success.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check,
                      size: 60, color: BusinessTokens.success),
                ),
                const SizedBox(height: 32),
                const Text(
                  '견적 요청이 전달되었습니다!',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  '${link.displayName ?? '사업자'}님이 내용을 확인한 뒤\n올수리를 통해 견적 또는 연락을 드릴 예정입니다.',
                  style: TextStyle(
                    fontSize: 15,
                    color: BusinessTokens.mutedText,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.popUntil(context, (route) => route.isFirst);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: BusinessTokens.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '확인',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
