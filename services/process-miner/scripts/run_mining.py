"""마이닝 1회 실행 CLI.

실행:
  cd services/process-miner
  ./.venv/bin/python scripts/run_mining.py --tenant localhost \
      --process-id mined_quote_process --name "견적 처리 프로세스" [--dry-run] [--out result.json]
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app import miner  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tenant", default="localhost")
    ap.add_argument("--process-id", default="mined_quote_process")
    ap.add_argument("--name", default="견적 처리 프로세스")
    ap.add_argument("--min-freq", type=int, default=1)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    result = miner.run(
        tenant_id=args.tenant,
        process_id=args.process_id,
        process_name=args.name,
        min_freq=args.min_freq,
        dry_run=args.dry_run,
    )

    if not result.get("ok"):
        print("도출 실패:", result.get("reason"))
        for p in result.get("problems", []):
            print("  -", p)
        return 1

    s = result["stats"]
    print(f"이벤트 {s['event_count']}건 / 케이스 {s['case_count']}건 / 활동 {s['activity_count']}종")
    print("\n관측된 흐름(변형):")
    for v in s["variants"]:
        print(f"  {v['count']:>2}건  {' → '.join(v['trace'])}")
    print("\n도출된 구조:")
    print("  ", result["tree"])

    defn = result["definition"]
    print(f"\n활동 {len(defn['activities'])}개 / 게이트웨이 {len(defn['gateways'])}개 / 역할 {len(defn['roles'])}개")
    for a in defn["activities"]:
        tag = f"  [{a['agent']} · {a['orchestration']} · {a['agentMode']}]" if a.get("agent") else ""
        print(f"  - {a['name']}  (역할: {a['role']}){tag}")

    if result.get("pr"):
        pr = result["pr"]
        print(f"\nPR 생성됨: {pr['title']}  (id={pr['pr_id']}, version={pr['version']})")

    if args.out:
        payload = {k: v for k, v in result.items() if k != "tree_node"}
        Path(args.out).write_text(json.dumps(payload, ensure_ascii=False, indent=2, default=str), encoding="utf-8")
        print(f"결과 저장: {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
