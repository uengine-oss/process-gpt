## 결정

| 항목 | 결정 | 이유 |
|---|---|---|
| 시작자 | 인스턴스에서 가장 먼저 시작된 업무의 담당자 | 인스턴스 표에 시작자 칸이 없다. 화면의 「시작자」 표시와 같은 기준을 써야 화면과 권한이 어긋나지 않는다 |
| 위임 허용 | 담당자 본인, 시작자, 관리자 | 검토에서 「시작자니까 그렇다 치지만 다른 참여자는 바꿀 수 없어야」라는 지적이 있었다. 담당자가 자기 업무를 넘기는 것도 허용한다 |
| 에이전트 맡기기 · 채택 허용 | 담당자만(관리자 포함 타인 불가) | 에이전트 시작은 업무 상태를 `IN_PROGRESS`로 바꾸고 담당자의 폼을 채운다. 남이 대신하면 담당자가 모르는 결과가 생긴다 |
| 한 번에 맡기기 방식 | 정의에 정해 둔 방식 → 지난번 고른 방식 → 딥 에이전트 · 초안 | 검토에서 「누르면 바로 맡겨져야 하는데 매번 눌러야 한다」는 지적이 있었다. 지난 선택은 브라우저에 사용자별로 저장하고, 저장할 수 없으면 기본값을 쓴다 |
| 인스턴스 ＋ | 정의 체계도의 프로세스 목록으로 이동 | 프로세스를 골라 실행하는 별도 창이 없다. 목록에서 프로세스를 열면 「실행」 단추가 있다 |
| 대화 ＋ | 첫 화면 입력창에 커서 | 새 대화는 원래 첫 말로 시작한다(첫 말 없이 방을 만드는 흐름은 이름 · 참여자만 묻는 빈 방이었다). 사람과의 대화는 사람 동료를 눌러 1:1로 연다 |
| 관리 메뉴 위치 | 상단 아이콘 줄의 「관리」(관리자 전용) | 사이드바에서 뺀 관리 진입점을 한곳에 모은다. 첫 화면을 바꾸면 프로세스 체계도로 가는 길이 없어지므로 여기에 둔다 |
| 사이드바 인스턴스 정렬 | 조회 `updated_at.desc`, 받은 뒤 다시 정렬 | PostgreSQL은 `DESC`에서 NULL을 맨 앞에 둔다. 그래서 `start_date`가 빈 옛 인스턴스가 위에 올라왔다 |

## 서버 쪽 권한 (제안 — 적용하지 않음)

지금의 todolist 정책은 다음과 같다.
- `todolist_update_policy`: `USING (tenant_id = tenant_id())`
- `membership_access_gate`

그래서 같은 조직 사용자면 API로 남의 업무 담당자 · 상태 · 에이전트 칸을 바꿀 수 있다. 화면에서 막은 것을 서버에서도 막으려면 아래 정책이 필요하다. 엔진과 에이전트 서비스는 `service_role`이라 RLS를 거치지 않는다.

```sql
-- 업무를 고칠 수 있는가: 담당자 본인 · 그 인스턴스의 시작자 · 같은 조직 관리자 · 담당자가 비어 있는 업무
create or replace function public.can_modify_todo(p_user_id text, p_proc_inst_id text, p_tenant_id text)
returns boolean
language sql stable security definer set search_path = public as $$
    select
        p_user_id is null
        or auth.uid()::text = any (string_to_array(replace(p_user_id, ' ', ''), ','))
        or exists (select 1 from users u where u.id = auth.uid() and u.tenant_id = p_tenant_id and u.is_admin)
        or auth.uid()::text = (
            select split_part(replace(t.user_id, ' ', ''), ',', 1) from todolist t
            where t.proc_inst_id = p_proc_inst_id and t.start_date is not null
            order by t.start_date asc limit 1
        );
$$;

drop policy if exists todolist_update_policy on public.todolist;
create policy todolist_update_policy on public.todolist for update
    using (tenant_id = tenant_id() and public.can_modify_todo(user_id, proc_inst_id, tenant_id))
    with check (tenant_id = tenant_id());
```

