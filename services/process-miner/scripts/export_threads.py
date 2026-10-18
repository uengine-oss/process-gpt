"""데모용: 인계 스레드 묶음을 JSON 으로 내보낸다(Gmail forward 묶음 형태)."""
from __future__ import annotations

import json
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app import db  # noqa: E402


def main() -> None:
    tenant = sys.argv[1] if len(sys.argv) > 1 else "localhost"
    out = sys.argv[2] if len(sys.argv) > 2 else "threads.json"

    rows = db.fetch_handover_events(tenant)
    threads: dict[str, list[dict]] = defaultdict(list)
    for r in rows:
        threads[r["origin_room_id"] or r["case_id"]].append(
            {
                "from": r["from_user_name"] or r["from_user_id"],
                "to": r["to_user_name"] or r["to_user_id"],
                "to_is_agent": r["to_is_agent"],
                "activity": r["next_activity_label"],
                "source": r["source"],
                "is_explicit": r["is_explicit"],
                "occurred_at": str(r["occurred_at"]),
            }
        )

    payload = [
        {"origin_room_id": k, "steps": v, "step_count": len(v)}
        for k, v in sorted(threads.items())
    ]
    Path(out).write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"스레드 {len(payload)}개 / 총 {sum(t['step_count'] for t in payload)}단계 → {out}")


if __name__ == "__main__":
    main()
