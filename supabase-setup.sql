-- 충남더힐 이웃정: 실시간 게시판 테이블 만들기
-- Supabase 대시보드 → SQL Editor → New query 에 전체를 붙여 넣고 Run 을 누르세요.

-- 1) 게시글 (나눔·품앗이 = share, 건의함 = suggest)
create table if not exists public.posts (
  id          uuid primary key default gen_random_uuid(),
  board       text not null check (board in ('share', 'suggest')),
  cat         text not null check (char_length(cat) between 1 and 20),
  title       text not null check (char_length(title) between 1 and 100),
  body        text not null default '' check (char_length(body) <= 2000),
  author      text not null check (char_length(author) between 1 and 30),
  author_key  text check (char_length(author_key) <= 30),
  status      text check (status in ('접수', '검토중', '답변완료')),
  done        boolean not null default false,
  created_at  timestamptz not null default now()
);

-- 2) 댓글 (post_id 는 예시 글 id도 받을 수 있게 text 로 둠)
create table if not exists public.comments (
  id          uuid primary key default gen_random_uuid(),
  post_id     text not null check (char_length(post_id) <= 60),
  body        text not null check (char_length(body) between 1 and 500),
  author      text not null check (char_length(author) between 1 and 30),
  author_key  text check (char_length(author_key) <= 30),
  created_at  timestamptz not null default now()
);
create index if not exists comments_post_id_idx on public.comments (post_id);

-- 3) 보안 규칙(RLS): 누구나 읽고 새로 쓸 수 있지만, 수정·삭제는 불가
alter table public.posts    enable row level security;
alter table public.comments enable row level security;

drop policy if exists "posts_read"     on public.posts;
drop policy if exists "posts_insert"   on public.posts;
drop policy if exists "comments_read"  on public.comments;
drop policy if exists "comments_insert" on public.comments;

create policy "posts_read"   on public.posts for select to anon, authenticated using (true);
create policy "posts_insert" on public.posts for insert to anon, authenticated
  with check (done = false and (status is null or status = '접수'));

create policy "comments_read"   on public.comments for select to anon, authenticated using (true);
create policy "comments_insert" on public.comments for insert to anon, authenticated with check (true);

-- 3-1) 사이트(anon)에서 테이블을 읽고 쓸 수 있도록 권한 부여
grant usage on schema public to anon, authenticated;
grant select, insert on public.posts    to anon, authenticated;
grant select, insert on public.comments to anon, authenticated;

-- 4) 실시간(Realtime) 켜기: 새 글·댓글을 접속한 모든 사람에게 바로 전송
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'posts') then
    alter publication supabase_realtime add table public.posts;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'comments') then
    alter publication supabase_realtime add table public.comments;
  end if;
end $$;

-- (선택) 건의 처리 상태를 바꾸고 싶을 때는 Table Editor 에서 status 값을 직접 수정하거나 아래처럼 실행
-- update public.posts set status = '답변완료' where id = '글의 id';
