# 웹 고객 문자 알림 (Solapi SMS)

올수리 웹에서 견적을 넣은 일반 고객에게, 아래 이벤트가 생길 때마다 **문자(LMS)** 를 보냅니다.
카카오톡 채널·알림톡은 사용하지 않습니다.

설정이 없으면 로그만 남기고 앱/웹 동작은 그대로입니다.

## 발송 조건

| 시점 | 수신 | 내용 |
|---|---|---|
| 사업자 입찰 | 웹 고객 | 상호, 견적가, 평점, `/my-order` 링크 |
| 사업자 낙찰 | 웹 고객 | 상호, 사업자 연락처, `/my-order` 링크 |
| 사업자가 공사 완료 | 웹 고객 | 완료 안내 + 평점 요청, `/my-order` 링크 |

입찰 문자는 앱에서 마켓 입찰 API(`POST /api/market/listings/:id/bid`)가 호출될 때 나갑니다. (`web_order_id`가 있는 웹 오더만)

**중요:** 입찰 API는 `api.allsuri.app`(allsuriapp)에서 실행됩니다. Solapi 키를 웹 사이트(allsuricommerce)에만 넣으면 입찰 문자가 나가지 않습니다. 아래 세 값을 **두 사이트 모두**에 넣으세요.

낙찰 문자는 웹에서 사업자를 선택할 때 나갑니다. (allsuri-web `/api/customer/order/:id/award` 및 레거시 Netlify `customer` 함수)

공사 완료·평점 문자는 사업자가 앱에서 공사 완료를 누르면 `POST /api/customer/order/:id/notify-work-done` 으로 나갑니다.

## 필요한 준비

1. [Solapi](https://solapi.com) 가입
2. **발신번호 사전 등록·승인**
3. 아래 환경변수 설정

카카오 채널(`SOLAPI_PF_ID`)과 알림톡 템플릿 ID는 더 이상 필요하지 않습니다.

## 환경변수

**allsuriapp Netlify** (Functions: `api.allsuri.app` 등)

```
SOLAPI_API_KEY=<Solapi API Key>
SOLAPI_API_SECRET=<Solapi API Secret>
SOLAPI_SENDER_PHONE=<사전 등록된 발신번호, 숫자만. 예: 0212345678>
ALLSURI_WEB_URL=https://allsuricommerce.netlify.app
```

**allsuri-web Netlify** (낙찰 문자 + 입찰 문자 위임)

같은 `SOLAPI_*` 세 값을 넣고, 공개 사이트 주소가 다르면:

```
NEXT_PUBLIC_SITE_URL=https://allsuricommerce.netlify.app
```

입찰 문자는 `api.allsuri.app`에서 Solapi로 먼저 보내고, 키가 없거나 실패하면 웹 `POST /api/internal/sms`로 위임합니다. 웹에만 Solapi 키가 있어도 입찰 문자가 나갈 수 있습니다. 위임이 되려면 두 사이트의 `SUPABASE_SERVICE_ROLE_KEY`가 같아야 합니다.

문자 본문의 확인 링크는 `https://allsuricommerce.netlify.app/my-order?phone=01012345678` 형식입니다. 전화번호가 미리 채워져 고객은 비밀번호만 입력하면 됩니다.

## 문자 템플릿 (상태별)

일반 문자는 Solapi 콘솔 알림톡 템플릿을 쓰지 않습니다. 문구와 변수는 코드에서 상태(이벤트)별로 정합니다.

- allsuriapp: `netlify/lib/sms_templates.ts`
- allsuri-web: `lib/sms-templates.ts` (낙찰 문구 — 위 파일과 동일하게 유지)

| 오더 상태 / 이벤트 | 템플릿 ID | 채워지는 변수 |
|---|---|---|
| `bidding` (입찰) | `bid_received` | `#{오더명}` `#{상호}` `#{견적가}` `#{평점}` `#{링크}` |
| `in_progress` (낙찰) | `awarded` | `#{오더명}` `#{상호}` `#{연락처}` `#{링크}` |
| `awaiting_confirmation` (공사 완료) | `work_done` | `#{오더명}` `#{링크}` |

배포 없이 문구만 바꾸려면 Netlify 환경변수로 덮어씁니다. `#{변수}` 자리는 그대로 두세요.

```
SOLAPI_SMS_TPL_BID_RECEIVED
SOLAPI_SMS_TPL_AWARDED
SOLAPI_SMS_TPL_WORK_DONE
```

## 참고

- 한글+URL이 포함되어 **LMS** 로 발송합니다.
- 수신번호가 없거나 Solapi 설정이 비어 있으면 발송을 건너뜁니다. 입찰/낙찰/완료 처리 자체는 실패하지 않습니다.
- 입찰 문자가 스킵/실패하면 Netlify 로그에 `[solapi-sms]` / `[market] 웹 오더 문자 미발송` 이 남습니다.
