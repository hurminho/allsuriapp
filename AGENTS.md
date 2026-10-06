# 올수리 앱 (allsuriapp)

올수리 공사 견적·입찰 플랫폼의 Flutter 앱, 앱 API(Netlify Functions), DB 마이그레이션 저장소입니다. 공개 웹은 별도 저장소 `allsuri-web`이며 같은 Supabase를 씁니다. 웹 저장소는 이 폴더의 `allsuri-web` 심볼릭 링크(gitignore)로 엽니다. 자세한 관계는 `docs/ALLSURI_WEB.md`를 봅니다.

## 구조

| 경로 | 내용 |
|---|---|
| `lib/` | Flutter 앱 (provider, go_router, supabase_flutter, 카카오·애플 로그인, FCM) |
| `netlify/functions/` | 앱·웹이 부르는 API (`api.allsuri.app/api/*`, 라우팅은 `netlify.toml`) |
| `netlify/tests/` | Functions 단위 테스트 (vitest) |
| `database/*.sql` | Supabase 스키마·RLS 마이그레이션. 웹 전용은 `web_*.sql` |
| `backend/public/` | 레거시 정적 HTML·관리자 (Netlify publish 폴더). 새 기능은 `allsuri-web`에 만듭니다 |
| `test/`, `integration_test/` | Flutter 테스트 |

## 실행·확인

```bash
flutter pub get
flutter analyze
flutter test
npm test
npm run typecheck
flutter run --dart-define-from-file=dart_defines.json
```

- `dart_defines.json`(gitignore)이 앱 설정입니다. 형식은 `dart_defines.example.json`을 봅니다.
- `flutter analyze`는 기존 경고·정보가 많습니다. 새 코드에서 에러와 새 경고를 늘리지 않는 것을 기준으로 합니다.

## 배포

- `main`에 push하면 Netlify가 Functions와 `backend/public`을 운영에 바로 배포합니다.
- 스토어 배포는 자동이 아닙니다. `pubspec.yaml`의 `version`을 올리고 `build_aab.sh` / `build_ios.sh`로 빌드해 콘솔에 올립니다(`docs/APP_DEPLOYMENT_GUIDE.md`).

## 주의

- 공개 저장소입니다. 키·키스토어·`dart_defines*.json`·`.env`는 커밋하지 않습니다.
- 스키마 변경은 `database/`에 SQL 파일로 남기고, 운영 DB 적용 전에도 코드가 새 컬럼 없이 동작하게 만듭니다.
