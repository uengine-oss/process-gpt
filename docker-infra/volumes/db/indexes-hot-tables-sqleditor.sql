-- ============================================================================
-- 핫 테이블 인덱스 — Supabase 대시보드 SQL Editor 붙여넣기용
--
-- CONCURRENTLY 를 뺀 버전이다. SQL Editor 는 문장을 트랜잭션으로 감싸는 경우가 있어
-- CONCURRENTLY 가 "cannot run inside a transaction block" 으로 거부된다.
--
-- 잠금 걱정은 하지 않아도 된다. 2026-08 기준 uengine 테넌트 실측 크기가 작다:
--   chats 7,575행 / chat_rooms 617행 / proc_def 325행
-- 이 규모면 인덱스 생성 잠금은 밀리초 단위다.
--
-- 테이블이 크게 자란 뒤에 다시 걸 일이 있으면 indexes-hot-tables.sql(CONCURRENTLY 판)을
-- psql 로 실행할 것.
--
-- 전체를 한 번에 실행해도 되고, 한 문장씩 실행해도 된다. 이미 있으면 건너뛴다.
-- ============================================================================

-- chats — 채팅방 열 때마다 타는 경로.
-- 지금은 방 id 인덱스가 없어 전체 스캔 + JSONB 표현식 정렬이다.
-- 실측: 정렬 있음 190ms vs 정렬 없음 51ms (47건짜리 방 기준)
CREATE INDEX IF NOT EXISTS idx_chats_id
    ON public.chats (id);

CREATE INDEX IF NOT EXISTS idx_chats_room_ts
    ON public.chats (id, ((messages ->> 'timeStamp')) DESC);

CREATE INDEX IF NOT EXISTS idx_chats_tenant
    ON public.chats (tenant_id);

-- chat_rooms — 사이드바 방 목록
CREATE INDEX IF NOT EXISTS idx_chat_rooms_tenant
    ON public.chat_rooms (tenant_id);

-- todolist — 할일 목록
CREATE INDEX IF NOT EXISTS idx_todolist_tenant_updated
    ON public.todolist (tenant_id, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_todolist_user
    ON public.todolist (user_id);

-- bpm_proc_inst — 인스턴스 목록
CREATE INDEX IF NOT EXISTS idx_inst_tenant_start
    ON public.bpm_proc_inst (tenant_id, start_date DESC);

CREATE INDEX IF NOT EXISTS idx_inst_status
    ON public.bpm_proc_inst (tenant_id, status);

-- proc_def — (id, tenant_id) 유니크는 이미 있다. 목록은 tenant + isdeleted 로 좁힌다.
CREATE INDEX IF NOT EXISTS idx_proc_def_tenant_visible
    ON public.proc_def (tenant_id, isdeleted);


-- ---------------------------------------------------------------------------
-- 적용 확인 (위 실행 후 이것만 따로 돌려서 9개가 보이면 성공)
-- ---------------------------------------------------------------------------
-- SELECT tablename, indexname
--   FROM pg_indexes
--  WHERE schemaname = 'public'
--    AND indexname LIKE 'idx_%'
--    AND tablename IN ('chats','chat_rooms','todolist','bpm_proc_inst','proc_def')
--  ORDER BY tablename, indexname;
