#!/usr/bin/env bash
# e2e 이미지 빌드 + kind 적재. 각 저장소의 현재 작업 트리(커밋 전 변경 포함)로 빌드한다.
set -euo pipefail
WS=/Users/soon/ws; E="$(cd "$(dirname "$0")" && pwd)"; L="$E/.logs"; mkdir -p "$L"
SDK_CTX="$E/.sdk-ctx"; rm -rf "$SDK_CTX"; mkdir -p "$SDK_CTX"
rsync -a --exclude .venv --exclude '*.egg-info' --exclude __pycache__ --exclude .git --exclude tests "$WS/process-gpt-agent-sdk/" "$SDK_CTX/"
only="${1:-all}"
b(){ # name repo platform
  local n=$1 repo=$2 plat=$3
  [ "$only" = all ] || [ "$only" = "$n" ] || return 0
  echo "== build $n ($plat) $(date +%T)"
  local df=(); [ -f "$E/$n.Dockerfile" ] && df=(-f "$E/$n.Dockerfile")
  docker buildx build --platform "$plat" --load ${df[@]+"${df[@]}"} -t "pgpt-e2e/$n:base" "$WS/$repo" > "$L/build-$n.log" 2>&1
  docker buildx build --platform "$plat" --load --build-context sdk="$SDK_CTX" --build-arg BASE="pgpt-e2e/$n:base" \
    -t "pgpt-e2e/$n:e2e" -f "$E/Dockerfile.sdk-overlay" "$E" >> "$L/build-$n.log" 2>&1
  load "$n" "$plat"
  echo "   ok $n $(date +%T)"
}
load(){ # kind load 는 노드와 다른 플랫폼(amd64 on arm64) 이미지를 조용히 건너뛴다
  if [ "$2" = linux/arm64 ]; then kind load docker-image --name kind "pgpt-e2e/$1:e2e" >> "$L/build-$1.log" 2>&1
  else docker save --platform "$2" "pgpt-e2e/$1:e2e" | docker exec -i kind-control-plane ctr -n k8s.io images import --platform "$2" - >> "$L/build-$1.log" 2>&1; fi
}
p(){ # plain: name repo dockerfile-dir platform
  local n=$1 ctx=$2 plat=$3
  [ "$only" = all ] || [ "$only" = "$n" ] || return 0
  echo "== build $n ($plat) $(date +%T)"
  docker buildx build --platform "$plat" --load -t "pgpt-e2e/$n:e2e" "$ctx" > "$L/build-$n.log" 2>&1
  load "$n" "$plat"
  echo "   ok $n $(date +%T)"
}
b deepagents process-gpt-deepagents linux/arm64
b cli-agent  process-gpt-cli-agent  linux/arm64
p completion "$WS/process-gpt-completion" linux/arm64
# frontend: 저장소 Dockerfile 의 npm ci 가 lock 불일치로 실패해(커밋 상태) 호스트 node_modules 로 dist 를 만든다
if [ "$only" = all ] || [ "$only" = frontend ]; then
  echo "== build frontend (linux/arm64) $(date +%T)"
  rm -rf "$E/.frontend-dist"
  (cd "$WS/process-gpt-vue3" && NODE_OPTIONS=--max-old-space-size=6144 npx vite build --outDir "$E/.frontend-dist") > "$L/build-frontend.log" 2>&1
  docker buildx build --platform linux/arm64 --load --build-context vue3="$WS/process-gpt-vue3" \
    -t pgpt-e2e/frontend:e2e -f "$E/frontend.runtime.Dockerfile" "$E" >> "$L/build-frontend.log" 2>&1
  load frontend linux/arm64
  rm -rf "$E/.frontend-dist"
  echo "   ok frontend $(date +%T)"
fi
p polling    "$WS/process-gpt-completion/polling_service" linux/arm64
b codex      process-gpt-codex      linux/amd64
p memento    "$WS/process-gpt-memento" linux/arm64
echo "ALL DONE $(date +%T)"
