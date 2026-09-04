import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../screens/home/home_screen.dart';
import 'package:allsuriapp/utils/app_logger.dart';
class NavigationUtils {
  static void navigateToRoleHome(BuildContext context) {
    final auth = Provider.of<AuthService>(context, listen: false);

    // 사용자 객체 전체를 찍으면 이름·전화번호·이메일이 로그에 남습니다.
    // 분기 판단에 필요한 값만 남깁니다.
    AppLog.debug(
      'NavigationUtils',
      'isAuthenticated=${auth.isAuthenticated} '
          'role=${auth.currentUser?.role} '
          'uid=${AppLog.shortId(auth.currentUser?.id)}',
    );

    // HomeScreen이 로그인 시 사업자 온보딩/대시보드로 분기함
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }
}


