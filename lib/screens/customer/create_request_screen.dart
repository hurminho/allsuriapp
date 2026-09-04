import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:webview_flutter/webview_flutter.dart';
import '../../models/order.dart' as app_models;
import '../../services/order_service.dart';
import '../../services/image_service.dart';
import '../../services/messaging_service.dart';
import '../../services/kakao_share_service.dart';
import '../../providers/user_provider.dart';
import '../../utils/responsive_utils.dart';
import '../../widgets/common_app_bar.dart';
import 'package:allsuriapp/utils/app_logger.dart';
// 사용하지 않는 import 정리

class CreateRequestScreen extends StatefulWidget {
  final app_models.Order? editingOrder;
  final String? initialCategory;
  
  const CreateRequestScreen({Key? key, this.editingOrder, this.initialCategory}) : super(key: key);

  @override
  State<CreateRequestScreen> createState() => _CreateRequestScreenState();
}

class _CreateRequestScreenState extends State<CreateRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _addressController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  
  String _selectedCategory = '누수';
  DateTime? _selectedDate;
  List<String> _imageUrls = [];
  bool _isLoading = false;
  static const String _sessionKey = 'allsuri_session_id';
  static const String _lastPhoneKey = 'allsuri_last_phone';
  // Build-time injection via --dart-define
  static const String kakaoRestApiKey = String.fromEnvironment('KAKAO_REST_API_KEY', defaultValue: '');
  final TextEditingController _addressQueryController = TextEditingController();
  List<String> _addressResults = [];
  final TextEditingController _addressDetailController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now().add(const Duration(days: 1));
    
    // 초기 카테고리가 제공된 경우 설정
    if (widget.initialCategory != null) {
      _selectedCategory = widget.initialCategory!;
    }
    
    // 수정 모드인 경우 기존 데이터 로드
    if (widget.editingOrder != null) {
      _loadOrderData();
    }
    _prefillSavedPhone();
  }
  Future<String> _getOrCreateSessionId() async {
    // 로컬에 세션ID 저장
    final prefs = await SharedPreferences.getInstance();
    String? sid = prefs.getString(_sessionKey);
    if (sid != null && sid.isNotEmpty) return sid;
    sid = const Uuid().v4();
    await prefs.setString(_sessionKey, sid);
    return sid;
  }

  void _loadOrderData() {
    final order = widget.editingOrder!;
    _titleController.text = order.title;
    _descriptionController.text = order.description;
    _addressController.text = order.address;
    _nameController.text = order.customerName;
    _phoneController.text = order.customerPhone;
    _selectedCategory = order.category;
    _selectedDate = order.visitDate;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _addressController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressQueryController.dispose();
    _addressDetailController.dispose();
    super.dispose();
  }

  // Future<void> _selectDate(BuildContext context) async {}
  // Future<void> _addImage() async {}
  // void _removeImage(int index) {}
  
  // 전화번호 정규화 함수
  String _normalizePhoneNumber(String phone) {
    // 하이픈, 공백, 괄호 제거
    return phone.replaceAll(RegExp(r'[-\s()]'), '');
  }

  Future<void> _prefillSavedPhone() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_lastPhoneKey);
    if (saved != null && saved.isNotEmpty && _phoneController.text.isEmpty) {
      setState(() {
        _phoneController.text = saved;
      });
    }
  }

  Future<void> _submitRequest() async {
    print('견적 요청 제출 시작');
    
    if (!_formKey.currentState!.validate()) {
      print('폼 검증 실패');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      print('견적 요청 데이터 준비 중...');
      
      // UserProvider에서 현재 사용자 정보 가져오기
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final currentUser = userProvider.currentUser;
      
      // 전화번호 결정: 로그인한 사용자 전화번호 우선, 없으면 입력된 전화번호 사용
      String phoneNumber;
      String customerName;
      
      if (currentUser != null && !currentUser.isAnonymous) {
        // 로그인한 사용자인 경우
        phoneNumber = currentUser.phoneNumber ?? _phoneController.text;
        customerName = currentUser.name ?? _nameController.text.trim();
        // 이름·전화번호를 로그로 남기지 않습니다.
        AppLog.debug('CreateRequest', '로그인 사용자 정보로 요청 작성');
      } else {
        // 로그인하지 않은 사용자인 경우
        phoneNumber = _phoneController.text;
        customerName = _nameController.text.trim();
      }
      
      // 전화번호 정규화
      final normalizedPhone = _normalizePhoneNumber(phoneNumber);
      AppLog.debug('CreateRequest', '연락처 정규화 완료 (자릿수 ${normalizedPhone.length})');
      
      final orderService = Provider.of<OrderService>(context, listen: false);
      
      if (widget.editingOrder != null) {
        // 수정 모드
        final updatedOrder = widget.editingOrder!.copyWith(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          address: _addressController.text.trim(),
          visitDate: _selectedDate ?? DateTime.now(),
          category: _selectedCategory,
          customerName: customerName,
          customerPhone: normalizedPhone,
        );
        
        await orderService.updateOrder(updatedOrder);
        print('✅ 견적 요청 수정 성공!');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('견적 요청이 성공적으로 수정되었습니다'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // 새 견적 요청 생성
        // 비로그인 사용자를 위한 세션 ID 생성/로딩
        String sessionId = await _getOrCreateSessionId();

        final order = app_models.Order(
          id: null, // Supabase가 UUID 자동 생성
          customerId: currentUser?.id,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          address: _addressController.text.trim(),
          visitDate: _selectedDate ?? DateTime.now(),
          status: 'pending',
          createdAt: DateTime.now(),
          images: [],
          estimatedPrice: 0.0,
          technicianId: null,
          selectedEstimateId: null,
          category: _selectedCategory,
          customerName: customerName,
          customerPhone: normalizedPhone,
          customerEmail: currentUser?.email,
          isAnonymous: currentUser == null,
          isAwarded: false,
          awardedAt: null,
          awardedEstimateId: null,
          sessionId: sessionId,
        );

        final createdOrder = await orderService.createOrder(order);
        print('✅ 견적 요청 생성 성공!');
        
        // 푸시 알림 전송 (사업자들에게)
        try {
          final messagingService = MessagingService();
          await messagingService.sendNewRequestNotification(order);
          print('✅ 푸시 알림 전송 성공');
        } catch (e) {
          print('⚠️ 푸시 알림 전송 실패 (무시): $e');
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('견적 요청이 성공적으로 제출되었습니다'),
              backgroundColor: Colors.green,
            ),
          );
          
          // 카카오톡 공유 다이얼로그 표시
          _showKakaoShareDialog(createdOrder);
        }
      }
      
      if (mounted) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_lastPhoneKey, _phoneController.text.trim());
        } catch (_) {}
        Navigator.of(context).pop();
      }
    } catch (e) {
      print('견적 요청 제출 중 오류 발생: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('견적 요청 ${widget.editingOrder != null ? '수정' : '제출'} 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  /// 카카오톡 공유 다이얼로그 표시
  void _showKakaoShareDialog(app_models.Order order) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Image.asset(
              'assets/images/kakao_logo.png',
              height: 24,
            ),
            const SizedBox(width: 8),
            const Text('카카오톡으로 공유'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '견적 요청을 카카오톡으로 공유하시겠어요?',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 16),
                      SizedBox(width: 4),
                      Text('나에게 보내기로 기록 보관'),
                    ],
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 16),
                      SizedBox(width: 4),
                      Text('오픈채팅방 링크 포함'),
                    ],
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 16),
                      SizedBox(width: 4),
                      Text('더 많은 사업자와 상담 가능'),
                    ],
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
              Navigator.of(context).pop(); // 견적 요청 화면 닫기
            },
            child: const Text('나중에'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.of(context).pop(); // 다이얼로그 닫기
              
              // 카카오톡 공유 실행
              final kakaoShareService = KakaoShareService();
              final success = await kakaoShareService.shareEstimate(
                estimateId: order.id ?? 'unknown',
                title: order.title,
                category: order.category,
                address: order.address,
                description: order.description,
              );
              
              if (mounted) {
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('카카오톡 공유가 완료되었습니다'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('카카오톡 공유에 실패했습니다'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
                Navigator.of(context).pop(); // 견적 요청 화면 닫기
              }
            },
            icon: const Icon(Icons.share),
            label: const Text('공유하기'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFEE500),
              foregroundColor: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = ResponsiveUtils.isTablet(context);
    
    return Scaffold(
      appBar: CommonAppBar(
        title: widget.editingOrder != null ? '견적 요청 수정' : '견적 요청',
        showBackButton: true,
        showHomeButton: true,
      ),
      body: WillPopScope(
        onWillPop: () async {
          if (_hasChanges()) {
            final shouldPop = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('변경사항이 있습니다'),
                content: const Text('작성 중인 내용이 있습니다. 정말 나가시겠습니까?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('취소'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text('나가기'),
                  ),
                ],
              ),
            );
            return shouldPop ?? false;
          }
          return true;
        },
        child: SingleChildScrollView(
          padding: EdgeInsets.all(isTablet ? 32.0 : 16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 카테고리 선택
                DropdownButtonFormField<String>(
                  value: _selectedCategory,
                  decoration: const InputDecoration(
                    labelText: '카테고리 *',
                    border: OutlineInputBorder(),
                  ),
                  items: app_models.Order.CATEGORIES.map((category) {
                    return DropdownMenuItem<String>(
                      value: category,
                      child: Text(category),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedCategory = value!;
                    });
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '카테고리를 선택해주세요';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                // 제목 입력 (카테고리 기반)
                TextFormField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: '제목 *',
                    border: const OutlineInputBorder(),
                    hintText: '예: $_selectedCategory 수리 요청',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '제목을 입력해주세요';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                // 설명 입력
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: '설명 *',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '설명을 입력해주세요';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                // 주소 입력
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _addressController,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: '주소 *',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return '주소를 입력해주세요';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _openAddressPostcodeWebview,
                      icon: const Icon(Icons.search),
                      label: const Text('주소 검색'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressDetailController,
                  decoration: const InputDecoration(
                    labelText: '상세 주소 (동/호 등)',
                    border: OutlineInputBorder(),
                    hintText: '예: 101동 1203호',
                  ),
                ),
                const SizedBox(height: 16),
                
                // 이름 입력
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: '이름 *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '이름을 입력해주세요';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                // 전화번호 입력 (테스트용 버튼 포함)
                Row(
                  children: [
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _phoneController,
                        decoration: const InputDecoration(
                          labelText: '전화번호 *',
                          hintText: '010-1234-5678',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.phone,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return '전화번호를 입력해주세요';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // 방문일 선택
                InkWell(
                  onTap: _selectDate,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today),
                        const SizedBox(width: 8),
                        Text(
                          _selectedDate != null
                              ? '방문일: ${_formatDate(_selectedDate!)}'
                              : '방문일을 선택해주세요 *',
                          style: TextStyle(
                            color: _selectedDate != null ? Colors.black : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_selectedDate == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 8, left: 16),
                    child: Text(
                      '방문일을 선택해주세요',
                      style: TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 24),
                
                // 제출 버튼
                FilledButton(
                  onPressed: _isLoading ? null : _submitRequest,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          widget.editingOrder != null ? '견적 요청 수정' : '견적 요청 제출',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[600]),
                const SizedBox(width: 8),
                Text(
                  '간편 견적 요청',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              '• 회원가입 없이도 견적을 요청할 수 있습니다\n'
              '• 여러 업체에서 견적을 받아보세요\n'
              '• 연락처는 견적 제공 목적으로만 사용됩니다',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '연락처 정보',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '이름 *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '이름을 입력해주세요';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: '연락처 *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone),
              ),
              keyboardType: TextInputType.phone,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '연락처를 입력해주세요';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: '이메일 (선택)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '서비스 정보',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: '서비스 제목 *',
                border: OutlineInputBorder(),
                hintText: '예: 에어컨 청소, 보일러 수리 등',
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '서비스 제목을 입력해주세요';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: '상세 설명 *',
                border: OutlineInputBorder(),
                hintText: '서비스에 대한 자세한 설명을 입력해주세요',
              ),
              maxLines: 4,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '상세 설명을 입력해주세요';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _addressController,
              decoration: const InputDecoration(
                labelText: '서비스 주소 *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '서비스 주소를 입력해주세요';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text('방문 희망 날짜'),
              subtitle: Text(
                _selectedDate != null 
                    ? '${_selectedDate!.year}년 ${_selectedDate!.month}월 ${_selectedDate!.day}일'
                    : '날짜를 선택해주세요',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _selectDate,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '사진 첨부 (선택)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '문제 상황의 사진을 첨부하면 더 정확한 견적을 받을 수 있습니다',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._imageUrls.map((url) => _buildImageTile(url)),
                _buildAddImageTile(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageTile(String url) {
    return Stack(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            image: DecorationImage(
              image: NetworkImage(url),
              fit: BoxFit.cover,
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () => _removeImage(url),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddImageTile() {
    return GestureDetector(
      onTap: _addImage,
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
          color: Colors.grey[50],
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo, color: Colors.grey),
            SizedBox(height: 4),
            Text('사진 추가', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _submitRequest,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue[600],
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: _isLoading
            ? const CircularProgressIndicator(color: Colors.white)
            : const Text(
                '견적 요청하기',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now().add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _addImage() async {
    try {
      final imageService = ImageService();
      final url = await imageService.pickAndUploadImage();
      if (url != null) {
        setState(() {
          _imageUrls.add(url);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('이미지 업로드 실패: $e')),
      );
    }
  }

  void _removeImage(String url) {
    setState(() {
      _imageUrls.remove(url);
    });
  }

  bool _hasChanges() {
    return _titleController.text.isNotEmpty ||
           _descriptionController.text.isNotEmpty ||
           _addressController.text.isNotEmpty ||
           _phoneController.text.isNotEmpty;
  }

  String _formatDate(DateTime date) {
    return '${date.year}년 ${date.month}월 ${date.day}일';
  }

  Future<void> _openAddressSearch() async {
    // 간단한 바텀시트 검색 UI + 카카오 주소검색 REST 예시 (키 필요)
    _addressResults = [];
    _addressQueryController.clear();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _addressQueryController,
                  decoration: const InputDecoration(
                    labelText: '주소 검색',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _searchAddress(),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _searchAddress,
                    child: const Text('검색'),
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: StatefulBuilder(
                    builder: (context, setModalState) {
                      Future<void> rerender() async => setModalState(() {});
                      return ListView.separated(
                        shrinkWrap: true,
                        itemCount: _addressResults.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final addr = _addressResults[index];
                          return ListTile(
                            title: Text(addr),
                            onTap: () {
                              _addressController.text = addr;
                              Navigator.pop(context);
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _searchAddress() async {
    final q = _addressQueryController.text.trim();
    if (q.isEmpty) return;
    try {
      if (kakaoRestApiKey.isEmpty) {
        // 키 미설정: 더미 결과
        setState(() {
          _addressResults = ['${q} 1', '${q} 2', '${q} 3'];
        });
        return;
      }
      final uri = Uri.parse('https://dapi.kakao.com/v2/local/search/address.json?query=${Uri.encodeQueryComponent(q)}');
      final res = await http.get(uri, headers: {'Authorization': 'KakaoAK $kakaoRestApiKey'});
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        final docs = (data['documents'] as List?) ?? [];
        final items = docs.map((e) => e['address_name']?.toString() ?? '').where((s) => s.isNotEmpty).cast<String>().toList();
        setState(() {
          _addressResults = items;
        });
      } else {
        setState(() {
          _addressResults = [];
        });
      }
    } catch (_) {
      setState(() {
        _addressResults = [];
      });
    }
  }

  Future<void> _openAddressPostcodeWebview() async {
    // HTML 문자열 + baseUrl(https)로 로드하여 postMessage origin 문제 회피
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          final url = request.url;
          // 화이트리스트: daumcdn, postcode.daum, kakao 도메인만 허용
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
          Navigator.of(this.context, rootNavigator: true).pop();
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
          var payload = JSON.stringify({
            roadAddress: data.roadAddress || '',
            jibunAddress: data.jibunAddress || '',
            address: (data.roadAddress || data.address || ''),
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

    await controller.loadHtmlString(html, baseUrl: 'https://t1.daumcdn.net');

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final size = MediaQuery.of(context).size;
        final height = size.height * 0.85;
        return SizedBox(
          height: height,
          width: size.width,
          child: WebViewWidget(controller: controller),
        );
      },
    );
  }
}
