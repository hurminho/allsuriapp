import 'package:flutter/material.dart';
import '../models/role.dart';
import '../widgets/business/business_tab_shell.dart';
import '../widgets/customer_dashboard.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends StatelessWidget {
  final UserRole userRole;

  const HomeScreen({
    Key? key,
    required this.userRole,
  }) : super(key: key);

  String get _getTitle {
    switch (userRole) {
      case UserRole.admin:
        return '관리자 대시보드';
      case UserRole.business:
        return '사업자 대시보드';
      case UserRole.customer:
        return '견적 요청 대시보드';
    }
  }

  Widget _buildDashboard() {
    switch (userRole) {
      case UserRole.admin:
        return const Center(child: Text('관리자 대시보드는 웹에서 접근하세요'));
      case UserRole.business:
        return const BusinessTabShell();
      case UserRole.customer:
        return const CustomerDashboard();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getTitle),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              // TODO: Implement profile view
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              context.go('/');
            },
          ),
        ],
      ),
      body: _buildDashboard(),
    );
  }
} 