"""서비스(ProcessGPT deepagent) 모드 검증 모듈.

pdf2bpmn 의 ProcessValidator(scripts/validation/process_validator.py, vendored)를
그대로 사용한다. 이 래퍼는 검증기가 요구하는 의존성(LLM 호출 / 정의 재저장 /
인스턴스 상태 조회 / 인스턴스 정리)을 Supabase·Anthropic 로 주입한다.

엔진(process-gpt-completion)이 COMPLETION_ENGINE_URL 로 도달 가능해야 실제 실행 검증을
한다. 미설정/미도달이면 검증기가 graceful 하게 skip 한다.

환경변수:
  COMPLETION_ENGINE_URL           실행 엔진 base URL (없으면 검증 skip)
  PDF2BPMN_VALIDATION_MAX_ITERS   최대 개선 반복 (기본 5)
  PDF2BPMN_VALIDATION_ADVANCE_TIMEOUT  제출 후 진행 대기(초, 기본 70)
  PDF2BPMN_VALIDATION_CLEANUP     검증 인스턴스 삭제 여부 (기본 false)
  ANTHROPIC_API_KEY               자동교정 LLM (없으면 교정 없이 검증만)
"""

from __future__ import annotations

import os
import json
import asyncio
import logging
from typing import Any, Dict, List, Optional

from validation.process_validator import ProcessValidator

logger = logging.getLogger("bpmn.validate")


# ---------------------------------------------------------------------------
# 주입 의존성
# ---------------------------------------------------------------------------
def _extract_json(text: str) -> Optional[dict]:
    if not text:
        return None
    t = text.strip()
    if "```" in t:
        import re
        m = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", t, re.DOTALL)
        if m:
            t = m.group(1)
    s, e = t.find("{"), t.rfind("}")
    if s >= 0 and e > s:
        t = t[s:e + 1]
    try:
        return json.loads(t)
    except Exception:
        return None


def _make_llm_call():
    """async (messages, max_tokens) -> dict|None.

    ProcessGPT deepagent(core/model.py)와 동일한 우선순위로 LLM 을 고른다:
      1) LLM_PROXY_URL + LLM_PROXY_API_KEY (OpenAI 호환 프록시)
      2) ANTHROPIC_API_KEY
      3) OPENAI_API_KEY
    하나도 없으면 자동교정 없이 검증만(noop 반환).
    """
    model = os.getenv("LLM_MODEL")
    proxy_url = os.getenv("LLM_PROXY_URL")
    proxy_key = os.getenv("LLM_PROXY_API_KEY")
    anthropic_key = os.getenv("ANTHROPIC_API_KEY")
    openai_key = os.getenv("OPENAI_API_KEY")

    def _noop(reason):
        async def _f(messages, max_tokens):
            logger.info("[VALIDATE] 자동교정 LLM 비활성: %s", reason)
            return None
        return _f

    # --- OpenAI 호환 (프록시 또는 OPENAI_API_KEY) ---
    def _make_openai_call(*, base_url, api_key, mdl):
        try:
            from openai import OpenAI  # type: ignore
        except Exception:
            return _noop("openai 패키지 없음")
        client = OpenAI(api_key=api_key, base_url=base_url) if base_url \
            else OpenAI(api_key=api_key)

        async def _call(messages: List[Dict[str, Any]], max_tokens: int) -> Optional[dict]:
            def _do():
                resp = client.chat.completions.create(
                    model=mdl or "gpt-4o",
                    messages=messages,  # system/user role 그대로 사용
                    max_completion_tokens=int(max_tokens or 4000),
                )
                return resp.choices[0].message.content or ""
            try:
                text = await asyncio.to_thread(_do)
                return _extract_json(text)
            except Exception as e:
                logger.warning("[VALIDATE] LLM(OpenAI호환) 호출 실패: %s", e)
                return None
        return _call

    if proxy_url and proxy_key:
        return _make_openai_call(base_url=proxy_url, api_key=proxy_key, mdl=model)

    if anthropic_key:
        try:
            import anthropic  # type: ignore
        except Exception:
            return _noop("anthropic 패키지 없음")
        client = anthropic.Anthropic(api_key=anthropic_key)

        async def _call_anthropic(messages: List[Dict[str, Any]], max_tokens: int) -> Optional[dict]:
            sys_parts = [m["content"] for m in messages if m.get("role") == "system"]
            chat = [m for m in messages if m.get("role") != "system"]
            system = "\n\n".join(sys_parts) if sys_parts else None

            def _do():
                kwargs = dict(model=model or "claude-sonnet-4-6",
                              max_tokens=int(max_tokens or 4000), messages=chat)
                if system:
                    kwargs["system"] = system
                resp = client.messages.create(**kwargs)
                return "".join(getattr(b, "text", "") for b in resp.content)
            try:
                text = await asyncio.to_thread(_do)
                return _extract_json(text)
            except Exception as e:
                logger.warning("[VALIDATE] LLM(Anthropic) 호출 실패: %s", e)
                return None
        return _call_anthropic

    if openai_key:
        return _make_openai_call(base_url=None, api_key=openai_key, mdl=model)

    return _noop("LLM 자격증명 없음(LLM_PROXY_*/ANTHROPIC_API_KEY/OPENAI_API_KEY)")


