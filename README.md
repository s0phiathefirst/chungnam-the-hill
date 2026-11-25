# 충남더힐 이웃정

<디자인씽킹과 교육 혁신> 2조 프로젝트 **정(情)의 재분배**의 프로토타입입니다. 아파트 주민만 들어오는 커뮤니티 사이트예요.

- 시연용 로그인 (102동): **101호 / 1111**, **102호 / 1234**, **202호 / 2222**, **303호 / 3333**, **404호 / 4444**
- 실시간 게시판: **나눔·품앗이**, **건의함**. 다른 사람이 쓴 글과 댓글이 새로고침 없이 바로 올라옵니다.

## 폴더 구성

| 파일 | 설명 |
|---|---|
| `index.html` | 사이트 전체 (화면, 디자인, 동작) |
| `bg.jpg` | 배경 사진 |
| `supabase-config.js` | Supabase 연결 정보 (2단계에서 직접 채움) |
| `supabase-setup.sql` | 게시판 테이블, 보안 규칙, 실시간 설정 (Supabase에서 한 번 실행) |
| `netlify.toml` | Netlify 배포 설정 |

## 왜 Supabase가 필요한가요?

Netlify는 만들어 둔 화면 파일을 보여주기만 해서, 여러 사람이 쓴 글을 저장하고 나눌 데이터베이스가 없습니다. 그래서 글과 댓글은 **Supabase**(무료 데이터베이스 + 실시간 기능)에 저장합니다. 수업 프로젝트 규모는 무료 플랜으로 충분해요.

Supabase를 연결하지 않아도 사이트는 열립니다. 이때는 **체험 모드**로 동작해서, 글이 내 브라우저에만 저장되고 같은 브라우저의 다른 탭에만 실시간으로 반영됩니다.

---

## 1단계. GitHub에 올리기

1. https://github.com 에 로그인하고 오른쪽 위 **+ → New repository**를 누릅니다.
2. 저장소 이름은 `chungnam-the-hill`처럼 정하고, Public을 선택한 뒤 **Create repository**를 누릅니다.
3. 만든 저장소 화면에서 **uploading an existing file**을 누릅니다.
4. 압축을 푼 파일 6개를 모두 끌어다 놓고 **Commit changes**를 누릅니다.

## 2단계. Supabase 만들기 (실시간 게시판)

1. https://supabase.com 에서 **Start your project**를 누르고 GitHub 계정으로 로그인합니다.
2. **New project**를 누르고 아래처럼 입력한 뒤 **Create new project**를 누릅니다. 1~2분 정도 기다리면 준비돼요.
   - Name: `chungnam-the-hill`
   - Database Password: 아무 비밀번호 (따로 적어 두세요)
   - Region: **Northeast Asia (Seoul)**
3. 왼쪽 메뉴 **SQL Editor → New query**를 누르고, `supabase-setup.sql` 내용을 전부 붙여 넣은 뒤 **Run**을 누릅니다. "Success"가 나오면 테이블, 보안 규칙, 실시간 설정이 한 번에 끝납니다.
4. 왼쪽 아래 톱니바퀴 **Project Settings → API**로 들어가 두 값을 복사합니다.
   - **Project URL**: `https://○○○○.supabase.co`
   - **Project API keys → anon public**: `eyJ...`로 시작하는 긴 키
5. GitHub 저장소에서 `supabase-config.js`를 열고 연필 아이콘(편집)을 누른 뒤, `url`과 `anonKey`에 위 두 값을 넣고 **Commit changes**를 누릅니다.

> `anon public` 키는 웹사이트에 공개되어도 괜찮은 키입니다. 데이터는 3번에서 실행한 보안 규칙(RLS)이 지켜 줍니다. 바로 아래 있는 **service_role** 키는 모든 권한을 가진 키라서 절대 넣으면 안 돼요.

## 3단계. Netlify로 배포하기

1. https://app.netlify.com 에 **GitHub 계정으로 로그인**합니다.
2. **Add new site → Import an existing project → GitHub**를 누르고, 1단계에서 만든 저장소를 고릅니다.
3. 설정은 그대로 두고(Build command 비움, Publish directory `.`) **Deploy**를 누릅니다.
4. 1분쯤 뒤 `https://○○○.netlify.app` 주소가 생깁니다. **Site configuration → Change site name**에서 `chungnam-the-hill`처럼 바꿀 수 있어요.
5. 이제 GitHub에서 파일을 고치면 Netlify가 자동으로 다시 배포합니다.

## 4단계. 실시간 동작 확인하기

1. 배포된 주소를 휴대폰과 노트북에서 각각 열고 둘 다 로그인합니다.
2. 한쪽에서 **건의함 → 건의하기**로 글을 씁니다.
3. 다른 쪽 화면에 새로고침 없이 글이 나타나고 "새 글이 올라왔어요" 알림이 뜨면 성공입니다.
4. 게시판 위에 **● 실시간 연결됨**이 초록색으로 보이면 Supabase에 연결된 상태예요. 회색 "체험 모드"라면 `supabase-config.js` 값을, 빨간 "연결 실패"라면 SQL을 실행했는지 다시 확인해 주세요.

카톡으로는 이 Netlify 주소만 보내면 됩니다.

---

## 추가 기능 (동 행사·투표·소모임·정 포인트 실시간 공유)

`supabase-setup-events.sql`은 행사 일정, 역할 신청, 손님 참여, 투표, 소모임, 정 포인트를 여러 사람이 함께 쓰도록 만드는 테이블·규칙·예시 데이터입니다. **이미 Supabase에 적용되어 있어** 다시 실행할 필요는 없어요. 새 프로젝트로 옮길 때만 `supabase-setup.sql` 다음에 한 번 실행하면 됩니다.

- 모든 변경(역할 신청, 투표, 가입 등)은 서버 함수로만 처리되고, 사이트는 데이터를 읽기만 할 수 있습니다.
- 행사 일정은 2026년 11월~2027년 1월 토요일로 들어 있어요. 일정을 바꾸려면 Supabase **Table Editor → events / event_roles**에서 고치면 됩니다.
- "이웃정 소개" 메뉴에서 기능 목록과 두 사람 시연 순서를 볼 수 있어요.

---

## 알아 둘 점 (발표 때 한계로 말해도 좋아요)

- **로그인**: 시연용이라 화면에서만 확인합니다. 실제 서비스라면 관리사무소가 세대별 계정을 발급하는 Supabase Auth 같은 진짜 인증이 필요합니다.
- **게시글 공개 범위**: 지금은 사이트 주소를 아는 사람이면 누구나 게시판 데이터를 읽을 수 있으니, 개인정보는 쓰지 않도록 안내해 주세요.
- **수정·삭제**: 보안 규칙에서 막아 두었습니다. 지울 글이 있거나 건의 처리 상태(접수 → 검토중 → 답변완료)를 바꾸려면 Supabase의 **Table Editor**에서 직접 고치면 됩니다.
- **무료 플랜 일시정지**: Supabase 무료 프로젝트는 일주일 넘게 아무도 쓰지 않으면 일시정지돼요. 발표 전날 대시보드에 들어가 **Restore**를 눌러 깨워 두세요.
- **나머지 기능**: 공지사항, 행사, 소모임, 정 포인트는 시연용 예시 데이터라 새로고침하면 처음 상태로 돌아갑니다.
