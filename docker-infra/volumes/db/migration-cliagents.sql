-- cliagents 오케스트레이션: 실행 CLI·모델·권한 설정 전달 컬럼
--
-- 오케스트레이션마다 필요한 설정이 다르므로 컬럼을 3개 늘리지 않고 하나의
-- jsonb 로 싣는다. 프로세스 정의의 activity.agentConfig 가 엔진을 거쳐 이 컬럼에
-- 들어오고, cliagents 서비스가 실행 시점에 읽는다.
--
-- 형태: {"agent_cli": "claude-code" | "codex",
--        "model": "<선택, 비우면 CLI 기본값>",
--        "permission": "read_only" | "workspace_write" | "command_exec"}
--
-- nullable 이므로 기존 워크아이템과 다른 오케스트레이션에는 영향이 없다.
alter table if exists public.todolist
    add column if not exists agent_config jsonb null;

comment on column public.todolist.agent_config is
    'cliagents 등 오케스트레이션별 실행 설정(CLI 종류·모델·권한). activity.agentConfig 에서 전달된다.';
