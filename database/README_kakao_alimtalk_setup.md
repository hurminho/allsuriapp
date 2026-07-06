# 카카오 알림톡 (웹 오더 플로우) 설정 가이드

P1 작업으로 웹 오더 플로우에 카카오 알림톡 발송 코드가 이미 붙어 있습니다 (`netlify/functions/market.ts`, `netlify/functions/customer.ts`).
**Solapi 계정/템플릿이 준비되지 않으면 자동으로 로그만 남기고 조용히 스킵**되므로, 지금 배포해도 앱/웹 동작에는 영향이 없습니다.
아래 절차대로 준비되는 대로 Netlify 환경변수만 채우면 즉시 발송이 활성화됩니다.

## 1. 필요한 사전 준비

1. [Solapi](https://solapi.com) 가입 및 발신번호 등록 (사전 승인 필요)
2. 카카오톡 채널(플러스친구) 개설 후 Solapi에 채널 연동 → `pfId` 발급
3. 아래 4종 알림톡 템플릿을 카카오에 등록/승인 (검수 1~2일 소요)

## 2. 알림톡 템플릿 (4종)

| 이벤트 | 발송 시점 | 발송 대상 | 변수 |
|---|---|---|---|
| 입찰 접수 (BID_RECEIVED) | 사업자가 견적/입찰 제출 시 즉시 | 소비자(웹) | `#{고객명}`, `#{오더명}`, `#{링크}` |
| 낙찰 완료 (BID_AWARDED) | 소비자가 사업자를 선택(낙찰)한 직후 즉시 | 소비자(웹) | `#{고객명}`, `#{오더명}`, `#{사업자명}`, `#{링크}` |
| 완료 유도 (WORK_DONE) | 사업자가 앱에서 "공사 완료"를 누른 직후 즉시 | 소비자(웹) | `#{고객명}`, `#{오더명}`, `#{링크}` |
| 후기 요청 (REVIEW_REQUEST) | 소비자가 최종 "공사 완료 확인"을 누른 직후 즉시 | 소비자(웹) | `#{고객명}`, `#{오더명}`, `#{링크}` |

템플릿 문구 예시:

- **BID_RECEIVED**: `#{고객명}님, "#{오더명}"에 새로운 견적이 도착했습니다. 지금 확인해보세요.\n#{링크}`
- **BID_AWARDED**: `#{고객명}님, "#{오더명}"에 #{사업자명} 사업자가 선정되었습니다. 공사 진행 후 완료 확인을 부탁드립니다.\n#{링크}`
- **WORK_DONE**: `#{고객명}님, 신청하신 "#{오더명}" 공사가 완료되었다고 사업자가 알려왔습니다. 확인 후 완료 버튼을 눌러주세요.\n#{링크}`
- **REVIEW_REQUEST**: `#{고객명}님, 공사 완료를 확인해 주셔서 감사합니다. 서비스는 어떠셨나요? 후기를 남겨주세요.\n#{링크}`

> 템플릿이 승인되지 않은 상태에서도 `disableSms: false` 설정으로 인해 알림톡 발송 실패 시 자동으로 문자(SMS)로 대체 발송되도록 되어 있습니다 (발신번호 사전 등록 필요).

## 3. Netlify 환경변수 (Site settings → Environment variables)

```
SOLAPI_API_KEY=<Solapi API Key>
SOLAPI_API_SECRET=<Solapi API Secret>
SOLAPI_SENDER_PHONE=<사전 등록된 발신번호, 예: 0212345678>
SOLAPI_PF_ID=<카카오 채널 pfId>
SOLAPI_TEMPLATE_BID_RECEIVED=<입찰 접수 템플릿 ID>
SOLAPI_TEMPLATE_BID_AWARDED=<낙찰 완료 템플릿 ID>
SOLAPI_TEMPLATE_WORK_DONE=<완료 유도 템플릿 ID>
SOLAPI_TEMPLATE_REVIEW_REQUEST=<후기 요청 템플릿 ID>
```

환경변수 중 하나라도 비어있으면 해당 알림은 로그(`[kakao-alimtalk] SOLAPI 환경변수/템플릿 미설정 - 발송 스킵`)만 남기고 조용히 스킵됩니다.

## 4. DB 마이그레이션

`database/p0_bidding_unification_and_completion_sync.sql` 을 Supabase SQL Editor에서 먼저 실행해야 합니다.
(orders.awarded_bid_id 컬럼 추가, orders.status에 'bidding'/'awaiting_confirmation' 허용 등)

## 5. 변경된 플로우 요약

1. **입찰 데이터 단일화**: 웹 `my-order` 페이지가 이제 `estimates`가 아닌 `order_bids`를 조회합니다.
   앱 사업자가 입찰한 내용이 그대로 웹에도 표시되며, 사업자 평점/후기도 함께 노출됩니다.
2. **낙찰(award) API**: `estimateId` 대신 `bidId`를 사용합니다.
3. **완료 정책**: 소비자가 `POST /api/customer/order/:id/complete` 를 호출해야만 최종 `completed` 처리되며,
   이때 `orders`, `jobs`, `marketplace_listings` 상태가 모두 `completed`로 동기화됩니다.
   사업자가 앱에서 "공사 완료"를 눌러도 `awaiting_confirmation` 상태로만 바뀌고, 소비자에게 완료 유도 알림톡이 발송될 뿐
   최종 완료 처리는 되지 않습니다.
