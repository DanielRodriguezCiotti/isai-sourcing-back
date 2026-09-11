-- ---------------------------------------------------------------------------
-- List folders.
-- Same pattern as view_folders.sql: folders are organizational only, not
-- access control — every folder is visible to everyone. One folder per list,
-- deleting a folder ungroups its lists rather than deleting them.
-- Idempotent: safe to run multiple times.
-- ---------------------------------------------------------------------------

create table if not exists public.list_folders (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  kind       text not null default 'personal' check (kind in ('team', 'personal')),
  sort_order int  not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Attach saved lists to a folder. null folder_id = "no folder" (top level).
-- on delete set null: deleting a folder keeps its lists (they become ungrouped).
alter table public.saved_lists
  add column if not exists folder_id uuid
  references public.list_folders(id) on delete set null;

create index if not exists saved_lists_folder_id_idx
  on public.saved_lists (folder_id);

-- Row-level security: mirror saved_lists/view_folders (full access for authenticated users).
-- Without a policy, RLS-enabled tables deny everything.
alter table public.list_folders enable row level security;
drop policy if exists "Allow all for authenticated" on public.list_folders;
create policy "Allow all for authenticated"
  on public.list_folders
  for all
  to authenticated
  using (true)
  with check (true);
