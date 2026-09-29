import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config.dart';
import '../../models/order.dart';
import '../../models/personal_order_link.dart';
import '../../services/personal_order_link_service.dart';
import '../../widgets/business/business_app_shell.dart';
import '../../widgets/business/business_tokens.dart';
import '../../widgets/business/business_primary_button.dart';
import '../../utils/app_logger.dart';

/// 개인 오더 링크 편집 화면
class EditPersonalOrderLinkScreen extends StatefulWidget {
  final PersonalOrderLink link;

  const EditPersonalOrderLinkScreen({super.key, required this.link});

  @override
  State<EditPersonalOrderLinkScreen> createState() =>
      _EditPersonalOrderLinkScreenState();
}

class _EditPersonalOrderLinkScreenState
    extends State<EditPersonalOrderLinkScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _slugController;
  late final TextEditingController _displayNameController;
  late final TextEditingController _headlineController;
  late final TextEditingController _introductionController;
  final _regionController = TextEditingController();

  late List<String> _selectedCategories;
  late List<String> _selectedRegions;
  late bool _acceptsDirectOrders;

  bool _isCheckingSlug = false;
  bool _isSlugAvailable = true;
  String? _slugError;

  bool _isSaving = false;

  final String _baseUrl = AppConfig.publicWebBaseUrl;

  @override
  void initState() {
    super.initState();
    _slugController = TextEditingController(text: widget.link.slug);
    _displayNameController =
        TextEditingController(text: widget.link.displayName ?? '');
    _headlineController =
        TextEditingController(text: widget.link.headline ?? '');
    _introductionController =
        TextEditingController(text: widget.link.introduction ?? '');

    _selectedCategories = List.from(widget.link.supportedCategories);
    _selectedRegions = List.from(widget.link.serviceRegions);
    _acceptsDirectOrders = widget.link.acceptsDirectOrders;

    _slugController.addListener(_onSlugChanged);
  }

  @override
  void dispose() {
    _slugController.removeListener(_onSlugChanged);
    _slugController.dispose();
    _displayNameController.dispose();
    _headlineController.dispose();
    _introductionController.dispose();
    _regionController.dispose();
    super.dispose();
  }

  void _onSlugChanged() {
    // slug가 변경되었는지 확인
    if (_slugController.text != widget.link.slug) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_slugController.text.isNotEmpty && mounted) {
          _checkSlugAvailability();
        }
      });
    } else {
      setState(() {
        _isSlugAvailable = true;
        _slugError = null;
      });
    }
  }

  Future<void> _checkSlugAvailability() async {
    final slug = _slugController.text.trim();
    if (slug.isEmpty || slug == widget.link.slug) {
      setState(() {
        _isSlugAvailable = true;
        _slugError = null;
      });
      return;
    }

    setState(() {
      _isCheckingSlug = true;
      _slugError = null;
    });

    try {
      final service =
          Provider.of<PersonalOrderLinkService>(context, listen: false);
      final isAvailable =
          await service.checkSlugAvailability(slug, excludeLinkId: widget.link.id);

      if (mounted) {
        setState(() {
          _isSlugAvailable = isAvailable;
          _isCheckingSlug = false;
          if (!isAvailable) {
            _slugError = '이미 사용 중인 링크 주소입니다';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCheckingSlug = false;
          _slugError = '링크 주소 확인 중 오류가 발생했습니다';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BusinessAppShell(
      title: '개인 링크 수정',
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSection(
              title: '기본 정보',
              children: [
                _buildTextField(
                  controller: _displayNameController,
                  label: '상호 또는 표시 이름',
                  hint: '예: 김 사장님 설비',
                  prefixIcon: Icons.storefront,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '표시 이름을 입력하세요';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _headlineController,
                  label: '한 줄 소개',
                  hint: '예: 누수·배관·화장실 수리 전문',
                  prefixIcon: Icons.short_text,
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _introductionController,
                  label: '상세 소개 (선택)',
                  hint: '사업자님의 전문성과 서비스를 자유롭게 소개해주세요',
                  maxLines: 5,
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildSection(
              title: '링크 주소',
              children: [
                TextFormField(
                  controller: _slugController,
                  decoration: InputDecoration(
                    hintText: '내 링크 주소',
                    helperText: '소문자, 숫자, 하이픈(-), 언더스코어(_)만 사용 가능',
                    errorText: _slugError,
                    suffixIcon: _isCheckingSlug
                        ? const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : _isSlugAvailable
                            ? Icon(Icons.check_circle,
                                color: BusinessTokens.success)
                            : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: BusinessTokens.border),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '링크 주소를 입력하세요';
                    }
                    if (value.length < 3) {
                      return '링크 주소는 3자 이상이어야 합니다';
                    }
                    if (!_isSlugAvailable) {
                      return '사용할 수 없는 링크 주소입니다';
                    }
                    return null;
                  },
                ),
                if (_slugController.text != widget.link.slug) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: BusinessTokens.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: BusinessTokens.warning.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber,
                            size: 18, color: BusinessTokens.warning),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '링크 주소를 변경하면 기존 링크가 작동하지 않습니다',
                            style: TextStyle(
                              fontSize: 12,
                              color: BusinessTokens.warning,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),
            _buildSection(
              title: '전문 공정',
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: Order.CATEGORIES.map((category) {
                    final isSelected = _selectedCategories.contains(category);
                    return FilterChip(
                      label: Text(category),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedCategories.add(category);
                          } else {
                            _selectedCategories.remove(category);
                          }
                        });
                      },
                      selectedColor: BusinessTokens.blueLight,
                      checkmarkColor: BusinessTokens.blue,
                    );
                  }).toList(),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildSection(
              title: '활동 지역',
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _regionController,
                        decoration: InputDecoration(
                          hintText: '예: 서울 강서구',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: BusinessTokens.border),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                        ),
                        onSubmitted: _addRegion,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: () => _addRegion(_regionController.text),
                      icon: const Icon(Icons.add),
                      style: IconButton.styleFrom(
                        backgroundColor: BusinessTokens.blue,
                      ),
                    ),
                  ],
                ),
                if (_selectedRegions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _selectedRegions.map((region) {
                      return Chip(
                        label: Text(region),
                        deleteIcon: const Icon(Icons.close, size: 18),
                        onDeleted: () {
                          setState(() {
                            _selectedRegions.remove(region);
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),
            _buildSection(
              title: '직접 오더 받기',
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: BusinessTokens.border),
                  ),
                  child: SwitchListTile(
                    title: const Text(
                      '직접 오더 받기',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'OFF로 설정하면 새로운 견적 요청을 받지 않습니다',
                      style: TextStyle(
                        fontSize: 12,
                        color: BusinessTokens.mutedText,
                      ),
                    ),
                    value: _acceptsDirectOrders,
                    onChanged: (value) {
                      setState(() {
                        _acceptsDirectOrders = value;
                      });
                    },
                    activeColor: BusinessTokens.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
            BusinessPrimaryButton(
              label: '저장',
              onPressed: _isSaving ? null : _saveChanges,
              loading: _isSaving,
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  void _addRegion(String value) {
    if (value.isNotEmpty && !_selectedRegions.contains(value)) {
      setState(() {
        _selectedRegions.add(value);
        _regionController.clear();
      });
    }
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: BusinessTokens.sectionTitle,
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }

  Widget _buildTextField({
    TextEditingController? controller,
    required String label,
    String? hint,
    IconData? prefixIcon,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
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
        fillColor: Colors.white,
      ),
      maxLines: maxLines,
      validator: validator,
    );
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final service =
          Provider.of<PersonalOrderLinkService>(context, listen: false);

      // 변경된 필드만 전송
      String? slug;
      if (_slugController.text.trim() != widget.link.slug) {
        slug = _slugController.text.trim();
      }

      await service.updatePersonalOrderLink(
        linkId: widget.link.id,
        slug: slug,
        displayName: _displayNameController.text.trim(),
        headline: _headlineController.text.trim().isEmpty
            ? null
            : _headlineController.text.trim(),
        introduction: _introductionController.text.trim().isEmpty
            ? null
            : _introductionController.text.trim(),
        supportedCategories: _selectedCategories,
        serviceRegions: _selectedRegions,
        acceptsDirectOrders: _acceptsDirectOrders,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('개인 링크가 수정되었습니다'),
              ],
            ),
            backgroundColor: BusinessTokens.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e, stack) {
      AppLog.error('EditPersonalOrderLink', e,
          stack: stack, message: '링크 수정 실패');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('링크 수정에 실패했습니다: ${e.toString()}'),
            backgroundColor: BusinessTokens.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }
}
