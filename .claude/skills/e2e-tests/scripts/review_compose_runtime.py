#!/usr/bin/env python3
"""Review docker-compose.e2e.yml for likely Hybrid Runtime Rule violations.

The Hybrid Runtime Rule (see SKILL.md) requires:
  - Infrastructure dependencies (db, cache, queue, gateway, mail, mocks of
    external boundaries, ...) MAY be Docker services in docker-compose.e2e.yml.
  - Repository-owned application services (frontend, owning backend services,
    repo-owned API gateway / reverse proxy / BFF / worker) MUST run from the
    working tree using local source commands. They MUST NOT be added to
    docker-compose.e2e.yml.

This script reads docker-compose.e2e.yml and emits WARNINGS (not errors) when
it sees Compose service entries that look like containerized application
services. Warnings are intentional — there are legitimate exceptions
(prebuilt UI image when local source build is impossible, user-approved
overrides, infrastructure mocks that happen to share a name, etc.). The
purpose is to interrupt the agent BEFORE it boots an invalid runtime and
force a conscious decision instead of relying on the LLM to remember the
rule mid-flow.

Usage:
    python .claude/skills/e2e-tests/scripts/review_compose_runtime.py \
        --compose docker-compose.e2e.yml

Exit codes:
    0  - no warnings (compose looks compliant)
    0  - warnings emitted, but allowed (default behavior; warnings are
         informational and DO NOT block)
    1  - the compose file is missing or unreadable
    2  - --strict was passed AND warnings were emitted (opt-in hard gate)

The script intentionally avoids any non-stdlib dependency so it can run on a
clean Python 3.10+ without `pip install pyyaml`.
"""
from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path


# ---------------------------------------------------------------------------
# Heuristics
# ---------------------------------------------------------------------------

# Tokens that strongly suggest a Compose service is a repository-owned frontend.
FRONTEND_NAME_TOKENS = (
    "frontend",
    "front-end",
    "front_end",
    "webapp",
    "web-app",
    "spa",
    "vue",
    "react",
    "next",
    "nuxt",
    "ui",
)

# Image substrings that suggest a containerized frontend (custom or prebuilt).
# Be specific: bare 'process-gpt' would false-positive on backend images
# named 'process-gpt-e2e-completion:local'. Match the SPA image namespace
# instead.
FRONTEND_IMAGE_TOKENS = (
    "uengine-oss/process-gpt",  # ghcr.io/uengine-oss/process-gpt:<tag> SPA image
    "spa-http-server",
    "vite",
    "nuxt",
    "nginx-spa",
)

# Tokens that strongly suggest a Compose service is a repository-owned backend.
# Keep these conservative — the matcher checks for whole-token boundaries
# to avoid false positives on names like "auth", "rest", "kong", "db".
BACKEND_NAME_TOKENS = (
    "completion",
    "backend",
    "api-server",
    "api_server",
    "apiserver",
    "fcm-service",
    "fcm_service",
    "agent",
    "memento",
    "crewai",
    "polling",
    "bff",
    "gateway-bff",
    "worker",
)

# Known infrastructure service names — never warned about even if they share
# substrings with the above.
INFRA_ALLOWLIST = {
    "db",
    "postgres",
    "redis",
    "rabbitmq",
    "kafka",
    "kong",
    "nginx",  # nginx-only reverse proxy is infrastructure when it just routes
    "gateway",  # plain `gateway` is the shared nginx reverse proxy
    "auth",  # supabase gotrue
    "rest",  # supabase postgrest
    "realtime",
    "storage",
    "imgproxy",
    "studio",
    "meta",
    "vector",
    "analytics",
    "supavisor",
    "functions",
    "minio",
    "mailhog",
    "smtp",
    "mock-llm",
    "mock-external-agent",
    "mock-llm-pdq",
    "mock-llm-ate",
}

# `db-seed*` services are infrastructure (one-shot data seeding).
INFRA_PREFIX_ALLOWLIST = (
    "db-seed",
    "db_seed",
    "seed-",
    "mock-",
    "mock_",
)


@dataclass
class ServiceEntry:
    name: str
    line: int  # 1-based line number in the compose file
    block: list[str] = field(default_factory=list)

    @property
    def joined_block(self) -> str:
        return "\n".join(self.block)


@dataclass
class Finding:
    service: str
    line: int
    category: str  # "frontend" or "backend"
    reason: str


# ---------------------------------------------------------------------------
# Compose parsing (yaml without pyyaml — we only need service names + blocks)
# ---------------------------------------------------------------------------

_SERVICES_HEADING_RE = re.compile(r"^services\s*:\s*$")
_SERVICE_KEY_RE = re.compile(r"^( {2}|\t)([A-Za-z0-9][A-Za-z0-9_.\-]*)\s*:\s*(#.*)?$")
_TOP_LEVEL_KEY_RE = re.compile(r"^[A-Za-z0-9_.\-]+\s*:\s*(#.*)?$")


def parse_services(text: str) -> list[ServiceEntry]:
    """Yield ServiceEntry objects for each service under the top-level
    `services:` mapping. Comment-only lines are stripped from blocks so the
    heuristics can scan real config values.
    """
    lines = text.splitlines()
    services: list[ServiceEntry] = []
    in_services = False
    current: ServiceEntry | None = None
    for idx, raw in enumerate(lines, start=1):
        # leaving the `services:` section?
        if in_services and _TOP_LEVEL_KEY_RE.match(raw) and not raw.startswith((" ", "\t")):
            if current is not None:
                services.append(current)
                current = None
            in_services = False

        if _SERVICES_HEADING_RE.match(raw):
            in_services = True
            continue

        if not in_services:
            continue

        m = _SERVICE_KEY_RE.match(raw)
        if m:
            if current is not None:
                services.append(current)
            current = ServiceEntry(name=m.group(2), line=idx)
            continue

        if current is not None and (raw.startswith("    ") or raw.startswith("\t\t")):
            stripped = raw.split("#", 1)[0].rstrip()
            if stripped:
                current.block.append(stripped)

    if current is not None:
        services.append(current)
    return services


