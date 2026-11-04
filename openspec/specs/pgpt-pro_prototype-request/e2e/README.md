# 검증: 시작품 요청 메일

## 실행
- 실제 BFF(`PRO_PORT=8792 PRO_BACKGROUND=0`, `PRO_ARTCRAFT_ROOT`, Craft CLI) + 공용 Supabase + 공용 deepagents + 회사 게이트웨이 모델 `frentis-ai-model`. Vite `PRO_API_TARGET=http://127.0.0.1:8792 --port 5192`.
- 끝까지(실제 모델·실제 도구·실제 에이전트): `cd server && API_URL=http://localhost:8792 node test/prototype.e2e.mjs`
- 판별·치수·첨부: `cd server && node --test test/prototype.test.js` (사례 `test/prototype-cases.json`)
- PSpice 호환(값은 이론과 비교): `cd craft/pspice && node --test test/pspice.test.mjs`. 벤더 모델은 저장소에 없다: `test/fetch-models.sh`. 진짜 TDK 모델은 `TDK_MODEL`, `TDK_FARADS`.
- 실제 프로젝트 측정(시험이 아니라 측정, 파일은 저장소에 없다): `node craft/pspice/test/corpus.mjs <폴더>`
- 시뮬레이션 MCP: `cd craft/circuitcraft-cli && node --test test/mcp.test.mjs`
- CircuitCraft: `cd craft/circuitcraft && ./build.sh && node --test test/circuitcraft.e2e.mjs`
- SolidCraft: `craft/solidcraft/build.sh`, `craft/solidcraft/test/fetch-samples.sh`, `cd craft/solidcraft-cli && node --test test/solidcraft.test.mjs`, `cd craft/solidcraft/test && node --test web.e2e.mjs`
- OrCAD 읽기: `craft/orcad/build.sh`, `ORCAD_TEST_DIR=<폴더> node --test craft/orcad/test/dsn.test.mjs`
- 화면: `cd e2e && PGPT_URL=http://localhost:5192 API_URL=http://localhost:8792 PGPT_SERVER_DIR=$PWD/../server npx playwright test --project=feature tests/feature/prototype.spec.js`

## 시나리오 ↔ 시험
| 시나리오 | 시험 |
|---|---|
| 말로 요청한다 / 말 없이 파일만 / 다른 요청 | `prototype-cases.json`, `prototype.e2e.mjs` 1 |
| 매장 설계 프로세스가 등록되어 있다 | `prototype.e2e.mjs` 1(공용 DB 에 실제로 등록되어 있다) |
| 첨부 세 개 | `prototype.e2e.mjs` 1 |
| Gmail 본문 | `prototype.test.js`. 실제 Gmail 계정으로는 시험하지 않았다 |
| 회로를 돌린다 / 근사한 것을 알린다 | `prototype.e2e.mjs` 2, `prototype.test.js` |
| 회로 파일이 없다 | 첫 시험 판에서 확인(첨부가 사라진 메일), 자동 시험 없음 |
| 실제 PSpice 값과 같다 | `corpus.mjs`(CMOSedu 180개) |
| 옮기지 않으면 틀리는 회로 / 쓰고 다시 읽는다 / 큰 벤더 라이브러리 | `pspice.test.mjs` |
| 옮기지 못하는 문법 / 없는 부품 / 암호화 / 돌릴 회로가 없다 / 치명 오류 | `pspice.test.mjs`, `mcp.test.mjs`, F-PR-02 |
| Capture 넷리스트와 같다 / OrCAD 파일이 아니다 | `craft/orcad/test/dsn.test.mjs`, `prototype.test.js` |
| 큰 보드 | F-PR-05, `dsn.test.mjs` |
| 메일의 치수 | `prototype.e2e.mjs` 3(OCP 로 잰다) |
| 메일에 없는 치수 / 말이 안 되는 치수 | `prototype.test.js` |
| 벤더 CAD 파일 | 벤더 파일 13개 측정(저장소에 없다), `solidcraft.test.mjs` |
| 도면 | `prototype.e2e.mjs` 4 |
| 제안서 / 견적서 | `prototype.e2e.mjs` 5 |
| 회로 카드 / 라이브러리 없이 / 3D 카드 | F-PR-01, F-PR-02, F-PR-03, `circuitcraft.e2e.mjs`, `web.e2e.mjs` |
| CircuitCraft 가 없다 | 코드 경로로만 확인 |

## 측정(2026-11-04)
- 실제 OrCAD 프로젝트 180개(CMOSedu PSpice 묶음): 시뮬레이션 성공 167개(93%). 나머지는 PSpice 기본 부품 모델 없음 6, 회로 파일 없음 4, 실패 2, 옮기지 못함 1.
- 같은 묶음에서 PSpice 가 남긴 .out 과 대조: 회로 77개, 노드 552개, 소스에 안 물리고 값이 있는 내부 노드 189개 모두 2% 안.
- 진짜 TDK 모델(C1608C0G1H470J080AA, 공개 저장소에서 찾음, 재배포 금지라 저장소에 없음): 1 MHz 임피던스 6% 안, 자기 공진 보임. 요청받은 C1608C0G1H100D080AA 파일 자체는 구하지 못했다(TDK 사이트가 자동 접속을 막는다).
- OrCAD .dsn: Capture 가 만든 넷리스트가 있는 설계 141개 중 139개가 부품 이름·값·핀 연결까지 일치(나머지 2개는 넷리스트가 파일보다 옛것으로 보임). BeagleBoard-xM(438 부품)·BeagleBone AI(716 부품)는 PDF·BOM·PCB 와 대조(`craft/orcad/test/evidence.md`).
- 벤더 CAD 파일 13개(STEP·IGES, 최대 10.6 MB): 모두 읽고 쓰고 다시 읽음.
- 외함 부피: 손계산과 OCP 측정 일치.

## 하지 못한 것
OrCAD .dsn 쓰기, 실제 Gmail 계정 시험, 실제 OrCAD 로 결과 확인, 암호화 벤더 모델, 몬테카를로·최악 조건, LAPLACE, 디지털 소자.
