---
name: coverage-flush-windows-force-stop
description: Windows 호스트에서 source-run 한 uvicorn(coverage.py parallel-mode) 을 Stop-Process -Force 로 종료하면 .coverage.* 데이터가 flush 되지 않는다
applies-to:
  - windows
  - source-run-backend
  - coverage.py
  - uvicorn
  - powershell
last-verified: 2026-05-28
metadata:
  type: pitfall
---

# Windows source-run + Stop-Process -Force 는 coverage.py 데이터를 잃는다

`coverage run --parallel-mode -m uvicorn ...` 로 호스트에서 직접 띄운 backend
프로세스를 PowerShell `Stop-Process -Force` (또는 포트 점유 프로세스 강제 종료)
로 끝내면 atexit 핸들러가 실행되지 않아 `.coverage.<host>.<pid>.*` 파일이
한 건도 남지 않는다. `coverage combine` 은 "No data to combine" 으로
끝나고 `coverage xml/html` 도 빈 결과를 만든다.

Linux 에서 검증된 패턴 (`coverage run --save-signal=USR2 ...` + `kill -USR2`)
은 Windows 에서 사용 불가하다. POSIX 신호가 SIGINT/SIGBREAK 외에는 의미가
없으므로 USR2 flush 가 트리거되지 않는다.

## What works

- (선호) Linux 컨테이너 안에서 source-run 한다. compose 의 `gateway` 가
  `host.docker.internal` 로 호스트 앱을 가리키게 두는 대신, 백엔드는
  `services/<svc>` 디렉토리를 마운트한 thin python 컨테이너에서 source-run
  하고 `--save-signal=USR2` 패턴을 그대로 사용한다.
- 호스트 source-run 을 유지해야 한다면, 종료 직전에 `coverage save` 를
  호출하는 관리용 HTTP 엔드포인트(예: `POST /debug/coverage-flush`) 를
  one-shot 추가하여 Playwright 종료 직전에 호출한다. 또는 `python -c "import coverage; coverage.Coverage().save()"`
  같은 sidecar 스크립트를 종료 직전 시그널 없이 실행한다.
- 또는 PowerShell 에서 `Stop-Process -Id <pid>` (Force 없음) → 종료 wait → 그래도 안 멈추면 Force 의 2단계로 변경한다. 다만 uvicorn 의 graceful shutdown 도 atexit 까지 실행하지 않는 경우가 있어 위의 명시 flush 가 더 안정적이다.

## Why

PowerShell 의 `Stop-Process -Force` 는 Windows `TerminateProcess` API 를 호출
한다. 이는 Python 인터프리터의 atexit 핸들러, signal handler, finally 블록을
모두 우회한다. coverage.py 는 atexit 시점에 데이터를 디스크에 쓰기 때문에
flush 자체가 일어나지 않는다.

## How to apply

- Triggered when: Windows 호스트에서 `coverage run --parallel-mode -m uvicorn ...` 로 source-run 한 backend 를 종료한 뒤 `.coverage.*` 가 한 건도 안 보일 때, 또는 `coverage combine` 이 "No data to combine" 으로 끝날 때.
- Skip if: 백엔드가 Docker (Linux) 컨테이너 내부에서 실행되고 SIGUSR2 flush 패턴을 그대로 쓰는 경우.

Related: [[coverage-py-usr2-flush]], [[completion-coverage-override-workdir]]
