# 공유 폴더 설계 — 파일시스템 구조 선택안

이 문서는 구현 전에 사용자가 저장 구조를 고르기 위한 것이다. 1장은 지금 코드에서 확인한 사실, 2장은 모든 안에 공통인 개념, 3장은 네 가지 안, 4장은 비교와 추천, 5장은 사용자가 정할 질문이다.

## 1. 현재 상태 (코드 확인 결과)

### 1.1 업무 인계(handover)
- 인계는 프런트엔드가 직접 DB 에 쓰는 흐름이다(검토 대상: process-gpt 프런트 `ProcessGPTBackend.ts` 의 채팅 인계 생성, `HandoverDialog.vue`).
  1. 산출물 영속화: 샌드박스 작업공간 파일은 에이전트 쪽에만 있으므로 내용을 스토리지(`files` 버킷)에 **사본으로** 올린다.
  2. 받는 사람 방 생성: `chat_rooms.context.handover = {origin_room_id, case_id, from_room_id, from_user_id, artifact_refs}`. 이메일의 References 헤더처럼 스레드 뿌리(`origin_room_id`)를 다음 방으로 계속 넘긴다.
  3. 브리핑 메시지, 4. 산출물을 받는 방 첨부(`chat_attachments`)로 연결.
  5. ad-hoc 작업(`todolist`, `adhoc=true`, `tracing_tag=handover_<id>`) 생성. 받는 쪽이 에이전트면 `IN_PROGRESS` + `agent_orch` 로 올려 폴러가 바로 집어간다.
  6. `handover_events` 기록(`source` = `chat_handover` | `agent_delegation` | `todolist`, `artifact_refs jsonb`, `case_id`, `origin_room_id`). process-miner 가 이 로그로 조직·프로세스를 도출한다.
- 넘어가는 것: 방(대화 맥락), 할 일, 산출물 **사본**. 파일 묶음이나 작업 이력(브랜치)은 넘어가지 않는다.
- 확장 지점: `artifact_refs` 는 `{type, ref, name, storage_path}` 자유 형식 jsonb 라 `type: 'folder_variation'` 을 더해도 스키마를 바꿀 필요가 없다.

### 1.2 프로세스 인스턴스와 실행
- `bpm_proc_inst`(`proc_inst_id`, `root_proc_inst_id`, `parent_proc_inst_id`, `variables_data`, `project_id`, `is_clean_up` …) ↔ `todolist`(워크아이템: `proc_inst_id`, `root_proc_inst_id`, `activity_id`, `agent_orch`, `agent_config`, `output`, `rework_count` …).
- `project` 테이블과 두 테이블의 `project_id` 열이 있지만 로컬 DB 기준으로 비어 있다(인스턴스 318건 중 0건).
- 완료 인스턴스의 스토리지 파일은 `proc_inst_source` 로 연결되어 주기적으로 지워진다(`completion_process-instance-file-cleanup`). 공유 폴더 파일은 여기에 등록하면 안 된다.

### 1.3 cli-agent 의 worktree (이미 git worktree 기반)
- 실행 폴더: `<CLIAGENTS_WORKSPACE_ROOT>/<tenant>/<todo id>` (로컬 `/tmp/cli-agent-ws/localhost/<todo id>`). 72시간 지나면 폴더를 지운다.
- `agent_config.project_repo` 가 있으면 그 저장소에서 `git worktree add -b pgpt-agent/<run id 12자> <실행 폴더>/<저장소 이름> <base_ref>`. `base_ref` 기본 `origin/main`, `@previous` 면 같은 `proc_inst_id` 의 앞 단계 `todolist.output.worktree.branch` 를 이어받는다.
- 에이전트는 커밋하지 않고 서비스가 실행 브랜치에 커밋한다. 결과 `output.worktree = {branch, base, commit, files, stat, worktree}`, Claude 세션 `output.cliagents_session_id`. 병합은 하지 않는다.
- 관찰된 문제: 지금 `project_repo` 가 실제 제품 체크아웃(`<process-gpt>`)이라 그 저장소에 `pgpt-agent/*` 브랜치 10개, `/tmp` 아래 worktree 9개가 쌓여 있다. 폴더 정리는 디렉터리만 지우고 `git worktree prune` 은 하지 않는다.

### 1.4 deepagents 작업공간과 샌드박스
- 호스트 `services/deepagents/workspace/<tenant>/` 가 테넌트당 컨테이너 하나(`deepagent-sandbox-<tenant>`, `python:3.13-slim`, root, git 2.47.3)의 `/workspace` 로 rw 마운트된다. 스킬은 `/skills/*` ro.
- 마운트는 컨테이너를 만들 때 정해지므로 실행 중에 폴더를 더 붙일 수 없다(컨테이너를 다시 만들어야 한다).
- 실행별 분리는 디렉터리 규칙과 **도구 수준 범위**로만 한다: `.bpmn/<방 또는 인스턴스>`, `.checkouts/<방>`(7일 보존), `<instance_id>/inputs|outputs`. ls/read_file/glob/grep 은 범위 밖을 거절하지만 셸 명령은 막지 못한다.
- 알려진 격리 문제: 작업공간 루트 파일(예: `11월 고객 세미나 안내문.hwpx`)과 첨부 `/workspace/uploads/<uid>/<id>/<이름>` 은 같은 테넌트의 모든 실행에서 셸로 보인다.
- 다중 파드 운영: 로컬 디스크는 파드 로컬(공유 RWX 저장소 없음)이라, 대화방 폴더를 스토리지에서 내려받는 하이드레이션 경로가 있다.
- 컨테이너 안 git 은 2.47.3 이라 worktree 상대 경로(2.48 이상)를 쓸 수 없다. worktree 의 `.git` 파일은 호스트 절대 경로를 가리키므로, 같은 경로로 마운트하지 않으면 컨테이너 안에서 git 명령이 실패한다. 서비스가 호스트에서 커밋하는 지금 방식이면 문제되지 않는다.

