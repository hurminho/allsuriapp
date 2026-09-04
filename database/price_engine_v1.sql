-- =============================================================================
-- 가격 엔진 v1 — 비파괴 마이그레이션
-- =============================================================================
-- 실행: Supabase SQL Editor 에 전체 붙여넣기 (여러 번 실행해도 안전)
--
-- 원칙
--  * 기존 테이블/컬럼을 지우거나 이름을 바꾸지 않습니다. 추가만 합니다.
--  * 기존 행은 새 컬럼이 NULL 이며, 앱/웹은 NULL 을 "데이터 없음"으로 처리합니다.
--  * 새 테이블은 RLS 를 켜고 정책을 만들지 않습니다.
--    → service_role(Netlify Functions)만 접근합니다. 앱은 /api/price/* 를 씁니다.
--  * 금액은 원(KRW) 정수입니다. 부가세 포함 여부는 별도 boolean 으로 저장합니다.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. 질문 은행 — 공정별 필수/선택 질문을 구성 데이터로 관리
-- -----------------------------------------------------------------------------
create table if not exists price_questions (
  id            text primary key,
  label         text not null,
  input_type    text not null default 'single'
                  check (input_type in ('single', 'multi', 'bool', 'text', 'number', 'photo')),
  options       jsonb not null default '[]'::jsonb,   -- [{ "value": "...", "label": "..." }]
  maps_to       text,                                  -- urgency | propertyType | workScopeTags | symptomTags | accessDifficulty | materialIncluded
  tag_map       jsonb not null default '{}'::jsonb,     -- { "overflow": ["관통 작업", "고압 세척"] }
  affects_price boolean not null default false,
  help_text     text,
  sort_order    integer not null default 100
);

-- 이 파일을 이미 한 번 실행한 환경을 위한 추가 컬럼(비파괴).
alter table price_questions add column if not exists tag_map jsonb not null default '{}'::jsonb;

comment on table price_questions is '가격 엔진 질문 정의. 하드코딩 분기 대신 이 표를 늘려 공정 질문을 확장합니다.';
comment on column price_questions.maps_to is 'null 이면 참고용 질문. 값이 있으면 가격 엔진 입력 필드로 정규화됩니다.';
comment on column price_questions.tag_map is 'maps_to 가 workScopeTags/symptomTags 일 때 선택지→태그 매핑. 라벨 문자열 매칭에 의존하지 않습니다.';

-- -----------------------------------------------------------------------------
-- 2. 공정 카탈로그 — category/subcategory 단위 정의
-- -----------------------------------------------------------------------------
create table if not exists trade_catalog (
  id                           text primary key,          -- 예: 'plumbing.toilet_clog'
  category                     text not null,             -- 배관 / 화장실 / 누수 / 방수 / 주방 ...
  subcategory                  text not null,             -- 변기 막힘 ...
  aliases                      text[] not null default '{}',
  symptom_tags                 text[] not null default '{}',
  work_scope_tags              text[] not null default '{}',
  required_questions           text[] not null default '{}',
  optional_questions           text[] not null default '{}',
  price_factors                text[] not null default '{}',
  base_labor_min               integer,
  base_labor_typical           integer,
  base_labor_max               integer,
  material_included_by_default boolean not null default false,
  visit_fee_applies            boolean not null default true,
  visit_fee_typical            integer not null default 0,
  urgency_surcharge_applies    boolean not null default true,
  urgency_multipliers          jsonb not null default '{}'::jsonb,  -- { "emergency": 1.4, "today": 1.2 }
  sanity_min                   integer not null default 10000,
  sanity_max                   integer not null default 5000000,
  sufficient_completed_jobs    integer not null default 8,
  preliminary_min_samples      integer not null default 3,
  active                       boolean not null default true,
  sort_order                   integer not null default 100,
  created_at                   timestamptz not null default now(),
  updated_at                   timestamptz not null default now()
);

create index if not exists trade_catalog_category_idx on trade_catalog (category) where active;

comment on table trade_catalog is '초기 지원 공정 정의. 광범위한 집수리 전체가 아니라 견적 구조가 표준화되는 세부 공정만 active=true 로 둡니다.';
comment on column trade_catalog.sanity_min is '이 금액 미만 표본은 오입력으로 보고 버립니다.';
comment on column trade_catalog.sufficient_completed_jobs is 'priceState=sufficient 판정을 위한 완료 거래 수 임계값.';

-- -----------------------------------------------------------------------------
-- 3. 운영자 기준표 — 데이터가 쌓이기 전 최후순위 근거
-- -----------------------------------------------------------------------------
create table if not exists price_baselines (
  id                uuid primary key default gen_random_uuid(),
  trade_id          text not null references trade_catalog (id) on delete cascade,
  region_level1     text,                                -- null = 전국
  property_type     text,                                -- null = 전체
  min_amount        integer not null,
  typical_amount    integer not null,
  max_amount        integer not null,
  material_included boolean not null default false,
  vat_included      boolean not null default false,
  note              text,
  updated_by        text,
  updated_at        timestamptz not null default now(),
  check (min_amount > 0 and min_amount <= typical_amount and typical_amount <= max_amount)
);

create unique index if not exists price_baselines_scope_uniq
  on price_baselines (trade_id, coalesce(region_level1, '*'), coalesce(property_type, '*'));

comment on table price_baselines is '운영자가 관리하는 초기 기준표. 실거래·입찰 데이터가 부족할 때만 사용하며 신뢰도는 low 로 내려갑니다.';

-- -----------------------------------------------------------------------------
-- 4. 사업자 표준 단가 — "빠른 등록" 으로 받는 검증 가능한 단가
-- -----------------------------------------------------------------------------
create table if not exists contractor_rate_cards (
  id                          uuid primary key default gen_random_uuid(),
  contractor_id               uuid not null,
  trade_id                    text not null references trade_catalog (id) on delete cascade,
  base_labor_cost             integer not null,
  material_avg_cost           integer not null default 0,
  material_included           boolean not null default false,
  visit_fee                   integer not null default 0,
  vat_included                boolean not null default false,
  additional_cost_conditions  text[] not null default '{}',
  service_regions             text[] not null default '{}',
  verified                    boolean not null default false,
  active                      boolean not null default true,
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),
  check (base_labor_cost >= 0 and material_avg_cost >= 0 and visit_fee >= 0)
);

create unique index if not exists contractor_rate_cards_uniq
  on contractor_rate_cards (contractor_id, trade_id);
create index if not exists contractor_rate_cards_trade_idx
  on contractor_rate_cards (trade_id) where active;

comment on table contractor_rate_cards is '사업자 표준 단가. verified=true(사업자등록 진위확인 완료) 카드만 가격 엔진 3순위 근거로 씁니다.';

-- -----------------------------------------------------------------------------
-- 5. 최종 거래 — 가격 엔진 1순위 근거 (입찰가와 반드시 분리)
-- -----------------------------------------------------------------------------
create table if not exists completed_jobs (
  id                     uuid primary key default gen_random_uuid(),
  order_id               uuid,        -- orders.id (웹 고객 요청)
  listing_id             uuid,        -- marketplace_listings.id
  job_id                 uuid,        -- jobs.id
  bid_id                 uuid,        -- order_bids.id (선정된 입찰)
  trade_id               text references trade_catalog (id) on delete set null,
  category               text,
  subcategory            text,
  region_level1          text,
  region_level2          text,
  property_type          text,
  urgency                text,
  selected_contractor_id uuid,
  final_labor_cost       integer,
  final_material_cost    integer,
  final_additional_cost  integer,
  final_total_amount     integer not null,
  vat_included           boolean not null default false,
  payment_method         text,
  completion_at          timestamptz not null default now(),
  as_occurred            boolean not null default false,
  customer_rating        numeric(2, 1),
  final_work_scope_tags  text[] not null default '{}',
  source                 text not null default 'app',
  created_at             timestamptz not null default now(),
  check (final_total_amount > 0)
);

create unique index if not exists completed_jobs_listing_uniq
  on completed_jobs (listing_id) where listing_id is not null;
create index if not exists completed_jobs_trade_idx
  on completed_jobs (trade_id, completion_at desc);
create index if not exists completed_jobs_region_idx
  on completed_jobs (region_level1, trade_id);

comment on table completed_jobs is '실제 완료·정산된 금액. ContractorBid.bid_amount 와 절대 섞지 않습니다.';
comment on column completed_jobs.final_total_amount is '고객이 실제로 지불한 총액. 가격 엔진 최우선 표본.';

-- -----------------------------------------------------------------------------
-- 6. 엔진 설정 — 임계값을 코드 배포 없이 조정
-- -----------------------------------------------------------------------------
create table if not exists price_engine_settings (
  key        text primary key,
  value      jsonb not null,
  note       text,
  updated_by text,
  updated_at timestamptz not null default now()
);

comment on table price_engine_settings is '데이터 충분성 임계값·가중치. 없으면 코드 기본값을 씁니다.';

-- -----------------------------------------------------------------------------
-- 7. 엔진 결과 스냅샷 — 계산 근거와 엔진 버전 보관
-- -----------------------------------------------------------------------------
create table if not exists price_estimates (
  id                 uuid primary key default gen_random_uuid(),
  order_id           uuid,
  session_id         text,
  trade_id           text,
  engine_version     text not null,
  request            jsonb not null,
  price_state        text not null check (price_state in ('sufficient', 'preliminary', 'insufficient')),
  estimated_min      integer,
  estimated_typical  integer,
  estimated_max      integer,
  confidence_level   text not null check (confidence_level in ('high', 'medium', 'low')),
  confidence_score   numeric(4, 3),
  evidence_count     integer not null default 0,
  weighted_evidence  numeric(10, 3) not null default 0,
  factors            text[] not null default '{}',
  basis              jsonb not null default '[]'::jsonb,
  created_at         timestamptz not null default now()
);

create index if not exists price_estimates_order_idx on price_estimates (order_id, created_at desc);
create index if not exists price_estimates_session_idx on price_estimates (session_id, created_at desc);

comment on table price_estimates is '가격 엔진이 낸 결과의 감사 로그. 근거(basis)와 engine_version 을 함께 남깁니다.';

-- -----------------------------------------------------------------------------
-- 8. RLS — 새 테이블은 service_role 전용
-- -----------------------------------------------------------------------------
alter table price_questions        enable row level security;
alter table trade_catalog          enable row level security;
alter table price_baselines        enable row level security;
alter table contractor_rate_cards  enable row level security;
alter table completed_jobs         enable row level security;
alter table price_engine_settings  enable row level security;
alter table price_estimates        enable row level security;

-- 정책을 만들지 않으므로 anon/authenticated 는 접근 불가.
-- 앱·웹은 Netlify Functions(/api/price/*)를 통해서만 읽고 씁니다.

-- -----------------------------------------------------------------------------
-- 9. orders — AI 구조화 결과와 가격 상태 (기존 컬럼과 동일한 camelCase)
-- -----------------------------------------------------------------------------
alter table orders add column if not exists "tradeId"               text;
alter table orders add column if not exists "subcategory"           text;
alter table orders add column if not exists "symptomTags"           text[];
alter table orders add column if not exists "locationLevel1"        text;
alter table orders add column if not exists "locationLevel2"        text;
alter table orders add column if not exists "propertyType"          text;
alter table orders add column if not exists "urgency"               text;
alter table orders add column if not exists "aiSummary"             text;
alter table orders add column if not exists "aiMissingFields"       text[];
alter table orders add column if not exists "aiConfidence"          numeric(4, 3);
alter table orders add column if not exists "priceEngineVersion"    text;
alter table orders add column if not exists "priceState"            text;
alter table orders add column if not exists "estimatedMin"          integer;
alter table orders add column if not exists "estimatedMax"          integer;
alter table orders add column if not exists "priceConfidenceLevel"  text;
alter table orders add column if not exists "priceEvidenceCount"    integer;
alter table orders add column if not exists "priceFactors"          text[];

comment on column orders."priceState" is 'sufficient | preliminary | insufficient. NULL 은 엔진 미실행(기존 행).';
comment on column orders."estimatedMin" is '가격 엔진 산출 범위. priceState=insufficient 면 NULL 로 둡니다.';

-- -----------------------------------------------------------------------------
-- 10. order_bids — 구조화된 입찰 내역 (기존 bid_amount 는 그대로 총액)
-- -----------------------------------------------------------------------------
alter table order_bids add column if not exists visit_fee           integer;
alter table order_bids add column if not exists labor_cost          integer;
alter table order_bids add column if not exists material_cost       integer;
alter table order_bids add column if not exists additional_cost     integer;
alter table order_bids add column if not exists additional_note     text;
alter table order_bids add column if not exists vat_included        boolean;
alter table order_bids add column if not exists estimated_hours     numeric(5, 1);
alter table order_bids add column if not exists as_period_months    integer;
alter table order_bids add column if not exists availability        text;
alter table order_bids add column if not exists site_visit_required boolean;
alter table order_bids add column if not exists work_scope_tags     text[];
alter table order_bids add column if not exists trade_id            text;
alter table order_bids add column if not exists breakdown_provided  boolean not null default false;

comment on column order_bids.bid_amount is '총 견적가. 세부 항목이 있으면 breakdown_provided=true.';
comment on column order_bids.breakdown_provided is 'false 면 총액만 입력된 입찰. 가격 엔진 가중치가 낮아집니다.';

-- -----------------------------------------------------------------------------
-- 11. 초기 공정 10종 시드 (upsert — 운영자가 수정한 값은 덮지 않도록 id 충돌 시 skip)
-- -----------------------------------------------------------------------------
insert into price_questions (id, label, input_type, options, maps_to, tag_map, affects_price, sort_order) values
  ('urgency', '언제 방문이 필요하세요?', 'single',
   '[{"value":"emergency","label":"지금 당장(긴급)"},{"value":"today","label":"오늘 안에"},{"value":"soon","label":"2~3일 안"},{"value":"normal","label":"급하지 않아요"}]',
   'urgency', '{}', true, 10),
  ('property_type', '어떤 건물인가요?', 'single',
   '[{"value":"apartment","label":"아파트"},{"value":"villa","label":"빌라·다세대"},{"value":"house","label":"단독주택"},{"value":"officetel","label":"오피스텔"},{"value":"commercial","label":"상가·매장"},{"value":"office","label":"사무실"},{"value":"other","label":"그 외"}]',
   'propertyType', '{}', true, 20),
  ('access_difficulty', '작업 공간 접근은 어떤가요?', 'single',
   '[{"value":"easy","label":"바로 접근 가능"},{"value":"tight","label":"좁거나 가구를 옮겨야 해요"},{"value":"hard","label":"철거·해체가 필요해 보여요"},{"value":"unknown","label":"잘 모르겠어요"}]',
   'accessDifficulty', '{}', true, 30),
  ('clog_severity', '물이 어떻게 내려가나요?', 'single',
   '[{"value":"slow","label":"천천히 내려가요"},{"value":"none","label":"전혀 안 내려가요"},{"value":"overflow","label":"역류해서 넘쳐요"},{"value":"unknown","label":"잘 모르겠어요"}]',
   'workScopeTags',
   '{"slow":["관통 작업","트랩 청소"],"none":["관통 작업","고압 세척","트랩 청소"],"overflow":["관통 작업","고압 세척","변기 탈착","배수관 보수"]}',
   true, 40),
  ('leak_visible', '물이 새는 곳이 눈에 보이나요?', 'single',
   '[{"value":"visible","label":"보이는 곳에서 새요"},{"value":"hidden","label":"어디서 새는지 모르겠어요"},{"value":"wall_ceiling","label":"벽·천장이 젖었어요"}]',
   'workScopeTags',
   '{"visible":["연결부 보수","배관 교체"],"hidden":["누수 탐지","장비 점검"],"wall_ceiling":["누수 탐지","부분 철거"]}',
   true, 50),
  ('fixture_supply', '기구(변기·수전 등)는 누가 준비하나요?', 'single',
   '[{"value":"contractor","label":"업체가 준비"},{"value":"customer","label":"제가 준비했어요"},{"value":"unknown","label":"잘 모르겠어요"}]',
   'materialIncluded', '{}', true, 60),
  ('area_size', '보수할 면적이 대략 어느 정도인가요?', 'single',
   '[{"value":"spot","label":"한 지점만"},{"value":"under_3sqm","label":"3㎡ 이하"},{"value":"over_3sqm","label":"3㎡ 이상"},{"value":"unknown","label":"잘 모르겠어요"}]',
   'workScopeTags',
   '{"spot":["균열 보수","실리콘 재시공"],"under_3sqm":["균열 보수","우레탄 도포","기존 실리콘 제거","실리콘 재시공"],"over_3sqm":["우레탄 도포","프라이머 시공","기존 실리콘 제거"]}',
   true, 70),
  ('symptom_started', '언제부터 그런가요?', 'single',
   '[{"value":"today","label":"오늘부터"},{"value":"few_days","label":"2~3일 전"},{"value":"week_plus","label":"일주일 이상"},{"value":"unknown","label":"잘 모르겠어요"}]',
   null, '{}', false, 80),
  ('photos', '현장 사진을 올려주실 수 있나요?', 'photo', '[]', null, '{}', false, 90),
  ('prior_repair', '전에 같은 곳을 수리한 적이 있나요?', 'single',
   '[{"value":"yes","label":"있어요"},{"value":"no","label":"없어요"},{"value":"unknown","label":"잘 모르겠어요"}]',
   'workScopeTags', '{"yes":["부분 철거","배수관 보수"],"no":[]}', true, 100)
on conflict (id) do nothing;

insert into trade_catalog (
  id, category, subcategory, aliases, symptom_tags, work_scope_tags,
  required_questions, optional_questions, price_factors,
  base_labor_min, base_labor_typical, base_labor_max,
  material_included_by_default, visit_fee_applies, visit_fee_typical,
  urgency_surcharge_applies, urgency_multipliers,
  sanity_min, sanity_max, sufficient_completed_jobs, preliminary_min_samples, sort_order
) values
  ('plumbing.toilet_clog', '배관', '변기 막힘',
   '{변기막힘,변기 막힘,변기 뚫기,양변기 막힘}', '{배수 지연,역류,악취}', '{관통 작업,변기 탈착,고압 세척}',
   '{clog_severity,urgency,property_type}', '{photos,prior_repair,access_difficulty}',
   '{출장비,기본 작업비,변기 탈착 여부,고압 세척 장비,야간·긴급 작업}',
   50000, 80000, 150000, false, true, 15000, true, '{"emergency":1.4,"today":1.15}',
   20000, 800000, 8, 3, 10),

  ('plumbing.sink_clog', '배관', '싱크대 막힘',
   '{싱크대막힘,싱크 막힘,주방 싱크 막힘}', '{배수 지연,악취,배수 정체}', '{관통 작업,트랩 청소,고압 세척}',
   '{clog_severity,urgency,property_type}', '{photos,prior_repair,access_difficulty}',
   '{출장비,기본 작업비,트랩 교체,고압 세척 장비,야간·긴급 작업}',
   50000, 80000, 150000, false, true, 15000, true, '{"emergency":1.4,"today":1.15}',
   20000, 800000, 8, 3, 20),

  ('bath.washbasin_faucet_replace', '화장실', '세면대·수전 교체',
   '{세면대 교체,수전 교체,수도꼭지 교체}', '{누수,노후,파손}', '{기구 교체,수전 교체,실리콘 마감}',
   '{fixture_supply,urgency,property_type}', '{photos,access_difficulty}',
   '{출장비,기본 작업비,자재비(기구),기존 기구 철거,실리콘 마감,부가세 포함 여부}',
   60000, 100000, 180000, false, true, 15000, true, '{"emergency":1.3,"today":1.1}',
   30000, 1500000, 8, 3, 30),

  ('bath.shower_replace', '화장실', '샤워기 교체',
   '{샤워기 교체,샤워수전 교체,해바라기 교체}', '{누수,수압 저하,노후}', '{기구 교체,수전 교체,실리콘 마감}',
   '{fixture_supply,urgency,property_type}', '{photos,access_difficulty}',
   '{출장비,기본 작업비,자재비(기구),벽체 타일 손상 위험,부가세 포함 여부}',
   50000, 80000, 150000, false, true, 15000, true, '{"emergency":1.3,"today":1.1}',
   25000, 1000000, 8, 3, 40),

  ('plumbing.drain_clog_basic', '배관', '단순 배관 막힘',
   '{배관 막힘,하수구 막힘,배수구 막힘}', '{배수 지연,악취,역류}', '{관통 작업,고압 세척,트랩 청소}',
   '{clog_severity,urgency,property_type}', '{photos,access_difficulty,prior_repair}',
   '{출장비,기본 작업비,관통 길이,고압 세척 장비,야간·긴급 작업}',
   50000, 90000, 200000, false, true, 15000, true, '{"emergency":1.4,"today":1.15}',
   20000, 1000000, 8, 3, 50),

  ('leak.detection', '누수', '누수 탐지',
   '{누수탐지,누수 탐지,누수 검사}', '{천장 누수,벽체 누수,수도 요금 급증}', '{누수 탐지,장비 점검,부분 철거}',
   '{leak_visible,urgency,property_type}', '{photos,access_difficulty,symptom_started}',
   '{출장비,탐지 장비비,탐지 범위,부분 철거 필요,후속 보수 별도}',
   100000, 180000, 350000, false, true, 20000, true, '{"emergency":1.35,"today":1.15}',
   50000, 1500000, 6, 3, 60),

  ('waterproof.silicone_caulking', '방수', '실리콘·코킹 보수',
   '{실리콘 재시공,코킹,줄눈 보수}', '{곰팡이,들뜸,틈새}', '{기존 실리콘 제거,실리콘 재시공,곰팡이 제거}',
   '{area_size,urgency,property_type}', '{photos,access_difficulty}',
   '{출장비,기본 작업비,시공 길이,기존 실리콘 제거,자재비}',
   50000, 90000, 200000, true, true, 15000, false, '{}',
   20000, 1200000, 8, 3, 70),

  ('waterproof.small_repair', '방수', '소규모 방수 보수',
   '{부분 방수,방수 보수,우레탄 보수}', '{빗물 유입,균열,들뜸}', '{균열 보수,우레탄 도포,프라이머 시공}',
   '{area_size,urgency,property_type}', '{photos,access_difficulty,symptom_started}',
   '{출장비,기본 작업비,시공 면적,자재비(우레탄),날씨·건조 시간,부가세 포함 여부}',
   150000, 350000, 800000, true, true, 20000, false, '{}',
   50000, 5000000, 6, 3, 80),

  ('plumbing.pipe_leak_repair', '배관', '배관 누수 보수',
   '{배관 누수,수도관 누수,배관 보수}', '{누수,천장 누수,수압 저하}', '{배관 교체,부분 철거,연결부 보수}',
   '{leak_visible,urgency,property_type}', '{photos,access_difficulty,prior_repair}',
   '{출장비,기본 작업비,부분 철거·복구,자재비(배관),작업 난이도,야간·긴급 작업}',
   100000, 200000, 500000, false, true, 20000, true, '{"emergency":1.4,"today":1.2}',
   50000, 3000000, 6, 3, 90),

  ('kitchen.drain_issue', '주방', '주방 배수 문제',
   '{주방 배수,싱크 배수 불량,주방 하수}', '{배수 지연,악취,누수}', '{트랩 교체,관통 작업,배수관 보수}',
   '{clog_severity,urgency,property_type}', '{photos,access_difficulty,prior_repair}',
   '{출장비,기본 작업비,트랩·배수관 자재,싱크 하부 철거,야간·긴급 작업}',
   50000, 90000, 200000, false, true, 15000, true, '{"emergency":1.4,"today":1.15}',
   20000, 1000000, 8, 3, 100)
on conflict (id) do nothing;

-- 운영자 초기 기준표: 카탈로그 기본 작업비 + 출장비 기준으로 전국 단일 값 생성.
-- 운영자가 나중에 수정하면 그 값이 유지됩니다 (충돌 시 skip).
insert into price_baselines (trade_id, region_level1, property_type, min_amount, typical_amount, max_amount, material_included, vat_included, note, updated_by)
select
  t.id,
  null,
  null,
  t.base_labor_min + t.visit_fee_typical,
  t.base_labor_typical + t.visit_fee_typical,
  t.base_labor_max + t.visit_fee_typical,
  t.material_included_by_default,
  false,
  '초기 시드 (실거래 데이터 확보 후 운영자 검토 필요)',
  'seed:price_engine_v1'
from trade_catalog t
on conflict do nothing;

insert into price_engine_settings (key, value, note) values
  ('thresholds', '{
     "sufficientCompletedJobs": 8,
     "sufficientWeightedEvidence": 12,
     "preliminaryMinSamples": 3,
     "maxSampleAgeDays": 540,
     "preliminaryWidenRatio": 0.18,
     "roundToWon": 1000
   }'::jsonb, '데이터 충분성 임계값'),
  ('weights', '{
     "completedJob": 1.0,
     "contractorBid": 0.55,
     "rateCard": 0.35,
     "baseline": 0.2,
     "bidWithoutBreakdown": 0.7,
     "regionExact": 1.0,
     "regionLevel1": 0.85,
     "regionMismatch": 0.6,
     "propertyMatch": 1.0,
     "propertyMismatch": 0.85
   }'::jsonb, '표본 가중치'),
  ('outliers', '{ "iqrMultiplier": 1.5, "iqrMinSamples": 8, "madMultiplier": 3.5, "madMinSamples": 5 }'::jsonb,
   '이상치 제거 파라미터')
on conflict (key) do nothing;

-- =============================================================================
-- 확인용
-- =============================================================================
-- select id, category, subcategory, active from trade_catalog order by sort_order;
-- select key, value from price_engine_settings;
-- select count(*) from completed_jobs;
