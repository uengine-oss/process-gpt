#!/usr/bin/env bash
# Process GPT 설치 사전점검 (read-only — 아무것도 변경하지 않음)
# 사용: bash preflight.sh   (레포 루트 어디서 실행해도 무방)

PASS=0; WARN=0; FAIL=0
ok()   { echo "  [OK]   $*"; PASS=$((PASS+1)); }
warn() { echo "  [WARN] $*"; WARN=$((WARN+1)); }
fail() { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }

echo "== Process GPT preflight =="

# --- 필수 바이너리 ---------------------------------------------------
command -v git >/dev/null 2>&1 && ok "git $(git --version | awk '{print $3}')" || fail "git 없음"
if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    ok "docker 데몬 실행 중 ($(docker --version | sed 's/,.*//'))"
  else
    fail "docker는 있으나 데몬 미기동 (Docker Desktop 시작 필요)"
  fi
else
  fail "docker 없음"
fi
docker compose version >/dev/null 2>&1 && ok "docker compose v2" \
  || { docker-compose version >/dev/null 2>&1 && warn "docker-compose v1만 존재 (v2 권장)" || fail "docker compose 없음"; }

# --- 아키텍처 / 메모리 ------------------------------------------------
ARCH=$(uname -m)
case "$ARCH" in
  arm64|aarch64) warn "CPU=$ARCH — 대부분 이미지가 amd64라 에뮬레이션 실행(성능·메모리 오버헤드, troubleshooting #6)";;
  *) ok "CPU=$ARCH";;
esac
if docker info >/dev/null 2>&1; then
  MEM_BYTES=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)
  MEM_GB=$((MEM_BYTES / 1024 / 1024 / 1024))
  if   [ "$MEM_GB" -ge 16 ]; then ok "Docker 메모리 ${MEM_GB}GB (Full 가능)"
  elif [ "$MEM_GB" -ge 8  ]; then warn "Docker 메모리 ${MEM_GB}GB — Core/Standard 권장, Full은 OOM 위험 (troubleshooting #14)"
  else fail "Docker 메모리 ${MEM_GB}GB — 최소 8GB로 상향 필요"; fi
fi

# --- 포트 점유 ---------------------------------------------------------
PORTS="8088 54321 3001 8443 4010 7474 7687 8000 8001 8002 8003 8005 8006 8007 8008 8009 8010 8011 8012 8013 8020 8021 8081 8765 5504 5001 5900 6080 6789 3000 1192"
BUSY=""
for p in $PORTS; do
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1 && BUSY="$BUSY $p"
  else
    (exec 3<>"/dev/tcp/127.0.0.1/$p") 2>/dev/null && { exec 3>&-; BUSY="$BUSY $p"; }
  fi
done
if [ -n "$BUSY" ]; then
  warn "점유된 포트:$BUSY — 해당 서비스만 충돌. lsof -nP -iTCP:<port> 로 소유자 확인 (troubleshooting #4/#7)"
else
  ok "필요 포트 모두 비어 있음"
fi

# --- 기존 설치 감지 -----------------------------------------------------
# 프로젝트명은 docker-compose.yml에 top-level `name:`이 없으면 컴포즈 파일이
# 있는 디렉터리명으로 정해진다 (process-gpt-infra-docker 레포를 클론 안내대로
# 그대로 clone했다면 "process-gpt-infra-docker"). 하드코딩된 "process-gpt"와
# 비교하면 정상 기동된 자기 자신의 컨테이너까지 "충돌"로 오탐한다.
COMPOSE_ROOT=""
if [ -f "./docker-compose.yml" ] && [ -f "./start-all-services.sh" ]; then
  COMPOSE_ROOT="$(pwd)"
elif [ -n "$(git rev-parse --show-toplevel 2>/dev/null)" ] && [ -f "$(git rev-parse --show-toplevel 2>/dev/null)/start-all-services.sh" ]; then
  COMPOSE_ROOT="$(git rev-parse --show-toplevel)"
fi
if [ -n "$COMPOSE_ROOT" ]; then
  EXPECTED_PROJECT="$(basename "$COMPOSE_ROOT")"
else
  EXPECTED_PROJECT="process-gpt-infra-docker"
fi

if docker info >/dev/null 2>&1; then
  RUNNING=$(docker ps --filter "label=com.docker.compose.project=${EXPECTED_PROJECT}" --format '{{.Names}}' 2>/dev/null | wc -l | tr -d ' ')
  if [ "${RUNNING:-0}" -gt 0 ]; then
    warn "${EXPECTED_PROJECT} 컨테이너 ${RUNNING}개가 이미 실행 중 — 신규 설치가 아니라 기존 스택 점검/재기동 시나리오일 수 있음 (위 포트 점유의 원인일 가능성 큼)"
  fi
