import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';

/// 사업자 활동(오더 생성, 입찰, 견적, 공사 등록) 전 자격 점검.
///
/// 2026-06 정책: 사업자등록 진위확인 경고/안내 다이얼로그를 완전히 제거.
/// - 비로그인/비사업자 회원은 SnackBar 안내 후 차단
/// - 그 외(사업자 회원)는 사업자번호 등록 여부와 무관하게 모두 통과
///   (사업자번호 등록은 프로필 화면에서 사용자가 자율적으로 진행)
class BusinessVerifyGuard {
  /// 현재 사용자가 사업자 활동을 수행 가능한지 확인한다.
  /// 통과 가능하면 true, 차단되었으면 false를 반환한다.
  static Future<bool> ensure(BuildContext context, {String action = '이 작업'}) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final user = auth.currentUser;
    if (user == null) {
      _snack(context, '로그인이 필요합니다.');
      return false;
    }
    if (user.role != 'business') {
      _snack(context, '사업자 회원만 이용할 수 있습니다.');
      return false;
    }
    return true;
  }

  /// 인증 안내 다이얼로그만 노출 (액션 없이 안내 용도)
  /// 정책 변경으로 더 이상 다이얼로그를 띄우지 않는다 (no-op).
  static Future<void> showVerifyPrompt(BuildContext context) async {
    return;
  }

  static void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
