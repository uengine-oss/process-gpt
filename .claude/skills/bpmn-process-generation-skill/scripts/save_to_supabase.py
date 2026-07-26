"""서비스(ProcessGPT deepagent) 모드 저장 모듈.

09-service-execution.md 의 출력 계약 JSON 을 받아 pdf2bpmn 와 동일하게 Supabase 에
저장한다. 저장 대상: proc_def / configuration(proc_map) / form_def / users(agent) /
agent_skills / tenants.skills.

핵심:
- 우리 스킬의 processDefinition 은 elements[] 형식(02-generate-definition 규격)이다.
  ProcessGPT/완료엔진이 소비하는 proc_def.definition 은 **flattened 형식**
  (activities/sequences/gateways/events/roles 분리 배열)이므로 flatten() 으로 변환한다.
- bpmn 컬럼은 pdf2bpmn 와 동일하게 None(=XML 비움). 프론트가 definition 으로 렌더.

환경변수: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY(또는 SERVICE_ROLE_KEY).
"""

from __future__ import annotations

import os
import re
import json
import logging
from typing import Any, Dict, List, Optional

logger = logging.getLogger("bpmn.save")

try:
    from supabase import create_client, Client  # type: ignore
    SUPABASE_AVAILABLE = True
except Exception:  # pragma: no cover
    create_client = None  # type: ignore
    Client = Any  # type: ignore
    SUPABASE_AVAILABLE = False


# ---------------------------------------------------------------------------
# Supabase client
# ---------------------------------------------------------------------------
def get_client() -> "Client":
    """ProcessGPT deepagent(core/db.py)와 동일한 순서로 Supabase 클라이언트를 만든다."""
    if not SUPABASE_AVAILABLE:
        raise RuntimeError("supabase 패키지가 없습니다. requirements.txt 를 설치하세요.")
    url = os.getenv("SUPABASE_URL") or os.getenv("SUPABASE_KEY_URL")
    key = (
        os.getenv("SERVICE_ROLE_KEY")
        or os.getenv("SUPABASE_SERVICE_ROLE_KEY")
        or os.getenv("SUPABASE_KEY")
        or os.getenv("SUPABASE_ANON_KEY")
    )
    if not url or not key:
        raise RuntimeError("SUPABASE_URL 과 SUPABASE_KEY(또는 SERVICE_ROLE_KEY) 환경변수가 필요합니다.")
    return create_client(url, key)


# ---------------------------------------------------------------------------
# elements[] → flattened 변환
# ---------------------------------------------------------------------------
_EVENT_TYPE_MAP = {
    "StartEvent": "startEvent",
    "EndEvent": "endEvent",
    "IntermediateCatchEvent": "intermediateCatchEvent",
    "IntermediateThrowEvent": "intermediateThrowEvent",
}
_GATEWAY_TYPE_MAP = {
    "ExclusiveGateway": "exclusiveGateway",
    "ParallelGateway": "parallelGateway",
    "InclusiveGateway": "inclusiveGateway",
}
_ACTIVITY_TYPE_MAP = {
    "UserActivity": "userTask",
    "ManualActivity": "manualTask",
    "ServiceActivity": "serviceTask",
    "ScriptActivity": "scriptTask",
}


def _as_props_string(value: Any) -> str:
    """properties 는 ProcessGPT 규격상 JSON 문자열로 저장한다."""
    if value is None:
        return "{}"
    if isinstance(value, str):
        return value or "{}"
    try:
        return json.dumps(value, ensure_ascii=False)
    except Exception:
        return "{}"


def _as_int_duration(value: Any) -> Any:
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return value if value is not None else None