fi

# --- 컨테이너 이름 충돌 (troubleshooting #5) ---------------------------
if docker info >/dev/null 2>&1; then
  FIXED_NAMES="supabase-db supabase-kong supabase-auth supabase-rest supabase-storage supabase-imgproxy supabase-meta supabase-analytics supabase-studio supabase-edge-functions neo4j deepagents process-gpt-nginx process-gpt-frontend process-gpt-completion"
  CONFLICTS=""
  for n in $FIXED_NAMES; do
    PROJ=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$n" 2>/dev/null)
    if [ $? -eq 0 ] && [ "$PROJ" != "$EXPECTED_PROJECT" ]; then CONFLICTS="$CONFLICTS $n(project:${PROJ:-none})"; fi
  done
  [ -n "$CONFLICTS" ] && warn "고정 이름 선점 컨테이너:$CONFLICTS → project 라벨이 '${EXPECTED_PROJECT}'가 아니면 다른 스택과의 진짜 충돌, 맞으면 자기 자신이므로 무시 가능. 사용자 승인 후 docker rm -f 필요" \
                      || ok "컨테이너 이름 충돌 없음"
fi

# --- GHCR 접근 ----------------------------------------------------------
if docker info >/dev/null 2>&1; then
  if grep -q '"ghcr.io"' "$HOME/.docker/config.json" 2>/dev/null; then
    ok "GHCR 로그인 흔적 있음"
  else
    LOCAL_IMGS=$(docker images --format '{{.Repository}}' 2>/dev/null | grep -c 'ghcr.io/uengine-oss' || true)
    if [ "${LOCAL_IMGS:-0}" -gt 5 ]; then
      warn "GHCR 미로그인이지만 로컬 이미지 ${LOCAL_IMGS}개 존재 → 'up -d --pull never' 사용 가능 (troubleshooting #3)"
    else
      warn "GHCR 미로그인 + 로컬 이미지 없음 → docker login ghcr.io 필요 (PAT read:packages)"
    fi
  fi
fi

# --- 레포 상태 -----------------------------------------------------------
if [ -n "$COMPOSE_ROOT" ]; then
  [ -x "$COMPOSE_ROOT/start-all-services.sh" ] && ok "start-all-services.sh 실행 가능" \
    || warn "start-all-services.sh 실행권한 없음 → chmod +x 필요 (troubleshooting #2)"
  [ -f "$COMPOSE_ROOT/.env" ] && ok ".env 존재" || warn ".env 없음 → .env.example 복사 후 시크릿 입력 필요"
  # .env.example의 placeholder는 키 값 자체가 문자열 "dream-flow"인 것 (URL의
  # ai-server.dream-flow.com 호스트명은 실사용 환경에서도 그대로 유지되는 값이라
  # 이것만으로는 placeholder 여부를 판단할 수 없다 — 반드시 키 필드로 검사).
  if [ -f "$COMPOSE_ROOT/.env" ] && grep -qE '^(OPENAI_API_KEY|LLM_PROXY_API_KEY)=dream-flow\s*$' "$COMPOSE_ROOT/.env"; then
    warn ".env의 OPENAI_API_KEY/LLM_PROXY_API_KEY가 placeholder(dream-flow) 그대로임 — 실제 LLM 키로 교체 필요 (troubleshooting #9)"
  fi
else
  warn "process-gpt-infra-docker 레포 루트가 아님 (start-all-services.sh를 찾을 수 없음) — 레포 클론/이동 후 재실행"
fi

# --- Docker VM 디스크 여유공간 (troubleshooting #17) ---------------------
if docker info >/dev/null 2>&1; then
  DISK_LINE=$(docker run --rm busybox df -k / 2>/dev/null | awk 'NR==2{print $2, $4}')
  if [ -n "$DISK_LINE" ]; then
    TOTAL_KB=$(echo "$DISK_LINE" | awk '{print $1}')
    AVAIL_KB=$(echo "$DISK_LINE" | awk '{print $2}')
    AVAIL_GB=$((AVAIL_KB / 1024 / 1024))
    if [ "$AVAIL_GB" -lt 10 ]; then
      warn "Docker VM 디스크 여유공간 ${AVAIL_GB}GB — 부족 시 이미지 pull 중 containerd content store 손상 위험 (troubleshooting #17). 'docker image prune -a' 또는 Docker Desktop 디스크 이미지 크기 상향 필요"
    else
      ok "Docker VM 디스크 여유공간 ${AVAIL_GB}GB"
    fi
  fi
fi

echo
echo "== 결과: OK=$PASS WARN=$WARN FAIL=$FAIL =="
[ "$FAIL" -gt 0 ] && exit 1 || exit 0
