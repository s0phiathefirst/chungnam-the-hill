-- 충남더힐 이웃정: 동 행사·투표·소모임·정 포인트 공유 데이터
-- 모든 변경은 아래 함수(RPC)로만 하고, 사이트(anon)는 읽기만 가능

create table if not exists public.events (
  id         text primary key,                 -- 행사 날짜 (YYYY-MM-DD)
  date       date not null,
  dong       text not null,
  title      text not null,
  place      text not null,
  time_text  text not null
);

create table if not exists public.event_roles (
  id          uuid primary key default gen_random_uuid(),
  event_id    text not null references public.events(id) on delete cascade,
  sort        int  not null default 100,
  label       text not null check (char_length(label) between 1 and 40),
  ho          text check (char_length(ho) <= 10),
  taken_key   text check (char_length(taken_key) <= 30),
  proposed    boolean not null default false,
  updated_at  timestamptz not null default now()
);
create index if not exists event_roles_event_idx on public.event_roles(event_id);

create table if not exists public.event_going (
  event_id   text not null references public.events(id) on delete cascade,
  user_key   text not null check (char_length(user_key) <= 30),
  created_at timestamptz not null default now(),
  primary key (event_id, user_key)
);

create table if not exists public.poll_votes (
  poll_id    text not null check (char_length(poll_id) <= 40),
  user_key   text not null check (char_length(user_key) <= 30),
  option     int  not null check (option between 0 and 9),
  updated_at timestamptz not null default now(),
  primary key (poll_id, user_key)
);

create table if not exists public.clubs (
  id            text primary key default gen_random_uuid()::text,
  name          text not null check (char_length(name) between 1 and 30),
  when_text     text not null default '조율 중' check (char_length(when_text) <= 30),
  place         text not null default '조율 중' check (char_length(place) <= 30),
  tag           text not null default '신규' check (char_length(tag) <= 10),
  max_members   int  not null default 10 check (max_members between 2 and 50),
  base_members  int  not null default 0,
  sort          int  not null default 100,
  created_by    text,
  created_at    timestamptz not null default now()
);

create table if not exists public.club_members (
  club_id    text not null references public.clubs(id) on delete cascade,
  user_key   text not null check (char_length(user_key) <= 30),
  created_at timestamptz not null default now(),
  primary key (club_id, user_key)
);

create table if not exists public.point_log (
  id         uuid primary key default gen_random_uuid(),
  user_key   text not null check (char_length(user_key) <= 30),
  dong       text not null check (char_length(dong) <= 10),
  reason     text not null check (char_length(reason) <= 60),
  points     int  not null check (points between -50 and 50),
  created_at timestamptz not null default now()
);
create index if not exists point_log_user_idx on public.point_log(user_key);