def _make_engine_deps(sb, tenant_id: str):
    """save_definition / fetch_instance_state / cleanup_instance 를 만든다."""

    async def save_definition(proc_def_id: str, definition: dict) -> bool:
        def _do():
            sb.table("proc_def").update({"definition": definition}) \
                .eq("id", proc_def_id).eq("tenant_id", tenant_id).execute()
            return True
        try:
            return await asyncio.to_thread(_do)
        except Exception as e:
            logger.warning("[VALIDATE] 정의 재저장 실패: %s", e)
            return False

    async def fetch_instance_state(proc_inst_id: str) -> dict:
        def _do():
            rows = sb.table("bpm_proc_inst") \
                .select("proc_inst_id,status,current_activity_ids") \
                .or_(f"proc_inst_id.eq.{proc_inst_id},root_proc_inst_id.eq.{proc_inst_id}") \
                .eq("tenant_id", tenant_id).execute().data or []
            return rows
        rows = await asyncio.to_thread(_do)
        status = "RUNNING"
        current: List[str] = []
        for r in rows:
            if str(r.get("proc_inst_id")) == str(proc_inst_id):
                status = r.get("status") or status
                cur = r.get("current_activity_ids")
                if isinstance(cur, list):
                    current = [str(x) for x in cur]
                elif isinstance(cur, str) and cur:
                    try:
                        parsed = json.loads(cur)
                        current = [str(x) for x in parsed] if isinstance(parsed, list) \
                            else [s.strip() for s in cur.split(",") if s.strip()]
                    except Exception:
                        current = [s.strip() for s in cur.split(",") if s.strip()]
                break
        return {"status": status, "current_activity_ids": current}

    async def cleanup_instance(proc_inst_id: str) -> None:
        def _do():
            for table in ("todolist", "bpm_proc_inst"):
                try:
                    sb.table(table).delete() \
                        .or_(f"proc_inst_id.eq.{proc_inst_id},root_proc_inst_id.eq.{proc_inst_id}") \
                        .eq("tenant_id", tenant_id).execute()
                except Exception:
                    pass
        await asyncio.to_thread(_do)

    return save_definition, fetch_instance_state, cleanup_instance


# ---------------------------------------------------------------------------
# forms 변환: 계약 forms[] → validator 가 기대하는 {activity_id: {form_id, fields_json}}
# ---------------------------------------------------------------------------
def build_forms_map(contract_forms: List[Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    from save_to_supabase import html_to_fields_json
    out: Dict[str, Dict[str, Any]] = {}
    for f in contract_forms or []:
        aid = (f.get("activity_id") or "").strip()
        if not aid:
            continue
        out[aid] = {
            "form_id": f.get("form_id") or "",
            "fields_json": f.get("fields_json") or html_to_fields_json(f.get("html") or ""),
        }
    return out


# ---------------------------------------------------------------------------
# 진입점
# ---------------------------------------------------------------------------
async def validate_async(*, sb, tenant_id: str, proc_def_id: str, process_name: str,
                         definition: Dict[str, Any], forms: List[Dict[str, Any]],
                         actor_email: Optional[str] = None,
                         report_path: Optional[str] = None) -> Dict[str, Any]:
    engine_url = os.getenv("COMPLETION_ENGINE_URL", "").strip()
    max_iters = int(os.getenv("PDF2BPMN_VALIDATION_MAX_ITERS", "5") or "5")
    advance_timeout = float(os.getenv("PDF2BPMN_VALIDATION_ADVANCE_TIMEOUT", "70") or "70")

    if not engine_url:
        return {
            "proc_def_id": proc_def_id, "process_name": process_name,
            "passed": None, "skipped": True,
            "skip_reason": "COMPLETION_ENGINE_URL 미설정 — 검증 skip",
            "iterations": 0, "repaired": False, "remaining_defects": [],
            "note": "실행 엔진 URL 이 없어 검증을 건너뜀(저장은 정상).",
        }

    save_definition, fetch_state, cleanup = _make_engine_deps(sb, tenant_id)

    async def _progress(message: str, pct: int, extra: dict = None) -> None:
        logger.info("[VALIDATE %s%%] %s", pct, message)

    validator = ProcessValidator(
        llm_call=_make_llm_call(),
        save_definition=save_definition,
        engine_base_url=engine_url,
        tenant_id=tenant_id,
        fetch_instance_state=fetch_state,
        cleanup_instance=cleanup,
        max_iters=max_iters,
        actor_email=actor_email,
        advance_timeout=advance_timeout,
        report_path=report_path,
        logger=logger,
        progress=_progress,
    )
    forms_map = build_forms_map(forms)
    report = await validator.validate_and_repair(
        proc_def_id=proc_def_id,
        process_name=process_name,
        proc_json=definition,
        forms=forms_map,
    )
    return report


def validate(*, sb, tenant_id: str, proc_def_id: str, process_name: str,
             definition: Dict[str, Any], forms: List[Dict[str, Any]],
             actor_email: Optional[str] = None,
             report_path: Optional[str] = None) -> Dict[str, Any]:
    return asyncio.run(validate_async(
        sb=sb, tenant_id=tenant_id, proc_def_id=proc_def_id, process_name=process_name,
        definition=definition, forms=forms, actor_email=actor_email, report_path=report_path,
    ))