def flatten(process_definition: Dict[str, Any]) -> Dict[str, Any]:
    """elements[] 형식 processDefinition → flattened proc_def.definition.

    pdf2bpmn output/generated_procdef_from_procid.json 의 형태를 그대로 따른다.
    """
    pd = process_definition or {}
    proc_id = pd.get("processDefinitionId") or pd.get("processDefinitionName") or ""
    elements = pd.get("elements") or []

    activities: List[Dict[str, Any]] = []
    gateways: List[Dict[str, Any]] = []
    events: List[Dict[str, Any]] = []
    sequences: List[Dict[str, Any]] = []

    for el in elements:
        if not isinstance(el, dict):
            continue
        et = el.get("elementType")
        if et == "Activity":
            activities.append({
                "id": el.get("id"),
                "name": el.get("name"),
                "role": el.get("role"),
                "tool": el.get("tool"),
                "type": _ACTIVITY_TYPE_MAP.get(el.get("type"), "userTask"),
                "agent": el.get("agent"),
                "process": proc_id,
                "duration": _as_int_duration(el.get("duration")),
                "agentMode": el.get("agentMode") or "none",
                "skills": el.get("skills") or [],
                "inputData": el.get("inputData") or [],
                "outputData": el.get("outputData") or [],
                "properties": _as_props_string(el.get("properties")),
                "attachments": el.get("attachments") or [],
                "checkpoints": el.get("checkpoints") or [],
                "description": el.get("description") or "",
                "instruction": el.get("instruction") or "",
                "orchestration": el.get("orchestration"),
                "attachedEvents": el.get("attachedEvents"),
                "customProperties": el.get("customProperties") or [],
            })
        elif et == "Gateway":
            gateways.append({
                "id": el.get("id"),
                "name": el.get("name"),
                "role": el.get("role"),
                "type": _GATEWAY_TYPE_MAP.get(el.get("type"), "exclusiveGateway"),
                "process": proc_id,
                "conditionData": el.get("conditionData") or [],
                "properties": _as_props_string(el.get("properties")),
                "description": el.get("description") or "",
            })
        elif et == "Event":
            events.append({
                "id": el.get("id"),
                "name": el.get("name"),
                "role": el.get("role"),
                "type": _EVENT_TYPE_MAP.get(el.get("type"), "startEvent"),
                "process": proc_id,
                "trigger": el.get("trigger") or "",
                "properties": _as_props_string(el.get("properties")),
                "description": el.get("description") or "",
            })
        elif et == "Sequence":
            sequences.append({
                "id": el.get("id"),
                "name": el.get("name") or "",
                "source": el.get("source"),
                "target": el.get("target"),
                "condition": el.get("condition") or "",
                "properties": _as_props_string(el.get("properties")),
            })

    flat: Dict[str, Any] = {
        "data": pd.get("data") or [],
        "roles": pd.get("roles") or [],
        "events": events,
        "gateways": gateways,
        "sequences": sequences,
        "activities": activities,
        "description": pd.get("description") or "",
        "isHorizontal": pd.get("isHorizontal", True),
        "participants": pd.get("participants") or [],
        "subProcesses": pd.get("subProcesses") or [],
        "processDefinitionId": proc_id,
        "processDefinitionName": pd.get("processDefinitionName") or "",
    }
    # DMN(있으면) 그대로 보존
    if pd.get("dmn_decisions") is not None:
        flat["dmn_decisions"] = pd.get("dmn_decisions")
    if pd.get("dmn_rules") is not None:
        flat["dmn_rules"] = pd.get("dmn_rules")
    if pd.get("megaProcessId"):
        flat["megaProcessId"] = pd.get("megaProcessId")
    if pd.get("majorProcessId"):
        flat["majorProcessId"] = pd.get("majorProcessId")
    return flat


# ---------------------------------------------------------------------------
# form HTML → fields_json
# ---------------------------------------------------------------------------
_FIELD_TAG_TYPE = {
    "text-field": "text",
    "textarea-field": "textarea",
    "boolean-field": "boolean",
    "select-field": "select",
    "checkbox-field": "checkbox",
    "radio-field": "radio",
    "user-select-field": "user",
    "file-field": "file",
    "report-field": "report",
    "slide-field": "slide",
    "label-field": "label",
    "date-field": "date",
    "number-field": "number",
}


