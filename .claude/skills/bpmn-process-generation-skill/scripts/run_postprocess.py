#!/usr/bin/env python3
"""서비스(ProcessGPT deepagent) 모드 후처리 오케스트레이터.

09-service-execution.md 의 출력 계약 JSON 을 입력받아:
  1) Supabase 저장 (proc_def / configuration / form_def / users / agent_skills / tenants.skills)
  2) (옵션) 실행 검증 + 자동교정 (process-gpt-completion 엔진)
을 pdf2bpmn 와 동일하게 수행하고, 생성된 프로세스 정보를 **최종 요약 JSON** 으로 출력한다.

입력 형태(둘 다 지원):
  - 단일:   { "type": "process-definition-result", "processDefinition": {...}, "forms": [...], "agents": [...], "skills": [...] }
  - 멀티:   { "processes": [ <위 단일 계약>, ... ] }   또는 위 단일 객체들의 JSON 배열 [ {...}, {...} ]

사용:
  pip install -r <skill_dir>/scripts/requirements.txt
  python <skill_dir>/scripts/run_postprocess.py --input result.json --tenant <tenant_id>
  옵션: --no-validate  (저장만)  /  --actor-email <email>  /  --report-dir <dir>

최종 stdout 마지막 줄에 요약 JSON 한 줄을 출력한다(앞 줄들은 로그). 프론트/호출자는
마지막 JSON 을 파싱하면 된다.
"""

from __future__ import annotations

import os
import sys
import json
import argparse
import logging
from datetime import datetime, timezone
from typing import Any, Dict, List

# scripts/ 를 import 경로에 추가 (save_to_supabase / validation 패키지)
_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)

from save_to_supabase import get_client, save_contract  # noqa: E402
import validate_process  # noqa: E402

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"),
                    format="%(asctime)s %(levelname)s %(name)s: %(message)s")
logger = logging.getLogger("bpmn.postprocess")


def _normalize_inputs(raw: Any) -> List[Dict[str, Any]]:
    """입력을 '단일 계약 리스트' 로 정규화한다."""
    if isinstance(raw, list):
        return [c for c in raw if isinstance(c, dict)]
    if isinstance(raw, dict):
        if isinstance(raw.get("processes"), list):
            return [c for c in raw["processes"] if isinstance(c, dict)]
        if raw.get("processDefinition"):
            return [raw]
    raise ValueError("입력 JSON 형식을 인식할 수 없습니다 (processDefinition / processes / 배열).")


def main() -> int:
    ap = argparse.ArgumentParser(description="ProcessGPT 후처리: 저장 + 검증")
    ap.add_argument("--input", default=None,
                    help="출력 계약 JSON 파일 경로. 생략하고 --stdin 으로 표준입력 사용 권장(파일 미생성)")
    ap.add_argument("--stdin", action="store_true",
                    help="출력 계약 JSON 을 표준입력(STDIN)에서 읽는다. 파일을 만들지 않는 서비스 모드 기본 경로.")
    ap.add_argument("--tenant", default=None,
                    help="tenant_id. 생략하면 TENANT_ID 환경변수를 사용")
    ap.add_argument("--no-validate", action="store_true", help="검증 건너뛰고 저장만")
    ap.add_argument("--actor-email", default=None, help="검증 실행 actor 이메일")
    ap.add_argument("--report-dir", default=None, help="검증 상세 리포트(.md) 저장 디렉토리")
    args = ap.parse_args()

    # tenant_id 우선순위: --tenant > TENANT_ID env. (deepagent 의 tenant_id 는 요청
    # 컨텍스트 값이므로, 셸 실행 시 TENANT_ID 로 넘기거나 --tenant 로 전달해야 한다.)
    tenant_id = (args.tenant or os.getenv("TENANT_ID") or "").strip()
    if not tenant_id:
        logger.error("tenant_id 가 없습니다. --tenant <id> 또는 TENANT_ID 환경변수를 지정하세요.")
        return 2

    # 입력은 STDIN(파일 미생성, 서비스 모드 기본) 또는 --input 파일.
    if args.stdin or not args.input:
        stdin_text = sys.stdin.read()
        if not stdin_text.strip():
            logger.error("STDIN 이 비어 있습니다. 출력 계약 JSON 을 stdin 으로 파이프하거나 --input 파일을 지정하세요.")
            return 2
        raw = json.loads(stdin_text)
    else:
        with open(args.input, "r", encoding="utf-8") as f:
            raw = json.load(f)
    contracts = _normalize_inputs(raw)

    sb = get_client()

    saved_processes: List[Dict[str, Any]] = []
    saved_skills: List[str] = []
    saved_agents: List[Dict[str, Any]] = []
    validation: Dict[str, Any] = {}

    for idx, contract in enumerate(contracts, 1):
        pd = contract.get("processDefinition") or {}
        name = pd.get("processDefinitionName") or pd.get("processDefinitionId") or f"process-{idx}"
        logger.info("[%d/%d] 저장 시작: %s", idx, len(contracts), name)

        save_res = save_contract(contract, tenant_id=tenant_id, sb=sb)
        proc_def_id = save_res["proc_def_id"]
        saved_processes.append({"id": proc_def_id, "name": save_res["process_name"],
                                "proc_def": save_res["proc_def"],
                                "forms_saved": save_res["forms_saved"]})
        for s in save_res.get("skills_registered") or []:
            if s not in saved_skills:
                saved_skills.append(s)
        for a in save_res.get("agents_saved") or []:
            saved_agents.append(a)
        logger.info("[%d/%d] 저장 완료: proc_def=%s forms=%d agents=%d",
                    idx, len(contracts), save_res["proc_def"],
                    save_res["forms_saved"], len(save_res.get("agents_saved") or []))

        if args.no_validate:
            validation[proc_def_id] = {"skipped": True, "skip_reason": "--no-validate", "passed": None}
            continue

        report_path = None
        if args.report_dir:
            os.makedirs(args.report_dir, exist_ok=True)
            report_path = os.path.join(args.report_dir, f"validation_{proc_def_id}.md")
        try:
            report = validate_process.validate(
                sb=sb, tenant_id=tenant_id, proc_def_id=proc_def_id,
                process_name=save_res["process_name"], definition=save_res["definition"],
                forms=contract.get("forms") or [], actor_email=args.actor_email,
                report_path=report_path,
            )
        except Exception as e:
            logger.warning("[%d/%d] 검증 예외: %s", idx, len(contracts), e)
            report = {"passed": None, "skipped": True, "skip_reason": f"검증 예외: {e}"}
        # 최종 정의(있으면)는 요약에서 제외(용량) — 이미 DB 저장됨
        report.pop("final_definition", None)
        report.pop("history", None)
        validation[proc_def_id] = report
        logger.info("[%d/%d] 검증: passed=%s skipped=%s repaired=%s",
                    idx, len(contracts), report.get("passed"),
                    report.get("skipped"), report.get("repaired"))

    n = len(saved_processes)
    msg = (f"[COMPLETED] {n}개 프로세스 저장 완료"
           + ("" if args.no_validate else " · 검증 수행"))
    summary = {
        "type": "process-definition-postprocess-result",
        "status": "completed",
        "success": True,
        "tenant_id": tenant_id,
        "process_count": n,
        "saved_processes": saved_processes,
        "saved_skills": saved_skills,
        "saved_agents": saved_agents,
        "validation": validation,
        "message": msg,
        "generated_at": datetime.now(timezone.utc).isoformat(),
    }
    # 마지막 줄에 요약 JSON (호출자가 파싱)
    print(json.dumps(summary, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
