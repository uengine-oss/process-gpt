-- Earlier turns of a context, folded into keywords each time its summary is replaced, so a
-- long-running conversation stays findable without keeping its history.
alter table public.context_threads add column if not exists gist text default '';
