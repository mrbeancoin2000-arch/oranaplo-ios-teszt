-- ÓraNapló public leaderboard – never store GPS positions, DOB, heart rate or Google IDs.
-- Execute in the chosen Supabase project SQL editor after enabling anonymous sign-ins.
-- Any user can self-report values; rankings are NOT verified without trusted server attestation.

create table if not exists public.oranaplo_rankings (
    user_id uuid primary key references auth.users(id) on delete cascade,
    display_name text not null check (char_length(display_name) between 3 and 24 and position(chr(10) in display_name)=0),
    total_steps bigint not null default 0 check (total_steps between 0 and 1000000000000),
    longest_run_m double precision not null default 0 check (longest_run_m >= 0 and longest_run_m < 1000000),
    published boolean not null default false,
    updated_at timestamptz not null default now()
);

alter table public.oranaplo_rankings enable row level security;
revoke all on public.oranaplo_rankings from anon;
grant select,insert,update,delete on public.oranaplo_rankings to authenticated;

-- The application signs in anonymously through Supabase Auth, obtaining a unique JWT.
-- Read ONLY explicitly published rows, and your own (including hidden) record.
drop policy if exists "published leaderboard read" on public.oranaplo_rankings;
create policy "published leaderboard read" on public.oranaplo_rankings
 for select to authenticated using (published=true or user_id=(select auth.uid()));

drop policy if exists "owner leaderboard insert" on public.oranaplo_rankings;
create policy "owner leaderboard insert" on public.oranaplo_rankings
 for insert to authenticated with check (user_id=(select auth.uid()));

drop policy if exists "owner leaderboard update" on public.oranaplo_rankings;
create policy "owner leaderboard update" on public.oranaplo_rankings
 for update to authenticated
 using (user_id=(select auth.uid()))
 with check (user_id=(select auth.uid()));

drop policy if exists "owner leaderboard delete" on public.oranaplo_rankings;
create policy "owner leaderboard delete" on public.oranaplo_rankings
 for delete to authenticated using (user_id=(select auth.uid()));

create index if not exists oranaplo_step_public on public.oranaplo_rankings(total_steps desc) where published=true;
create index if not exists oranaplo_run_public on public.oranaplo_rankings(longest_run_m desc) where published=true;

-- IMPORTANT for launch:
-- 1. Configure rate limiting and bot protection in Supabase Auth / API gateway.
-- 2. Client-sent step/run totals are NOT authenticated sport results. Never claim otherwise.
-- 3. Private medical records belong ONLY to the user's Google Sheet, not this table.
-- 4. Users must explicitly publish; DELETE removes their ranking row.