적용하기 전에 확인할 것:
1. 사용자 JWT로 남의 업무 행을 고치는 정상 흐름이 있는지 찾아야 한다. 예를 들면 검토자의 피드백 저장, 칸반 끌어 옮기기, 역할 업무 가져오기(담당자 null → 나)가 있다. null 담당자는 위 함수가 허용한다.
2. `trigger_update_bpm_proc_inst_updated_at` 함수는 SECURITY INVOKER다. 일반 사용자의 todolist 갱신으로는 `bpm_proc_inst`(관리자만 UPDATE)의 `updated_at`이 바뀌지 않는다.
   - SECURITY DEFINER와 `set search_path = public`으로 바꾸면 사이드바 최근 갱신순이 사용자의 임시 저장 · 맡기기에도 반응한다.
3. 위 SQL은 설치본(VM)에도 적용하지 않았다. 적용 여부는 운영 담당이 정한다.
   - 설치본 DB의 `ROLLBACK`하는 트랜잭션 안에서 컴파일과 판정만 확인했다. 대상은 담당자가 김민지이고 시작자가 장진영인 업무다.
   - 판정 결과: 박서연 `false`, 김민지 `true`, 관리자 장진영 `true`.
   - 사용자를 바꿀 때는 문장을 나눠야 한다. `auth.uid()`가 STABLE이라 한 문장 안에서는 첫 값이 유지된다.

### 2026-11-10 조사 결과 — 이대로는 적용하지 않는다

「적용하기 전에 확인할 것」 1번을 코드에서 찾았다. 아래 정상 흐름은 사용자 JWT로 담당자가 아닌 업무 행을 고친다. 위 정책을 그대로 걸면 모두 막힌다.

| 흐름 | 누가 | 막히면 |
|---|---|---|
| 인계 뒤 후속 처리(새 담당자에게 넘긴 업무의 행 추가 · 갱신) | 넘기는 사람 | 인계가 반쯤 끝난 채 남는다 |
| 인스턴스 보드에서 카드를 끌어 옮기기 · 간트 일정 바꾸기 | 그 인스턴스를 보는 사람 | 화면은 옮겨지고 저장은 안 된다(일부 경로는 결과를 기다리지 않아 오류도 안 보인다) |
| 피드백 저장 | 검토자 | 피드백이 사라진다 |
| PAL 모드 업무 화면 | PAL 사용자 | 업무 저장 실패 |

또 시작자 판정이 맞지 않는다.
- 시작자는 업무의 `proc_inst_id`가 아니라 최상위 인스턴스(`COALESCE(root_proc_inst_id, proc_inst_id)`)에서 찾아야 한다. 하위 인스턴스 업무에서는 엉뚱한 사람이 시작자가 된다.
- 'start event' 행(도구 없음)은 건너뛰어야 한다.
- `user_id`에는 공백 · 이메일이 섞여 있다. 앞뒤 공백을 지우고 `auth.email()`과도 맞춰 봐야 한다.
- 시작자를 찾는 하위 질의가 행마다 돈다. `(root_proc_inst_id, start_date)` 색인과 SECURITY DEFINER 도움 함수가 필요하다.

엔진 · 에이전트 서비스는 모두 `service_role`로 쓰므로 영향이 없다. 다시 설계한 정책은 위 네 흐름을 시험 계정으로 밟아 본 뒤 운영 담당이 적용한다(결정 기록 `docs/decisions/2026-11.md` D-1110-11).

## 화면 구조 메모

- 사이드바 구역 머리는 공통 컴포넌트 하나로 그린다. 각 구역은 `@search` · `@add`만 넘긴다.
- 관리 화면으로 들어가는 쿼리:
  - `/organization?createAgent=1`
  - `/skills?add=1`
  - `/account-settings?tab=ManageAccess&invite=1`
  - `/definition-map?focus=chat|processes`, `?search=1`
  - 받는 화면은 처리한 뒤 쿼리를 지운다. 새로고침해도 창이 다시 열리지 않게 하려는 것이다.
- 담당자가 아닌 사람의 에이전트 탭은 같은 컴포넌트를 읽기 전용으로 그린다. 진행 기록 컴포넌트에도 같은 읽기 전용 표시를 넘겨 채택 · 질문 응답 단추를 숨긴다.
