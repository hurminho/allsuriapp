/// 앱 런타임 설정.
///
/// `--dart-define-from-file=dart_defines.json` 이 있으면 그 값을 쓰고,
/// Xcode Archive / TestFlight처럼 dart-define이 빠지면 프로덕션 기본값을 사용합니다.
/// (Supabase anon key는 클라이언트에 넣는 공개 키입니다.)
class AppConfig {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://iiunvogtqssxaxdnhqaj.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlpdW52b2d0cXNzeGF4ZG5ocWFqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTQ5NTUzMTksImV4cCI6MjA3MDUzMTMxOX0.PjA01VwTmJwEGEYTc-g1UOR7FkeGTeN7smIQXyusKP8',
  );

  /// Info.plist URL scheme `kakao{key}` 와 동일해야 합니다.
  static const String kakaoNativeAppKey = String.fromEnvironment(
    'KAKAO_NATIVE_APP_KEY',
    defaultValue: '9462c73fdeaba67181aadcc46af6d293',
  );

  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static bool get hasKakao => kakaoNativeAppKey.isNotEmpty;
}
