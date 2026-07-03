import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';

import '../app_navigator_key.dart';

/// Google Play In-App Update(Play Core) 연동 서비스.
///
/// Android + Google Play를 통해 설치된 앱에서만 정상 동작합니다.
/// iOS, 사이드로드 APK, `flutter run` 디버그 설치, 아직 심사/배포되지 않은 빌드 등에서는
/// Play 쪽에서 "업데이트 없음"으로 응답하거나 예외가 발생하므로,
/// 이 서비스의 모든 메서드는 그런 경우 안전하게 false를 반환합니다.
/// 호출부(위젯)는 false를 받으면 기존 스토어 링크 이동(url_launcher) 방식으로 폴백해야 합니다.
///
/// ⚠️ 로컬에서는 테스트할 수 없습니다. Google Play 콘솔의 내부 테스트(Internal Testing) 트랙에
/// 배포한 뒤, 이미 구버전이 설치된 기기에서 새 빌드를 심사 완료 상태로 올려야 확인할 수 있습니다.
/// 참고: https://developer.android.com/guide/playcore/in-app-updates
class AndroidInAppUpdateService {
  AndroidInAppUpdateService._();

  static final AndroidInAppUpdateService instance =
      AndroidInAppUpdateService._();

  StreamSubscription<InstallStatus>? _installSub;
  bool _listenerAttached = false;

  bool get _isSupportedPlatform => !kIsWeb && Platform.isAndroid;

  /// 강제 업데이트: 전체 화면 즉시 업데이트(Immediate Update)를 시도합니다.
  ///
  /// 반환값이 true면 네이티브 업데이트 플로우가 성공적으로 완료된 것입니다
  /// (일반적으로 이 시점에 앱이 이미 재시작되어 이 코드로 다시 돌아오지 않습니다).
  /// false면 (API 미지원 / 배포된 최신 버전 없음 / 사용자 취소 / 오류) 호출부가
  /// 기존 커스텀 다이얼로그+스토어 링크로 폴백해야 합니다.
  Future<bool> tryImmediateUpdate() async {
    if (!_isSupportedPlatform) return false;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        debugPrint('ℹ️ [InAppUpdate] Play가 인지한 업데이트가 없어 스토어 링크로 폴백합니다.');
        return false;
      }
      if (!info.immediateUpdateAllowed) {
        debugPrint('ℹ️ [InAppUpdate] 즉시 업데이트가 허용되지 않아 스토어 링크로 폴백합니다.');
        return false;
      }

      final result = await InAppUpdate.performImmediateUpdate();
      if (result == AppUpdateResult.success) return true;

      debugPrint('ℹ️ [InAppUpdate] 사용자가 즉시 업데이트를 취소했습니다 ($result).');
      return false;
    } catch (e) {
      debugPrint('⚠️ [InAppUpdate] 즉시 업데이트 실패 - 스토어 링크로 폴백: $e');
      return false;
    }
  }

  /// 선택 업데이트: 백그라운드 다운로드(Flexible Update)를 시도합니다.
  ///
  /// 다운로드가 시작되면 true를 반환합니다(설치는 비동기로 진행되며, 완료 시
  /// [_attachInstallListener]가 재시작 안내 스낵바를 띄웁니다).
  /// false면 호출부가 스토어 링크로 폴백해야 합니다.
  Future<bool> tryFlexibleUpdate(BuildContext context) async {
    if (!_isSupportedPlatform) return false;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        debugPrint('ℹ️ [InAppUpdate] Play가 인지한 업데이트가 없어 스토어 링크로 폴백합니다.');
        return false;
      }
      if (!info.flexibleUpdateAllowed) {
        debugPrint('ℹ️ [InAppUpdate] 유연한 업데이트가 허용되지 않아 스토어 링크로 폴백합니다.');
        return false;
      }

      _attachInstallListener();

      final result = await InAppUpdate.startFlexibleUpdate();
      if (result == AppUpdateResult.success) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('새 버전을 다운로드하고 있어요. 완료되면 알려드릴게요.')),
          );
        }
        return true;
      }

      debugPrint('ℹ️ [InAppUpdate] 사용자가 다운로드를 취소했습니다 ($result).');
      return false;
    } catch (e) {
      debugPrint('⚠️ [InAppUpdate] 유연한 업데이트 실패 - 스토어 링크로 폴백: $e');
      return false;
    }
  }

  /// 다운로드 완료(InstallStatus.downloaded) 시 재시작을 안내하는 스낵바를 띄웁니다.
  /// 앱 어느 화면으로 이동해 있어도 동작하도록 전역 [navigatorKey](main.dart에서 사용 중인 것과 동일)를 사용합니다.
  void _attachInstallListener() {
    if (_listenerAttached) return;
    _listenerAttached = true;
    _installSub = InAppUpdate.installUpdateListener.listen((status) {
      debugPrint('ℹ️ [InAppUpdate] 설치 상태 변경: $status');
      if (status == InstallStatus.downloaded) {
        final context = navigatorKey.currentContext;
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('업데이트 다운로드가 완료되었습니다. 지금 재시작할까요?'),
              action: SnackBarAction(
                label: '재시작',
                onPressed: () => InAppUpdate.completeFlexibleUpdate(),
              ),
              duration: const Duration(seconds: 10),
            ),
          );
        }
      }
    });
  }

  /// 앱 종료 시(테스트 등) 리스너를 정리합니다.
  void dispose() {
    _installSub?.cancel();
    _installSub = null;
    _listenerAttached = false;
  }
}