# ---------------------------------------------------------------------------
# Heuristic checks
# ---------------------------------------------------------------------------


def _word_hit(name: str, tokens: tuple[str, ...]) -> str | None:
    low = name.lower()
    for tok in tokens:
        if tok in low:
            return tok
    return None


def _is_allowlisted_infra(name: str) -> bool:
    if name in INFRA_ALLOWLIST:
        return True
    for prefix in INFRA_PREFIX_ALLOWLIST:
        if name.startswith(prefix):
            return True
    return False


def _has_build_directive(block: str) -> bool:
    return bool(re.search(r"^\s*build\s*:", block, re.MULTILINE)) or "build:" in block


def _image_token_hit(block: str, tokens: tuple[str, ...]) -> str | None:
    image_match = re.search(r"image\s*:\s*([^\s#]+)", block)
    if not image_match:
        return None
    img = image_match.group(1).lower()
    for tok in tokens:
        if tok in img:
            return tok
    return None


def check_service(entry: ServiceEntry) -> list[Finding]:
    findings: list[Finding] = []
    name = entry.name
    block = entry.joined_block

    if _is_allowlisted_infra(name):
        return findings

    # ---- frontend heuristic ------------------------------------------------
    fe_name_hit = _word_hit(name, FRONTEND_NAME_TOKENS)
    fe_image_hit = _image_token_hit(block, FRONTEND_IMAGE_TOKENS)
    if fe_name_hit or fe_image_hit:
        why = []
        if fe_name_hit:
            why.append(f"service name contains '{fe_name_hit}'")
        if fe_image_hit:
            why.append(f"image reference contains '{fe_image_hit}'")
        findings.append(
            Finding(
                service=name,
                line=entry.line,
                category="frontend",
                reason=(
                    "looks like a repository-owned FRONTEND being containerized "
                    "(" + "; ".join(why) + "). Hybrid Runtime Rule: run the "
                    "frontend from source via a suite-local helper, not Docker. "
                    "Exceptions must be explicitly approved by the user and "
                    "documented in the execution summary."
                ),
            )
        )

    # ---- backend heuristic -------------------------------------------------
    be_name_hit = _word_hit(name, BACKEND_NAME_TOKENS)
    if be_name_hit:
        # If the service has a `build:` directive or an image tag that points
        # at a locally built artifact, that's an even stronger signal.
        has_build = _has_build_directive(block)
        image_match = re.search(r"image\s*:\s*([^\s#]+)", block)
        local_image = bool(
            image_match and re.search(r"(local|e2e|process-gpt-e2e-)", image_match.group(1))
        )

        why = [f"service name contains '{be_name_hit}'"]
        if has_build:
            why.append("has a `build:` directive (builds from repo source)")
        if local_image:
            why.append(f"image '{image_match.group(1)}' looks locally built")

        findings.append(
            Finding(
                service=name,
                line=entry.line,
                category="backend",
                reason=(
                    "looks like a repository-owned BACKEND/application service "
                    "being containerized (" + "; ".join(why) + "). "
                    "Hybrid Runtime Rule: run owning backend services from "
                    "source via a suite-local helper, not Docker. Exceptions "
                    "must be explicitly approved by the user and documented "
                    "in the execution summary."
                ),
            )
        )

    return findings


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def format_report(path: Path, findings: list[Finding]) -> str:
    if not findings:
        return (
            f"OK: {path} 의 services 중 프론트엔드/백엔드 컨테이너화로 의심되는 항목이 없습니다.\n"
            "주의: 본 스크립트는 휴리스틱이며, 새로 추가된 owned 서비스를 모두 잡아내지는 못합니다. "
            "여전히 Hybrid Runtime Rule 을 사람이 한번 더 확인하세요."
        )

    lines = [
        f"WARNING: {path} 에 Hybrid Runtime Rule 위반으로 의심되는 컨테이너 항목이 있습니다.",
        "각 경고는 예외가 있을 수 있어 hard fail 이 아니라 주의 환기 목적입니다.",
        "필요하다고 판단되면 owned 서비스를 source-run 으로 옮기거나, 예외 사유를 execution summary 에 명시하세요.",
        "",
    ]
    for f in findings:
        lines.append(f"  [{f.category}] services.{f.service}  (line {f.line})")
        lines.append(f"      → {f.reason}")
        lines.append("")
    return "\n".join(lines).rstrip()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Review docker-compose.e2e.yml for likely Hybrid Runtime Rule "
            "violations (containerized frontend / backend services)."
        )
    )
    parser.add_argument(
        "--compose",
        default="docker-compose.e2e.yml",
        help="Path to the compose file (default: docker-compose.e2e.yml).",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help=(
            "Exit with non-zero status when warnings are emitted. Default is "
            "informational (exit 0 even with warnings)."
        ),
    )
    args = parser.parse_args(argv)

    compose_path = Path(args.compose)
    if not compose_path.exists():
        print(f"ERROR: compose file not found: {compose_path}", file=sys.stderr)
        return 1

    try:
        text = compose_path.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"ERROR: cannot read {compose_path}: {exc}", file=sys.stderr)
        return 1

    findings: list[Finding] = []
    for svc in parse_services(text):
        findings.extend(check_service(svc))

    print(format_report(compose_path, findings))

    if findings and args.strict:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