### 1.5 pgpt-pro
- 작업실 `resolveRoom(kind, id)`: `todo`(cli-agent → 실행 폴더·`output.worktree.worktree`·세션, deepagents → `/workspace/.bpmn/<proc_inst_id>`), `run`, `chat`. 파일 트리·편집(mtime 충돌 409)·PTY 셸·`claude --resume`·`/chat/steer`. 접근 권한 확인은 아직 없다(남은 일 2.4).
- 첨부: 호스트 `/workspace/uploads/<uid>/<id>/<이름>` + `files` 버킷 `pgpt-pro/<uid>/att/<id>.<ext>`(공개 URL). 이음오피스 카드도 공개 스토리지 URL 이 필요하다.
- process-gpt 의 "폴더" 개념은 memento 의 `knowledge_folders`/`knowledge_files`(RAG 인덱싱용 메타)와 Google Drive 연동뿐이다. 파일시스템 공간은 아니다.

## 2. 공통 개념 (어느 안이든 같음)

| 개념 | 정의 |
| --- | --- |
| 공유 폴더 | 테넌트 안의 이름 있는 파일 공간. 기준본 브랜치 `main` 하나와 변형 여러 개를 가진다. 종류: **관리형**(새로 만든 폴더)과 **연결형**(기존 git 저장소, 예: 제품 저장소 등록). |
| 구성원 | 사람·에이전트·역할. 권한: `owner`(구성원·삭제·반영 승인) ⊃ `editor`(main 직접 편집·반영) ⊃ `runner`(변형 생성·에이전트 실행) ⊃ `viewer`(보기·내려받기). |
| 변형 | `main`(또는 다른 변형)의 한 커밋에서 갈라진 브랜치 + 필요할 때만 있는 작업 사본. 상태: `open` → `ready`(실행 끝·커밋됨) → `merged` / `discarded`, 충돌 시 `conflicted`. 보유자(holder)가 한 명 있다. |
| 변형 이름 | 실행: `var/run/<todo id 12자>` · 인스턴스 라인: `inst/<인스턴스 짧은 id>` · 사람: `var/u/<uid 8자>/<이름>` · 반영: `int/<반영 id>`. 연결형 폴더는 cli-agent 기존 이름 `pgpt-agent/<run>` 을 그대로 인정한다. |
| 인스턴스 라인 | 한 인스턴스의 단계들이 이어 쌓는 브랜치. `@previous` 는 "이 인스턴스 라인의 최신 커밋" 이다. 같은 활동을 여러 번(병렬 변형·재작업) 돌리면 같은 기준에서 형제 변형이 생긴다. |
| 일괄 반영 | 고른 변형들을 통합 작업 사본에서 순서대로 합치고, 검사를 통과하면 `main` 을 그 결과로 앞으로 민다(fast-forward). `main` 이 그 사이 움직였으면 새 `main` 위에서 다시 합친다(낙관적). |
| git 조작 주체 | **에이전트는 git 을 쓰지 않는다.** 브랜치 생성·커밋·병합·정리는 서버(pgpt-pro 폴더 서비스, 또는 cli-agent 의 기존 커밋 단계)만 한다. 지금 cli-agent 규칙과 같다. |

### 2.1 일괄 반영 절차 (공통)
1. 고른 변형이 모두 `ready` 인지 확인한다(실행 중이면 거절).
2. 통합 작업 사본을 현재 `main` 커밋에서 분리 상태로 만든다.
3. 변형마다 `merge --no-ff` 한다. 충돌이 나면 멈추고 충돌 파일·양쪽 내용을 기록한다. 정책:
   - `stop`(기본): 사람이 작업실에서 풀고 "계속" 을 누른다.
   - `agent`: 해결 에이전트 실행을 통합 작업 사본 위에 띄운다(같은 작업실·스티어링 사용).
   - `choose`: 파일별로 `main` 쪽/변형 쪽을 고른다. 문서·미디어 같은 바이너리는 이 방법만 가능하다.
4. 검사(선택): 폴더 설정의 검사 명령(예: 테스트) 또는 검토 에이전트.
5. `main` 의 미커밋 사람 편집을 먼저 자동 커밋하고, `main` 을 통합 결과로 fast-forward 한다. 실패하면 3단계로 돌아간다.
6. 변형을 `merged` 로 바꾸고 작업 사본을 지운다. 브랜치는 보존 기간 뒤 지운다. 반영 기록·알림을 남긴다.
- "여러 변형 중 하나만 고르기"(택1)는 반영 대상이 하나인 일괄 반영이다. 나머지는 `discarded`.

### 2.2 프로세스·인계 연결 (공통)
- 활동 설정 `agent_config.folder = <폴더 id>`, `base_ref = main | @previous | var:<브랜치>`. 서버가 이를 해석해 cli-agent 에는 `project_repo`/`base_ref` 로, deepagents 에는 실행 폴더 안의 작업 사본으로 넘긴다.
- 인스턴스 ↔ 폴더 연결은 `pro_folder_variations.proc_inst_id` 와 인스턴스 라인 브랜치로 남긴다. 인스턴스 시작 화면에서 폴더를 고를 수도 있다.
- "검토·반영" 을 프로세스의 사람 활동으로 둘 수 있다. 그 활동의 폼은 이 인스턴스의 변형 목록이고, 제출이 곧 일괄 반영이다. 폴더 화면의 "반영" 버튼과 같은 서버 기능을 쓴다.
- 인계: `artifact_refs` 에 `{type: 'folder_variation', folder_id, variation_id, branch, commit}` 를 싣는다. 받는 쪽 기본값은 "이어받기"(같은 브랜치, 보유자만 바뀜)이고, "갈래 만들기"(그 커밋에서 새 변형)를 고를 수 있다. 인계 중에는 작업 사본을 잠근다(`git worktree lock`). 받는 쪽이 에이전트면 ad-hoc 작업의 `agent_config` 에 폴더·`base_ref=var:<브랜치>` 를 넣는다. `handover_events` 형식은 바꾸지 않는다.
- 받는 사람이 폴더 구성원이 아니면 인계할 때 `runner` 권한을 줄지 묻는다.

