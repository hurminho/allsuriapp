import 'package:flutter/material.dart';

import '../../widgets/business/business_app_shell.dart';
import '../../widgets/business/business_tokens.dart';
import 'job_management_screen.dart';
import 'my_estimates_screen.dart';

/// 입찰부터 완료까지 한 화면에서 보는 공사 관리 허브.
class WorkHubScreen extends StatelessWidget {
  final int initialTab;

  const WorkHubScreen({super.key, this.initialTab = 0});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: initialTab.clamp(0, 2),
      child: BusinessAppShell(
        title: '공사 관리',
        appBarBottom: const TabBar(
          labelColor: BusinessTokens.blue,
          unselectedLabelColor: BusinessTokens.mutedText,
          indicatorColor: BusinessTokens.blue,
          labelStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          tabs: [
            Tab(text: '내 입찰'),
            Tab(text: '진행 중'),
            Tab(text: '완료'),
          ],
        ),
        body: const TabBarView(
          children: [
            BusinessMyEstimatesScreen(embedded: true),
            JobManagementScreen(
              embedded: true,
              hideFilters: true,
              initialFilter: 'in_progress',
            ),
            JobManagementScreen(
              embedded: true,
              hideFilters: true,
              initialFilter: 'completed',
            ),
          ],
        ),
      ),
    );
  }
}
