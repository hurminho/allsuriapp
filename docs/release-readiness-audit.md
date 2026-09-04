# 올수리 앱 릴리즈 준비 감사

| 항목 | 값 |
|---|---|
| 감사일 | 2026-09-04 |
| 앱 버전 | `1.0.13+70` (`pubspec.yaml`) |
| Flutter | 3.38.6 stable |
| 대상 | `lib/` (155 Dart 파일), `android/`, `ios/`, `netlify/` |
| 감사 범위 제외 | `E-commerce-Complete-Flutter-UI-master/` (미사용 벤더 템플릿) |

이 문서는 **현재 상태 기록**입니다. 이번 작업에서 실제로 수정한 항목은
[수정 완료](#9-수정-완료-이슈)에, 남은 항목은 [미해결](#10-미해결-이슈)에 정리했습니다.

---

## 1. 앱 구조와 주요 모듈

```
lib/
├── main.dart                 앱 진입점, Provider 등록, 전역 오류 훅
├── config.dart               dart-define 기반 런타임 설정
├── supabase_config.dart      Supabase URL/anon key
├── app_navigator_key.dart    전역 navigatorKey (FCM·딥링크용)
├── firebase_options.dart     Firebase 설정
├── screens/   (56)  화면. business(23) customer(5) auth(3) admin(3)
│                    community(3) profile(2) + home/chat/notification 등
├── widgets/   (36)  재사용 UI. widgets/business(17) 포함
├── services/  (27)  데이터·API·인증·알림 계층
├── models/    (18)  데이터 클래스
├── utils/     (8)   딥링크, 내비게이션, 가드, 로깅, 오류 매핑
├── providers/ (4)   ChangeNotifier
├── config/    (2)   상수, 피처 플래그
└── theme/     (1)   business_theme.dart
```

핵심 모듈 4개:

| 모듈 | 파일 | 역할 |
|---|---|---|
| API 계층 | `lib/services/api_service.dart` | Netlify `/api/*` REST 호출. 모든 입찰·가격 트래픽이 통과 |
| 인증 | `lib/services/auth_service.dart` | Supabase Auth + Apple/Kakao 로그인 |
| 마켓 | `lib/services/marketplace_service.dart` | 일감 목록(Supabase 읽기) + 입찰(Netlify 쓰기) |
| 가격 엔진 클라이언트 | `lib/services/price_service.dart` | `/api/price/*`. 앱은 금액을 계산하지 않음 |

---

## 2. 상태관리 방식

**Provider(ChangeNotifier) + 화면별 `setState` 혼용**입니다. Riverpod·Bloc은 없습니다.

`main.dart:170–188` `MultiProvider` 에 등록된 것:

`AuthService`, `ApiService`, `OrderService`, `EstimateService`, `JobService`,
`PaymentService`, `ChatService`, `CommunityService`, `UserProvider`
(`ChangeNotifierProxyProvider<AuthService, UserProvider>`)

### 확인된 불일치

| 문제 | 위치 | 심각도 |
|---|---|---|
| `EstimateProvider`·`OrderProvider` 를 `Provider.of` 로 읽지만 트리에 등록되지 않음 | `screens/order/create_order_screen.dart:62`, `screens/business/transferred_estimates_screen.dart:55` | P1 (해당 화면 진입 시 ProviderNotFound) |
| 서비스가 데이터 계층과 전역 상태를 겸함 (7개) | `main.dart:173–181` | P3 |
| `MarketplaceService` 는 `ChangeNotifier` 인데 화면마다 지역 인스턴스 생성 | `order_marketplace_screen.dart:47` | P3 |
| `AnonymousProvider` 미사용 | `providers/anonymous_provider.dart` | P3 |
| `AuthWrapper` 클래스 2개, `HomeScreen` 클래스 2개 (하나는 레거시) | `main.dart:208`, `widgets/auth_wrapper.dart:7` / `screens/home/home_screen.dart:20`, `screens/home_screen.dart:7` | P3 |

`transferred_estimates_screen` 과 `create_order_screen` 중 전자는 **참조하는 곳이 없어
현재 도달 불가**(dead code)이고, `create_order_screen` 은 `OrderProvider` 를 62행에서
읽습니다. 이 화면의 실제 도달 경로를 확인해야 합니다 → [미해결 P1-3](#10-미해결-이슈).

---

## 3. 라우팅 구조

**중앙 라우트 테이블이 없습니다.** `MaterialApp` 에 `routes` / `onGenerateRoute` /
`routerConfig` 가 모두 없고(`main.dart:193–201`), 전부 명령형
`Navigator.push(MaterialPageRoute(...))` 입니다.

```
SplashScreen (home)
  └─ pushReplacement → HomeScreen (screens/home/home_screen.dart)
       ├─ 비로그인        → 온보딩 + 로그인 바  ← 로그인 없이 견적 요청 가능
       ├─ 로그인·승인     → BusinessTabShell (IndexedStack 5탭)
       └─ 로그인·승인대기 → BusinessPendingScreen / BusinessProfileScreen
```

`BusinessTabShell` 탭: `ProfessionalDashboard` · `WorkHubScreen` ·
`CreateJobScreen` · `ChatListPage` · `ProfileScreen`
(`widgets/business/business_tab_shell.dart:61–68`)

### `go_router` 미설정 — 이번 감사의 최대 발견

`pubspec.yaml` 에 `go_router: ^17.0.0` 이 있고 8개 파일이 import 하지만,
**`GoRouter(...)` 인스턴스가 코드베이스에 단 한 곳도 없습니다.** 라우터 조상이
없는 상태에서 `context.go/push/pop` 을 호출하면 예외가 발생합니다.

| 호출 위치 | 도달 가능? | 심각도 |
|---|---|---|
| `screens/business/business_profile_screen.dart:233` `context.pop()` | **예** — `home_screen`·`profile_screen` 에서 진입 | **P1 → 수정 완료** |
| `widgets/login_required_dialog.dart:85,170–176` | 아니오 (import 하는 곳 없음) | P3 |
| `widgets/auth_wrapper.dart:22–31` | 아니오 | P3 |
| `screens/business/transferred_estimates_screen.dart:240` | 아니오 | P3 |
| `screens/business/select_estimate_for_transfer_screen.dart:185` | 아니오 | P3 |
| `screens/home_screen.dart:53` (레거시) | 아니오 | P3 |
| `screens/customer/create_request_screen.dart`, `screens/admin/estimate_dashboard_screen.dart` | 미사용 import 뿐 | P3 |

### 딥링크 / 알림 진입

| 경로 | 처리 | 비고 |
|---|---|---|
| `allsuri://order/...`, `https://api.allsuri.app/order/...` | `utils/app_deep_links.dart:52–56` → `OrderMarketplaceScreen` | **추출한 `orderId` 를 화면에 넘기지 않음** (P2) |
| FCM 탭 | `services/fcm_service.dart:234–287` | `chat_message`→`ChatScreen`, `bid_selected`→`JobManagementScreen`, `new_order`→**이동 없음** |
| 로컬 알림 탭 | `main.dart:92–95` | **`// TODO` — 아무 화면으로도 이동하지 않음** (P2) |
| 인앱 알림함 | `screens/notification/notification_screen.dart:674–814` | 타입별 분기 구현됨 |

---

## 4. 핵심 플로우

### 견적 요청 (고객, 로그인 불필요)

```
CreateRequestScreen
  └─ 비로그인이면 SharedPreferences 의 allsuri_session_id 로 주문 귀속
       (customer/my_estimates_screen.dart:85–92 에서 같은 키로 조회)
  └─ OrderService.createOrder() → Supabase orders
```
로그인 없는 견적 요청 정책은 **유지되고 있습니다.**

### AI 견적

앱 안에 OpenAI 직접 호출은 `screens/labs/ai_assistant_screen.dart:311` 한 곳뿐이고,
`labs` 는 실험 화면입니다. **OpenAI 키는 앱에 없습니다** (§6 확인).
고객용 AI 구조화는 웹(`allsuri-web`)과 서버가 담당합니다.

### 가격 엔진

`PriceService` → `/api/price/estimate`. 앱은 서버 `uiCopy` 를 그대로 렌더링하고
금액을 만들지 않습니다. 3상태(충분/일부/부족)는 `widgets/business/price_estimate_card.dart`
에서 분기하며, 부족 상태에서는 숫자를 그리지 않습니다(자동 테스트로 고정).

### 사업자 입찰

```
OrderMarketplaceScreen ─ claimListing ─┐
CreateEstimateScreen ──────────────────┴→ POST /market/listings/{id}/bid
                                            (BidBreakdown 세부 원가 포함)
OrderBiddersScreen ─ _selectBidder → POST select-bidder
                                       → 채팅방 생성 + 타 지원 미선정 + 알림
JobManagementScreen ─ CompletionAmountSheet → POST /price/completed-jobs
```

### 내 견적

- 사업자: `screens/business/my_estimates_screen.dart` (`/market/bids?bidderId=`)
- 고객: `screens/customer/my_estimates_screen.dart` (전화번호 또는 세션ID 매칭)

---

## 5. 외부 API 목록

| 대상 | 클라이언트 | 위치 | 앱에 비밀값? |
|---|---|---|---|
| Netlify Functions `/api/*` | `http` | `services/api_service.dart` | 아니오 (Supabase 세션 JWT 사용) |
| Supabase (DB·Auth·Storage·Realtime) | `supabase_flutter` | 20+ 서비스 | anon key (공개 키, 정상) |
| Firebase Messaging (FCM) | `firebase_messaging` | `services/fcm_service.dart` | `google-services.json` / `GoogleService-Info.plist` (공개 설정) |
| Kakao 로그인·공유 | Kakao SDK | `auth_service.dart`, `kakao_share_service.dart` | native app key (공개 키, 정상) |
| 사업자등록 진위확인 | `http` | `services/business_verify_service.dart` | 서버 경유 |
| Google Play In-App Update | `in_app_update` | `services/android_in_app_update_service.dart` | — |
| **OpenAI** | — | **서버(Netlify)에서만** | **아니오** |
| **Solapi (문자·알림톡)** | — | **서버(Netlify)에서만** | **아니오** |

결제(PG)는 미연동입니다. `services/payment_service.dart` 는 수수료 **알림만** 보내는
스텁이며 실제 과금이 없습니다 → [결정 필요 항목](#11-운영-배포-전-결정-필요-항목).

---

## 6. 환경 변수·비밀값 관리

`String.fromEnvironment` + `--dart-define-from-file=dart_defines.json` 방식이고,
dart-define 이 빠지는 Xcode Archive 를 대비해 프로덕션 기본값이 하드코딩돼 있습니다.

| 값 | 기본값 위치 | 판정 |
|---|---|---|
| `API_BASE_URL` | `api_service.dart:10` → `https://api.allsuri.app/api` | 정상 (https, localhost 아님 — 자동 테스트로 고정) |
| `SUPABASE_URL` / `SUPABASE_ANON_KEY` | `config.dart:7–18` | 정상 (anon key 는 클라이언트 공개 키) |
| `KAKAO_NATIVE_APP_KEY` | `config.dart:20` | 정상 (공개 키, Info.plist URL scheme 과 일치) |

### 비밀값 유출 점검 결과

- `lib/` 전체에 `service_role`, `SUPABASE_SERVICE_*`, `sk-*`, `OPENAI_API_KEY`,
  `SOLAPI_API_SECRET` **없음** (주석 1건 제외).
- `android/key.properties` 는 `android/.gitignore:11` 로 **git 추적 안 됨**. 정상.
- `google-services.json` / `GoogleService-Info.plist` 는 추적되지만 공개 설정 파일이라 정상.

---

## 7. 현재 테스트 코드 유무

| 구분 | 감사 전 | 감사 후 |
|---|---|---|
| Flutter 테스트 | 8파일 / **57 통과** | 14파일 / **167 통과** |
| 백엔드 (vitest) | 5파일 / 127 통과 | 5파일 / **127 통과** (변경 없음) |
| Integration 테스트 | **없음** | 가짜 API 서버 기반 14건 추가 |
| `integration_test/` (기기 실행) | 없음 | 없음 → [미해결](#10-미해결-이슈) |

감사 전에는 오류 처리·타임아웃·개인정보 마스킹·중복 제출에 대한 테스트가
**전혀 없었습니다.** 추가한 테스트는 `docs/test-matrix.md` 참조.

---

## 8. 빌드·배포 설정

### Android

| 항목 | 값 | 판정 |
|---|---|---|
| applicationId | `com.ononcompany.allsuri` | — |
| 앱 이름 | `올수리` | 정상 |
| minSdk / targetSdk | `flutter.minSdkVersion` / `flutter.targetSdkVersion` | Flutter 기본값 위임 |
| release 서명 | 로컬 `key.properties` 또는 CI 비밀 환경변수 사용. 설정·keystore 누락 시 릴리즈 빌드 즉시 실패 | 정상 (`build.gradle`). 관리 절차는 `docs/android-signing.md` |
| `minifyEnabled` / `shrinkResources` | `true` / `true` | 정상 — 실제 사용되는 `build.gradle` 기준 |
| 권한 | INTERNET, ACCESS_NETWORK_STATE, CAMERA, READ_EXTERNAL_STORAGE, READ_MEDIA_IMAGES, READ_MEDIA_VIDEO, POST_NOTIFICATIONS, VIBRATE, WAKE_LOCK | 과다 권한 없음. 정상 |
| 딥링크 | `allsuri://order`, `https://api.allsuri.app/order` (`autoVerify="true"`) | **assetlinks.json 확인 필요** (P2) |

### iOS

| 항목 | 값 | 판정 |
|---|---|---|
| Bundle ID | `com.allsuri.app` | **Android(`com.ononcompany.allsuri`)와 다름** — 의도 확인 필요 (P2) |
| 표시 이름 | `올수리` | 정상 |
| 버전 | `$(FLUTTER_BUILD_NAME)` / `$(FLUTTER_BUILD_NUMBER)` | 정상 (pubspec 연동) |
| 권한 문구 | 카메라·사진보관함·사진저장·알림 4종 모두 한국어로 구체적 기술 | **정상** |
| URL scheme | `allsuri`, `kakao9462c...` | 정상 |
| Associated Domains | **없음** | **iOS 에서 `https://` 유니버설 링크 동작 안 함** (P2) |

권한 문구는 심사 통과에 충분한 수준입니다. 예:
`NSCameraUsageDescription = "프로필 사진 및 첨부 사진을 촬영하기 위해 카메라 접근이 필요합니다."`

### 정적 분석

`flutter analyze` 가 감사 전 **526개 error** 를 뱉었는데 **전부 미사용 벤더 템플릿**
(`E-commerce-Complete-Flutter-UI-master/`)에서 나온 것이었습니다. 앱은 이 디렉터리를
참조하지 않습니다. 실제 error 는 **0개**였지만, 노이즈에 묻혀 게이트로 쓸 수
없었습니다 → `analysis_options.yaml` 에서 제외 처리(수정 완료).

---

## 9. 크래시 가능성이 높은 비동기 처리 위치

`await` 이후 `mounted` 확인 없이 `setState` / `Navigator` / `ScaffoldMessenger`
를 호출하는 지점 **약 35곳 / 18파일**. 화면을 빠르게 벗어나면 예외가 납니다.

| 위치 | 패턴 | 심각도 |
|---|---|---|
| `screens/customer/my_estimates_screen.dart:99–101` | `finally { setState(...) }` 에 가드 없음 | P1 → **수정 완료** |
| `screens/business/rate_card_screen.dart:34–37` | `_loading=true` 후 예외 시 `finally` 없음 → **스피너 영구 회전** | P1 → **수정 완료** |
| `screens/business/estimate_requests_screen.dart:57–66` | 로드 후 `setState` 가드 없음 | P2 |
| `screens/notification/notification_screen.dart:57–73` | `setState` 3곳 가드 없음 | P2 |
| `screens/community/community_board_screen.dart:35–38`, `post_detail_screen.dart:35–40` | 동일 | P2 |
| `screens/login_screen.dart:114,135`, `auth/signup_page.dart:53–55` | `finally` 가드 없음 | P2 |
| `screens/labs/ai_assistant_screen.dart:319–341` | `http.post` 후 다중 `setState` | P2 |

`await` 뒤 `BuildContext` 사용은 `flutter analyze` 기준 **58건**입니다.
이번에 `use_build_context_synchronously` 를 info → warning 으로 올려 가시화했습니다.

### 타임아웃 (감사 전)

`ApiService` 의 GET/POST/PUT/DELETE/업로드 **전부 타임아웃이 없었습니다.**
입찰 제출·내 견적 조회·가격 조회 6개 엔드포인트가 모두 이 경로를 씁니다.
네트워크가 응답하지 않으면 스피너가 무한히 돌았습니다. → **수정 완료**

---

## 10. 중복 요청 · null 처리 · 생명주기 위험 구간

### 중복 제출

| 플로우 | 감사 전 | 결과 |
|---|---|---|
| 고객 견적 채택 `customer/my_estimates_screen.dart:709` | 가드 없음 → 이중 탭 시 **주문 갱신·낙찰·B2C 수수료 알림이 2회** | **P0 → 수정 완료** |
| 사업자 배정 `order_bidders_screen.dart:_selectBidder` | 가드 없음 → **채팅방·알림 중복 생성** 가능 | **P0 → 수정 완료** |
| 견적 수정 다이얼로그 `estimate_management_screen.dart:1437` | 저장 중 버튼 활성 | P1 → **수정 완료** |
| 입찰 제출 `create_estimate_screen.dart` | `_isSubmitting` 있음 (진입 가드는 없었음) | 보강 완료 |
| 입찰/취소 `order_marketplace_screen.dart` | `_isClaiming` / `_isCancelling` + `finally` | 양호 |
| 오더 생성 `create_job_screen.dart` | `_submitting` / `_creatingOrder` | 양호 |

### null / 파싱

| 위치 | 위험 | 결과 |
|---|---|---|
| `create_estimate_screen.dart:300–301` | `double.parse`/`int.parse` 로 사용자 입력 파싱 → "10만원" 입력 시 FormatException 문구 노출 | **P1 → 수정 완료** |
| `estimate_management_screen.dart:1440–1442` | 동일 | **P1 → 수정 완료** |
| `services/estimate_service.dart:291,331` | `firstWhere` 로 stale 목록 조회 → StateError | P2 |
| `estimate_management_screen.dart:731,740` | `estimate.mediaUrls!` 강제 언랩 | P2 |
| `order_marketplace_screen.dart:261–264` | `as Map<String,String>` / `as Set<String>` 캐스트 | P2 |
| `business/pending_approval_screen.dart:130` | `user!.phoneNumber!` 이중 강제 언랩 | P2 |

### 로그 / 개인정보 (감사 전)

`print(` **569회**, `debugPrint(` **228회** = 797회. `print` 는 **릴리즈 빌드에서도
그대로 실행**됩니다. 이 중 개인정보·비밀값이 섞인 곳:

| 위치 | 유출 대상 | 결과 |
|---|---|---|
| `services/api_service.dart:90` | **모든 POST 응답 본문 전체** (주문·입찰·고객 정보) | **P0 → 수정 완료** |
| `services/order_service.dart:75` | 고객 이름 + **전화번호** | **P0 → 수정 완료** |
| `screens/customer/create_request_screen.dart:147,156` | 고객 이름 + **정규화 전화번호** | **P0 → 수정 완료** |
| `services/auth_service.dart:303,307,322` | 로그인 응답 전문 + **user 객체 전체** | **P0 → 수정 완료** |
| `services/fcm_service.dart:73,91` | **FCM 토큰 전문** | **P0 → 수정 완료** |
| `services/media_service.dart:148` | **액세스 토큰 앞 20자** | **P0 → 수정 완료** |
| `utils/navigation_utils.dart:11–12` | `currentUser` 객체 전체 | **P0 → 수정 완료** |
| `screens/notification/notification_screen.dart:54`, `services/notification_service.dart:56,76` | 알림 레코드 전문 (주소 포함 가능) | **P0 → 수정 완료** |

나머지 `print` 약 750건은 개인정보를 담지 않는 진행 로그이지만 릴리즈에서
실행되므로 P2 로 남겨 두었습니다 → [미해결](#10-미해결-이슈).

---

## 11. 플랫폼별 iOS · Android 차이

| 항목 | iOS | Android | 위험 |
|---|---|---|---|
| Bundle ID / applicationId | `com.allsuri.app` | `com.ononcompany.allsuri` | P2 — 의도 확인 필요 |
| `https://` 딥링크 | Associated Domains 없음 → **동작 안 함** | `autoVerify="true"` 선언 | P2 — 플랫폼 간 동작 불일치 |
| 커스텀 스킴 `allsuri://` | 선언됨 | 선언됨 | 정상 |
| 포그라운드 알림 | `setForegroundNotificationPresentationOptions(alert:false)` 로 시스템 배너 끄고 로컬 알림만 표시 (중복 표시 방지) | 기본 동작 | 정상 — iOS 이중 알림 대응 완료 |
| 인앱 업데이트 | `VersionService` + 스토어 이동 | `in_app_update` (Play Core) | 정상 |
| 배지 | `_BadgeLifecycleObserver` (`!kIsWeb`) | 동일 | 정상 |
| 알림 권한 | `NSUserNotificationsUsageDescription` | `POST_NOTIFICATIONS` (Android 13+) | 정상 |
| 코드 축소 | Xcode 기본 | `isMinifyEnabled=false` | P3 |

---

## 12. 심각도별 이슈 목록

### P0 — 앱 크래시 / 개인정보 노출 / 견적 유실 / 중복 발송

| ID | 이슈 | 상태 |
|---|---|---|
| P0-1 | `ApiService` 가 모든 POST 응답 본문을 릴리즈 로그에 출력 | ✅ 수정 |
| P0-2 | 고객 이름·전화번호를 릴리즈 로그에 출력 (3개 파일) | ✅ 수정 |
| P0-3 | 로그인 응답·`user` 객체 전체를 릴리즈 로그에 출력 | ✅ 수정 |
| P0-4 | FCM 토큰·Supabase 액세스 토큰을 릴리즈 로그에 출력 | ✅ 수정 |
| P0-5 | 알림 레코드(주소 포함 가능) 전문을 릴리즈 로그에 출력 | ✅ 수정 |
| P0-6 | 고객 견적 채택 이중 탭 → 낙찰·수수료 알림 **중복 발송** | ✅ 수정 |
| P0-7 | 사업자 배정 이중 탭 → 채팅방·알림 **중복 생성** | ✅ 수정 |

### P1 — 핵심 플로우 실패 / 화면 진행 불가

| ID | 이슈 | 상태 |
|---|---|---|
| P1-1 | 사업자 프로필 저장 후 `context.pop()` → GoRouter 미설정으로 예외, 화면이 닫히지 않음 | ✅ 수정 |
| P1-2 | `ApiService` 전 메서드 타임아웃 없음 → 무한 스피너 | ✅ 수정 |
| P1-3 | `OrderProvider` 미등록 상태로 `create_order_screen.dart:62` 에서 참조 | ❌ 미해결 |
| P1-4 | `rate_card_screen` 로드 실패 시 스피너 영구 회전 | ✅ 수정 |
| P1-5 | 견적 금액에 `double.parse` 직접 사용 → FormatException 문구 노출 (2곳) | ✅ 수정 |
| P1-6 | 견적 수정 다이얼로그 저장 중 중복 탭 가능 | ✅ 수정 |
| P1-7 | Android release 서명이 `key.properties` 없으면 **debug 키로 조용히 폴백** | ✅ 수정 — 릴리즈 설정 누락 시 빌드 실패 |
| P1-8 | 로드 실패를 "항목 없음" 빈 상태로 표시 → 재시도 수단 없음 | ✅ 부분 수정 (2화면) |

### P2 — UI 깨짐 / 상태 갱신 오류 / 잘못된 안내 / 성능

| ID | 이슈 | 상태 |
|---|---|---|
| P2-1 | `await` 뒤 `mounted` 미확인 약 30곳 (P1 처리분 제외) | ❌ 미해결 |
| P2-2 | `await` 뒤 `BuildContext` 사용 58건 | ❌ 미해결 (warning 으로 가시화) |
| P2-3 | 로컬 알림 탭이 아무 화면으로도 이동하지 않음 (`main.dart:92` TODO) | ❌ 미해결 |
| P2-4 | 딥링크 `orderId` 를 화면에 전달하지 않음 | ❌ 미해결 |
| P2-5 | FCM `new_order` 타입 탭 시 이동 없음 | ❌ 미해결 |
| P2-6 | iOS Associated Domains 없어 `https://` 딥링크 미동작 | ❌ 미해결 |
| P2-7 | Android `assetlinks.json` 게시 여부 미확인 | ❌ 미해결 (확인 필요) |
| P2-8 | iOS/Android Bundle ID 불일치 | ❌ 미해결 (의도 확인) |
| P2-9 | `firstWhere`·강제 언랩·불안전 캐스트 (6곳) | ❌ 미해결 |
| P2-10 | 개인정보 없는 `print` 약 750건이 릴리즈에서 실행 | ❌ 미해결 |
| P2-11 | 빈 `catch (_) {}` 23곳 — 알림·채팅방 생성 실패가 조용히 사라짐 | ❌ 미해결 |
| P2-12 | 가격 엔진 5xx 응답 본문을 데이터로 오해해 `available=true` | ✅ 수정 |

### P3 — 스타일 / 사용성 / 코드 품질

| ID | 이슈 | 상태 |
|---|---|---|
| P3-1 | `go_router` 의존성이 있으나 미설정. 6개 파일이 dead code 로 남음 | ❌ 미해결 (정리 권장) |
| P3-2 | 미사용 벤더 템플릿 `E-commerce-Complete-Flutter-UI-master/` (526 analyzer error 원인) | ✅ 분석 제외 |
| P3-3 | `AuthWrapper`·`HomeScreen` 중복 클래스 | ❌ 미해결 |
| P3-4 | `AnonymousProvider`·`storage_service`·`messaging_service` 미사용 스텁 | ❌ 미해결 |
| P3-5 | 사용되지 않는 `build.gradle.kts` 때문에 R8 설정 판정이 혼동됨 | ✅ 미사용 KTS 제거, 활성 `build.gradle`의 R8·리소스 축소 확인 |
| P3-6 | 직접 의존성 24개가 메이저 버전 뒤처짐 (`firebase_core` 3→4, `fl_chart` 0.68→1.2 등) | ❌ 미해결 |
| P3-7 | `withOpacity` 등 deprecated API 153건 | ❌ 미해결 |

---

## 13. 수정 완료 이슈

새로 추가한 파일:

| 파일 | 역할 |
|---|---|
| `lib/utils/app_logger.dart` | 릴리즈 로그 차단 + 전화번호·이메일·토큰·API키·주소 마스킹. Crashlytics/Sentry 훅(`AppLog.onReport`)만 열어 두고 외부 연동은 하지 않음 |
| `lib/utils/api_failure.dart` | 예외·HTTP 상태를 사용자용 한국어 문구로 매핑. 서버 문구는 짧은 한국어일 때만 채택 |
| `lib/utils/input_parsers.dart` | 금액·일수 파싱과 검증 (`tryParse` 기반) |
| `lib/widgets/error_state_view.dart` | 공통 오류 상태 + 재시도 버튼 (터치 영역 48px) |

수정한 파일:

| 파일 | 변경 |
|---|---|
| `lib/services/api_service.dart` | 전 메서드 타임아웃(읽기 15s·쓰기 25s·업로드 60s), 오류 매핑, 응답 본문 로깅 제거, 업로드에 Authorization 헤더 추가, 테스트용 클라이언트 주입 지점 |
| `lib/services/price_service.dart` | 실패 응답 본문을 데이터로 오해하던 문제 수정 |
| `lib/screens/customer/my_estimates_screen.dart` | 채택·거절 중복 방지 + 버튼 잠금·스피너, `mounted` 가드, 오류 상태·재시도 |
| `lib/screens/business/order_bidders_screen.dart` | 배정 중복 방지 (`_assigning`) + 버튼 잠금 |
| `lib/screens/business/business_profile_screen.dart` | `context.pop()` → `Navigator` 로 교체 (P1 크래시) |
| `lib/screens/business/rate_card_screen.dart` | try/catch + 오류 상태, 병렬 로드 |
| `lib/screens/create_estimate_screen.dart` | 금액·일수 검증, 진입 중복 가드, 오류 문구 |
| `lib/screens/business/estimate_management_screen.dart` | 수정 다이얼로그 검증·중복 방지·`mounted` 처리 |
| `lib/screens/business/order_marketplace_screen.dart` | 입찰 취소 판정을 문구 대신 `statusCode` 기반으로 |
| `lib/services/order_service.dart`, `auth_service.dart`, `fcm_service.dart`, `media_service.dart`, `notification_service.dart` | 개인정보 로깅 제거 |
| `lib/screens/customer/create_request_screen.dart`, `screens/notification/notification_screen.dart`, `utils/navigation_utils.dart` | 개인정보 로깅 제거 |
| `analysis_options.yaml` | 벤더 템플릿 제외, `use_build_context_synchronously` → warning |

**운영 서비스에 영향을 주는 변경은 하지 않았습니다.** API 스펙 변경 없음,
데이터 삭제 없음, 외부 메시지 발송 없음, 배포 없음.

---

## 14. 검증 결과

| 명령 | 결과 |
|---|---|
| `flutter analyze` | **error 0** (감사 전 526 → 벤더 템플릿 제외 후 0), warning 135, info 763 |
| `flutter test` | **167 통과** (감사 전 57) |
| `npm test` (vitest, 백엔드) | **127 통과** |
| `flutter build appbundle --release` | **성공** — 서명된 AAB 56.3MB, versionCode 70 |
| `flutter build ios --release --no-codesign` | **성공** — Runner.app 30.5MB, CFBundleVersion 70 |
| `flutter build ipa --release` | **성공** — App Store IPA 53.8MB, 기본 Launch Image 경고 제거 |

---

## 15. 다음 문서

- `docs/test-matrix.md` — 고객·사업자·공통 시나리오 매트릭스와 자동화 현황
- `docs/ui-ux-qa.md` — 화면별 UI/UX 검수 결과와 4기기 해상도 검증