### 2.3 대용량·바이너리 (공통 정책, 안마다 저장처만 다름)
- docx/xlsx/pptx/hwpx 는 zip 이라 git 델타가 거의 안 되고 줄 단위 병합이 의미 없다. `.gitattributes` 에 `binary` + 병합 드라이버 `choose`(충돌 시 파일별 선택)를 둔다. 비교 화면은 텍스트 변환(문서 → 마크다운)과 이음오피스 미리보기로 보여 준다.
- 크기 임계값(기본 20MB) 이상 파일은 git 에 넣지 않고 스토리지에 올린 뒤 작은 포인터 파일로 둔다. 호스트·샌드박스 모두 git LFS 가 설치되어 있지 않아, 처음에는 LFS 대신 자체 포인터를 쓰고 필요해지면 LFS 로 바꾼다.

## 3. 선택안

### 안 1. 폴더당 bare 저장소 + 영속 worktree, 폴더별 샌드박스 마운트
모든 사본(기준본 포함)이 하나의 bare 저장소를 공유하는 worktree 이고, 전부 폴더 루트 아래에 모인다. 에이전트에게는 폴더 단위로 마운트한다.

```
<PRO_FOLDERS_ROOT>/<tenant>/<folder_id>/
├── repo.git/                     # bare: refs/heads/main, var/*, inst/*, int/*
├── main/                         # main worktree (드라이브 화면이 보는 사본)
├── wt/
│   ├── var-run-3d4732bc6cdb/     # 실행 변형 worktree
│   ├── inst-15cb35d0/            # 인스턴스 라인 worktree
│   └── var-u-ab12cd34-draft/     # 사람 변형
├── .integrate/int-7f3a/          # 반영용 임시 worktree
└── .blobs/                       # 임계값 초과 파일(또는 스토리지 포인터)
```
- **변형 생성**: `git -C repo.git worktree add wt/<이름> -b <브랜치> <기준>`. 변형이 끝나도 worktree 를 남겨 두고, 보존 기간 뒤 지운다.
- **에이전트 접근**: deepagents 는 (테넌트, 폴더)마다 샌드박스 컨테이너를 따로 만들어 `<폴더>/wt/<변형>` 만 `/workspace/folder` 로, bare 저장소는 같은 절대 경로로 ro 마운트한다(컨테이너 안에서도 git 조회 가능). cli-agent 는 호스트 경로를 그대로 쓴다(bare 저장소 지원을 위해 저장소 확인 조건 수정 필요).
- **권한**: 마운트 자체가 격리라 같은 테넌트의 다른 실행도 셸로 남의 폴더를 볼 수 없다. 가장 강하다.
- **인계**: 보유자 변경 + worktree 잠금. 작업 사본이 계속 있으므로 받는 쪽이 바로 연다.
- **백업**: `repo.git` 을 매일 `git bundle` 로 스토리지 버킷에 올린다.
- **장점**: git 그대로, 변형 생성이 빠르다(객체 공유), 비교·이력 완전, 격리 최강.
- **단점**: deepagents 수정(샌드박스 레지스트리를 폴더 단위로, 마운트 추가) 필요. 컨테이너 수가 폴더 수만큼 늘어난다. 영속 worktree 가 디스크를 먹는다. 공유 POSIX 파일시스템이 전제라 다중 파드에서는 RWX 볼륨이 필요하다.
- **깨지는 것**: 테넌트당 컨테이너 하나라는 deepagents 가정, 실행 폴더 `.bpmn/<방>` 바깥에서 일하므로 기존 산출물 수집(`.bpmn` 스캔)과 작업실 `todo` 경로 규칙이 폴더 경로를 알아야 한다.

### 안 2. 폴더 = 살아 있는 디렉터리(main 이 곧 폴더), 변형은 브랜치로만 두고 실행 때 실행 폴더 안에 체크아웃 — **추천**
폴더의 작업 트리가 곧 `main` 이다(드라이브처럼 사람이 바로 올리고 고친다). 변형은 평소에는 브랜치(ref)로만 있고, 실행이 시작될 때 그 **실행의 기존 폴더 안**에 worktree 로 꺼냈다가 끝나면 커밋하고 거둔다.

