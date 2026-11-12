## 1. 설계
- [x] 1.1 설명 영상과 v0.1 대조, v0.2 설계(`design.md`), 결정 D-1112-41~44 · D-1113-41~43

## 2. 서버
- [x] 2.1 `sql/033_process_ontology.sql` — 메일 이력 · 작업 · 이름 · 건 · 답
- [x] 2.2 `lib/ontology/store.js` — Bolt 접근, 설치 때만 그래프 · 타입 · 시점 속성, 외부에서 지운 그래프 다시 만들기
- [x] 2.3 `lib/ontology/history.js` · `names.js` — 메일 깔때기, 이름 맞추기 · 합치기
- [x] 2.4 `lib/ontology/stats.js` · `build.js` — 통계 · 자동 값 · 묶음 · 주마다 다시 계산
- [x] 2.5 `lib/ontology/run.js` · `taskdef.js` — 스냅샷 · 시작 일 · 건 · 일꾼 · 일 정의 · 점검
- [x] 2.6 `lib/ontology/review.js` — 검토 안건 · 고정 · 은퇴 · 결정 원장
- [x] 2.7 `routes/ontology.js`, 메일 연결 온보딩, 메일 라우팅(지도 먼저)

## 3. 화면
- [x] 3.1 `/process-map` — 지도 · 묶음 · θ · 시점 · 값 보기 · 이름 맞춘 기록 · 검토 안건 · 스냅샷 보기 · 일 정의
- [x] 3.2 채팅 카드 — 요약 · 시작 일 · 습관, 업무 에이전트 메시지의 점검 항목

## 4. 시험 · 회귀
- [x] 4.1 단위(`ontology-stats` · `ontology-taskdef` · `ontology-mapview`, 사례 `ontology-cases.json`)
- [x] 4.2 HTTP E2E S1 · S2 · S3, Playwright F-PO-01…08, 카탈로그 20절
- [x] 4.3 데모 테넌트 `ax-demo`(메일함 · 양식 · 채팅 인계 · 초기화)

## 5. 영상 · 문서
- [x] 5.1 시연 영상 3편 녹화 · 내레이션(`onto-map-ko` · `onto-run-ko` · `onto-review-ko`)
- [ ] 5.2 유튜브 업로드(일부 공개) — 업로드용 브라우저에서 채널 계정 로그인 대기
- [x] 5.3 튜토리얼 20장, 제품 페이지 항목(한 · 영)
- [ ] 5.4 영문 튜토리얼 장 · 영문 영상

## 6. 남은 것
- [ ] 6.1 설치판에 Ontological DB 컨테이너
- [ ] 6.2 Gmail 지난 메일 읽기 시험
- [ ] 6.3 굳은 길 묶음에서 습관이 실제로 묻는 장면
- [ ] 6.4 본판 엔진 정의 모델에 `skills` 칸
- [ ] 6.5 Ontological 원본에 `UNWIND … MERGE`(시간 이력 키 타입) 키 중복 알리기
