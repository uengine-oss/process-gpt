#!/usr/bin/env bash
# e2e 스택 기동: secret 생성 → 안전 점검 → 매니페스트 적용 → 롤아웃 대기 → 게이트웨이 포트포워드
set -euo pipefail
E="$(cd "$(dirname "$0")" && pwd)"; CTX=kind-kind; NS=resume-e2e
k(){ kubectl --context $CTX -n $NS "$@"; }
SB_DIR=/Users/soon/ws/process-gpt-vue3
eval "$(cd $SB_DIR && npx -y supabase status -o env 2>/dev/null | sed 's/^/export SB_/')"
LITELLM_KEY=$(grep '^LITELLM_MASTER_KEY=' /Users/soon/ws/process-gpt-llm-proxy/.env | cut -d= -f2- | tr -d '"')
DB_PASSWORD=$(python3 -c "import urllib.parse,os;print(urllib.parse.urlparse(os.environ['SB_DB_URL']).password)")

# 디스크 점검: colima VM 디스크가 차면 로컬 Supabase DB 가 "No space left on device" 로 재시작을 반복한다
# (2026-10-07 e2e 중 실제로 그랬다 — 이미지 빌드 캐시가 원인). 여유가 10GB 미만이면 시작하지 않는다.
free_gb=$(docker exec kind-control-plane df -BG --output=avail / | tail -1 | tr -dc 0-9)
if [ "${free_gb:-0}" -lt 10 ]; then echo "중단: VM 디스크 여유 ${free_gb}GB (< 10GB). docker builder prune -af 등으로 비울 것"; exit 1; fi

# 안전 점검: 이 스택의 워커가 남의 개발 데이터를 집지 않게 한다.
q(){ docker exec supabase_db_process-gpt-vue3 psql -U postgres -qtAX -c "$1"; }
claimable=$(q "select count(*) from todolist t where t.status='IN_PROGRESS' and t.agent_orch in ('deepagents','cli-agent','codex')
  and ((t.agent_mode in ('DRAFT','COMPLETE') and t.draft is null and t.draft_status is null) or t.draft_status='FB_REQUESTED'
       or (t.draft_status='STARTED' and t.lease_until < now() and coalesce(t.claim_count,0) < 3))
  and coalesce(t.proc_def_id,'') not like 'resume_e2e_%'")
submitted=$(q "select count(*) from todolist where status='SUBMITTED' and coalesce(proc_def_id,'') not like 'resume_e2e_%'")
if [ "$claimable" != 0 ] || [ "$submitted" != 0 ]; then
  echo "중단: e2e 밖의 집힐 수 있는 행 claimable=$claimable submitted=$submitted"; exit 1; fi

kubectl --context $CTX apply -f "$E/k8s/stack.yaml" >/dev/null
k create secret generic e2e-secrets --dry-run=client -o yaml \
  --from-literal=SUPABASE_SERVICE_KEY="$SB_SERVICE_ROLE_KEY" --from-literal=SUPABASE_ANON_KEY="$SB_ANON_KEY" \
  --from-literal=SUPABASE_JWT_SECRET="$SB_JWT_SECRET" --from-literal=LITELLM_KEY="$LITELLM_KEY" \
  --from-literal=DB_PASSWORD="$DB_PASSWORD" | kubectl --context $CTX apply -f - >/dev/null
k rollout restart deploy >/dev/null
for d in $(k get deploy -o name); do k rollout status $d --timeout=240s || echo "NOT READY: $d"; done
pkill -f "port-forward.*$NS.*svc/gateway" 2>/dev/null || true
nohup kubectl --context $CTX -n $NS port-forward svc/gateway 18088:8088 > "$E/.logs/port-forward.log" 2>&1 &
sleep 2; curl -s -o /dev/null -w "gateway http://localhost:18088 -> %{http_code}\n" http://localhost:18088/