```
<PRO_FOLDERS_ROOT>/<tenant>/
├── <folder-slug>/                # 일반 git 저장소, 작업 트리 = main
│   ├── .git/                     # 객체·refs: main, var/*, inst/*, int/*
│   ├── .gitattributes            # 바이너리·병합 드라이버
│   ├── 계약서/…, 설계/…           # 사람이 보는 파일
│   └── .pgpt/folder.json         # 폴더 설정(검사 명령, 임계값)
└── .integrate/<folder-slug>/<int_id>/   # 반영용 임시 worktree

# 실행 중일 때만 생기는 변형 작업 사본 (기존 실행 폴더 규칙 안)
deepagents:  services/deepagents/workspace/<tenant>/.bpmn/<방|인스턴스>/folders/<folder-slug>/
             (컨테이너 안: /workspace/.bpmn/<방|인스턴스>/folders/<folder-slug>/)
cli-agent:   /tmp/cli-agent-ws/<tenant>/<todo id>/<folder-slug>/        ← 지금 worktree 위치 그대로
사람:        작업실에서 열 때 <PRO_FOLDERS_ROOT>/<tenant>/.people/<uid>/<변형 id>/
```
- **변형 생성**: 서버가 `git -C <folder> worktree add <실행 폴더>/folders/<slug> -b <브랜치> <기준>`. 실행이 끝나면 서버가 커밋하고 `worktree remove` 한다. 남는 것은 브랜치뿐이라 쉬고 있는 변형은 디스크를 거의 쓰지 않는다. 다시 열면 다시 꺼낸다.
- **cli-agent**: 바꾸지 않는다. 폴더 저장소 경로를 `project_repo` 로, `main` 또는 `@previous` 를 `base_ref` 로 넘기면 지금 코드가 worktree·커밋·`output.worktree` 를 그대로 만든다(원격이 없어 `fetch` 는 조용히 실패하고 넘어간다).
- **deepagents**: 바꾸지 않는다. 작업 사본이 `.bpmn/<방|인스턴스>` 아래에 있으므로 지금의 도구 범위(set_workspace_scope)에 그대로 들어간다. 프로세스 단계 행은 엔진이 `TODO` 로 미리 만들므로, pgpt-pro 가 그 시점에 작업 사본을 준비하고, `DONE`/`SUBMITTED` 가 되면 커밋한다.
- **권한**: 폴더 화면·API·작업실은 서버가 구성원 권한으로 막는다. 에이전트는 자기 실행 폴더의 작업 사본만 받는다. 다만 샌드박스 셸은 지금처럼 테넌트 수준까지 볼 수 있다(다른 실행의 `.bpmn` 작업 사본). 폴더 저장소 자체(`.git`·main)는 샌드박스 마운트 밖이라 보이지 않는다.
- **인계**: 이어받기 = 보유자 변경 + 브랜치 그대로(작업 사본이 있으면 잠금). 받는 실행이 시작되면 그 실행 폴더에 다시 꺼낸다.
- **백업**: 폴더마다 매일 `git bundle` → 스토리지 버킷(`folders-backup`). 연결형 폴더는 원래 원격이 백업이다.
- **장점**: process-gpt 서비스 수정 없음, 기존 작업실·worktree·`@previous` 규칙 재사용, 드라이브 화면이 그냥 디렉터리, 쉬는 변형 비용 거의 0, 연결형 폴더(기존 제품 저장소)도 같은 방식.
- **단점**: 에이전트 격리는 지금 수준(도구 범위 + 테넌트 샌드박스). `main` 직접 편집과 반영이 경합하므로 반영 직전 자동 커밋·잠금이 필요하다. 공유 POSIX 파일시스템 전제(단일 호스트는 문제 없음, 다중 파드는 RWX 또는 폴더 친화 배치 필요).
- **깨지는 것**: 거의 없음. 정리 작업(72시간 sweep, `.checkouts` 7일)이 작업 사본 디렉터리를 지우면 worktree 등록이 남으므로 서버가 `git worktree prune` 을 주기적으로 돌려야 한다(지금도 필요한 정리).

### 안 3. 스토리지(Supabase) 가 원본, git 은 변형 작업공간에서만
파일의 정본은 스토리지 버킷과 DB 목록(매니페스트)이다. 변형을 열 때만 실행 노드 로컬 디스크에 내려받아 임시 git 저장소를 만들고, 끝나면 바뀐 파일만 올린다.

```
스토리지 버킷 folders/
└── <tenant>/<folder_id>/
    ├── blobs/<sha256>             # 내용 주소 저장(같은 파일은 한 번만)
    └── bundles/<variation_id>.bundle   # (선택) 변형 이력 묶음

DB
├── pro_folder_revisions(folder_id, rev, parent_rev, author, message)
├── pro_folder_entries(folder_id, rev, path, sha256, size, mime)   # rev 별 매니페스트
└── pro_folder_variations(…, base_rev, head_rev, status)

실행 노드 로컬(임시)
└── /var/pgpt/folder-ws/<tenant>/<variation_id>/   # base_rev 내려받기 → git init → 기준 커밋 → 에이전트 편집 → 차이 업로드
    (deepagents 는 .bpmn/<방>/folders/<slug>/ 에 같은 방식으로 내려받음)
```
- **변형 생성**: DB 에 `base_rev` 만 기록. 실행 때 매니페스트대로 내려받는다(지금 deepagents 하이드레이션과 같은 모양).
- **일괄 반영**: 매니페스트 3자 비교(기준 rev / 변형 / 현재 main). 경로별로 한쪽만 바뀌면 자동, 양쪽이 바뀐 텍스트는 `git merge-file` 로 3자 병합, 바이너리는 선택. 새 rev 를 만든다.
- **권한**: 스토리지 정책(RLS)과 서버 확인. 파일 URL 을 서명 URL 로 주면 폴더 권한이 그대로 지켜진다.
- **인계**: 변형 보유자 변경. 사본이 스토리지에 있으므로 다른 파드·다른 서비스도 바로 이어받는다. 지금 인계가 산출물을 스토리지에 올리는 것과 같은 방향이다.
- **백업**: 스토리지 자체가 정본·백업. 이음오피스는 스토리지 URL 로 바로 연다.
- **장점**: 다중 파드·공유 디스크 없이 동작, 대용량 파일에 강함(내용 주소·중복 제거), 이음오피스·첨부·인계와 저장처가 같다.
- **단점**: 진짜 git 이력이 아니다(변형 안에서만 git). 병합기·매니페스트·업로드 동기화를 새로 만들어야 한다. 큰 폴더는 변형을 열 때마다 내려받는 비용. 연결형 폴더(기존 git 저장소)와 모델이 달라 두 갈래가 된다. cli-agent 는 `project_repo` 대신 내려받은 임시 저장소를 넘겨야 한다.
- **깨지는 것**: `@previous`(브랜치 이름 기반)가 rev 기반으로 바뀐다. 사람 편집이 늘 업로드를 거쳐야 해서 작업실 "그 자리 편집" 이 업로드 단계가 된다.

