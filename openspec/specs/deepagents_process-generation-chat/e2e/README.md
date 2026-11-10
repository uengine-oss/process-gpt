# deepagents_process-generation-chat — E2E

## 실행 환경
- VM 설치본. deepagents는 통합 브랜치(`integrate/tutorial-fixes-1110`, process-gpt-deepagents #11) 이미지 `process-gpt-deepagents:tutorial-1110`.
- 프런트: 설치본 빌드(답한 질문 패널 수정 전) 또는 `fix/hitl-stale-panel`(process-gpt-vue3 #243) 개발 서버.
- 계정: 관리자 장진영. 모델 호출은 설치본 `.env`의 OpenAI 키(11-10 갱신).

## 실행 명령
```bash
# process-gpt/demo/tutorial 에서 — 3장 프롬프트를 딥 에이전트로 N번, 끝(생성/보류)·패널·답을 잰다
PGPT_ENV=vm DOCKER_CONTEXT=colima-pgtut SHOTS=<결과 폴더> RUN=1 node _measure-deep-ch3.mjs
PGPT_URL=http://127.0.0.1:5291 ...   # 프런트를 개발 서버로

# 단위 시험
pytest tests/test_hitl.py tests/test_stream_scope.py      # deepagents
node --test src/shared/hitl/hitl.test.js                   # process-gpt-vue3
```

## 스펙 시나리오 ↔ 시험
| 시나리오 | 시험 | 결과 |
|---|---|---|
| 고르기를 연다 | process-gpt-vue3 F-UX-15 | ✅ |
| 3장 프롬프트 | `results/deep-ch3-runs.md` B · C 판 4회 모두 생성(55~65초), 보류 0 | ✅ |
| 건너뛰기 | 단위 `test_empty_candidate_answer_*` · B · C 판 답에 스킬 언급 없음(A 판 3회 중 2회 있음) | ✅ (파일 개수는 ◐ 화면 확인) |
| 스킬을 고른다 | 단위 `test_task_tool_subagent_namespaces` · B · C 판 답에 「created:」 없음(A 판 3회 중 2회 있음) | ✅ |
| 승인한 뒤 | 단위 「이미 답한 질문의 패널」 3개 · C 판 2회 「승인」 1번, 패널 2개(B 판 2회 중 1회 「승인」 2번) | ✅ |

## 증거
- `results/deep-ch3-runs.md`: 판(A 수정 전 · B 백엔드 수정 · C 백엔드+프런트 수정)별 회차 결과
- `results/before-stale-draft-panel.png`: 수정 전 — 「승인」을 보낸 뒤에도 위의 초안 질문에 「응답 제출」이 열려 있다
- `results/after-created.png`: 수정 뒤 — 생성 완료, 작업 폴더에 흐름도 · 폼
- `results/unit-deepagents-chat.txt`, `results/unit-hitl-panels.txt`: 단위 시험 출력

## 남은 공백
- 초안 질문 문장이 패널 머리와 본문에 세 번 되풀이된다(스킬 문서의 질문 형식). 고치지 않았다.
- 운영(*.process-gpt.io)에서 같은 시험은 운영 시험 계정이 있어야 한다.
