import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/user.dart';
import '../../providers/user_provider.dart';
import '../../services/auth_service.dart';
import '../../services/business_verify_service.dart';
import '../../widgets/common_app_bar.dart';
import 'package:go_router/go_router.dart';
import '../../utils/navigation_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/star_rating.dart';
import '../../services/review_service.dart';
import '../../services/media_service.dart';
import 'package:app_settings/app_settings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:convert';

class BusinessProfileScreen extends StatefulWidget {
  const BusinessProfileScreen({Key? key}) : super(key: key);

  @override
  State<BusinessProfileScreen> createState() => _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends State<BusinessProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _businessNumberController = TextEditingController();
  final _addressController = TextEditingController();
  
  List<String> _selectedServiceAreas = [];
  List<String> _selectedSpecialties = [];
  bool _isLoading = false;
  bool _isVerifying = false;
  double _avgRating = 0;
  int _reviewCount = 0;
  String? _avatarUrl;
  DateTime? _businessOpenDate;
  final BusinessVerifyService _verifyService = BusinessVerifyService();

  @override
  void initState() {
    super.initState();
    _loadCurrentUserData();
    for (final c in [_nameController, _businessNameController, _businessNumberController]) {
      c.addListener(_refreshVerifyStatusCard);
    }
  }

  void _refreshVerifyStatusCard() {
    if (mounted) setState(() {});
  }

  /// 진위확인 UI용 필수 사업자 정보(사장님 성함·상호·사업자번호·개업일) 입력 여부
  bool _hasRequiredBusinessFields() {
    final repName = _nameController.text.trim();
    final bizName = _businessNameController.text.trim();
    final bNo = _businessNumberController.text.trim();
    return repName.length >= 2 &&
        bizName.isNotEmpty &&
        BusinessVerifyService.normalizeBusinessNumber(bNo) != null &&
        _businessOpenDate != null;
  }

  void _loadCurrentUserData() {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final currentUser = userProvider.currentUser;
    
    if (currentUser != null) {
      _nameController.text = currentUser.name;
      _phoneController.text = currentUser.phoneNumber ?? '';
      _businessNameController.text = currentUser.businessName ?? '';
      _businessNumberController.text = currentUser.businessNumber ?? '';
      _addressController.text = currentUser.address ?? '';
      _selectedServiceAreas = List.from(currentUser.serviceAreas);
      _selectedSpecialties = List.from(currentUser.specialties);
      _avatarUrl = currentUser.avatarUrl;
      _businessOpenDate = currentUser.businessOpenDate;
    }
    // 리뷰 통계 로드
    Future.microtask(_loadRatingStats);
  }

