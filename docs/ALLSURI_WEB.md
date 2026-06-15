# allsuri-web 연동 가이드

올수리 웹사이트(`allsuri-web`)는 Flutter 앱(`allsuriapp`)과 **같은 Supabase** 를 공유하는 별도 저장소입니다.

## 저장소 위치

| 프로젝트 | 경로 | Git remote |
|---|---|---|
| allsuriapp (앱 + Netlify Functions + DB) | `/Users/hurmin-ho/Documents/dev/allsuriapp` | `onondeveloper/allsuriapp` |
| allsuri-web (공개 웹 + 관리자) | `/Users/hurmin-ho/Documents/dev/allsuri-web` | `onondeveloper/allsuri-web` |

현재 워크스페이스에서는 `allsuriapp/allsuri-web` 심볼릭 링크로 웹 저장소에 접근합니다.

## 기술 스택

- **Next.js 16** (App Router)
- **Supabase** (SSR + service role in API routes)
- **Netlify** 배포 (`@netlify/plugin-nextjs`)
- **Tailwind CSS 4**

## 로컬 개발

```bash
cd /Users/hurmin-ho/Documents/dev/allsuri-web
npm install          # 최초 1회
npm run dev          # http://localhost:3000
```

환경 변수는 `allsuri-web/.env.local` (gitignore). allsuriapp 의 Supabase/Netlify 값과 동일 프로젝트를 가리켜야 합니다.

| 변수 | 용도 |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | 클라이언트/SSR |
| `SUPABASE_SERVICE_ROLE_KEY` | API routes (RLS bypass) |
| `ALLSURIAPP_API_URL` | Netlify Functions (`https://api.allsuri.app` 등) |

## allsuriapp 과의 관계

```
allsuri-web (Next.js, allsuri.app)
    ├── Supabase 직접 조회/쓰기 (users, marketplace_listings, …)
    └── allsuriapp Netlify API 호출 (customer/submit, featured-businesses 등)
            └── netlify/functions/*  (allsuriapp 저장소)

allsuriapp (Flutter)
    └── Supabase + api.allsuri.app
```

- **DB 마이그레이션**: `allsuriapp/database/*.sql` 에서 관리 (웹 전용: `web_*.sql`, `fix_web_*.sql`)
- **레거시 정적 HTML**: `allsuriapp/backend/public/` (my-order.html 등) — 신규 기능은 allsuri-web 우선
- **관리자**: 웹 `/admin/*` + 앱 `backend/public/admin.js` (Functions 경유)

## 주요 페이지 / API

| 경로 | 설명 |
|---|---|
| `/` | 홈 |
| `/requests` | 익명 견적/오더 접수 |
| `/my-order` | 고객 오더 조회 |
| `/business` | 사업자 목록 |
| `/admin/*` | 관리자 (미들웨어 세션 보호) |
| `app/api/customer/*` | 고객 API (service role) |

## Cursor / VS Code에서 열기

**방법 1 — 멀티루트 (권장)**

```bash
open /Users/hurmin-ho/Documents/dev/allsuri.code-workspace
```

**방법 2 — 현재 allsuriapp 워크스페이스**

`allsuriapp/allsuri-web/` 링크 아래에서 웹 파일 편집 가능 (이미 연결됨).

## 배포

- **allsuri-web**: Netlify (별도 사이트, `npm run build`)
- **allsuriapp Functions**: `git push` → Netlify (api.allsuri.app)

웹/API/DB 를 동시에 바꿀 때는 **DB → Functions → allsuri-web** 순으로 배포하는 것이 안전합니다.
