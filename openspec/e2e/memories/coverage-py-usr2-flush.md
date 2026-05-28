---
name: coverage-py-usr2-flush
description: uvicorn으로 띄운 FastAPI 백엔드는 종료하지 않으므로 coverage.py 데이터가 디스크에 안 써짐. coverage run --save-signal=USR2 + docker kill --signal=USR2로 강제 flush 필요.
applies-to:
  - fastapi
  - uvicorn
  - coverage.py
  - python-backend
  - backend-coverage
last-verified: 2026-05-27
metadata:
  type: workaround
---

# Backend coverage flush via USR2 for long-running FastAPI

`completion` 같은 장기 실행 FastAPI 서버를 `coverage run -m uvicorn ...`으로
띄운 뒤 Playwright 테스트가 끝나도 coverage 데이터 파일이 디스크에 기록되지
않음. 프로세스가 살아 있으므로 atexit hook이 안 돌아서 발생함.

## What works

1. 컨테이너 CMD 또는 override에서 `--save-signal=USR2` 옵션과 `--parallel-mode`를 사용:

   ```yaml
   # openspec/specs/<spec-name>/e2e/docker/coverage.override.yml
   services:
     completion:
       command: >
         coverage run --parallel-mode --save-signal=USR2
         --source=. -m uvicorn main:app --host 0.0.0.0 --port 8000
       volumes:
         - ./openspec/specs/<spec-name>/e2e/results/backend-coverage:/coverage
       environment:
         COVERAGE_FILE: /coverage/.coverage
   ```

2. Playwright 실행이 끝난 뒤 컨테이너에 USR2를 보내 flush:

   ```bash
   docker kill --signal=USR2 process-gpt-e2e-completion
   # 잠시 대기 후
   docker exec process-gpt-e2e-completion sh -c "
     cd /coverage && coverage combine && \
     coverage xml -o /coverage/coverage.xml && \
     coverage html -d /coverage/html
   "
   ```

3. 컨테이너에 `coverage`가 없으면 먼저 설치:
   `docker exec process-gpt-e2e-completion pip install coverage`

`backend-coverage/coverage.xml`과 `backend-coverage/html/index.html` 양쪽이
생성되어야 OUTPUT_CONTRACT.md의 backend coverage 게이트를 통과함.

## Why

- uvicorn은 SIGTERM/SIGKILL을 받기 전에는 종료하지 않으므로 coverage.py의
  `atexit` 저장 경로가 실행되지 않음.
- `--save-signal=USR2`는 임의 신호로 coverage 데이터를 디스크로 flush하게
  해주는 공식 옵션 (coverage.py 7.4+).
- `--parallel-mode`는 여러 워커가 있을 때를 대비. 단일 워커라도
  `coverage combine`이 무해하게 통과하므로 기본값으로 둠.

## How to apply

- Triggered when:
  - 백엔드가 FastAPI/uvicorn처럼 장기 실행 서버
  - Phase E에서 backend coverage 게이트가 필요한데 `.coverage` 파일이 비어 있음
- Skip if:
  - 백엔드가 단발 실행 스크립트나 단명 worker 형태
  - c8/nyc (Node) 또는 JaCoCo (JVM)를 쓰는 경우 — 그쪽 도구의 자체 flush 메커니즘 사용

Related: [[mem0-vecs-table-reinit]]
