-- ============================================================================
-- 핫 테이블 인덱스
--
-- chats / chat_rooms / todolist / bpm_proc_inst 에는 PK 외 인덱스가 하나도 없다.
-- 조회 패턴은 openspec/changes/frontend-query-performance/design.md 5장 참고.
--
-- 적용:
--   Supabase 대시보드 → SQL Editor 에 붙여넣어 실행하거나
--   psql "$DATABASE_URL" -f docker-infra/volumes/db/indexes-hot-tables.sql
--
-- CONCURRENTLY 는 테이블을 잠그지 않으므로 운영 중에도 안전하다.
-- 단, 트랜잭션 블록 안에서는 실행할 수 없다(한 문장씩 실행할 것).
-- 이미 있으면 건너뛴다(IF NOT EXISTS).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- chats — 채팅방을 열 때마다 쓰이는 경로. 지금은 전체 스캔 + JSONB 표현식 정렬이다.
--   SELECT * FROM chats WHERE id = $1 ORDER BY messages->>'timeStamp' DESC
-- ---------------------------------------------------------------------------

-- 방 id 로 좁히기 (현재 인덱스 없음 → seq scan)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_chats_id
    ON public.chats (id);

-- 방 id + 시간 정렬을 한 번에. messages->>'timeStamp' 는 표현식이라
-- 일반 컬럼 인덱스로는 정렬을 못 탄다. 표현식 인덱스가 필요하다.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_chats_room_ts
    ON public.chats (id, ((messages ->> 'timeStamp')) DESC);

-- 테넌트 스코프 조회용
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_chats_tenant
    ON public.chats (tenant_id);

-- ---------------------------------------------------------------------------
-- chat_rooms — 사이드바 방 목록 (tenant_id 로 필터)
-- ---------------------------------------------------------------------------
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_chat_rooms_tenant
    ON public.chat_rooms (tenant_id);

-- ---------------------------------------------------------------------------
-- todolist — 할일 목록 (tenant + 담당자, updated_at 정렬)
-- ---------------------------------------------------------------------------
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_todolist_tenant_updated
    ON public.todolist (tenant_id, updated_at DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_todolist_user
    ON public.todolist (user_id);

-- ---------------------------------------------------------------------------
-- bpm_proc_inst — 인스턴스 목록 (tenant + start_date 내림차순)
-- ---------------------------------------------------------------------------
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_inst_tenant_start
    ON public.bpm_proc_inst (tenant_id, start_date DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_inst_status
    ON public.bpm_proc_inst (tenant_id, status);

-- ---------------------------------------------------------------------------
-- proc_def — (id, tenant_id) 유니크는 이미 있다. 목록은 tenant + isdeleted 로 좁힌다.
-- ---------------------------------------------------------------------------
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_proc_def_tenant_visible
    ON public.proc_def (tenant_id, isdeleted);

-- ---------------------------------------------------------------------------
-- 적용 후 확인
-- ---------------------------------------------------------------------------
-- SELECT tablename, indexname FROM pg_indexes
--  WHERE schemaname = 'public'
--    AND tablename IN ('chats','chat_rooms','todolist','bpm_proc_inst','proc_def')
--  ORDER BY tablename, indexname;
