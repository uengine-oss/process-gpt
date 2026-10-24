-- Contexts the router has seen for each user: one row per conversation it routed to.
-- The router reads the most recent ones as candidates for the next message.
create table if not exists public.context_threads (
  tenant_id text not null,
  user_id text not null,
  conversation_id text not null,
  title text not null,
  summary text default '',
  kind text default 'conversation',
  turns int default 0,
  updated_at timestamptz default now(),
  created_at timestamptz default now(),
  primary key (tenant_id, user_id, conversation_id)
);
create index if not exists context_threads_recent on public.context_threads (tenant_id, user_id, updated_at desc);
grant select, insert, update, delete on public.context_threads to service_role;
