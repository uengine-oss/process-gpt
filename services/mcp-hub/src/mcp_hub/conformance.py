"""연계 표준 적합성 검사.

사내 업무시스템이 MCP 서버를 구현했을 때, 등록 전에 표준을 지켰는지
스스로 확인할 수 있게 한다. 등급은 A/B/C.
"""
import re
from typing import Any

from .validator_client import validator_client

GUIDE: dict[str, Any] = {
    "version": "1.0",
    "title": "Process GPT MCP 연계 표준",
    "rules": [
        {"id": "transport", "level": "권장",
         "text": "사내 업무시스템은 streamable-http 로 노출한다. stdio 는 로컬 도구에만 쓴다.",
         "why": "stdio 는 허브가 프로세스를 spawn 해야 해서 확장·격리가 어렵다."},
        {"id": "secrets", "level": "필수",
         "text": "토큰·비밀번호는 값을 직접 넣지 말고 ${SECRET:KEY} 참조로 등록한다."},
        {"id": "tool-naming", "level": "필수",
         "text": "툴 이름은 snake_case 의 동사_명사 형태이며 서버 안에서 유일해야 한다.",
         "example": "create_purchase_order"},
        {"id": "input-schema", "level": "필수",
         "text": "모든 툴은 inputSchema 를 제공하고, 각 필드에 description 을 단다."},
        {"id": "annotations", "level": "권장",
         "text": "annotations.readOnlyHint / destructiveHint 를 명시한다.",
         "why": "허브가 위험한 툴을 구분해 권한을 좁힐 수 있다."},
        {"id": "errors", "level": "필수",
         "text": "오류는 JSON-RPC error 와 함께 data.errorType 을 준다. "
                 "분류는 AUTH · VALIDATION · UPSTREAM · TIMEOUT 중 하나."},
        {"id": "performance", "level": "필수",
         "text": "p95 응답 3초 이내, 타임아웃 30초."},
        {"id": "tools-list", "level": "필수",
         "text": "tools/list 는 부작용 없이 항상 응답해야 한다.",
         "why": "허브의 헬스체크가 이 호출로 살아있음을 판정한다."},
        {"id": "versioning", "level": "필수",
         "text": "호환이 깨지는 변경은 serverInfo.version 의 major 를 올린다."},
    ],
}

_SNAKE = re.compile(r"^[a-z][a-z0-9_]*$")


async def check_conformance(name: str, conn: dict[str, Any]) -> dict[str, Any]:
    findings: list[dict[str, Any]] = []

    def add(rule: str, level: str, ok: bool, detail: str) -> None:
        findings.append({"rule": rule, "level": level, "pass": ok, "detail": detail})

    # 1) 전송 방식
    transport = conn.get("transport")
    add("transport", "권장", transport in ("streamable-http", "sse"),
        f"transport={transport}" +
        ("" if transport in ("streamable-http", "sse")
         else " — 사내 시스템은 streamable-http 를 권장합니다"))

    # 2) 시크릿 하드코딩
    raw = f"{conn.get('headers')}{conn.get('env')}"
    hardcoded = bool(re.search(r"(Bearer\s+[A-Za-z0-9._\-]{16,}|password=|:[^@/\s]{8,}@)", raw)) \
        and "${SECRET:" not in raw
    add("secrets", "필수", not hardcoded,
        "시크릿이 하드코딩된 것으로 보입니다 — ${SECRET:KEY} 참조를 쓰세요"
        if hardcoded else "하드코딩된 시크릿이 보이지 않습니다")

    # 3) 실제 연결 + tools/list
    result = await validator_client.validate(name, conn)
    connected = result.get("status") == "success"
    add("tools-list", "필수", connected,
        "연결과 tools/list 성공" if connected
        else f"연결 실패: {result.get('error_message')}")

    tools = result.get("tools") or []
    if connected:
        bad_names = [t["name"] for t in tools if not _SNAKE.match(t.get("name") or "")]
        add("tool-naming", "필수", not bad_names,
            f"규칙에 어긋난 이름: {', '.join(bad_names)}" if bad_names
            else f"{len(tools)}개 툴 이름이 snake_case 입니다")

        no_schema = [t["name"] for t in tools if not (t.get("parameters") or {}).get("properties")
                     and (t.get("parameters") or {}) != {}]
        missing_desc = [t["name"] for t in tools if not t.get("description")]
        add("input-schema", "필수", not missing_desc,
            f"description 이 없는 툴: {', '.join(missing_desc)}" if missing_desc
            else "모든 툴에 description 이 있습니다")

        latency = (result.get("validation_time") or 0)
        add("performance", "필수", latency < 3.0,
            f"tools/list 응답 {latency:.2f}s" +
            ("" if latency < 3.0 else " — 3초를 넘습니다"))
    else:
        for rule in ("tool-naming", "input-schema", "performance"):
            add(rule, "필수", False, "연결 실패로 검사할 수 없었습니다")

    required_failed = [f for f in findings if f["level"] == "필수" and not f["pass"]]
    recommended_failed = [f for f in findings if f["level"] == "권장" and not f["pass"]]
    if required_failed:
        grade = "C"
    elif recommended_failed:
        grade = "B"
    else:
        grade = "A"

    return {
        "name": name,
        "grade": grade,
        "connected": connected,
        "tool_count": len(tools),
        "findings": findings,
        "violations": [f["detail"] for f in required_failed],
    }