### 안 4. 내부 Git 서버가 원본 + 실행별 부분 클론, 큰 파일은 스토리지
폴더마다 사내 git 서버(예: Gitea, soft-serve 같은 단일 노드 git 서비스)의 저장소가 정본이다. 실행 노드는 부분 클론(`--filter=blob:none`)해서 변형 브랜치를 만들고, 끝나면 push 한다. 반영은 서버 쪽에서 한다(풀 리퀘스트와 같은 모양).

```
git 서버 (정본, 단일 노드 + 백업)
└── <tenant>/<folder-slug>.git      # refs: main, var/*, inst/*, int/*  + LFS 객체는 스토리지

실행 노드(임시, 파드 로컬)
├── deepagents: workspace/<tenant>/.bpmn/<방>/folders/<slug>/   ← clone --filter=blob:none -b <변형>
├── cli-agent:  /tmp/cli-agent-ws/<tenant>/<todo>/<slug>/        ← project_repo = 클론, base_ref = origin/main (지금 기본값 그대로)
└── pgpt-pro:   드라이브 화면은 git 서버 API(트리·내용)로 읽음
```
- **변형 생성**: 서버 API 로 브랜치 생성 → 실행 노드가 클론. 끝나면 서비스가 커밋·push(실행별 짧은 토큰).
- **일괄 반영**: git 서버에서 통합 브랜치 생성·병합·검사, `main` 보호 브랜치로 반영. 충돌 해결은 클론한 통합 사본에서 사람·에이전트가 한다.
- **권한**: git 서버의 저장소 권한(구성원 동기화) + 실행별 토큰. 에이전트는 자기 변형 브랜치에만 push 할 수 있다.
- **장점**: 다중 파드에서 진짜 git, cli-agent 의 `origin/main` + `fetch` 흐름과 정확히 맞는다, 보호 브랜치·리뷰·웹훅 같은 기존 도구를 쓴다, 대용량은 LFS → 스토리지.
- **단점**: 새 인프라(git 서버 운영·백업·인증 연동), 실행마다 클론·push 지연, 드라이브 화면이 원격 API 에 의존, 구성원 권한을 두 곳(pgpt-pro·git 서버)에 맞춰야 한다.
- **깨지는 것**: 로컬 단일 호스트 개발에도 git 서버를 띄워야 한다. 사람 "그 자리 편집" 은 작업 사본 클론을 거쳐 push 해야 한다.

## 4. 비교와 추천

| 기준 | 안 1 bare + 영속 worktree | 안 2 살아 있는 폴더 + 필요 시 체크아웃 | 안 3 스토리지 정본 | 안 4 git 서버 정본 |
| --- | --- | --- | --- | --- |
| process-gpt 서비스 수정 | deepagents(폴더별 컨테이너), cli-agent(bare 지원) | 없음 | cli-agent·deepagents 연결 지점 | 거의 없음(cli-agent 는 원래 원격 기준) |
| 새로 만들 것 | 폴더 서비스, 샌드박스 수정 | 폴더 서비스 | 폴더 서비스 + 매니페스트·병합기·동기화 | 폴더 서비스 + git 서버 운영·인증 |
| 에이전트 격리 | 최강(마운트) | 지금 수준(도구 범위, 셸은 테넌트) | 지금 수준 | 지금 수준 + push 권한 제한 |
| 변형 생성 비용 | 빠름(영속 사본) | 빠름(로컬 worktree), 쉬는 변형 0 | 매번 내려받기 | 매번 부분 클론 |
| 다중 파드 운영 | RWX 필요 | RWX 또는 폴더 친화 배치 필요 | 그대로 됨 | 그대로 됨 |
| git 이력·비교 | 완전 | 완전 | 변형 안에서만 | 완전 + 리뷰 도구 |
| 대용량·문서 | 포인터/LFS 직접 | 포인터/LFS 직접 | 강함(내용 주소) | LFS → 스토리지 |
| 드라이브 화면(사람 편집) | main worktree | 폴더 그 자체 | 업로드 경유 | 원격 API·클론 경유 |
| 기존 제품 저장소 등록 | 가능(bare 미러 필요) | 그대로 가능 | 따로 처리 | 가능(원격 미러) |
| 구현 난이도 | 중상 | 하 | 상 | 중(+운영) |

### 추천: 안 2, 단 안 4 로 옮겨 갈 길을 열어 둔다
- 지금 pgpt-pro·process-gpt 는 한 호스트에서 돈다. 안 2 는 process-gpt 서비스를 하나도 바꾸지 않고 cli-agent 의 worktree·`@previous`·서비스 커밋, deepagents 의 실행 폴더 범위, pgpt-pro 작업실을 그대로 쓴다. 가장 빨리 실제로 돌려 볼 수 있다.
- 사용자가 말한 "드라이브처럼 등록해 두고 쓰는 공간" 은 폴더가 곧 디렉터리인 안 2 가 가장 자연스럽다. 쉬는 변형이 디스크를 쓰지 않아 변형을 많이 만들어도 부담이 없다.
- 옮겨 갈 길: 모든 git 조작을 폴더 서비스 한 곳에서만 하고, 브랜치 이름 규칙을 원격에서도 같게 쓰면, 나중에 각 폴더의 `.git` 을 git 서버로 올리고 `project_repo` 를 클론으로 바꾸는 것만으로 안 4 가 된다. 다중 파드 운영이 필요해지는 시점에 옮긴다.
- 격리가 꼭 필요한 폴더(계약서 등)는 안 1 의 "폴더별 샌드박스" 만 부분 도입할 수 있다(deepagents 수정이 필요하므로 별도 변경으로).

