#!/usr/bin/env python
"""strategy_graph-store E2E 러너 (자체 서버 수명주기 제어).

이 스위트는 기동/초기화/저장소 선택/테넌트 격리를 검증하므로, 8114 상시 서버가
아니라 러너가 직접 uvicorn 서브프로세스를 띄우고 내린다(재기동 멱등성·기동 실패
시나리오를 관측하기 위함). 전략목표는 그래프에 저장되므로 별도 플랫폼 seed 는 없다.

실행:
  services/strategy/.venv/bin/python \
    openspec/specs/strategy_graph-store/e2e/run_e2e.py

인프라: process-gpt-age-postgres (127.0.0.1:55433, postgres/postgres/postgres).
"""
import os
import signal
import subprocess
import sys
import tempfile
import time
import uuid

import httpx

SERVICE_DIR = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", "services", "strategy")
)
PY = os.path.join(SERVICE_DIR, ".venv", "bin", "python")
PORT = 8115
BASE = f"http://127.0.0.1:{PORT}"
GRAPH_NAME = "corp_ontology_e2e_store"
# 서버 로그는 임시 디렉터리에 남긴다(스펙 폴더를 오염시키지 않음). 실패 시 여기서 확인.
LOG_DIR = os.path.join(tempfile.gettempdir(), "strategy_graph_store_e2e_logs")
os.makedirs(LOG_DIR, exist_ok=True)

BASE_ENV = {
    **os.environ,
    "DB_HOST": "127.0.0.1", "DB_PORT": "55433", "DB_USER": "postgres",
    "DB_PASSWORD": "postgres", "DB_NAME": "postgres",
    "GRAPH_STORE": "age", "GRAPH_NAME": GRAPH_NAME, "MEASURE_AUTO_START": "false",
}

RESULTS: list[tuple[str, bool, str]] = []


def check(name: str, cond: bool, detail: str = "") -> None:
    RESULTS.append((name, bool(cond), detail))
    print(("PASS" if cond else "FAIL"), "-", name, "" if cond else f":: {detail}")


def start_server(env: dict, log_name: str, port: int = PORT):
    logf = open(os.path.join(LOG_DIR, log_name), "w")
    proc = subprocess.Popen(
        [PY, "-m", "uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", str(port)],
        cwd=SERVICE_DIR, env=env, stdout=logf, stderr=subprocess.STDOUT,
    )
    return proc, logf


def wait_health(port: int = PORT, timeout: float = 25.0) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            r = httpx.get(f"http://127.0.0.1:{port}/health", timeout=2)
            if r.status_code == 200 and r.json().get("status") == "ok":
                return True
        except Exception:
            pass
        time.sleep(0.5)
    return False


def stop_server(proc) -> None:
    if proc.poll() is None:
        proc.send_signal(signal.SIGINT)
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)


