-- ÓraNapló v0.8.0: fail-closed invite graph and Apple offer-code allocation.
-- Run AFTER configuring Supabase Auth Sign in with Apple. No health or Google data here.
-- Do NOT add service_role or App Store private keys to the iPhone app.
create extension if not exists pgcrypto;

create table if not exists public.oranaplo_referral_accounts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  invite_code text not null unique default upper(substring(replace(gen_random_uuid()::text, '-', '') from 1 for 12)),
  created_at timestamptz not null default now(),
  constraint oranaplo_refcode_pattern check (invite_code ~ '^[A-F0-9]{12}$')
);
create table if not exists public.oranaplo_referral_claims (
  id uuid primary key default gen_random_uuid(),
  inviter_id uuid not null unique references public.oranaplo_referral_accounts(user_id) on delete cascade,
  invitee_id uuid not null unique references public.oranaplo_referral_accounts(user_id) on delete cascade,
  state text not null default 'pending' check (state in ('pending','verified','revoked')),
  created_at timestamptz not null default now(),
  verified_at timestamptz,
  invitee_discount_ends_at timestamptz,
  constraint oranaplo_no_self_referral check(inviter_id <> invitee_id)
);
create table if not exists public.oranaplo_referral_grants (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.oranaplo_referral_accounts(user_id) on delete cascade,
  claim_id uuid not null references public.oranaplo_referral_claims(id) on delete cascade,
  role text not null check (role in ('invitee','inviter')),
  state text not null default 'pending_code' check (state in ('pending_code','assigned','redeemed','revoked')),
  apple_transaction_id text unique,
  created_at timestamptz not null default now(),
  unique (user_id, role),
  unique (claim_id, role)
);
create table if not exists public.oranaplo_referral_offer_inventory (
  code text primary key,
  grant_id uuid unique references public.oranaplo_referral_grants(id),
  created_at timestamptz not null default now(),
  assigned_at timestamptz
);
-- Real App Store Connect offer codes are seeded here by an operator, never fabricated in-app.
-- Example ADMIN ONLY: insert into public.oranaplo_referral_offer_inventory(code) values ('REAL_APPLE_CODE');

alter table public.oranaplo_referral_accounts enable row level security;
alter table public.oranaplo_referral_claims enable row level security;
alter table public.oranaplo_referral_grants enable row level security;
alter table public.oranaplo_referral_offer_inventory enable row level security;
revoke all on public.oranaplo_referral_accounts, public.oranaplo_referral_claims, public.oranaplo_referral_grants, public.oranaplo_referral_offer_inventory from anon, authenticated;

create or replace function public.oranaplo_referral_register()
returns text language plpgsql security definer set search_path = '' as $$
declare me uuid := auth.uid(); mycode text;
begin
  if me is null or coalesce(auth.jwt()->>'is_anonymous','true') = 'true' then
    raise exception 'verified_account_required' using errcode='42501';
  end if;
  -- A real Apple-ID-backed Supabase account is required; anonymous leaderboard auth is insufficient.
  if not exists(select 1 from auth.identities i where i.user_id=me and i.provider='apple') then
    raise exception 'apple_sign_in_required' using errcode='42501';
  end if;
  insert into public.oranaplo_referral_accounts(user_id) values(me)
  on conflict(user_id) do nothing;
  select invite_code into mycode from public.oranaplo_referral_accounts where user_id=me;
  return mycode;
end $$;

create or replace function public.oranaplo_referral_redeem(the_code text)
returns text language plpgsql security definer set search_path = '' as $$
declare me uuid := auth.uid(); sponsor uuid; newclaim uuid; signup timestamptz;
begin
  perform public.oranaplo_referral_register();
  if the_code is null or upper(trim(the_code)) !~ '^[A-F0-9]{12}$' then
    raise exception 'invalid_code';
  end if;
  -- Exactly once and at FIRST ACCOUNT REGISTRATION, not per install.
  select u.created_at into signup from auth.users u where u.id=me;
  if signup is null or now() > signup + interval '24 hours' then
    raise exception 'first_registration_only';
  end if;
  select a.user_id into sponsor from public.oranaplo_referral_accounts a
    where a.invite_code=upper(trim(the_code));
  if sponsor is null then raise exception 'code_not_found'; end if;
  if sponsor=me then raise exception 'self_invite_not_allowed'; end if;
  if exists(select 1 from public.oranaplo_referral_claims c where c.invitee_id=me) then
    raise exception 'invitee_already_claimed';
  end if;
  if exists(select 1 from public.oranaplo_referral_claims c where c.inviter_id=sponsor) then
    raise exception 'inviter_reward_already_used';
  end if;
  -- Chain rule: a previously invited person may invite only AFTER their
  -- original discounted year has ended and the first purchase is verified.
  if exists(select 1 from public.oranaplo_referral_claims c where c.invitee_id=sponsor
             and (c.state<>'verified' or c.invitee_discount_ends_at is null
                  or c.invitee_discount_ends_at > now())) then
    raise exception 'inviter_must_finish_discounted_year';
  end if;
  -- Collision protection is also enforced by the two UNIQUE constraints.
  insert into public.oranaplo_referral_claims(inviter_id,invitee_id) values(sponsor,me)
  returning id into newclaim;
  insert into public.oranaplo_referral_grants(user_id,claim_id,role)
    values(me,newclaim,'invitee');
  return 'pending_apple_offer';
