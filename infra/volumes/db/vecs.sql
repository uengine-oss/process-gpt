-- ==========================================
-- Mem0 vector store 함수 (vecs 스키마)
-- ※ vecs 스키마가 있는 경우에만 아래 함수 생성 쿼리들을 실행하세요
-- ==========================================
-- 조회 (agent_id 필터링 + limit)
create or replace function public.get_memories(agent text, lim int default 100)
returns setof vecs.memories
language sql stable
security definer
as $$
  select *
  from vecs.memories
  where (agent is null or metadata->>'agent_id' = agent)
  order by id
  limit lim;
$$;

-- 단일 행 삭제
create or replace function public.delete_memory(mem_id text)
returns void
language sql volatile
security definer
as $$
  delete from vecs.memories where id = mem_id;
$$;

-- 특정 agent_id의 모든 메모리 삭제
create or replace function public.delete_memories_by_agent(agent text)
returns void
language sql volatile
security definer
as $$
  delete from vecs.memories where metadata->>'agent_id' = agent;
$$;

