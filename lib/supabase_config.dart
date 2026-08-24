/// Supabase 연결 정보.
///
/// `flutter run` 만 실행하면 값이 비어 **호스트 없음** 오류가 납니다
/// (`No host specified in URI /auth/v1/token`, `/rest/v1/...`).
///
/// 반드시 빌드/실행 시 주입:
/// `flutter run --dart-define-from-file=dart_defines.json`
/// 또는 `./run_app.sh` / `./run_release.sh`
///
/// `dart_defines.json` 은 .gitignore — `example_dart_defines.json` 을 복사해 채우면 됩니다.
/// dart-define이 비어도 [AppConfig] 프로덕션 기본값으로 연결됩니다.
import 'config.dart';

class SupabaseConfig {
  static const String url = AppConfig.supabaseUrl;
  static const String anonKey = AppConfig.supabaseAnonKey;
}


