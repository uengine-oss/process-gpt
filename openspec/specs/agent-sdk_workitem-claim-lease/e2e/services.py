"""lease 를 검증할 실제 서비스들과, 그것을 로컬에서 띄우는 방법.

워커는 각 서비스의 **실제 진입점**으로 띄운다. SDK 를 흉내 낸 워커가 아니라 그
서비스의 실행기·컨텍스트 조립·결과 저장을 그대로 탄다. 서비스마다 다른 것은
기동 명령과 환경변수뿐이다.

비밀값과 로컬 경로는 services.env 에서 읽는다(커밋하지 않는다, services.env.example 참고).
"""

from __future__ import annotations

import os
import signal
import subprocess
import tempfile
import time
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

HERE = Path(__file__).resolve().parent
# ws/infra/process-gpt/openspec/specs/<spec>/e2e → ws
DEFAULT_SERVICES_ROOT = HERE.parents[5]

#: 테스트용 lease. 운영(120초)과 비율(heartbeat = lease/4)은 같고 길이만 줄였다 —
#: LLM 수행이 4초만 넘어도 연장이 두 번 관찰된다.
LEASE_SECONDS = int(os.getenv("LEASE_SVC_LEASE_SECONDS", "8"))
HEARTBEAT_SECONDS = max(1, LEASE_SECONDS // 4)
#: 빈 폴링 뒤 SDK 가 쉬는 시간. 재점유 지연의 상한을 계산할 때 쓴다.
POLL_IDLE_SECONDS = 10


def load_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


CONF = {**load_env_file(HERE / "services.env"), **{k: v for k, v in os.environ.items() if k.startswith("LEASE_SVC_")}}


def conf(key: str, default: str = "") -> str:
    return os.getenv(key) or CONF.get(key, default)


@dataclass
class Service:
    name: str
    agent_orch: str
    cwd: Path
    argv: list[str]
    #: 워커별 환경. consumer 이름과 포트를 받아 만든다.
    env: Callable[[str, int], dict[str, str]]
    #: 실행에 꼭 필요한데 없으면 테스트를 건너뛸 항목(이유 문자열). 없으면 빈 목록.
    missing: Callable[[], list[str]] = field(default=lambda: [])


def _common(consumer: str, port: int) -> dict[str, str]:
    return {
        "SUPABASE_URL": conf("SUPABASE_URL", "http://127.0.0.1:54321"),
        "SUPABASE_KEY": conf("SUPABASE_KEY"),
        "CONSUMER_ID": consumer,
        "PORT": str(port),
        "TASK_LEASE_SECONDS": str(LEASE_SECONDS),
        "TASK_LEASE_HEARTBEAT_SECONDS": str(HEARTBEAT_SECONDS),
        "PYTHONUNBUFFERED": "1",
    }


def _root(env_key: str, default_dir: str) -> Path:
    return Path(conf(env_key) or DEFAULT_SERVICES_ROOT / default_dir)


def _python(root: Path, env_key: str) -> str:
    return conf(env_key) or str(root / ".venv" / "bin" / "python")


def _bin(value: str) -> str:
    """상대 경로는 이 폴더 기준이다(워커는 서비스 저장소에서 돈다)."""
    return str((HERE / value).resolve()) if value.startswith(".") else value


def _need(*checks: tuple[bool, str]) -> list[str]:
    return [reason for ok, reason in checks if not ok]


def deepagents() -> Service:
    root = _root("LEASE_SVC_DEEPAGENTS_DIR", "process-gpt-deepagents")
    py = _python(root, "LEASE_SVC_DEEPAGENTS_PYTHON")
    return Service(
        name="deepagents", agent_orch="deepagents", cwd=root, argv=[py, "server.py"],
        env=lambda c, p: {**_common(c, p), "FEEDBACK_POLLING_ENABLED": "false"},
        missing=lambda: _need(
            (Path(py).exists(), f"python 없음: {py}"),
            (bool(conf("SUPABASE_KEY")), "SUPABASE_KEY 없음"),
        ),
    )


def cliagents() -> Service:
    root = _root("LEASE_SVC_CLIAGENT_DIR", "process-gpt-cli-agent")
    py = _python(root, "LEASE_SVC_CLIAGENT_PYTHON")
    work = Path(tempfile.mkdtemp(prefix="lease-svc-cli-"))
    (work / "skills").mkdir()

    def env(c: str, p: int) -> dict[str, str]:
        e = {
            **_common(c, p),
            "CLIAGENTS_WORKSPACE_ROOT": str(work / "ws"),
            "CLIAGENTS_SYSTEM_SKILLS_DIR": str(root / "system-skills"),
            "SKILLS_DIRS": str(work / "skills"),
            "CLIAGENTS_RUN_TIMEOUT_SECONDS": conf("LEASE_SVC_CLIAGENT_RUN_TIMEOUT", "60"),
        }
        # CLI 의 자격증명. cli-agent 는 실행마다 설정 폴더를 바꾸므로 로컬 로그인은
        # 보이지 않는다 — 환경변수로 넘겨야 한다.
        for key in ("ANTHROPIC_BASE_URL", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY",
                    "CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_MODEL", "ANTHROPIC_SMALL_FAST_MODEL"):
            if conf(key):
                e[key] = conf(key)
        return e

    return Service(
        name="cliagents", agent_orch="cliagents", cwd=root, argv=[py, "server.py"], env=env,
        missing=lambda: _need(
            (Path(py).exists(), f"python 없음: {py} (uv venv && uv pip install -r requirements.txt)"),
            (bool(conf("SUPABASE_KEY")), "SUPABASE_KEY 없음"),
        ),
    )


def codex() -> Service:
    root = _root("LEASE_SVC_CODEX_DIR", "process-gpt-codex")
    py = _python(root, "LEASE_SVC_CODEX_PYTHON")
    proxy = conf("LLM_PROXY_URL", "http://localhost:4000").rstrip("/")

    def env(c: str, p: int) -> dict[str, str]:
        return {
            **_common(c, p),
            "CODEX_BIN": _bin(conf("LEASE_SVC_CODEX_BIN", "codex")),
            # 비우면 네이티브로 돈다. 로컬 이미지가 amd64 면 arm64 맥에서 bwrap 이 실패한다.
            "CODEX_APP_SERVER_CONTAINER_IMAGE": conf("LEASE_SVC_CODEX_IMAGE", ""),
            "CODEX_HOME": ".data/codex-home",
            "CODEX_MODEL_PROFILE": "custom",
            "CUSTOM_PROVIDER_API_KEY": conf("LLM_PROXY_API_KEY"),
            "CODEX_CUSTOM_MODEL": conf("LEASE_SVC_CODEX_MODEL", "gpt-5.4-mini"),
            "CODEX_CUSTOM_REASONING_EFFORT": "low",
            "CODEX_CUSTOM_PROVIDER_BASE_URL": f"{proxy}/v1",
            "CODEX_CUSTOM_PROVIDER_API_KEY_ENV": "CUSTOM_PROVIDER_API_KEY",
            # 샘플링 프록시는 temperature 를 붙이는데 gpt-5 계열이 거절한다.
            "CODEX_CUSTOM_SAMPLING_PROXY_ENABLED": "false",
            "CODEX_WEB_SEARCH": "disabled",
            "SKIP_WARMUP": "true",
            # 종료 시 진행 중 작업을 기다리는 유예. 기본 600초면 다음 워커가 포트를 못 잡는다.
            "CODEX_POLLING_DRAIN_SECONDS": "5",
        }

    return Service(
        name="codex", agent_orch="codex", cwd=root, argv=[py, "main.py"], env=env,
        missing=lambda: _need(
            (Path(py).exists(), f"python 없음: {py}"),
            (bool(conf("SUPABASE_KEY")), "SUPABASE_KEY 없음"),
            (bool(conf("LLM_PROXY_API_KEY")), "LLM_PROXY_API_KEY 없음"),
        ),
    )


SERVICES: dict[str, Callable[[], Service]] = {
    "deepagents": deepagents,
    "cliagents": cliagents,
    "codex": codex,
}


class Worker:
    """서비스 프로세스 하나. 자기 프로세스 그룹을 가진다.

    kill() 은 그룹 전체에 SIGKILL 을 보낸다 — 파드/컨테이너가 죽는 것과 같다.
    프로세스 하나만 죽이면 CLI 자식 프로세스가 고아로 남아 계속 돈다.
    """

    def __init__(self, service: Service, consumer: str, port: int, log_dir: Path):
        self.service = service
        self.consumer = consumer
        self.port = port
        self.log_path = log_dir / f"{service.name}-{consumer}.log"
        self.proc: subprocess.Popen | None = None

    def start(self, ready_timeout: float = 120.0) -> "Worker":
        env = {**os.environ, **self.service.env(self.consumer, self.port)}
        log = open(self.log_path, "ab")
        self.proc = subprocess.Popen(
            self.service.argv, cwd=self.service.cwd, env=env,
            stdout=log, stderr=subprocess.STDOUT, start_new_session=True,
        )
        deadline = time.monotonic() + ready_timeout
        while time.monotonic() < deadline:
            if self.proc.poll() is not None:
                raise RuntimeError(f"{self.consumer} 가 기동 중 종료됐다. 로그: {self.log_path}")
            try:
                with urllib.request.urlopen(f"http://127.0.0.1:{self.port}/health", timeout=2) as r:
                    if r.status == 200:
                        return self
            except OSError:
                pass
            time.sleep(0.5)
        raise TimeoutError(f"{self.consumer} 가 {ready_timeout}초 안에 /health 에 답하지 않았다. 로그: {self.log_path}")

    @property
    def alive(self) -> bool:
        return self.proc is not None and self.proc.poll() is None

    def kill(self) -> None:
        if self.proc is None:
            return
        try:
            os.killpg(self.proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        self.proc.wait(timeout=10)

    def stop(self, grace: float = 30.0) -> None:
        if not self.alive:
            return
        assert self.proc is not None
        os.killpg(self.proc.pid, signal.SIGTERM)
        try:
            self.proc.wait(timeout=grace)
        except subprocess.TimeoutExpired:
            pass
        # 정상 종료 뒤에도 그룹에 남은 자식(CLI, MCP 서버)을 치운다.
        self.kill()
