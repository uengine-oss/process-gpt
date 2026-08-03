# Tasks

## 1. 계측 기반 마련
- [x] 1.1 REST 응답시간 측정 스크립트 (`rest-latency-probe.mjs`)
- [x] 1.2 화면별 쿼리 프로파일러 (`query-profile.mjs`)
- [x] 1.3 운영 시나리오 벤치 (`prod-scenario-bench.mjs`)
- [x] 1.4 로컬에서 운영 테넌트로 붙기 위한 `VITE_TENANT_OVERRIDE` 지원

## 2. 진단
- [x] 2.1 네트워크 배제 (운영 TTFB ~60ms 확인)
- [x] 2.2 운영 기준선 측정 (로그인→첫 화면 21.5초, `proc_def` 11.7초)
- [x] 2.3 `SELECT *` 비용 정량화 (`users` 909ms/674KB vs 96ms/89KB)
- [x] 2.4 인덱스 부재 확인 (chats·chat_rooms·todolist·bpm_proc_inst)

## 3. 수정
- [x] 3.1 `listDefinition` 3경로에 컬럼 투영 — `definition`·`bpmn` 제외
- [x] 3.2 유사 프로세스 검색: 전량 조회 → `in` 필터 + 컬럼 축소
- [x] 3.3 `getAllInstanceList`: `page`/`size` 반영 + 상한 200
- [x] 3.4 `getChatRoomList`: `context` 제외
- [x] 3.5 사용자 목록 중복 호출 제거 (in-flight 공유 + 3초 캐시)

## 4. 검증
- [x] 4.1 `vue-tsc` 타입 에러 0
- [x] 4.2 운영 재측정 — 최대 지연 11.7초 → 1.4초, 전송량 12.1MB → 1.15MB
- [x] 4.3 호출부 전수 확인 — `listDefinition` 소비처가 `.definition`/`.bpmn` 미사용
- [ ] 4.4 채팅방 열기 시나리오 실측 (벤치의 방 선택 셀렉터가 운영 화면에서 불안정)

## 5. 후속 (이번 범위 밖)
- [ ] 5.1 운영 DB 인덱스 추가 — `design.md` 5장의 SQL, 별도 승인 필요
- [ ] 5.2 `InstanceCard` N+1 제거 (카드별 `getInstance` → `in` 일괄 조회)
- [ ] 5.3 `chat_rooms`·`users` 목록 추가 축소/페이지네이션