-- 읽기 전용 공개 (RLS)
do $$
declare t text;
begin
  foreach t in array array['events','event_roles','event_going','poll_votes','clubs','club_members','point_log'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "%s_read" on public.%I', t, t);
    execute format('create policy "%s_read" on public.%I for select to anon, authenticated using (true)', t, t);
    execute format('grant select on public.%I to anon, authenticated', t);
  end loop;
end $$;

-- ===== 함수 (RPC) =====
create or replace function public._key_ok(p_key text) returns boolean
language sql immutable as $$ select p_key ~ '^[0-9]{3}동-[0-9]{3,4}호$' $$;

create or replace function public._today() returns date
language sql stable as $$ select (now() at time zone 'Asia/Seoul')::date $$;

-- 역할 신청: 우리 동 행사, 지난 행사 아님, 빈 역할, 한 행사에 한 역할
create or replace function public.take_role(p_role uuid, p_key text) returns text
language plpgsql security definer set search_path = public as $$
declare r public.event_roles; e public.events;
begin
  if not public._key_ok(p_key) then return 'bad_key'; end if;
  select * into r from public.event_roles where id = p_role for update;
  if not found then return 'not_found'; end if;
  select * into e from public.events where id = r.event_id;
  if e.date < public._today() then return 'closed'; end if;
  if split_part(p_key,'-',1) <> e.dong then return 'wrong_dong'; end if;
  if r.ho is not null then return 'taken'; end if;
  if exists (select 1 from public.event_roles where event_id = e.id and taken_key = p_key) then return 'already'; end if;
  update public.event_roles set ho = split_part(p_key,'-',2), taken_key = p_key, updated_at = now() where id = p_role;
  insert into public.point_log(user_key, dong, reason, points) values (p_key, e.dong, left(e.title || ' 역할 신청', 60), 30);
  return 'ok';
end $$;

-- 역할 취소 (본인 것만, 제안한 역할이면 삭제)
create or replace function public.cancel_role(p_role uuid, p_key text) returns text
language plpgsql security definer set search_path = public as $$
declare r public.event_roles; e public.events;
begin
  select * into r from public.event_roles where id = p_role for update;
  if not found or r.taken_key is distinct from p_key then return 'not_mine'; end if;
  select * into e from public.events where id = r.event_id;
  if e.date < public._today() then return 'closed'; end if;
  if r.proposed then delete from public.event_roles where id = p_role;
  else update public.event_roles set ho = null, taken_key = null, updated_at = now() where id = p_role; end if;
  insert into public.point_log(user_key, dong, reason, points) values (p_key, e.dong, left(e.title || ' 역할 취소', 60), -30);
  return 'ok';
end $$;

-- 새 역할 제안 (제안한 사람이 바로 맡음)
create or replace function public.propose_role(p_event text, p_key text, p_label text) returns text
language plpgsql security definer set search_path = public as $$
declare e public.events; n int;
begin
  if not public._key_ok(p_key) then return 'bad_key'; end if;
  if char_length(trim(coalesce(p_label,''))) not between 1 and 40 then return 'bad_label'; end if;
  select * into e from public.events where id = p_event;
  if not found then return 'not_found'; end if;
  if e.date < public._today() then return 'closed'; end if;
  if split_part(p_key,'-',1) <> e.dong then return 'wrong_dong'; end if;
  if exists (select 1 from public.event_roles where event_id = e.id and taken_key = p_key) then return 'already'; end if;
  select coalesce(max(sort),0)+1 into n from public.event_roles where event_id = e.id;
  insert into public.event_roles(event_id, sort, label, ho, taken_key, proposed)
    values (e.id, n, trim(p_label), split_part(p_key,'-',2), p_key, true);
  insert into public.point_log(user_key, dong, reason, points) values (p_key, e.dong, left(e.title || ' 새 역할 제안', 60), 30);
  return 'ok';
end $$;

-- 다른 동 행사에 손님으로 참여 신청 / 취소
create or replace function public.toggle_going(p_event text, p_key text) returns text
language plpgsql security definer set search_path = public as $$
declare e public.events;
begin
  if not public._key_ok(p_key) then return 'bad_key'; end if;
  select * into e from public.events where id = p_event;
  if not found then return 'not_found'; end if;
  if e.date < public._today() then return 'closed'; end if;
  if split_part(p_key,'-',1) = e.dong then return 'own_dong'; end if;
  if exists (select 1 from public.event_going where event_id = p_event and user_key = p_key) then
    delete from public.event_going where event_id = p_event and user_key = p_key;
    insert into public.point_log(user_key, dong, reason, points) values (p_key, split_part(p_key,'-',1), left(e.title || ' 참여 취소', 60), -10);
    return 'left';
  end if;
  insert into public.event_going(event_id, user_key) values (p_event, p_key);
  insert into public.point_log(user_key, dong, reason, points) values (p_key, split_part(p_key,'-',1), left(e.title || ' 손님 참여', 60), 10);
  return 'joined';
end $$;

-- 투표 (한 세대 한 표, 다시 누르면 변경)
create or replace function public.cast_vote(p_poll text, p_key text, p_option int) returns text
language plpgsql security definer set search_path = public as $$
begin
  if not public._key_ok(p_key) then return 'bad_key'; end if;
  if p_poll not in ('201-winter') or p_option not between 0 and 2 then return 'bad_poll'; end if;
  insert into public.poll_votes(poll_id, user_key, option) values (p_poll, p_key, p_option)
  on conflict (poll_id, user_key) do update set option = excluded.option, updated_at = now();
  return 'ok';
end $$;

-- 소모임 가입 / 탈퇴
create or replace function public.toggle_club(p_club text, p_key text) returns text
language plpgsql security definer set search_path = public as $$
declare c public.clubs; cnt int;
begin
  if not public._key_ok(p_key) then return 'bad_key'; end if;
  select * into c from public.clubs where id = p_club for update;
  if not found then return 'not_found'; end if;
  if exists (select 1 from public.club_members where club_id = p_club and user_key = p_key) then
    delete from public.club_members where club_id = p_club and user_key = p_key;
    insert into public.point_log(user_key, dong, reason, points) values (p_key, split_part(p_key,'-',1), left(c.name || ' 탈퇴', 60), -15);
    return 'left';
  end if;
  select count(*) into cnt from public.club_members where club_id = p_club;
  if c.base_members + cnt >= c.max_members then return 'full'; end if;
  insert into public.club_members(club_id, user_key) values (p_club, p_key);
  insert into public.point_log(user_key, dong, reason, points) values (p_key, split_part(p_key,'-',1), left(c.name || ' 가입', 60), 15);
  return 'joined';
end $$;

-- 새 소모임 만들기 (만든 사람이 첫 멤버)
create or replace function public.create_club(p_key text, p_name text, p_when text, p_place text) returns text
language plpgsql security definer set search_path = public as $$
declare new_id text;
begin
  if not public._key_ok(p_key) then return 'bad_key'; end if;
  if char_length(trim(coalesce(p_name,''))) not between 1 and 30 then return 'bad_name'; end if;
  if (select count(*) from public.clubs where created_by = p_key) >= 3 then return 'too_many'; end if;
  insert into public.clubs(name, when_text, place, tag, max_members, base_members, sort, created_by)
    values (trim(p_name), left(coalesce(nullif(trim(p_when),''),'조율 중'),30), left(coalesce(nullif(trim(p_place),''),'조율 중'),30), '신규', 10, 0, 100, p_key)
    returning id into new_id;
  insert into public.club_members(club_id, user_key) values (new_id, p_key);
  insert into public.point_log(user_key, dong, reason, points) values (p_key, split_part(p_key,'-',1), left(trim(p_name) || ' 소모임 개설', 60), 15);
  return 'ok';
end $$;

-- 게시판 글·후기·환영 인사·빙고 등 화면에서 주는 포인트
create or replace function public.add_points(p_key text, p_reason text, p_points int) returns text
language plpgsql security definer set search_path = public as $$
begin
  if not public._key_ok(p_key) then return 'bad_key'; end if;
  if p_points not in (5, 10, 20, 50) then return 'bad_points'; end if;
  insert into public.point_log(user_key, dong, reason, points)
    values (p_key, split_part(p_key,'-',1), left(coalesce(nullif(trim(p_reason),''),'활동'),60), p_points);
  return 'ok';
end $$;

do $$
declare f text;
begin
  foreach f in array array['take_role(uuid,text)','cancel_role(uuid,text)','propose_role(text,text,text)','toggle_going(text,text)',
                           'cast_vote(text,text,int)','toggle_club(text,text)','create_club(text,text,text,text)','add_points(text,text,int)'] loop
    execute format('revoke all on function public.%s from public', f);
    execute format('grant execute on function public.%s to anon, authenticated', f);
  end loop;
end $$;

-- 실시간 전송 대상에 추가
do $$
declare t text;
begin
  foreach t in array array['event_roles','event_going','poll_votes','clubs','club_members','point_log'] loop
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- 시드 데이터

insert into public.events(id,date,dong,title,place,time_text) values
('2026-11-07','2026-11-07','207동','207동 푸드트럭 데이','207동 앞 광장','17:00~20:00'),
('2026-11-14','2026-11-14','102동','102동 이웃 한 상 (가을)','102동 옆 어린이 놀이터','16:00~19:00'),
('2026-11-21','2026-11-21','105동','105동 야시장','105동 필로티','18:00~21:00'),
('2026-11-28','2026-11-28','203동','203동 김장 나눔','203동 커뮤니티룸','10:00~14:00'),
('2026-12-05','2026-12-05','102동','102동 이웃 한 상','102동 옆 어린이 놀이터','16:00~19:00'),
('2026-12-12','2026-12-12','201동','201동 겨울 행사 (주제 투표 중)','201동 앞 광장','17:00~20:00'),
('2026-12-19','2026-12-19','101동','101동 크리스마스 마켓','101동 필로티','16:00~20:00'),
('2026-12-26','2026-12-26','207동','207동 송년 영화의 밤','207동 커뮤니티룸','18:30~21:00'),
('2027-01-09','2027-01-09','102동','102동 새해 윷놀이 한마당','102동 옆 어린이 놀이터','14:00~17:00'),
('2027-01-16','2027-01-16','106동','106동 떡국 나눔','106동 커뮤니티룸','11:00~14:00'),
('2027-01-23','2027-01-23','105동','105동 겨울 야시장','105동 필로티','18:00~21:00')
on conflict (id) do nothing;

insert into public.event_roles(event_id,sort,label,ho,taken_key) values
('2026-11-07',1,'떡볶이','101호','207동-101호'),
('2026-11-07',2,'떡볶이','102호','207동-102호'),
('2026-11-07',3,'회오리감자','202호','207동-202호'),
('2026-11-07',4,'어묵꼬치','305호','207동-305호'),
('2026-11-07',5,'붕어빵','401호','207동-401호'),
('2026-11-07',6,'음료·식혜','503호','207동-503호'),
('2026-11-14',1,'장터 · 수제 쿠키','501호','102동-501호'),
('2026-11-14',2,'장터 · 아이 옷·장난감 나눔','201호','102동-201호'),
('2026-11-14',3,'한 상 · 어묵탕','302호','102동-302호'),
('2026-11-14',4,'오프닝 진행','1101호','102동-1101호'),
('2026-11-14',5,'사진 기록','903호','102동-903호'),
('2026-11-21',1,'호떡','103호','105동-103호'),
('2026-11-21',2,'닭꼬치','204호','105동-204호'),
('2026-11-21',3,'핸드메이드 액세서리','601호','105동-601호'),
('2026-11-21',4,'조명·전구 설치','802호','105동-802호'),
('2026-11-28',1,'절임배추 준비','102호','203동-102호'),
('2026-11-28',2,'양념 만들기','301호','203동-301호'),
('2026-11-28',3,'수육 삶기',null,null),
('2026-11-28',4,'포장·배달 (어르신 세대)',null,null),
('2026-12-05',1,'오프닝 진행','501호','102동-501호'),
('2026-12-05',2,'장터 · 아이 옷·장난감 나눔','201호','102동-201호'),
('2026-12-05',3,'한 상 · 따뜻한 어묵탕','302호','102동-302호'),
('2026-12-05',4,'장터 · 수제 쿠키','1101호','102동-1101호'),
('2026-12-05',5,'장터 · 음료 부스 (유자차·핫초코)',null,null),
('2026-12-05',6,'이웃 빙고 운영',null,null),
('2026-12-05',7,'층별 대항전 심판',null,null),
('2026-12-05',8,'사진 기록',null,null),
('2026-12-05',9,'마감 정리·분리수거',null,null),
('2026-12-12',1,'행사 총괄',null,null),
('2026-12-12',2,'장소 꾸미기',null,null),
('2026-12-12',3,'먹거리 준비',null,null),
('2026-12-19',1,'뱅쇼 부스','204호','101동-204호'),
('2026-12-19',2,'쿠키 굽기','702호','101동-702호'),
('2026-12-19',3,'트리 꾸미기',null,null),
('2026-12-19',4,'캐럴 공연',null,null),
('2026-12-26',1,'영화 상영 준비','404호','207동-404호'),
('2026-12-26',2,'간식 준비',null,null),
('2026-12-26',3,'좌석 정리',null,null),
('2027-01-09',1,'윷놀이 진행','1101호','102동-1101호'),
('2027-01-09',2,'떡국 끓이기',null,null),
('2027-01-09',3,'층별 팀 구성',null,null),
('2027-01-09',4,'상품 준비',null,null),
('2027-01-09',5,'사진 기록',null,null),
('2027-01-16',1,'떡국 끓이기','301호','106동-301호'),
('2027-01-16',2,'배달 (어르신 세대)',null,null),
('2027-01-23',1,'호떡','103호','105동-103호'),
('2027-01-23',2,'어묵꼬치',null,null),
('2027-01-23',3,'핫팩 나눔',null,null);

insert into public.event_going(event_id,user_key) values
('2026-12-05','105동-1203호'),
('2026-12-05','201동-302호'),
('2026-12-05','106동-1502호'),
('2026-12-05','207동-404호'),
('2026-12-19','102동-1101호'),
('2026-12-19','105동-301호'),
('2027-01-09','203동-502호')
on conflict do nothing;

insert into public.clubs(id,name,when_text,place,tag,max_members,base_members,sort) values
('c1','더힐 새벽 러닝','화·목 06:30','단지 둘레길 3km','운동',20,12,0),
('c2','한 달 한 권 독서 모임','매월 마지막 금 20:00','커뮤니티룸','취미',10,8,1),
('c3','금요 보드게임','격주 금 19:30','102동 작은도서관','취미',12,6,2),
('c4','공동육아 놀이터 모임','토 10:00','102동 옆 놀이터','육아',25,15,3),
('c5','반려견 산책 메이트','매일 21:00','정문 앞 집결','반려동물',15,9,4),
('c6','1인 가구 반찬 나눔','격주 일 17:00','커뮤니티룸','청년',12,7,5)
on conflict (id) do nothing;

insert into public.point_log(user_key,dong,reason,points,created_at) values
('102동-101호','102동','207동 푸드트럭 데이 손님 참여',10,'2026-11-07 12:00:00+09'),
('102동-101호','102동','102동 이웃 한 상 (가을) 역할 신청',30,'2026-11-14 12:00:00+09'),
('102동-101호','102동','나눔 게시판 글 등록',20,'2026-11-02 12:00:00+09'),
('102동-101호','102동','행사 후기 작성',10,'2026-10-24 12:00:00+09'),
('102동-102호','102동','207동 푸드트럭 데이 손님 참여',10,'2026-11-07 12:00:00+09'),
('102동-102호','102동','나눔 게시판 글 등록',20,'2026-11-02 12:00:00+09'),
('102동-102호','102동','행사 후기 작성',10,'2026-10-24 12:00:00+09'),
('102동-102호','102동','새 이웃 환영 인사',5,'2026-10-12 12:00:00+09'),
('102동-202호','102동','105동 야시장 손님 참여',10,'2026-11-21 12:00:00+09'),
('102동-202호','102동','더힐 새벽 러닝 가입',15,'2026-11-03 12:00:00+09'),
('102동-303호','102동','이웃 빙고 완성',50,'2026-11-14 12:00:00+09'),
('102동-404호','102동','102동 이웃 한 상 (가을) 역할 신청',30,'2026-11-14 12:00:00+09'),
('102동-404호','102동','품앗이 게시판 글 등록',20,'2026-11-09 12:00:00+09');
