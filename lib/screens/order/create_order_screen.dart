import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/order.dart' as app_models;
import '../../services/auth_service.dart';
import '../../providers/order_provider.dart';
import '../home/home_screen.dart';

class CreateOrderScreen extends StatefulWidget {
  const CreateOrderScreen({super.key});

  @override
  State<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends State<CreateOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _equipmentTypeController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _addressController = TextEditingController();
  final _visitDateController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _equipmentTypeController.dispose();
    _descriptionController.dispose();
    _addressController.dispose();
    _visitDateController.dispose();
    super.dispose();
  }

  Future<void> _submitOrder() async {
    // 직접 값 검증
    if (_equipmentTypeController.text.trim().isEmpty) {
      _showError('장비 유형을 입력해주세요');
      return;
    }
    if (_descriptionController.text.trim().isEmpty) {
      _showError('문제 설명을 입력해주세요');
      return;
    }
    if (_addressController.text.trim().isEmpty) {
      _showError('주소를 입력해주세요');
      return;
    }
    if (_visitDateController.text.trim().isEmpty) {
      _showError('방문 희망일을 입력해주세요');
      return;
    }
    try {
      DateTime.parse(_visitDateController.text.trim());
    } catch (e) {
      _showError('올바른 날짜 형식을 입력해주세요 (YYYY-MM-DD)');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final orderProvider = Provider.of<OrderProvider>(context, listen: false);
      
      final user = authService.currentUser;
      if (user == null) {
        throw Exception('사용자 정보를 찾을 수 없습니다.');
      }

      final order = app_models.Order(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        customerId: user.id,
        title: _equipmentTypeController.text.trim(),
        description: _descriptionController.text.trim(),
        address: _addressController.text.trim(),
        visitDate: DateTime.parse(_visitDateController.text),
        status: app_models.Order.STATUS_PENDING,
        createdAt: DateTime.now(),
        category: _equipmentTypeController.text.trim(),
        customerName: user.name,
        customerPhone: user.phoneNumber ?? '',
      );

      await orderProvider.addOrder(order);
      
      if (mounted) {
        showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('견적 요청 완료'),
            content: const Text('견적 요청이 성공적으로 제출되었습니다!'),
            actions: [
              CupertinoDialogAction(
                onPressed: () {
                  Navigator.pop(context); // 다이얼로그 닫기
                  Navigator.pushAndRemoveUntil(
                    context,
                    CupertinoPageRoute(
                      builder: (context) => const HomeScreen(),
                    ),
                    (route) => false,
                  );
                },
                child: const Text('확인'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('오류'),
            content: Text('견적 요청 제출 중 오류가 발생했습니다: $e'),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context),
                child: const Text('확인'),
              ),
            ],
          ),
        );
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
        title: const Text('입력 오류'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('견적 요청')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '견적 요청 정보',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: CupertinoColors.label,
                  ),
                ),
                const SizedBox(height: 24),
                CupertinoTextField(
                  controller: _equipmentTypeController,
                  placeholder: '예: 에어컨, 냉장고, 세탁기',
                  decoration: BoxDecoration(
                    border: Border.all(color: CupertinoColors.separator),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 16),
                CupertinoTextField(
                  controller: _descriptionController,
                  placeholder: '어떤 문제가 있는지 자세히 설명해주세요',
                  decoration: BoxDecoration(
                    border: Border.all(color: CupertinoColors.separator),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                CupertinoTextField(
                  controller: _addressController,
                  placeholder: '방문할 주소를 입력해주세요',
                  decoration: BoxDecoration(
                    border: Border.all(color: CupertinoColors.separator),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 16),
                CupertinoTextField(
                  controller: _visitDateController,
                  placeholder: 'YYYY-MM-DD',
                  decoration: BoxDecoration(
                    border: Border.all(color: CupertinoColors.separator),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton.filled(
                    onPressed: _isSubmitting ? null : _submitOrder,
                    child: _isSubmitting
                        ? const CupertinoActivityIndicator()
                        : const Text(
                            '견적 요청 제출',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
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