## 5. 사용자가 정할 것
1. **저장 구조**: 안 2(추천) / 안 1 / 안 3 / 안 4. 운영 다중 파드까지 지금 고려할지.
2. **main 직접 편집**: 드라이브처럼 main 에 바로 올리고 고치게 할지(추천: 허용, 반영 직전 자동 커밋), 모든 변경을 변형으로만 받을지.
3. **변형 기본 단위**: 실행마다 + 인스턴스 라인(추천) / 인스턴스마다 하나 / 사람마다 하나.
4. **충돌 기본 정책**: `stop`(추천) / `agent` / `choose`.
5. **에이전트 격리**: 지금 수준으로 시작할지, 폴더별 샌드박스를 처음부터 넣을지.
6. **대용량 파일**: 임계값(제안 20MB)과 git LFS 도입 시점.
7. **기존 `project` 테이블**: 폴더를 프로젝트에 묶을지(`project_id` 는 있으나 비어 있음).
8. **반영 위치**: 프로세스의 "검토·반영" 사람 활동으로도 할지, 폴더 화면 버튼만 둘지(추천: 둘 다, 같은 서버 기능).
9. **인계 기본값**: 이어받기(같은 브랜치, 추천) / 갈래 만들기.
10. **연결형 폴더**: 지금 cli-agent 가 쓰는 제품 저장소(`<process-gpt>`)를 첫 연결형 폴더로 등록해 쌓인 `pgpt-agent/*` 브랜치·worktree 를 변형으로 거둘지.

## 6. 결정 (2026-10-24, 사용자 확정)
| 항목 | 결정 |
| --- | --- |
| 저장 구조 | **안 2** — 폴더 = 살아 있는 디렉터리(작업 트리가 곧 `main`), 변형은 브랜치로만 두고 실행할 때 실행 폴더 안에 꺼낸다. 안 4(git 서버)로 옮겨 갈 길은 열어 둔다 |
| `main` 직접 편집 | 허용(드라이브처럼 올리고 고친다). 반영 직전에 사람 편집을 자동 커밋한다 |
| 변형 단위 | 실행마다 변형 하나 + 인스턴스 라인 |
| 충돌 기본 정책 | `stop` — 멈추고 알린다. `agent`·`choose` 는 고를 수 있다 |
| 반영 위치 | 프로세스의 "검토·반영" 사람 활동과 폴더 화면 버튼, 둘 다(같은 서버 기능) |
| 인계 기본값 | 이어받기(같은 브랜치, 보유자만 바뀜) |
| 첫 연결형 폴더 | `<process-gpt>` 를 등록하고 쌓인 `pgpt-agent/*` 브랜치·worktree 를 변형으로 가져와 정리한다. **이번 단계에서는 저장소를 건드리지 않는다** |
| 에이전트 격리 | 지금 수준(도구 범위 + 테넌트 샌드박스)으로 시작. 폴더별 샌드박스는 별도 변경 |

## 7. 화면 (UI 프로토타입)
사용자 요청: 작업 폴더를 열어 보는 화면, 폴더마다 브랜치(변형)를 열어 보는 화면, 산출물을 누르면 바로 미리보기와 내용을 보는 기능.

### 7.1 agent-share 에서 가져올 것과 버릴 것
- agent-share(`<agent-share>`)에는 세션 폴더의 파일 패널(탐색·올리기·이름 바꾸기), 텍스트·마크다운·이미지·PDF 보기, LibreOffice 로 PDF 변환한 오피스 미리보기, 그리고 한 작업 사본의 git 변경 목록·파일별 diff·커밋 이력(gitview)이 있다.
- 어색한 이유: 터미널이 화면의 주인공이고 파일은 옆 패널이다. 폴더가 "세션의 작업 디렉터리 경로" 로만 보이며, 누가 만든 사본인지(사람/에이전트), 어느 실행·인스턴스에서 왔는지, 상태(작업 중/반영 대기/충돌)가 없다. diff 는 "지금 작업 사본 vs HEAD" 뿐이라 여러 갈래를 나란히 비교하거나 골라 합칠 수 없다. 오피스 문서는 PDF 로 바꾼 그림이라 원래 형식으로 열리지 않는다.
- 가져올 것: 파일 패널의 조작감, 마크다운 렌더링, 줄 단위 diff 표기. 버릴 것: 터미널 중심 배치, 경로 중심 표기, PDF 변환 미리보기(이음오피스·ArtCraft 앱으로 원래 형식 그대로 연다).

### 7.2 프로토타입 화면 (가짜 데이터, 서버 API 없음)
| 주소 | 화면 |
| --- | --- |
| `/folders` | 폴더 목록(드라이브): 이름·설명, 구성원(사람 동그라미/에이전트 네모), 최근 활동, 살아 있는 변형 수(작업 중·반영 대기), 색인 상태(문서 카드/파일 목록만/색인 중). 위쪽 검색창은 색인(파일 이름 + 문서 카드 요약·키워드)을 찾는다 |
| `/folders/:slug` | 폴더: 왼쪽 `main` 파일 트리(디렉터리 접기, 수정한 사람·날짜·크기, 카드 표시)·이력·색인 탭, 오른쪽 변형 목록(제목, 브랜치, 보유자, 출처 실행/인스턴스/사람, 상태, main 보다 앞섬/뒤처짐, 시각) + 고르기 → 일괄 반영(순서 정하기 → 차례로 합치기 → 충돌이면 멈춤·양쪽 비교·해결 에이전트/한쪽 고르기 → 반영 완료·고르지 않은 형제 갈래 버리기) |
| `/folders/:slug/v/:variation` | 변형: main 과 비교한 바뀐 파일(A/M/D, +/−), 텍스트·코드는 줄 단위 diff(코드 강조), 문서·이미지는 main/변형 양쪽 미리보기와 "바뀐 점"(카드 비교), 커밋, 인계하기(받는 사람·이어받기/갈래·한 일·할 일·비구성원 권한), 이 변형만 반영 |
| (어느 화면에서나) 파일 누르기 | 오른쪽 시트 미리보기: 마크다운 렌더링, 코드 강조, CSV 표, 이미지, 영상, 소리, 한글·워드·엑셀·파워포인트·PDF 는 이음오피스 읽기 전용, CAD·PSD 는 ArtCraft 앱. 옆에 색인의 문서 카드(요약·키워드·쪽 수·크기·마지막 수정·위치)와 "에이전트에게 이 파일로 묻기" |