def html_to_fields_json(html: str) -> List[Dict[str, Any]]:
    """폼 HTML 에서 컴포넌트 필드를 추출해 [{key,text,type}] 로 만든다."""
    if not html:
        return []
    out: List[Dict[str, Any]] = []
    seen = set()
    tag_pattern = "|".join(re.escape(t) for t in _FIELD_TAG_TYPE)
    for m in re.finditer(rf"<({tag_pattern})\b([^>]*)>", html, re.IGNORECASE):
        tag = m.group(1).lower()
        attrs = m.group(2)
        name_m = re.search(r"name\s*=\s*['\"]([^'\"]+)['\"]", attrs)
        if not name_m:
            continue
        key = name_m.group(1).strip()
        if not key or key in seen:
            continue
        seen.add(key)
        alias_m = re.search(r"alias\s*=\s*['\"]([^'\"]+)['\"]", attrs)
        label_m = re.search(r"label\s*=\s*['\"]([^'\"]+)['\"]", attrs)
        text = (alias_m.group(1) if alias_m else (label_m.group(1) if label_m else key)).strip()
        ftype_m = re.search(r"\btype\s*=\s*['\"]([^'\"]+)['\"]", attrs)
        ftype = ftype_m.group(1).strip() if ftype_m else _FIELD_TAG_TYPE.get(tag, "text")
        field = {"key": key, "text": text, "type": ftype}
        if tag == "select-field":
            options: List[str] = []
            options_m = re.search(r"\boptions\s*=\s*['\"]([^'\"]+)['\"]", attrs)
            if options_m:
                options = [value.strip() for value in options_m.group(1).split("/") if value.strip()]
            else:
                close_at = html.lower().find("</select-field>", m.end())
                body = html[m.end():close_at] if close_at >= 0 else ""
                options = [
                    value.strip() for value in re.findall(
                        r"<option\b[^>]*\bvalue\s*=\s*['\"]([^'\"]+)['\"]", body, re.IGNORECASE
                    ) if value.strip()
                ]
            if options:
                field["options"] = options
        out.append(field)
    return out


# ---------------------------------------------------------------------------
# 저장
# ---------------------------------------------------------------------------
def _save_proc_def(sb: "Client", *, proc_def_id: str, name: str,
                   definition: Dict[str, Any], tenant_id: str) -> str:
    """proc_def upsert. id 로 조회 → 있으면 uuid 로 update, 없으면 insert."""
    existing = (
        sb.table("proc_def").select("uuid,id")
        .eq("tenant_id", tenant_id).eq("id", proc_def_id).execute()
    )
    payload = {
        "id": proc_def_id,
        "name": name,
        "definition": definition,
        "bpmn": None,
        "type": "bpmn",
        "isdeleted": False,
        "tenant_id": tenant_id,
    }
    rows = existing.data or []
    if rows and rows[0].get("uuid"):
        sb.table("proc_def").update(payload).eq("uuid", rows[0]["uuid"]).execute()
        return "updated"
    sb.table("proc_def").insert(payload).execute()
    return "inserted"


def _save_proc_map(sb: "Client", *, proc_def_id: str, name: str, tenant_id: str) -> None:
    """configuration.proc_map 에 이 프로세스를 미분류로 등록(없으면 추가)."""
    res = (
        sb.table("configuration").select("value")
        .eq("key", "proc_map").eq("tenant_id", tenant_id).execute()
    )
    rows = res.data or []
    sub_entry = {"id": proc_def_id, "name": name, "path": proc_def_id, "new": True}
    if rows:
        proc_map = rows[0].get("value") or {}
        try:
            mega = proc_map.setdefault("mega_proc_list", [])
            if not mega:
                mega.append({"id": "unclassified", "name": "미분류", "major_proc_list": []})
            major = mega[0].setdefault("major_proc_list", [])
            if not major:
                major.append({"id": "unclassified_major", "name": "미분류", "sub_proc_list": []})
            sub = major[0].setdefault("sub_proc_list", [])
            if not any(s.get("id") == proc_def_id for s in sub):
                sub.append(sub_entry)
            sb.table("configuration").update({"value": proc_map}) \
                .eq("key", "proc_map").eq("tenant_id", tenant_id).execute()
        except Exception as e:  # pragma: no cover
            logger.warning("[SAVE] proc_map update 실패: %s", e)
    else:
        proc_map = {"mega_proc_list": [{
            "id": "unclassified", "name": "미분류",
            "major_proc_list": [{
                "id": "unclassified_major", "name": "미분류",
                "sub_proc_list": [sub_entry],
            }],
        }]}
        sb.table("configuration").insert({
            "key": "proc_map", "value": proc_map, "tenant_id": tenant_id,
        }).execute()


def _save_forms(sb: "Client", *, proc_def_id: str, forms: List[Dict[str, Any]],
                tenant_id: str) -> int:
    saved = 0
    for form in forms or []:
        activity_id = (form.get("activity_id") or "").strip()
        html = form.get("html") or ""
        form_id = (form.get("form_id") or "").strip() or f"{proc_def_id}_{activity_id}_form"
        form_id = form_id.replace("/", "#")
        fields_json = form.get("fields_json") or html_to_fields_json(html)
        existing = (
            sb.table("form_def").select("uuid,id")
            .eq("tenant_id", tenant_id).eq("proc_def_id", proc_def_id)
            .eq("activity_id", activity_id).execute()
        )
        payload = {
            "id": form_id, "html": html, "proc_def_id": proc_def_id,
            "activity_id": activity_id, "fields_json": fields_json, "tenant_id": tenant_id,
        }
        rows = existing.data or []
        if rows and rows[0].get("uuid"):
            sb.table("form_def").update(payload).eq("uuid", rows[0]["uuid"]).execute()
        else:
            sb.table("form_def").insert(payload).execute()
        saved += 1
    return saved


