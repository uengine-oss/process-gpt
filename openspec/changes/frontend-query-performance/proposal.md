## Why

프론트엔드 번들을 줄여 첫 로드는 빨라졌지만(gzip 3.86MB → 872KB), 운영 Supabase 에
붙이면 화면이 여전히 느렸다. 원인을 추정하지 않고 **운영 테넌트(uengine)에 실제로
로그인해 Playwright 로 계측**한 결과, 병목은 네트워크도 렌더링도 아니고 **데이터 조회
방식**이었다.

계측 기준선 — 로그인 → 첫 화면:

| 항목 | 값 |
|---|---|
| 벽시계 시간 | 21.5초 |
| 가장 느린 단일 호출 | `proc_def` **11.7초** |
| `users select=*` | 9회 / 합계 11.3초 |
| `bpm_proc_inst` 무제한 조회 | 5.4초 |

네트워크는 문제가 아니다. 운영 Supabase 의 TTFB 는 ~60ms 로 정상이다.

## What Changes

조회 계층의 네 가지 안티패턴을 제거한다.

- **목록 조회에서 대용량 본문 컬럼을 제외한다.** `proc_def` 의 `definition`(BPMN JSON)·
  `bpmn`(XML), `chat_rooms` 의 `context` 는 목록 렌더링에 쓰이지 않는데 응답의 대부분을
  차지한다.
- **서버에서 거를 수 있는 것을 클라이언트에서 거르지 않는다.** 유사 프로세스 검색이
  `proc_def` 전량을 받아 `Array.includes` 로 필터링하고 있었다. `in` 필터로 옮긴다.
- **페이지네이션 인자를 무시하지 않는다.** `getAllInstanceList(page, size)` 가 두 인자를
  받고도 전량을 조회했다.
- **같은 조회의 중복 발사를 막는다.** 화면 여러 곳이 각자 사용자 목록을 불러
  `users select=*` 가 한 화면에서 9번 나갔다.

## Impact

- Affected specs: 없음(기존 동작 유지, 조회 방식만 변경)
- Affected code: `services/frontend/src/components/api/ProcessGPTBackend.ts`
- 사용자에게 보이는 동작 변화 없음 — 목록에서 쓰지 않던 컬럼만 빼고, 중복 호출을 합쳤다.

## Non-goals

- **DB 인덱스 추가는 이 변경에 포함하지 않는다.** 운영 스키마 변경이라 별도 승인이 필요하다.
  다만 진단 과정에서 확인된 사실은 `design.md` 에 남긴다 — 인덱스를 추가하면 특히
  채팅 로딩에서 추가 개선 여지가 크다.
- 화면 컴포넌트의 N+1 호출(`InstanceCard` 카드별 `getInstance`)은 이번 범위 밖이다.
