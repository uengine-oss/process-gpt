# 검증: 가드레일이 글을 읽는 순서

## 실행
- 실제 BFF(`PRO_TENANT_HOSTS=…,team.localhost=team-demo`, :8798) + 공용 Supabase + 회사 게이트웨이 모델 `frentis-ai-model`. 시드 `node scripts/seed-team-context.mjs --live`.
- 단위: `node --test test/guard-reading.test.js test/context-policy.test.js`
- HTTP E2E: `node test/guard-reading.e2e.mjs`(모델이 닿지 않는 서버를 하나 더 띄운다), `PRO_API=http://127.0.0.1:8798 node test/scenario-mail.e2e.mjs --no-chat`
- 품질 하한: `node test/guard-eval.e2e.mjs`, 표: `node scripts/eval-guard.mjs <context|mail> <dev|test|all> [out.json]`, 필드: `node scripts/eval-guard-fields.mjs`

## 시나리오 ↔ 시험
| 시나리오 | 시험 |
|---|---|
| 돌려 말한 민감한 글 · 낱말만 같은 일반 글 · 주민번호 형식 · 전화 형식 · 정책 끔 | `guard-reading.e2e.mjs` 1–5, 9 |
| 같은 글과 고친 글 | `guard-reading.e2e.mjs` 6–7 |
| 모델이 끊긴 동안 · 돌아온 뒤 | `guard-reading.e2e.mjs` 10–13 |
| 확률을 주지 않는 모델 | `guard-reading.e2e.mjs` 14–15 |
| 표시 없는 기밀 자료 · 빈 양식 · 사내 메일 | `scenario-mail.e2e.mjs` |
| 품질 하한 | `guard-eval.e2e.mjs` |

## 사례(서버 `test/guard-eval/`)
구현과 모델을 모르는 별도 에이전트가 쓴 가상 사례: 맥락 260(명시 45 · 돌려 말함 75 · 낱말만 같음 60 · 평범 50 · 형식 20 · 모호 10), 메일 90, 필드 이름 80. id 해시로 dev·test 를 나눈다. 질문 문구는 dev 로만 고쳤고 기준값 0.5 는 test 를 돌리기 전에 고정했다. 사람이 쓴 뚜렷한 글이라 실제 업무 글의 성능을 그대로 뜻하지 않는다.

## 결과(2026-11-03)
맥락 test 103건(민감 56 · 일반 47, 모호 제외):
| 구성 | 민감 잡음 | 오탐 | 정확도 |
|---|---|---|---|
| 낱말·형식만(전) | 16/56 | 22/47 | 40% |
| 낱말·형식 먼저, 걸리면 민감 → 통과분 모델 | 56/56 | 22/47 | 79% |
| 구현(주민번호 → 모델) | 56/56 | 6/47 | 94% |

맥락 전체 250건(dev 포함, 모호 제외):
| 구성 | 민감 잡음 | 오탐 | 정확도 |
|---|---|---|---|
| 구현(주민번호 → 모델) | 129/129 | 11/121 | 96% |
| 형식 셋 먼저 → 모델(첫 안) | 129/129 | 16/121 | 94% |
| 모델만(0.5) | 129/129 | 9/121 | 96% |
| 낱말 먼저 → 모델 | 129/129 | 56/121 | 78% |

형식 묶음 20건: 민감 9건을 모두 잡고 일반 11건 중 오탐 3건이다. 형식 셋을 앞에 두면 오탐이 9건이었다.
기준값은 0.5 를 유지한다. 모델만 기준으로 0.7 이면 오탐이 9건에서 3건으로 줄고 놓친 글이 없었지만, 사례가 뚜렷한 글이라 실제 업무 글로 잰 뒤 정한다.

메일 test 47건: 구현 29/29·오탐 1/18·98%, 표시 낱말만(전) 9/29·4/18·49%, 낱말 먼저 29/29·5/18·89%. 모델이 끊긴 동안의 외부 메일은 표시 낱말로 판단하고, 걸리지 않으면 기록하고 보낸다(10분 안 회수).

패널 앱 필드 이름 80건(민감·개인 45, 일반 35): 낱말 하한 놓침 16·과잉 12, 모델 놓침 5·과잉 2, 낱말 또는 모델 놓침 2·과잉 14. 필드 민감도는 이번에 바꾸지 않았다(과잉의 비용이 칸 하나 가리는 정도이고, 실제 코드는 앱 설계 모델의 제안에 낱말 하한을 더하는 구조라 이 표와 같지 않다).

시험: 단위 377 통과(`browser-vault` 제외, 오래 붙잡는 시험), HTTP E2E guard-reading 15단계·28개·context-policy 35·context-share 8단계·context-grade 63·team-activity 12단계·repeat 22·scenario-mail 10단계(`--no-chat`), Playwright team-context+agentic 15. 출력은 `results/`.
