-- Personal Accounting — initial Supabase schema.
-- Paste the entire file into Supabase Dashboard → SQL Editor → New Query → Run.
-- Safe to re-run: every CREATE uses IF NOT EXISTS, every POLICY drops first.

-- ─────────────────────────────────────────────────────────────────────────────
-- Tables
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.categories (
  id          text primary key,
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name        text not null,
  icon_code   text not null default 'shopping_bag',
  color_code  bigint not null default 4288585374,  -- 0xFF9E9E9E (neutral grey)
  created_at  timestamptz not null default now()
);

create table if not exists public.merchants (
  id          text primary key,
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name        text not null,
  created_at  timestamptz not null default now()
);

create table if not exists public.costs (
  id            text primary key,
  user_id       uuid not null default auth.uid() references auth.users(id) on delete cascade,
  amount        double precision not null,
  date          timestamptz not null,
  category_id   text not null references public.categories(id) on delete restrict,
  merchant_id   text not null references public.merchants(id) on delete restrict,
  created_at    timestamptz not null default now()
);

create index if not exists idx_costs_user_date on public.costs(user_id, date desc);
create index if not exists idx_costs_user_category on public.costs(user_id, category_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- Row-Level Security
-- Every row carries its owner's auth.uid(); a user only ever sees their own.
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.categories enable row level security;
alter table public.merchants  enable row level security;
alter table public.costs      enable row level security;

drop policy if exists "own categories select" on public.categories;
drop policy if exists "own categories write"  on public.categories;
drop policy if exists "own merchants select"  on public.merchants;
drop policy if exists "own merchants write"   on public.merchants;
drop policy if exists "own costs select"      on public.costs;
drop policy if exists "own costs write"       on public.costs;

create policy "own categories select" on public.categories
  for select using (user_id = auth.uid());
create policy "own categories write" on public.categories
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "own merchants select" on public.merchants
  for select using (user_id = auth.uid());
create policy "own merchants write" on public.merchants
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "own costs select" on public.costs
  for select using (user_id = auth.uid());
create policy "own costs write" on public.costs
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