- 구현 위치(검토 대상): pgpt-pro `src/views/FoldersView.vue`, `src/components/folders/*`, 가짜 데이터 `src/prototype/foldersMock.js`, 진입점은 상단 탭 "폴더". 미리보기 파일은 로컬 스토리지 `files` 버킷에 이미 있는 실제 문서를 빌려 쓴다.
- 실제 구현 때 바뀌는 것: 가짜 데이터 → 폴더 서비스 API, 반영·인계 흉내 → 서버 기능, "작업실에서 열기" → 기존 작업실(`/workroom`)에 폴더·변형 종류 추가.

## 8. 색인
목표: 사람(검색창)과 에이전트(도구)가 "어느 폴더의 어느 파일이 지금 일에 맞는지" 를 빠르게 고른다. 파일을 많이 쓰지 않는 폴더는 파일 목록만으로 충분하고, 문서가 많아질수록 카드 → 본문 색인으로 단계를 올린다.

### 8.1 지금 있는 것 — memento 지식저장소의 문서 카드
- `knowledge_files.doc_card` = `{abstract, n_pages, generated_at, generation_model}`. 문서를 페이지로 나눠 저장(`document_pages`)한 뒤, 앞부분과 마지막 페이지를 LLM 에 한 번 보내 "이 문서가 무엇인지 1~2문장" 을 받는다(추측 금지 프롬프트). 용어집 문서는 `glossary_compact` 를 따로 만든다. 데이터셋(엑셀 등)은 페이지·임베딩 없이 workbook 카드만 만든다.
- 에이전트는 navigator 엔드포인트 세 개로 문서를 탐색한다: `GET /catalog`(고른 자료의 카드 목록) → `GET /document/grep`(한 문서 안 정확한 위치) → `GET /document/page`(페이지 본문). LLM 에는 긴 id 대신 파일 이름만 보인다. 그 밖에 청크·임베딩 기반 `/retrieve`(RAG)가 있다.
- 로컬 DB 기준 카드 26건 중 17건이 채워져 있고 일부는 `abstract: null`(생성 실패) — 카드 생성은 실패해도 목록에는 남아야 한다.

### 8.2 결정 — 3단계 색인
| 단계 | 대상 | 내용 | 언제 |
| --- | --- | --- | --- |
| 0. 파일 목록 | 모든 폴더의 `main` 과 살아 있는 변형의 바뀐 파일 | 경로·종류·크기·수정 시각·수정자·내용 해시 | 커밋마다(싸다). 늘 켜짐 |
| 1. 문서 카드 | 문서 파일(한글·워드·엑셀·파워포인트·PDF·마크다운·CSV·텍스트) | memento 와 같은 카드 모양 `{abstract, n_pages, generated_at, generation_model}` + `keywords` | `main` 에 반영된 뒤 비동기로. 내용 해시가 같으면 다시 만들지 않음. 변형의 바뀐 문서는 "바뀐 점" 한 줄(선택) |
| 2. 본문 색인 | 폴더 전체 문서 | 페이지 저장·grep·페이지 읽기·청크 임베딩 — memento 파이프라인 그대로 | 아래 임계값을 넘거나 폴더 설정에서 켰을 때만 |

- **2단계로 올리는 임계값(제안)**: 문서 파일 200개 초과, 또는 카드 목록이 약 12k 토큰(카드 1개 ≈ 60 토큰 × 200)을 넘을 때, 또는 추출 텍스트 합계 5MB 초과. 그 아래에서는 카드 목록을 통째로 에이전트에게 주는 편이 검색보다 빠르고 정확하다.
- **코드 중심 연결형 저장소**(예: process-gpt, 파일 4,812개): 0단계만. 에이전트는 경로·이름으로 고르고 작업 사본에서 직접 grep 한다. 카드는 README·설계 문서 같은 문서 파일에만 선택적으로.
- **이미지·소리·영상·CAD**: 0단계만(이름·위치). 캡션 카드는 나중 선택.
- **에이전트 도구**: `folder_catalog(query?)` — 읽을 수 있는 폴더 목록과 일치하는 파일의 카드 요약을 돌려준다. `folder_files(folder, path?)` — 0단계 목록. 본문은 실행의 변형 작업 사본에서 직접 읽는다. 2단계가 켜진 폴더는 memento navigator 와 같은 `grep`·`page` 를 쓴다. 도구는 pgpt-pro 의 MCP 게이트웨이로 낸다.
- **권한**: 색인 행은 폴더에 속하며, 검색 결과는 요청한 사람(에이전트 실행이면 실행을 시작한 사람·담당자)이 읽을 수 있는 폴더로만 SHALL 좁혀진다.
- **memento 재사용 방식(선택지)**: (가) 1단계 카드는 pgpt-pro 가 같은 프롬프트·모양으로 직접 만들고, 2단계에서만 폴더 파일을 memento 에 `source_type='folder'` 로 등록한다(추천 — 작은 폴더에 memento 의존이 생기지 않음). (나) 1단계부터 memento 에 등록해 카드 생성까지 맡긴다(코드 재사용 최대, memento 실행 필수).