def _save_agents(sb: "Client", *, agents: List[Dict[str, Any]], tenant_id: str) -> List[Dict[str, Any]]:
    """에이전트(users is_agent=true)에 skills 병합 + agent_skills 매핑.

    pdf2bpmn 와 동일하게 '이미 존재하는 agent user' 에만 스킬을 붙인다(신규 user 생성 안 함).
    매칭은 agent.id 로 users.id 를 찾는다.
    """
    out: List[Dict[str, Any]] = []
    for ag in agents or []:
        aid = (ag.get("id") or "").strip()
        skills = [str(s).strip() for s in (ag.get("skills") or []) if str(s).strip()]
        if not aid:
            continue
        res = sb.table("users").select("id,username,role,is_agent,skills") \
            .eq("id", aid).eq("tenant_id", tenant_id).execute()
        rows = res.data or []
        if not rows or rows[0].get("is_agent") is not True:
            logger.info("[SAVE] agent user 없음/비에이전트 → skip id=%s", aid)
            continue
        row = rows[0]
        prev = str(row.get("skills") or "")
        prev_list = [s.strip() for s in prev.split(",") if s.strip()]
        merged = list(dict.fromkeys(prev_list + skills))
        if merged:
            sb.table("users").update({"skills": ",".join(merged)}) \
                .eq("id", aid).eq("tenant_id", tenant_id).execute()
        for s in skills:
            try:
                sb.table("agent_skills").insert(
                    {"user_id": aid, "tenant_id": tenant_id, "skill_name": s}
                ).execute()
            except Exception:
                pass  # pk 충돌(중복) 무시
        out.append({"id": aid, "name": row.get("username") or row.get("name") or aid,
                    "role": row.get("role") or "", "skills": skills})
    return out


def _register_tenant_skills(sb: "Client", *, skills: List[str], tenant_id: str) -> None:
    skills = [str(s).strip() for s in (skills or []) if str(s).strip()]
    if not skills:
        return
    try:
        tres = sb.table("tenants").select("*").eq("id", tenant_id).execute()
        rows = tres.data or []
        prev = str((rows[0].get("skills") if rows else "") or "")
        prev_list = [s.strip() for s in prev.split(",") if s.strip()]
        merged = list(dict.fromkeys(prev_list + skills))
        sb.table("tenants").update({"skills": ",".join(merged)}).eq("id", tenant_id).execute()
    except Exception as e:  # 스키마에 skills 없을 수 있음 — best effort
        logger.info("[SAVE] tenants.skills 동기화 skip: %s", e)


def save_contract(contract: Dict[str, Any], *, tenant_id: str,
                  sb: Optional["Client"] = None) -> Dict[str, Any]:
    """출력 계약 JSON 을 Supabase 에 저장하고 요약을 반환한다."""
    sb = sb or get_client()
    pd = contract.get("processDefinition") or {}
    proc_def_id = pd.get("processDefinitionId") or ""
    name = pd.get("processDefinitionName") or proc_def_id
    if not proc_def_id:
        raise ValueError("processDefinition.processDefinitionId 가 비어 있습니다.")

    definition = flatten(pd)
    proc_action = _save_proc_def(sb, proc_def_id=proc_def_id, name=name,
                                 definition=definition, tenant_id=tenant_id)
    _save_proc_map(sb, proc_def_id=proc_def_id, name=name, tenant_id=tenant_id)
    forms_saved = _save_forms(sb, proc_def_id=proc_def_id,
                              forms=contract.get("forms") or [], tenant_id=tenant_id)
    agents_saved = _save_agents(sb, agents=contract.get("agents") or [], tenant_id=tenant_id)
    _register_tenant_skills(sb, skills=contract.get("skills") or [], tenant_id=tenant_id)

    return {
        "proc_def_id": proc_def_id,
        "process_name": name,
        "proc_def": proc_action,
        "forms_saved": forms_saved,
        "agents_saved": agents_saved,
        "skills_registered": contract.get("skills") or [],
        "definition": definition,  # 검증 단계로 넘김
    }
