-- Private abuse-control table: one report per signed-in anonymous user per UTC day.
-- Contains ONLY Supabase user ID and day; no personal measurements, notes or GPS.
create table if not exists public.oranaplo_report_daily (
    user_id uuid not null references auth.users(id) on delete cascade,
    day_utc date not null,
    primary key (user_id, day_utc)
);
alter table public.oranaplo_report_daily enable row level security;
revoke all on public.oranaplo_report_daily from anon;
grant insert, select on public.oranaplo_report_daily to authenticated;
revoke delete, update on public.oranaplo_report_daily from authenticated;
drop policy if exists "own bug report quota insert" on public.oranaplo_report_daily;
create policy "own bug report quota insert" on public.oranaplo_report_daily
 for insert to authenticated with check (user_id=(select auth.uid()) and day_utc=(now() at time zone 'utc')::date);
drop policy if exists "own bug report quota select" on public.oranaplo_report_daily;
create policy "own bug report quota select" on public.oranaplo_report_daily
 for select to authenticated using (user_id=(select auth.uid()));
drop policy if exists "own bug report quota delete" on public.oranaplo_report_daily;
-- Clients cannot remove their own quota. Only the authenticated Edge Function's
-- service-role client may release it when the mail provider returns an error.
-- Protect the anonymous signup endpoint with project-level CAPTCHA and rate limits.