  Future<void> _loadRatingStats() async {
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final userId = auth.currentUser?.id ?? '';
      if (userId.isEmpty) return;
      final stats = await ReviewService().getBusinessStats(userId);
      if (mounted) setState(() {
        _avgRating = stats?.averageRating ?? 0;
        _reviewCount = stats?.totalReviews ?? 0;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final c in [_nameController, _businessNameController, _businessNumberController]) {
      c.removeListener(_refreshVerifyStatusCard);
    }
    _nameController.dispose();
    _phoneController.dispose();
    _businessNameController.dispose();
    _businessNumberController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // 추가 필수/형식 검증
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final bizName = _businessNameController.text.trim();
    if (name.isEmpty || phone.isEmpty || bizName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사장님 성함, 전화번호, 상호명은 필수입니다.')),
      );
      return;
    }
    final phoneDigits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (phoneDigits.length < 9) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('전화번호 형식을 확인해 주세요.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      await auth.updateBusinessProfile(
        name: name,
        phoneNumber: phone,
        businessName: bizName,
        businessNumber: _businessNumberController.text.trim(),
        address: _addressController.text.trim(),
        serviceAreas: _selectedServiceAreas,
        specialties: _selectedSpecialties,
      );
      if (!mounted) return;
      
      // 🎉 환영 메시지 표시 (다이얼로그)
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.celebration, color: Theme.of(context).primaryColor, size: 28),
              const SizedBox(width: 12),
              const Text('환영합니다!'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${bizName} 님의 가입을 진심으로 환영합니다!',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '이제 올수리의 모든 기능을 사용하실 수 있습니다.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '💡 시작하기',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '• 견적 요청 확인하기\n'
                      '• 오더 마켓플레이스에서 입찰하기\n'
                      '• 고객과 채팅으로 소통하기',
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // 다이얼로그 닫기
                context.pop(); // 프로필 화면 닫기
              },
              child: const Text('시작하기', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        final msg = e.toString();
        String friendly = '프로필 저장 중 오류가 발생했습니다.';
        if (msg.contains('invalid input syntax for type uuid')) {
          friendly = '계정 식별 형식 문제로 서버에 저장하지 못했습니다. 프로필은 기기에 저장되었습니다. 고객센터로 문의해 주세요.';
        } else if (msg.contains('required') || msg.contains('null value')) {
          friendly = '필수 입력 항목을 확인해 주세요.';
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showServiceAreaDialog() {
    String searchText = '';
    List<String> filteredCities = List.from(KoreanCities.cities);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Filter cities based on search text
          filteredCities = KoreanCities.cities
              .where((city) => city.toLowerCase().contains(searchText.toLowerCase()))
              .toList();

          return AlertDialog(
            title: const Text('활동 지역 선택'),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: Column(
                children: [
                  Text('최대 5개까지 선택 가능합니다. (현재 ${_selectedServiceAreas.length}개)'),
                  const SizedBox(height: 16),
                  TextField( // Search input field
                    decoration: InputDecoration(
                      hintText: '지역 검색',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onChanged: (value) {
                      setDialogState(() {
                        searchText = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filteredCities.length,
                      itemBuilder: (context, index) {
                        final city = filteredCities[index];
                        final isSelected = _selectedServiceAreas.contains(city);

                        return CheckboxListTile(
                          title: Text(city),
                          value: isSelected,
                          onChanged: (bool? value) {
                            setDialogState(() { // Use setDialogState to update the dialog's state
                              if (value == true) {
                                if (_selectedServiceAreas.length < 5) {
                                  _selectedServiceAreas.add(city);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('최대 5개까지만 선택할 수 있습니다.'),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                }
                              } else {
                                _selectedServiceAreas.remove(city);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('확인'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSpecialtyDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('전문 분야 선택'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: ListView.builder(
              itemCount: EquipmentCategories.categories.length,
              itemBuilder: (context, index) {
                final category = EquipmentCategories.categories[index];
                final isSelected = _selectedSpecialties.contains(category);
                
                return CheckboxListTile(
                  title: Text(category),
                  value: isSelected,
                  onChanged: (bool? value) {
                    setState(() {
                      if (value == true) {
                        _selectedSpecialties.add(category);
                      } else {
                        _selectedSpecialties.remove(category);
                      }
                    });
                    setDialogState(() {}); // Dialog 내부 UI 업데이트
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('확인'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        NavigationUtils.navigateToRoleHome(context);
        return false;
      },
      child: Scaffold(
      appBar: CommonAppBar(
        title: '사업자 프로필',
        showBackButton: true,
        showHomeButton: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 상단 헤더: 상호명 표시 (프레임 내 Ellipsis)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _onChangeAvatar,
                      child: CircleAvatar(
                        radius: 20,
                        backgroundImage: (_avatarUrl != null && _avatarUrl!.isNotEmpty) ? NetworkImage(_avatarUrl!) : null,
                        child: (_avatarUrl == null || _avatarUrl!.isEmpty)
                            ? const Icon(Icons.storefront, size: 20)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _businessNameController.text.isNotEmpty
                            ? _businessNameController.text
                            : '상호명을 입력하세요',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (_avgRating > 0 || _reviewCount > 0)
                Row(
                  children: [
                    StarRating(rating: _avgRating, size: 18),
                    const SizedBox(width: 6),
                    Text('$_avgRating ($_reviewCount)', style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              const SizedBox(height: 16),
              // 기본 정보 섹션
              _buildSection(
                '기본 정보',
                [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: '사장님 성함 *',
                      hintText: '사장님 성함을 입력하세요',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return '사장님 성함을 입력해주세요';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: '전화번호 *',
                      hintText: '010-1234-5678',
                    ),
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      _PhoneNumberFormatter(),
                    ],
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return '전화번호를 입력해주세요';
                      }
                      return null;
                    },
                  ),
                ],
              ),
              
              const SizedBox(height: 24),

              // 알림 설정 섹션
              _buildSection(
                '알림 설정',
                [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.notifications_active),
                    title: const Text('기기 알림 설정 열기'),
                    subtitle: const Text('OS의 앱 알림 설정으로 이동합니다.'),
                    onTap: () {
                      AppSettings.openAppSettings();
                    },
                  ),
                ],
              ),
              
              // 사업자 정보 섹션
              _buildSection(
                '사업자 정보',
                [
                  _buildVerifyStatusCard(),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _businessNameController,
                    decoration: const InputDecoration(
                      labelText: '상호명 *',
                      hintText: '사업자 상호명을 입력하세요',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return '상호명을 입력해주세요';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _businessNumberController,
                    decoration: const InputDecoration(
                      labelText: '사업자 번호 *',
                      hintText: '123-45-67890',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: _pickOpenDate,
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: '개업일 *',
                        hintText: '예) 2020-01-15',
                        suffixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                      child: Text(
                        _businessOpenDate == null
                            ? '개업일을 선택하세요'
                            : DateFormat('yyyy-MM-dd').format(_businessOpenDate!),
                        style: TextStyle(
                          fontSize: 15,
                          color: _businessOpenDate == null
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.secondary,
                    ),
                    onPressed: _isVerifying ? null : _verifyBusinessNumber,
                    icon: _isVerifying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.verified_user_outlined),
                    label: Text(
                      _isVerifying ? '국세청 확인 중...' : '사업자등록 진위확인',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _addressController,
                    decoration: InputDecoration(
                      labelText: '주소',
                      hintText: '주소를 검색하세요',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: _openAddressSearch,
                      ),
                    ),
                    readOnly: true,
                    onTap: _openAddressSearch,
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // 활동 지역 섹션
              _buildSection(
                '활동 지역',
                [
                  Material(
                    elevation: 0,
                    borderRadius: BorderRadius.circular(12),
                    color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                    child: InkWell(
                      onTap: _showServiceAreaDialog,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.location_on_rounded,
                                      color: Theme.of(context).colorScheme.primary,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '활동 지역 선택',
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                ),
                                Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  size: 18,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _selectedServiceAreas.isEmpty
                                  ? '활동 지역을 선택해주세요 (최대 5개)'
                                  : '선택된 지역: ${_selectedServiceAreas.join(', ')}',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: _selectedServiceAreas.isEmpty
                                        ? Theme.of(context).colorScheme.onSurfaceVariant
                                        : Theme.of(context).colorScheme.onSurface,
                                    fontWeight: _selectedServiceAreas.isEmpty 
                                        ? FontWeight.w400 
                                        : FontWeight.w500,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // 전문 분야 섹션
              _buildSection(
                '전문 분야',
                [
                  Material(
                    elevation: 0,
                    borderRadius: BorderRadius.circular(12),
                    color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                    child: InkWell(
                      onTap: _showSpecialtyDialog,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.work_rounded,
                                      color: Theme.of(context).colorScheme.primary,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '전문 분야 선택',
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                ),
                                Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  size: 18,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _selectedSpecialties.isEmpty
                                  ? '전문 분야를 선택해주세요'
                                  : '선택된 분야: ${_selectedSpecialties.join(', ')}',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: _selectedSpecialties.isEmpty
                                        ? Theme.of(context).colorScheme.onSurfaceVariant
                                        : Theme.of(context).colorScheme.onSurface,
                                    fontWeight: _selectedSpecialties.isEmpty 
                                        ? FontWeight.w400 
                                        : FontWeight.w500,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 32),
              
              // 저장 버튼
              FilledButton.icon(
                onPressed: _isLoading ? null : _saveProfile,
                icon: _isLoading 
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.save_rounded, size: 22),
                label: Text(
                  _isLoading ? '저장 중...' : '프로필 저장',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),

              const SizedBox(height: 12),
              // 로그아웃 버튼
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    await Provider.of<AuthService>(context, listen: false).signOut();
                    if (mounted) NavigationUtils.navigateToRoleHome(context);
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('로그아웃 실패: $e')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.logout),
                label: const Text('로그아웃'),
              ),
            ],
          ),
        ),
      ),
    ));
  }

  Future<void> _pickOpenDate() async {
    final now = DateTime.now();
    final initial = _businessOpenDate ?? DateTime(now.year - 5, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1970, 1, 1),
      lastDate: DateTime(now.year, now.month, now.day),
      helpText: '개업일을 선택하세요',
      cancelText: '취소',
      confirmText: '확인',
    );
    if (picked != null) {
      setState(() => _businessOpenDate = picked);
    }
  }

  Future<void> _verifyBusinessNumber() async {
    final repName = _nameController.text.trim();
    final bNo = _businessNumberController.text.trim();
    final bizName = _businessNameController.text.trim();
    if (repName.length < 2) {
      _showSnack('대표자명(사장님 성함)을 입력해 주세요.');
      return;
    }
    if (BusinessVerifyService.normalizeBusinessNumber(bNo) == null) {
      _showSnack('사업자번호 10자리를 정확히 입력해 주세요.');
      return;
    }
    if (_businessOpenDate == null) {
      _showSnack('개업일을 선택해 주세요.');
      return;
    }

    setState(() => _isVerifying = true);
    try {
      final result = await _verifyService.verify(
        businessNumber: bNo,
        repName: repName,
        openDate: _businessOpenDate!,
        businessName: bizName.isEmpty ? null : bizName,
      );

      if (!mounted) return;

      if (result.success) {
        // AuthService에서 최신 사용자 상태(verifyStatus 등)를 다시 불러옴
        await Provider.of<AuthService>(context, listen: false)
            .refreshAfterBusinessVerify();
        if (!mounted) return;
        _showBusinessConfirmedDialog(result: result);
      } else if (_hasRequiredBusinessFields()) {
        // 국세청 API 실패/불일치여도 필수 항목이 모두 입력되면 '확인' 처리
        _showBusinessConfirmedDialog();
      } else {
        _showVerifyFailureDialog(result);
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack('진위확인 중 오류가 발생했습니다: $e');
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  void _showBusinessConfirmedDialog({BusinessVerifyResult? result}) {
    final ntsVerified = result?.success == true;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.green),
            SizedBox(width: 10),
            Text('확인'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('필수 사업자 정보가 모두 입력되어 확인되었습니다.'),
            if (ntsVerified && (result?.taxType ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('과세유형: ${result!.taxType}', style: const TextStyle(fontSize: 13)),
            ],
            if (ntsVerified && (result?.bStt ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('상태: ${result!.bStt}', style: const TextStyle(fontSize: 13)),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _showVerifySuccessDialog(BusinessVerifyResult r) {
    _showBusinessConfirmedDialog(result: r);
  }

  void _showVerifyFailureDialog(BusinessVerifyResult r) {
    final isMismatch = r.code == BusinessVerifyCode.notMatched ||
        r.code == BusinessVerifyCode.notRegistered ||
        r.code == BusinessVerifyCode.invalidFormat;
    final isTransient = r.code == BusinessVerifyCode.upstreamError ||
        r.code == BusinessVerifyCode.serviceUnavailable ||
        r.code == BusinessVerifyCode.networkError ||
        r.code == BusinessVerifyCode.rateLimited ||
        r.code == BusinessVerifyCode.unknownError;

    String title;
    IconData icon;
    Color iconColor;
    switch (r.code) {
      case BusinessVerifyCode.duplicate:
        title = '이미 등록된 사업자입니다';
        icon = Icons.group_remove_outlined;
        iconColor = Colors.orange;
        break;
      case BusinessVerifyCode.closed:
        title = '휴업·폐업 상태입니다';
        icon = Icons.do_disturb_alt_outlined;
        iconColor = Colors.orange;
        break;
      case BusinessVerifyCode.notMatched:
        title = '입력 정보가 일치하지 않습니다';
        icon = Icons.search_off_rounded;
        iconColor = Colors.red;
        break;
      case BusinessVerifyCode.notRegistered:
        title = '등록되지 않은 사업자번호입니다';
        icon = Icons.search_off_rounded;
        iconColor = Colors.red;
        break;
      case BusinessVerifyCode.networkError:
        title = '네트워크 오류';
        icon = Icons.wifi_off_rounded;
        iconColor = Colors.grey;
        break;
      case BusinessVerifyCode.upstreamError:
      case BusinessVerifyCode.serviceUnavailable:
      case BusinessVerifyCode.serverMisconfigured:
        title = '잠시 후 다시 시도해 주세요';
        icon = Icons.cloud_off_rounded;
        iconColor = Colors.grey;
        break;
      case BusinessVerifyCode.rateLimited:
        title = '요청이 너무 잦습니다';
        icon = Icons.hourglass_bottom_rounded;
        iconColor = Colors.orange;
        break;
      case BusinessVerifyCode.unauthorized:
        title = '로그인이 만료되었습니다';
        icon = Icons.login_rounded;
        iconColor = Colors.orange;
        break;
      case BusinessVerifyCode.forbidden:
        title = '사업자 회원만 이용할 수 있어요';
        icon = Icons.lock_outline_rounded;
        iconColor = Colors.orange;
        break;
      default:
        title = '진위확인 실패';
        icon = Icons.error_outline;
        iconColor = Colors.red;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: 10),
            Expanded(child: Text(title)),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            BusinessVerifyService.friendlyMessage(r),
            style: const TextStyle(height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('닫기'),
          ),
          if (isMismatch)
            FilledButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                FocusScope.of(context).requestFocus(FocusNode());
              },
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('정보 수정'),
            )
          else if (isTransient)
            FilledButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                _verifyBusinessNumber();
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('다시 시도'),
            ),
        ],
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _buildVerifyStatusCard() {
    final user = Provider.of<AuthService>(context).currentUser;
    if (user == null) return const SizedBox.shrink();

    Color bg;
    Color fg;
    IconData icon;
    String title;
    String subtitle;

    // 필수 항목이 모두 입력되면 '확인' 상태로 표시 (국세청 API 결과와 무관)
    if (_hasRequiredBusinessFields()) {
      bg = Colors.green.shade50;
      fg = Colors.green.shade800;
      icon = Icons.check_circle_outline;
      title = '확인';
      if (user.businessVerifyStatus == BusinessVerifyStatus.verified) {
        subtitle = user.businessVerifiedAt != null
            ? '국세청 진위확인 완료 · ${DateFormat('yyyy-MM-dd').format(user.businessVerifiedAt!.toLocal())}'
            : '필수 사업자 정보가 모두 입력되어 확인되었습니다.';
      } else {
        subtitle = '필수 사업자 정보가 모두 입력되어 확인되었습니다.';
      }
    } else {
      switch (user.businessVerifyStatus) {
        case BusinessVerifyStatus.verified:
          bg = Colors.green.shade50;
          fg = Colors.green.shade800;
          icon = Icons.check_circle_outline;
          title = '확인';
          subtitle = user.businessVerifiedAt != null
              ? '국세청 진위확인 완료 · ${DateFormat('yyyy-MM-dd').format(user.businessVerifiedAt!.toLocal())}'
              : '필수 사업자 정보가 모두 입력되어 확인되었습니다.';
          break;
        case BusinessVerifyStatus.failed:
          bg = Colors.orange.shade50;
          fg = Colors.orange.shade800;
          icon = Icons.edit_note_outlined;
          title = '사업자 정보 입력 필요';
          subtitle = '사장님 성함, 상호명, 사업자번호, 개업일을 모두 입력해 주세요.';
          break;
        case BusinessVerifyStatus.closed:
          bg = Colors.orange.shade50;
          fg = Colors.orange.shade800;
          icon = Icons.edit_note_outlined;
          title = '사업자 정보 입력 필요';
          subtitle = '사장님 성함, 상호명, 사업자번호, 개업일을 모두 입력해 주세요.';
          break;
        case BusinessVerifyStatus.unverified:
          bg = Colors.orange.shade50;
          fg = Colors.orange.shade800;
          icon = Icons.edit_note_outlined;
          title = '사업자 정보 입력 필요';
          subtitle = '사장님 성함, 상호명, 사업자번호, 개업일을 모두 입력해 주세요.';
          break;
      }
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(color: fg, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onChangeAvatar() async {
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final me = auth.currentUser;
      if (me == null) return;
      final media = MediaService();
      final file = await media.pickImageFromGallery();
      if (file == null) return;
      final url = await media.uploadProfileImage(userId: me.id, file: file);
      if (url == null) return;
      await Supabase.instance.client.from('users').update({'avatar_url': url}).eq('id', me.id);
      if (!mounted) return;
      setState(() => _avatarUrl = url);
    } catch (_) {}
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF222B45),
          ),
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    );
  }

  Future<void> _openAddressSearch() async {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          final url = request.url;
          final allowed = url.startsWith('https://t1.daumcdn.net') ||
                          url.startsWith('https://postcode.map.daum.net') ||
                          url.startsWith('https://map.daum.net') ||
                          url.startsWith('https://kakao.com') ||
                          url.startsWith('https://www.kakao.com');
          return allowed ? NavigationDecision.navigate : NavigationDecision.prevent;
        },
      ))
      ..addJavaScriptChannel('flutter', onMessageReceived: (msg) {
        try {
          final Map<String, dynamic> data = json.decode(msg.message) as Map<String, dynamic>;
          final addr = (data['roadAddress']?.toString().isNotEmpty ?? false)
              ? data['roadAddress'].toString()
              : (data['address']?.toString() ?? '');
          setState(() {
            _addressController.text = addr;
          });
        } catch (_) {}
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      });

    final html = '''
<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Kakao Postcode</title>
  <script src="https://t1.daumcdn.net/mapjsapi/bundle/postcode/prod/postcode.v2.js"></script>
  <style>
    html, body, #wrap { height: 100%; margin: 0; }
    #wrap { display: flex; }
    #container { flex: 1; }
  </style>
  <script>
    function sendAddressToFlutter(payload) {
      if (window.flutter && window.flutter.postMessage) {
        window.flutter.postMessage(payload);
      }
    }
    window.onload = function() {
      new daum.Postcode({
        oncomplete: function(data) {
          const payload = JSON.stringify({
            address: data.address || '',
            roadAddress: data.roadAddress || '',
            jibunAddress: data.jibunAddress || '',
            zonecode: data.zonecode || ''
          });
          sendAddressToFlutter(payload);
        },
        width: '100%',
        height: '100%'
      }).embed(document.getElementById('container'));
    };
  </script>
</head>
<body>
  <div id="wrap">
    <div id="container"></div>
  </div>
</body>
</html>
''';

    await controller.loadHtmlString(html, baseUrl: 'https://postcode.map.daum.net');

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '주소 검색',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              Expanded(
                child: WebViewWidget(controller: controller),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 전화번호 자동 하이픈 포맷터
class _PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    
    if (text.isEmpty) {
      return newValue;
    }

    String formatted = '';
    
    if (text.length <= 3) {
      formatted = text;
    } else if (text.length <= 7) {
      formatted = '${text.substring(0, 3)}-${text.substring(3)}';
    } else if (text.length <= 11) {
      formatted = '${text.substring(0, 3)}-${text.substring(3, 7)}-${text.substring(7)}';
    } else {
      formatted = '${text.substring(0, 3)}-${text.substring(3, 7)}-${text.substring(7, 11)}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
} 