def main() -> int:
    ts = int(time.time())
    tenant_a = f"e2e-store-a-{ts}"
    tenant_b = f"e2e-store-b-{ts}"

    # --- S1: 기본 저장소로 기동 + health ---
    proc, logf = start_server(BASE_ENV, "server_run1.log")
    try:
        ok = wait_health()
        check("S1 기동/health(AGE 기본 저장소)", ok, "health 200 실패")
        if not ok:
            return _finish()

        log1 = open(os.path.join(LOG_DIR, "server_run1.log")).read()
        check(
            "S1 AGE 어댑터 그래프 자동 초기화 로그",
            "준비 완료" in log1 and GRAPH_NAME in log1,
            "그래프 준비 로그 없음",
        )

        # --- S4: 테넌트 격리 (조회) — A/B 각각 목표 생성 ---
        with httpx.Client(base_url=BASE, timeout=10) as c:
            ra = c.post(f"/api/objectives?tenant_id={tenant_a}",
                        json={"name": "A-매출목표", "perspective": "financial"})
            rb = c.post(f"/api/objectives?tenant_id={tenant_b}",
                        json={"name": "B-고객목표", "perspective": "customer"})
            check("S4 테넌트 A 목표 생성", ra.status_code == 200, ra.text)
            check("S4 테넌트 B 목표 생성", rb.status_code == 200, rb.text)
            oid_a = ra.json()["id"]
            oid_b = rb.json()["id"]

            map_a = c.get(f"/api/map?tenant_id={tenant_a}").json()["objectives"]
            names_a = {o["name"] for o in map_a}
            check("S4 A 조회에 A 목표만 포함(격리)",
                  names_a == {"A-매출목표"}, f"A map={names_a}")

            map_b = c.get(f"/api/map?tenant_id={tenant_b}").json()["objectives"]
            check("S4 B 조회에 B 목표만 포함(격리)",
                  {o["name"] for o in map_b} == {"B-고객목표"}, f"B map")

            # 테넌트 격리(변경): B 로 A 목표 수정 시 404
            cross = c.put(f"/api/objectives/{oid_a}?tenant_id={tenant_b}",
                          json={"name": "탈취", "perspective": "financial"})
            check("S4 교차 테넌트 수정 404", cross.status_code == 404, f"status={cross.status_code}")
            still = c.get(f"/api/map?tenant_id={tenant_a}").json()["objectives"]
            check("S4 교차 수정 후 A 데이터 불변",
                  still[0]["name"] == "A-매출목표", "A 데이터가 변경됨")
    finally:
        stop_server(proc)
        logf.close()

    # --- S2: 재기동 멱등성 — 데이터 생존 ---
    proc2, logf2 = start_server(BASE_ENV, "server_run2.log")
    try:
        ok2 = wait_health()
        check("S2 재기동 후 health", ok2, "재기동 health 실패")
        if ok2:
            log2 = open(os.path.join(LOG_DIR, "server_run2.log")).read()
            check("S2 재기동 시 그래프 중복 생성/오류 없음",
                  "준비 완료" in log2 and "ERROR" not in log2, "재기동 로그 오류")
            with httpx.Client(base_url=BASE, timeout=10) as c:
                map_a = c.get(f"/api/map?tenant_id={tenant_a}").json()["objectives"]
                check("S2 재기동 후 기존 노드/관계 보존",
                      {o["name"] for o in map_a} == {"A-매출목표"} and map_a[0]["id"] == oid_a,
                      "재기동 후 데이터 유실")
    finally:
        stop_server(proc2)
        logf2.close()

    # --- S3: 지원하지 않는 저장소 지정 → 기동 실패 ---
    bad_env = {**BASE_ENV, "GRAPH_STORE": "unknown-db"}
    procb, logfb = start_server(bad_env, "server_unknown.log")
    healthy = wait_health(timeout=8)
    time.sleep(1)
    exited = procb.poll() is not None
    stop_server(procb)
    logfb.close()
    logb = open(os.path.join(LOG_DIR, "server_unknown.log")).read()
    check("S3 unknown-db 기동 실패(health 안 뜸)", (not healthy) and exited, "기동이 실패하지 않음")
    check("S3 오류에 지원 구현체 목록 포함",
          "지원하지 않는 GRAPH_STORE" in logb and "age" in logb,
          "지원 목록 오류 메시지 없음")

    # --- S5: AGE 미설치 Postgres 기동 실패 (litellm 5432, 있으면) ---
    import socket
    s = socket.socket()
    s.settimeout(2)
    reachable = False
    try:
        s.connect(("127.0.0.1", 5432))
        reachable = True
    except OSError:
        pass
    finally:
        s.close()
    if reachable:
        noage_env = {
            **BASE_ENV, "DB_HOST": "127.0.0.1", "DB_PORT": "5432",
            "DB_USER": "litellm", "DB_PASSWORD": "litellm", "DB_NAME": "litellm",
            "GRAPH_NAME": "test_noage_e2e",
        }
        procn, logfn = start_server(noage_env, "server_noage.log")
        healthy_n = wait_health(timeout=10)
        time.sleep(1)
        exited_n = procn.poll() is not None
        stop_server(procn)
        logfn.close()
        logn = open(os.path.join(LOG_DIR, "server_noage.log")).read()
        check("S5 AGE 미설치 Postgres 기동 실패",
              (not healthy_n) and exited_n, "기동이 실패하지 않음")
        check("S5 AGE 확장 필요 오류 로그",
              "AGE" in logn, "AGE 오류 메시지 없음")
    else:
        check("S5 AGE 미설치 Postgres(127.0.0.1:5432) 접근 불가 — 스킵", True,
              "litellm-db 미가동 — 단위 test_no_age_startup 이 동일 경로 검증")

    return _finish()


def _finish() -> int:
    total = len(RESULTS)
    passed = sum(1 for _, ok, _ in RESULTS if ok)
    print(f"\n=== SUMMARY: {passed}/{total} PASSED ===")
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
