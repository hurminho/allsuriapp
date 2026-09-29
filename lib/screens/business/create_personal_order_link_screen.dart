import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config.dart';
import '../../models/order.dart';
import '../../providers/user_provider.dart';
import '../../services/personal_order_link_service.dart';
import '../../widgets/business/business_app_shell.dart';
import '../../widgets/business/business_tokens.dart';
import '../../widgets/business/business_primary_button.dart';
import '../../utils/app_logger.dart';

/// 개인 오더 링크 생성 화면
class CreatePersonalOrderLinkScreen extends StatefulWidget {
  const CreatePersonalOrderLinkScreen({super.key});

  @override
  State<CreatePersonalOrderLinkScreen> createState() =>
      _CreatePersonalOrderLinkScreenState();
}

class _CreatePersonalOrderLinkScreenState
    extends State<CreatePersonalOrderLinkScreen> {
  final _formKey = GlobalKey<FormState>();
  final _slugController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _headlineController = TextEditingController();

  List<String> _selectedCategories = [];
  List<String> _selectedRegions = [];
  final _regionController = TextEditingController();

  bool _isCheckingSlug = false;
  bool _isSlugAvailable = false;
  String? _slugError;

  bool _isCreating = false;

  final String _baseUrl = AppConfig.publicWebBaseUrl;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _slugController.addListener(_onSlugChanged);
  }

  @override
  void dispose() {
    _slugController.removeListener(_onSlugChanged);
    _slugController.dispose();
    _displayNameController.dispose();
    _headlineController.dispose();
    _regionController.dispose();
    super.dispose();
  }

  void _loadUserData() {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.currentUser;

    if (user != null) {
      _displayNameController.text = user.businessName ?? user.name;
      _selectedCategories = List.from(user.specialties);
      _selectedRegions = List.from(user.serviceAreas);

      // slug 제안 생성
      final service =
          Provider.of<PersonalOrderLinkService>(context, listen: false);
      final suggestedSlug = service.generateSuggestedSlug(user.businessName ?? user.name);
      _slugController.text = suggestedSlug;
    }
  }

  void _onSlugChanged() {
    // 디바운싱: 입력 후 500ms 후에 체크
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_slugController.text.isNotEmpty && mounted) {
        _checkSlugAvailability();
      }
    });
  }

  Future<void> _checkSlugAvailability() async {
    final slug = _slugController.text.trim();
    if (slug.isEmpty) {
      setState(() {
        _isSlugAvailable = false;
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
      final isAvailable = await service.checkSlugAvailability(slug);

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
      title: '개인 링크 만들기',
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSection(
              title: '기본 정보',
              description: '공개 페이지에 표시됩니다',
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
                  label: '한 줄 소개 (선택)',
                  hint: '예: 누수·배관·화장실 수리 전문',
                  prefixIcon: Icons.short_text,
                  maxLines: 2,
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildSection(
              title: '링크 주소',
              description: '고객이 접속할 주소입니다',
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: BusinessTokens.canvas,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$_baseUrl/allsuri/',
                    style: TextStyle(
                      fontSize: 13,
                      color: BusinessTokens.mutedText,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _slugController,
                  decoration: InputDecoration(
                    hintText: '내 링크 주소',
                    helperText: '소문자, 숫자, 하이픈(-), 언더스코어(_)만 사용 가능',
                    helperStyle: TextStyle(color: BusinessTokens.mutedText),
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
                        : _isSlugAvailable && _slugController.text.isNotEmpty
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
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: BusinessTokens.blue, width: 2),
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
                if (_slugController.text.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: BusinessTokens.blueLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.link, size: 16, color: BusinessTokens.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$_baseUrl/allsuri/${_slugController.text}',
                            style: TextStyle(
                              fontSize: 12,
                              color: BusinessTokens.blue,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
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
              description: '어떤 수리를 전문으로 하시나요?',
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
              description: '어느 지역에서 활동하시나요?',
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
            const SizedBox(height: 40),
            BusinessPrimaryButton(
              label: '개인 링크 만들기',
              onPressed: _isCreating ? null : _createLink,
              loading: _isCreating,
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
    String? description,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: BusinessTokens.sectionTitle,
        ),
        if (description != null) ...[
          const SizedBox(height: 4),
          Text(
            description,
            style: BusinessTokens.caption,
          ),
        ],
        const SizedBox(height: 16),
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

  Future<void> _createLink() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      final service =
          Provider.of<PersonalOrderLinkService>(context, listen: false);

      await service.createPersonalOrderLink(
        slug: _slugController.text.trim(),
        displayName: _displayNameController.text.trim(),
        headline: _headlineController.text.trim().isEmpty
            ? null
            : _headlineController.text.trim(),
        supportedCategories: _selectedCategories,
        serviceRegions: _selectedRegions,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('개인 링크가 생성되었습니다!'),
              ],
            ),
            backgroundColor: BusinessTokens.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e, stack) {
      AppLog.error('CreatePersonalOrderLink', e,
          stack: stack, message: '링크 생성 실패');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('링크 생성에 실패했습니다: ${e.toString()}'),
            backgroundColor: BusinessTokens.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }
}