end $$;

create or replace function public.oranaplo_referral_status()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare me uuid := auth.uid(); c text; claim_state text; invitee_state text; reward_state text; yr_end timestamptz;
begin
  c := public.oranaplo_referral_register();
  select x.state,x.invitee_discount_ends_at into claim_state,yr_end
    from public.oranaplo_referral_claims x where x.invitee_id=me;
  select g.state into invitee_state from public.oranaplo_referral_grants g
    where g.user_id=me and g.role='invitee';
  select g.state into reward_state from public.oranaplo_referral_grants g
    where g.user_id=me and g.role='inviter';
  return jsonb_build_object('invite_code',c, 'claim_state',coalesce(claim_state,'none'),
    'invitee_offer',coalesce(invitee_state,'none'), 'inviter_offer',coalesce(reward_state,'none'),
    'discount_year_end',yr_end,
    'can_invite', not exists(select 1 from public.oranaplo_referral_claims x where x.inviter_id=me)
       and (claim_state is null or (claim_state='verified' and yr_end <= now())));
end $$;

-- User may allocate only THEIR OWN valid grant, never another user's code.
create or replace function public.oranaplo_referral_get_offer()
returns text language plpgsql security definer set search_path = '' as $$
declare me uuid := auth.uid(); mygrant uuid; usedcode text;
begin
  perform public.oranaplo_referral_register();
  select g.id into mygrant from public.oranaplo_referral_grants g
   where g.user_id=me and g.state in ('pending_code','assigned')
   order by g.created_at limit 1 for update;
  if mygrant is null then return null; end if;
  select o.code into usedcode from public.oranaplo_referral_offer_inventory o where o.grant_id=mygrant;
  if usedcode is not null then return usedcode; end if;
  select o.code into usedcode from public.oranaplo_referral_offer_inventory o
     where o.grant_id is null order by o.created_at for update skip locked limit 1;
  if usedcode is null then return null; end if;
  update public.oranaplo_referral_offer_inventory set grant_id=mygrant, assigned_at=now() where code=usedcode;
  update public.oranaplo_referral_grants set state='assigned' where id=mygrant;
  return usedcode;
end $$;

-- Only callable from VERIFIED Apple signed transaction processing on trusted server.
-- No public HTTP endpoint is allowed to mark payment verified based on client claims.
create or replace function public.oranaplo_referral_confirm_verified_purchase(
  purchased_user uuid, verified_transaction_id text, verified_expires_at timestamptz)
returns boolean language plpgsql security definer set search_path = '' as $$
declare linked_claim public.oranaplo_referral_claims%rowtype; user_grant uuid;
begin
  if current_setting('request.jwt.claim.role', true) is distinct from 'service_role' then
    raise exception 'server_only' using errcode='42501';
  end if;
  if purchased_user is null or verified_transaction_id is null or length(verified_transaction_id)<5
     or verified_expires_at is null or verified_expires_at<=now() then
    raise exception 'unverified_transaction_details';
  end if;
  select * into linked_claim from public.oranaplo_referral_claims
     where invitee_id=purchased_user and state='pending' for update;
  if linked_claim.id is null then return false; end if;
  select id into user_grant from public.oranaplo_referral_grants
     where claim_id=linked_claim.id and user_id=purchased_user and role='invitee' and state='assigned' for update;
  if user_grant is null then return false; end if;
  update public.oranaplo_referral_grants set state='redeemed',apple_transaction_id=verified_transaction_id where id=user_grant;
  update public.oranaplo_referral_claims set state='verified',verified_at=now(),
       invitee_discount_ends_at=verified_expires_at where id=linked_claim.id;
  insert into public.oranaplo_referral_grants(user_id,claim_id,role)
       values(linked_claim.inviter_id,linked_claim.id,'inviter')
       on conflict do nothing;
  return true;
end $$;

revoke all on function public.oranaplo_referral_confirm_verified_purchase(uuid,text,timestamptz) from public,anon,authenticated;
grant execute on function public.oranaplo_referral_confirm_verified_purchase(uuid,text,timestamptz) to service_role;
revoke all on function public.oranaplo_referral_register() from public, anon;
revoke all on function public.oranaplo_referral_redeem(text) from public, anon;
revoke all on function public.oranaplo_referral_status() from public, anon;
revoke all on function public.oranaplo_referral_get_offer() from public, anon;
grant execute on function public.oranaplo_referral_register() to authenticated;
grant execute on function public.oranaplo_referral_redeem(text) to authenticated;
grant execute on function public.oranaplo_referral_status() to authenticated;
grant execute on function public.oranaplo_referral_get_offer() to authenticated;
