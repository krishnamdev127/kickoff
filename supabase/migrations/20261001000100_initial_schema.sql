-- KickOff initial shared-data schema. Apply to a Supabase project after reviewing.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 60),
  avatar_url text,
  bio text check (char_length(coalesce(bio,'')) <= 240),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.games (
  id uuid primary key default gen_random_uuid(),
  organizer_id uuid not null references auth.users(id) on delete cascade,
  sport text not null check (sport in ('football','basketball','badminton','running','tennis','volleyball','other')),
  title text not null check (char_length(title) between 3 and 90),
  venue_name text not null check (char_length(venue_name) between 2 and 120),
  venue_lat double precision,
  venue_lng double precision,
  starts_at timestamptz not null,
  duration_minutes integer not null default 90 check (duration_minutes between 15 and 600),
  max_players integer not null check (max_players between 2 and 100),
  skill_level text not null default 'all' check (skill_level in ('beginner','intermediate','advanced','all')),
  status text not null default 'open' check (status in ('open','filled','starting_soon','live','completed','cancelled','archived')),
  description text check (char_length(coalesce(description,'')) <= 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.game_members (
  game_id uuid not null references public.games(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  membership_status text not null default 'joined' check (membership_status in ('joined','waitlisted','left')),
  joined_at timestamptz not null default now(),
  primary key (game_id,user_id)
);

create table if not exists public.game_messages (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);

create index if not exists games_starts_at_idx on public.games(starts_at);
create index if not exists games_status_starts_idx on public.games(status,starts_at);
create index if not exists game_members_user_idx on public.game_members(user_id,membership_status);
create index if not exists game_messages_game_created_idx on public.game_messages(game_id,created_at);

alter table public.profiles enable row level security;
alter table public.games enable row level security;
alter table public.game_members enable row level security;
alter table public.game_messages enable row level security;

create policy "Profiles are viewable by signed-in users" on public.profiles for select to authenticated using (true);
create policy "Users insert own profile" on public.profiles for insert to authenticated with check ((select auth.uid()) = id);
create policy "Users update own profile" on public.profiles for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

create policy "Signed-in users can view non-cancelled games" on public.games for select to authenticated using (status <> 'cancelled');
create policy "Organizer creates own games" on public.games for insert to authenticated with check ((select auth.uid()) = organizer_id);
create policy "Organizer updates own games" on public.games for update to authenticated using ((select auth.uid()) = organizer_id) with check ((select auth.uid()) = organizer_id);
create policy "Organizer deletes own games" on public.games for delete to authenticated using ((select auth.uid()) = organizer_id);

create policy "Members visible to signed-in users" on public.game_members for select to authenticated using (true);
-- Membership writes are intentionally restricted to the capacity-safe RPCs below.

create policy "Game members can read chat" on public.game_messages for select to authenticated using (
 exists (select 1 from public.game_members m where m.game_id = game_messages.game_id and m.user_id = (select auth.uid()) and m.membership_status = 'joined')
);
create policy "Joined members can send chat" on public.game_messages for insert to authenticated with check (
 (select auth.uid()) = user_id and exists (select 1 from public.game_members m where m.game_id = game_messages.game_id and m.user_id = (select auth.uid()) and m.membership_status = 'joined')
);

-- Capacity-safe join: row lock serializes joins for a given game. Waitlist is FIFO by joined_at.
create or replace function public.join_game(p_game_id uuid)
returns text language plpgsql security definer set search_path = ''
as $$
declare g public.games%rowtype; occupied integer; existing_status text;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select * into g from public.games where id = p_game_id for update;
 if not found then raise exception 'Game not found'; end if;
 if g.status in ('cancelled','completed','archived','live') then raise exception 'Game is not accepting players'; end if;
 select membership_status into existing_status from public.game_members where game_id=p_game_id and user_id=auth.uid();
 if existing_status in ('joined','waitlisted') then return existing_status; end if;
 select count(*) into occupied from public.game_members where game_id=p_game_id and membership_status='joined';
 if occupied < g.max_players then
   insert into public.game_members(game_id,user_id,membership_status) values(p_game_id,auth.uid(),'joined')
   on conflict(game_id,user_id) do update set membership_status='joined',joined_at=now();
   return 'joined';
 else
   insert into public.game_members(game_id,user_id,membership_status) values(p_game_id,auth.uid(),'waitlisted')
   on conflict(game_id,user_id) do update set membership_status='waitlisted',joined_at=now();
   return 'waitlisted';
 end if;
end; $$;

-- Leave and promote the earliest waitlisted player atomically.
create or replace function public.leave_game(p_game_id uuid)
returns void language plpgsql security definer set search_path = ''
as $
declare promoted uuid; occupied integer; capacity integer;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select max_players into capacity from public.games where id=p_game_id for update;
 if not found then raise exception 'Game not found'; end if;
 update public.game_members set membership_status='left' where game_id=p_game_id and user_id=auth.uid() and membership_status in ('joined','waitlisted');
 select count(*) into occupied from public.game_members where game_id=p_game_id and membership_status='joined';
 if occupied < capacity then
   select user_id into promoted from public.game_members where game_id=p_game_id and membership_status='waitlisted' order by joined_at limit 1;
   if promoted is not null then update public.game_members set membership_status='joined' where game_id=p_game_id and user_id=promoted; end if;
 end if;
end; $;

revoke all on function public.join_game(uuid) from public, anon;
grant execute on function public.join_game(uuid) to authenticated;
revoke all on function public.leave_game(uuid) from public, anon;
grant execute on function public.leave_game(uuid) to authenticated;