## 9. 2차 결정 (2026-10-24, 프로토타입 확인 후 사용자 확정)
| 항목 | 결정 |
| --- | --- |
| 화면 | 프로토타입 그대로(목록·폴더·변형·미리보기 시트) |
| 본문 색인 임계값 | 문서 200개 / 카드 약 12k 토큰 / 추출 텍스트 5MB, 또는 폴더 설정으로 켬 |
| memento 재사용 | (가) 문서 카드는 pgpt-pro 가 memento 와 같은 모양으로 직접 만든다. memento 는 본문 색인 단계에서만 쓴다 |
| 변형 "바뀐 점" 카드 | 만든다(변형 커밋 뒤 LLM 1회, 짧은 이름도 함께) |
| 검색 범위 | 이름·카드, 본문 색인이 켜진 폴더는 본문까지 |
| 이음오피스 읽기 전용 미리보기 | AI 패널을 숨긴다(채팅 시트의 편집 화면은 그대로) |

## 10. 구현 (pgpt-pro)
- **저장 위치**: 폴더 저장소는 `PRO_FOLDERS_ROOT`(기본 `~/pgpt-folders`)`/<tenant>/<slug>` — deepagents 작업공간 밖이라 샌드박스에서 보이지 않는다. 실행용 작업 사본은 실행 폴더 안 `services/deepagents/workspace/<tenant>/.bpmn/<방|인스턴스>/folders/<slug>`(샌드박스 `/workspace/.bpmn/…`), 사람 작업 사본은 `<root>/.people/<uid>/<변형>`, 반영용 통합 사본은 `<root>/.integrate/<slug>/<id>`.
- **DB**(`server/sql/007_folders.sql`, 로컬 적용): `pro_folders`, `pro_folder_members`, `pro_folder_variations`, `pro_folder_integrations`, `pro_folder_files`(목록·카드·본문 색인), 테넌트 MCP 항목 `pgpt-folders`.
- **서버**(검토 대상): `server/lib/folders/`(git·service·indexer·merge·handover·work·runner·rooms), `server/routes/folders.js`, `server/mcp/folders.js`. git 은 서버만 실행한다.
- **채팅**: 요청이 사용자가 실행 이상 권한을 가진 폴더 이름을 담고 고쳐 달라고 하면, 새 대화 id 로 변형을 만들어 그 실행 폴더에 꺼내고 deepagents 에 작업 폴더를 알려 준다. 턴이 끝나면 서버가 커밋·거두고 "바뀐 점" 카드를 만든 뒤 채팅에 변형 카드(`folder_variation`)를 남긴다.
- **프로세스 단계**: `agent_config.folder`(id 또는 slug)·`base_ref`(`main`/`@previous`/`var:<브랜치>`)가 있는 단계를 서버가 4초마다 살핀다. cli-agent 단계는 `project_repo`=폴더 저장소, `base_ref` 를 채워 주고(cli-agent 무수정), 끝난 뒤 그 브랜치를 변형으로 등록한다. deepagents 단계는 `TODO` 일 때 인스턴스 실행 폴더에 작업 사본을 만들고 지시문(`query`)에 `[Folder]` 안내를 덧붙이며, 끝나면 커밋한다. 단계 결과는 인스턴스 라인 `inst/<id>` 로 이어지고 `@previous` 가 이를 따른다.
- **인계**: process-gpt 프런트의 채팅 인계와 같은 기록을 한 트랜잭션으로 남긴다(받는 방 `context.handover`·브리핑·ad-hoc 할 일·`handover_events`·알림). 산출물은 `{type:'folder_variation', folder_id, variation_id, branch, commit, mode}`. ad-hoc 할 일은 인스턴스가 없지만 `todolist` 트리거(`task_execution_properties.proc_inst_id NOT NULL`)가 인스턴스 id 를 요구하므로 `handover.<case_id>` 를 넣는다(process-gpt 프런트의 putWorklist 도 같은 제약에 걸릴 수 있음 — 확인 필요). 받는 쪽이 에이전트면 pgpt-pro 가 그 방에서 deepagents 실행을 바로 돌리고 결과를 같은 변형에 커밋한 뒤 할 일을 `DONE` 으로 닫는다(폴러와 겹치지 않도록 `agent_orch='pgpt-pro-folders'`).
- **편집기 미리보기**: 이음오피스·ArtCraft 는 스토리지 주소만 열 수 있어, 그 버전의 blob 을 `files` 버킷 `pgpt-pro/folders/<폴더>/<blob sha>.<ext>` 로 한 번 올린 사본으로 연다(공개 버킷이라 주소를 아는 사람은 열 수 있음 — 운영에서는 서명 URL 로 바꿀 것). 본문은 작업실과 같은 `FileView` 를 쓴다.
- **작업실**: 방 종류 `folder`(main, 편집 권한)와 `variation`(사람 작업 사본, 실행 권한)을 더했고, 작업실 저장은 곧 커밋이 된다.

## 11. 남은 일·위험
- 운영 다중 파드: 폴더 저장소는 공유 파일시스템(RWX) 전제. 옮길 때는 안 4(git 서버).
- 에이전트 격리: 샌드박스 셸은 테넌트 수준까지 보인다(다른 실행 폴더의 작업 사본). 폴더별 샌드박스는 별도 변경.
- 프로세스 단계 연결은 시뮬레이션(할 일 행 직접 생성)으로만 검증했다. 실제 엔진으로 deepagents 단계를 돌릴 때 엔진이 `TODO` 를 거치지 않고 바로 `IN_PROGRESS` 로 만들면 작업 사본 준비가 늦을 수 있다.
- memento 가 로컬에서 꺼져 있어 본문 색인은 pgpt-pro 가 보관한 추출 텍스트로 찾는다(memento 등록은 시도만 함).
- 공개 버킷 사본(편집기용), 작업실 저장의 커밋 작성자가 '작업실' 로 남는 점.
