import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_version_info.dart';
import '../utils/version_compare.dart';

/// 업데이트 필요 정도.
enum UpdateSeverity {
  /// 최신 버전 이상 - 그대로 앱 진입
  none,

  /// 선택 업데이트 대상 - 안내 팝업(닫기 가능)
  optional,

  /// 강제 업데이트 대상 - 업데이트 전까지 앱 사용 불가
  forced,
}

/// 버전 체크 결과.
class VersionCheckResult {
  final UpdateSeverity severity;
  final AppVersionInfo? info;
  final String currentVersion;

  const VersionCheckResult({
    required this.severity,
    required this.info,
    required this.currentVersion,
  });

  bool get shouldShowDialog => severity != UpdateSeverity.none && info != null;
  bool get isForced => severity == UpdateSeverity.forced;
}

/// 앱 버전 체크 서비스.
///
/// Supabase `app_version` 테이블(단일 행, id=1)에서 최신 버전 정보를 조회합니다.
/// 서버 API 방식으로 교체하고 싶다면 [fetchLatestVersionInfo] 구현만 바꾸면 되고,
/// 나머지(비교/다이얼로그 노출 정책)는 그대로 재사용할 수 있도록 분리했습니다.
///
/// 추후 Android In-App Update(Play Core) API로 확장할 때도 이 서비스가 반환하는
/// [VersionCheckResult]를 그대로 활용해 flexible/immediate 업데이트 흐름을 트리거하면 됩니다.
class VersionService {
  static const _table = 'app_version';
  static const _prefsLastShownDateKey = 'update_dialog_last_shown_date';
  static const _prefsLastShownVersionKey = 'update_dialog_last_shown_version';

  final SupabaseClient _client = Supabase.instance.client;

  /// 서버(Supabase)에서 최신 버전 정보를 가져옵니다.
  /// 조회 실패(네트워크 오류, 테이블 없음 등) 시 null을 반환하며,
  /// 호출부는 이 경우 앱을 정상 진입시켜야 합니다.
  Future<AppVersionInfo?> fetchLatestVersionInfo() async {
    try {
      final row = await _client
          .from(_table)
          .select()
          .eq('id', 1)
          .maybeSingle()
          .timeout(const Duration(seconds: 6));

      if (row == null) {
        debugPrint('⚠️ [VersionService] app_version 테이블에 데이터가 없습니다. (정상 진입 처리)');
        return null;
      }
      return AppVersionInfo.fromJson(row);
    } catch (e) {
      debugPrint('⚠️ [VersionService] 버전 정보 조회 실패 (정상 진입 처리): $e');
      return null;
    }
  }

  /// 현재 설치된 앱 버전(예: "1.0.6")을 가져옵니다. 실패 시에도 크래시 없이 "0.0.0" 반환.
  Future<String> getCurrentVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return packageInfo.version;
    } catch (e) {
      debugPrint('⚠️ [VersionService] 현재 앱 버전 조회 실패: $e');
      return '0.0.0';
    }
  }

  /// 현재 버전과 서버 버전을 비교하여 업데이트 필요 여부를 판단합니다.
  ///
  /// - current < minimum_supported_version → 강제 업데이트
  /// - force_update == true 이고 current < latest_version → 강제 업데이트
  /// - current < latest_version → 선택 업데이트
  /// - 그 외 → 정상 진입
  Future<VersionCheckResult> checkForUpdate() async {
    final currentVersion = await getCurrentVersion();
    final info = await fetchLatestVersionInfo();

    if (info == null) {
      return VersionCheckResult(
        severity: UpdateSeverity.none,
        info: null,
        currentVersion: currentVersion,
      );
    }

    final belowMinimum =
        VersionCompare.isLessThan(currentVersion, info.minimumSupportedVersion);
    final belowLatest =
        VersionCompare.isLessThan(currentVersion, info.latestVersion);

    UpdateSeverity severity;
    if (belowMinimum || (info.forceUpdate && belowLatest)) {
      severity = UpdateSeverity.forced;
    } else if (belowLatest) {
      severity = UpdateSeverity.optional;
    } else {
      severity = UpdateSeverity.none;
    }

    debugPrint(
      '🔍 [VersionService] current=$currentVersion, latest=${info.latestVersion}, '
      'minimum=${info.minimumSupportedVersion}, forceFlag=${info.forceUpdate} '
      '=> $severity',
    );

    return VersionCheckResult(
      severity: severity,
      info: info,
      currentVersion: currentVersion,
    );
  }

  /// 선택 업데이트 팝업을 오늘 이미 (같은 latest_version 기준으로) 보여줬는지 확인합니다.
  Future<bool> wasOptionalPromptShownToday(String latestVersion) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastDate = prefs.getString(_prefsLastShownDateKey);
      final lastVersion = prefs.getString(_prefsLastShownVersionKey);
      return lastDate == _todayKey() && lastVersion == latestVersion;
    } catch (e) {
      debugPrint('⚠️ [VersionService] 팝업 노출 이력 조회 실패: $e');
      return false;
    }
  }

  /// 선택 업데이트 팝업을 오늘 보여줬다고 기록합니다 (하루 1회 노출 제한용).
  Future<void> markOptionalPromptShownToday(String latestVersion) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsLastShownDateKey, _todayKey());
      await prefs.setString(_prefsLastShownVersionKey, latestVersion);
    } catch (e) {
      debugPrint('⚠️ [VersionService] 팝업 노출 이력 저장 실패: $e');
    }
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}
