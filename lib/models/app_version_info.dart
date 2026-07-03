/// 서버(또는 Supabase)에서 내려오는 앱 최신 버전 정보.
///
/// 예시 JSON:
/// ```json
/// {
///   "latest_version": "1.4.2",
///   "minimum_supported_version": "1.3.0",
///   "force_update": false,
///   "android_store_url": "market://details?id=com.allsuri.app",
///   "ios_store_url": "itms-apps://itunes.apple.com/app/id123456789",
///   "update_message": "더 안정적인 사용을 위해 최신 버전으로 업데이트해 주세요."
/// }
/// ```
class AppVersionInfo {
  /// 스토어에 배포된 최신 버전 (예: "1.4.2")
  final String latestVersion;

  /// 이 버전 미만이면 무조건 강제 업데이트 대상 (예: "1.3.0")
  final String minimumSupportedVersion;

  /// true이면 최신 버전이 아닌 모든 사용자에게 강제 업데이트를 요구합니다.
  final bool forceUpdate;

  final String? androidStoreUrl;
  final String? iosStoreUrl;

  /// 업데이트 안내 문구 (서버에서 커스터마이즈 가능, 없으면 기본 문구 사용)
  final String? updateMessage;

  const AppVersionInfo({
    required this.latestVersion,
    required this.minimumSupportedVersion,
    this.forceUpdate = false,
    this.androidStoreUrl,
    this.iosStoreUrl,
    this.updateMessage,
  });

  /// 서버 응답이 일부 누락되거나 타입이 예상과 달라도 크래시 없이 안전하게 파싱합니다.
  factory AppVersionInfo.fromJson(Map<String, dynamic> json) {
    String parseString(dynamic value, String fallback) {
      final s = value?.toString().trim();
      return (s == null || s.isEmpty) ? fallback : s;
    }

    String? parseNullableString(dynamic value) {
      final s = value?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    bool parseBool(dynamic value) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final v = value.trim().toLowerCase();
        return v == 'true' || v == 't' || v == '1';
      }
      return false;
    }

    return AppVersionInfo(
      latestVersion: parseString(json['latest_version'], '0.0.0'),
      minimumSupportedVersion:
          parseString(json['minimum_supported_version'], '0.0.0'),
      forceUpdate: parseBool(json['force_update']),
      androidStoreUrl: parseNullableString(json['android_store_url']),
      iosStoreUrl: parseNullableString(json['ios_store_url']),
      updateMessage: parseNullableString(json['update_message']),
    );
  }

  Map<String, dynamic> toJson() => {
        'latest_version': latestVersion,
        'minimum_supported_version': minimumSupportedVersion,
        'force_update': forceUpdate,
        'android_store_url': androidStoreUrl,
        'ios_store_url': iosStoreUrl,
        'update_message': updateMessage,
      };

  @override
  String toString() => 'AppVersionInfo(${toJson()})';
}
