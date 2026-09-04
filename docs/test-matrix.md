# 올수리 앱 테스트 매트릭스

| 항목 | 값 |
|---|---|
| 작성일 | 2026-09-04 |
| Flutter 테스트 | **167 통과** (14파일) |
| 백엔드 테스트 | **127 통과** (vitest, 5파일) |
| 외부 의존성 | 전부 mock / fake API. 운영 DB·OpenAI·Solapi 미호출 |

`자동` = 자동 테스트로 고정됨 · `수동` = 수동 점검 필요 · `미커버` = 아직 검증 안 됨

---

## 실행 방법

```bash
# 앱: 단위 + 위젯 + 통합(가짜 서버)
flutter test

# 특정 영역만
flutter test test/api_service_test.dart          # API 계층 계약
flutter test test/quote_flow_integration_test.dart  # 견적→입찰→완료 흐름
flutter test test/responsive_layout_test.dart    # 4기기 해상도 · 글자 배율

# 정적 분석 (게이트: error 0)
flutter analyze

# 백엔드 (가격 엔진·입찰 원가)
npm test
```

### 외부 의존성 격리 방법

| 의존성 | 격리 수단 |
|---|---|
| Netlify API | `ApiService.testClient` 에 `MockClient` 주입. `test/quote_flow_integration_test.dart` 의 `FakeApiServer` 가 경로별 응답과 상태를 관리 |
| OpenAI | 앱에 호출 경로 없음 (서버 전용). 실험 화면 `labs/` 만 예외이며 테스트 대상 아님 |
| Solapi | 앱에 호출 경로 없음 (서버 전용) |
| 결제 | 미연동 (`PaymentService` 는 알림 스텁) |
| 이미지 업로드 | Supabase Storage. 위젯 테스트에서는 호출하지 않음 → 수동 점검 항목 |
| Supabase | 대부분의 서비스가 필드 초기화 시점에 `Supabase.instance.client` 를 잡아 단위 테스트에서 생성 불가 → [테스트 가능성 한계](#테스트-가능성-한계) |

**테스트 데이터에는 실제 전화번호·주소·API 키를 쓰지 않습니다.** 마스킹 테스트에
쓰는 값은 형식만 맞춘 가짜 값입니다 (`010-1234-5678`, `sk-abcdef...`).

---

## 1. 고객 플로우

| # | 시나리오 | 상태 | 근거 |
|---|---|---|---|
| C-01 | 로그인 없이 앱 실행 | 수동 | `SplashScreen`→`HomeScreen` 비로그인 분기. 기기 실행 필요 |
| C-02 | 홈 화면 진입 | 수동 | 동일 |
| C-03 | 견적 요청 시작 | 수동 | `CreateRequestScreen`. Supabase 의존으로 위젯 테스트 불가 |
| C-04 | 카테고리 선택 | 자동 | `price_estimate_card_test.dart` — 공정 후보 선택 콜백 |
| C-05 | 증상 입력 | 수동 | 자유 텍스트. 서버 정규화는 `netlify/tests/price_catalog.test.ts` 커버 |
| C-06 | 사진 미첨부 | 수동 | |
| C-07 | 사진 첨부 | 수동 | |
| C-08 | **사진 업로드 실패** | 미커버 | `MediaService` 가 Supabase Storage 직결. 어댑터 분리 필요 |
| C-09 | 위치·연락처 입력 | 수동 | 정규화 로그에 번호가 남지 않는 것은 자동 검증 |
| C-10 | AI 견적 요청 | 수동 | 웹·서버 담당 |
| C-11 | AI 응답 정상 | 자동 | `netlify/tests/price_catalog.test.ts` (JSON 정규화) |
| C-12 | **AI 응답 지연** | 자동 | `quote_flow_integration_test.dart` — 300ms 지연에도 예외 없이 화면 렌더 가능한 값 반환 |
| C-13 | **AI 응답 실패** | 자동 | 동일 — 500 응답 시 `available=false`, 숫자 미표시로 진행 |
| C-14 | **AI 형식 오류** | 자동 | `api_service_test.dart` — JSON 아닌 HTML 오류 본문도 크래시 없이 처리 |
| C-15 | 추가 질문 응답 | 자동 | 서버가 최대 3개로 제한 (`price.ts:337`), `netlify/tests` 커버 |
| C-16 | **가격 UI: 데이터 충분** | 자동 | `responsive_layout_test.dart` — 범위 + "참고" 문구 동시 표시 검증 |
| C-17 | **가격 UI: 일부** | 자동 | `price_estimate_test.dart`, `responsive_layout_test.dart` |
| C-18 | **가격 UI: 부족** | 자동 | `responsive_layout_test.dart` — "원" 문자가 렌더되지 않음을 단정 |
| C-19 | 견적 요청 제출 | 수동 | |
| C-20 | **중복 탭 (견적 채택)** | 자동 | `_processingEstimateId` 가드. 버튼 잠금 + 스피너 |
| C-21 | 뒤로가기 | 자동 | `business_tab_pop_safety_test.dart` |
| C-22 | 앱 재실행 | 수동 | 비로그인 세션ID 는 `SharedPreferences` 에 유지 |
| C-23 | 내 견적 조회 | 수동 | |
| C-24 | 업체 입찰 도착 | 자동 | `quote_flow_integration_test.dart` — 입찰 저장 후 조회 |
| C-25 | **알림 실패 시 앱 내 상태 확인** | 수동 | 인앱 알림함이 있어 확인 가능. 로컬 알림 탭 이동은 미구현(P2-3) |
| C-26 | **네트워크 끊김 후 재시도** | 자동 | `quote_flow_integration_test.dart` — 실패 시 `retryable=true`, 재시도 성공, 실패 요청 미저장 |

---

## 2. 사업자 플로우

| # | 시나리오 | 상태 | 근거 |
|---|---|---|---|
| B-01 | 신규 일감 목록 확인 | 자동(부분) | `business_ui_components_test.dart` — 카드 렌더 |
| B-02 | 필터·정렬 | 수동 | |
| B-03 | 견적 상세 확인 | 수동 | |
| B-04 | **입찰 금액·세부비용 입력** | 자동 | `bid_cost_fields_test.dart` (8건) + `bid_breakdown_test.dart` |
| B-05 | **필수값 누락** | 자동 | `input_parsers_test.dart` — 빈 금액·빈 일수 안내 문구 |
| B-06 | **잘못된 금액 형식** | 자동 | `input_parsers_test.dart` — "10만원" 거부, 예시 포함 안내 |
| B-07 | **금액 오타 (0 추가)** | 자동 | 상한 1억 초과 시 재확인 안내 |
| B-08 | **견적 제출** | 자동 | `quote_flow_integration_test.dart` — 세부 원가 포함 payload 검증 |
| B-09 | **총액만 입력** | 자동 | 세부 항목 없이도 제출됨 (정책) |
| B-10 | **제출 후 중복 전송 방지** | 자동 | 동일 — 서버 `alreadyBid` 흡수, 저장 1건 |
| B-11 | 채팅·연락·알림 진입 | 수동 | |
| B-12 | 수주 진행 상태 변경 | 자동(부분) | `business_ui_components_test.dart` — 상태 라벨 변환 |
| B-13 | **사업자 배정 중복 방지** | 자동 | `_assigning` 가드 + 버튼 잠금 |
| B-14 | **AS·완료 처리 (확정금액)** | 자동 | `quote_flow_integration_test.dart` — 입찰가와 최종금액 분리 저장 |
| B-15 | **세부 합계 불일치 차단** | 자동 | 합계가 총액과 1000원 넘게 다르면 서버로 보내지 않음 |
| B-16 | **표준 단가 등록** | 자동(부분) | 로드 실패 시 오류 상태 + 재시도 (`rate_card_screen`) |
| B-17 | 서버 거절 시 문구 | 자동 | `quote_flow_integration_test.dart` — `PGRST`·`constraint` 미노출 |

---

## 3. 공통 플로우

| # | 시나리오 | 상태 | 근거 |
|---|---|---|---|
| S-01 | **로딩** | 자동 | `responsive_layout_test.dart` — 가격 로딩 상태 4기기 |
| S-02 | 빈 상태 | 자동(부분) | `error_state_view_test.dart` 로 오류/빈 구분 |
| S-03 | **오류 상태** | 자동 | `error_state_view_test.dart` (6건) |
| S-04 | **재시도** | 자동 | 동일 — 콜백 호출 검증 |
| S-05 | **오프라인 상태** | 자동 | `api_service_test.dart`, `api_failure_test.dart` — "인터넷 연결을 확인해 주세요." |
| S-06 | **타임아웃** | 자동 | `api_service_test.dart` — 쓰기 제한이 읽기보다 길다는 불변식 포함 |
| S-07 | 권한 거부 | 수동 | 카메라·사진·알림. 기기 실행 필요 |
| S-08 | 앱 백그라운드·복귀 | 수동 | `_BadgeLifecycleObserver` |
| S-09 | **세션 만료** | 자동(부분) | 401 → "로그인이 만료되었습니다" 매핑. 실제 갱신 흐름은 수동 |
| S-10 | 로컬 데이터 초기화 | 수동 | |
| S-11 | **작은 화면 (320x568)** | 자동 | `responsive_layout_test.dart` |
| S-12 | **큰 화면 (800x1280 태블릿)** | 자동 | 동일 |
| S-13 | 다크모드 | **해당 없음** | `themeMode: ThemeMode.light` 로 고정. `darkTheme` 도 라이트 테마 |
| S-14 | **긴 한글 문구 줄바꿈** | 자동 | `responsive_layout_test.dart` — 60자 제목을 4기기에서 검증 |
| S-15 | **작은 글자 접근성 (배율 2.0x)** | 자동 | 동일 — 1.0 / 1.3 / 2.0배 |
| S-16 | **노치·하단 제스처 영역** | 자동 | 동일 — `padding: top 59, bottom 34` 로 내비 항목 전수 확인 |
| S-17 | **개인정보 로그 미노출** | 자동 | `app_logger_test.dart` (17건) + 통합 경로 검증 |
| S-18 | **개발자 문구 미노출** | 자동 | `api_failure_test.dart`, `input_parsers_test.dart` |
| S-19 | **릴리즈 API URL** | 자동 | `api_service_test.dart` — https·localhost 아님 |

---

## 4. 추가한 테스트 파일

| 파일 | 건수 | 검증 대상 |
|---|---|---|
| `test/app_logger_test.dart` | 17 | 전화번호·이메일·JWT·Bearer·API키·주소 마스킹, 리포터 훅, 오탐 방지(금액을 번호로 오인하지 않음) |
| `test/api_failure_test.dart` | 14 | 예외·상태코드 분류, 서버 문구 채택 규칙, 재시도 가능성 |
| `test/input_parsers_test.dart` | 20 | 금액·일수 파싱, 천단위·통화기호 허용, 한글 단위 거부, 검증 문구 |
| `test/api_service_test.dart` | 15 | 성공/오류 매핑, 타임아웃, 오프라인, 응답 본문·토큰 로깅 차단, base URL |
| `test/error_state_view_test.dart` | 6 | 오류 상태, 재시도, 44px 터치 영역, 긴 문구 줄바꿈 |
| `test/responsive_layout_test.dart` | 23 | 4기기 × (일감 카드·가격 3상태·로딩·오류), 노치, 글자 배율 3단계, 가격 오해 방지 |
| `test/quote_flow_integration_test.dart` | 14 | 견적→가격→입찰→완료 전 구간. 중복 제출, 네트워크 실패·재시도, 봉투 형식, 로그 안전성 |
| **합계** | **109** | |

기존 유지: `bid_action_test`, `bid_breakdown_test`, `bid_cost_fields_test`,
`business_tab_pop_safety_test`, `business_ui_components_test`,
`price_estimate_card_test`, `price_estimate_test`, `widget_test` (**55건**)

---

## 5. 통합 테스트가 실제로 잡아낸 결함

문서용으로 쓴 테스트가 아니라는 근거입니다.

| 결함 | 발견 경로 |
|---|---|
| 가격 엔진 5xx 응답 본문을 정상 데이터로 오해해 `available=true` 로 만들던 문제 | `quote_flow_integration_test.dart` 의 "엔진이 죽어도 진행" 케이스 |
| 앱이 기대하는 응답 봉투와 실제 `netlify/functions/price.ts` 의 `ok()` 봉투가 다름 (`data` 래핑 유무) | 동일 — 가짜 서버를 실제 응답 모양에 맞추는 과정에서 확인 |
| 입찰 취소 화면이 `error` 문구에 `'404'` 가 들어 있는지로 성공을 판정 → 오류 문구를 한국어로 바꾸면 깨짐 | `api_service_test.dart` 의 `statusCode` 케이스 |

---

## 6. 테스트 가능성 한계

지금 구조에서 자동화하지 못한 이유와 필요한 변경입니다. **이번에는 대규모
리팩터링을 하지 않았으므로 제안만 남깁니다.**

| 한계 | 원인 | 필요한 변경 |
|---|---|---|
| 화면 단위 위젯 테스트 대부분 불가 | `MarketplaceService` 등이 필드 초기화에서 `Supabase.instance.client` 를 잡음 → 미초기화 시 즉시 예외 | 클라이언트를 생성자 주입으로 바꾸거나 lazy getter 로 변경 |
| 이미지 업로드 실패 경로 (C-08) | `MediaService` 가 Storage 직결 | 업로더 인터페이스 분리 |
| 기기 통합 테스트 없음 | `integration_test/` 디렉터리 자체가 없음 | `integration_test` 패키지 추가 후 C-01·C-19·C-22 자동화 |
| 딥링크·알림 진입 화면 전환 | `navigatorKey` 직접 사용 | 라우팅 계층 정리 후 검증 가능 |

---

## 7. CI 게이트 제안

```bash
flutter analyze   # 통과 기준: error 0  (현재 충족)
flutter test      # 통과 기준: 전체 통과 (현재 167/167)
npm test          # 통과 기준: 전체 통과 (현재 127/127)
```

`warning` 은 현재 135건입니다. 대부분 `use_build_context_synchronously`(58)와
미사용 요소이며, **0으로 만들기 전까지는 error 0 만 게이트로 쓰는 것을 권합니다.**
warning 건수를 기준선으로 기록해 두고 증가하면 실패시키는 방식이 현실적입니다.
