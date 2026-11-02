#!/bin/bash
# 새 서비스의 매니페스트와 CI 워크플로를 템플릿에서 만든다. 커밋·푸시는 하지 않는다.
#
#   render-service.sh --service <이름> --repo <앱 저장소 이름> --app-dir <앱 저장소 경로> \
#                     --k8s-dir <process-gpt-k8s 경로> [--port 8000] [--health /health] \
#                     [--branch main] [--worker]
#
# 만드는 파일:
#   <k8s-dir>/deployments/<이름>.yaml           필수
#   <k8s-dir>/services/<이름>-service.yaml      다른 파드나 게이트웨이가 부를 때. --worker 면 만들지 않는다
#   <app-dir>/.github/workflows/deploy.yml      CI
# --worker: 받는 요청이 없는 워커. Service 를 만들지 않고 포트와 HTTP 프로브를 뺀다.
# 이미 있는 파일은 덮어쓰지 않는다.
set -euo pipefail
here=$(cd "$(dirname "$0")/../assets" && pwd)
service='' repo='' app='' k8s='' port=8000 health=/health branch=main worker=0
while [ $# -gt 0 ]; do
  case "$1" in
    --service) service=$2; shift 2 ;;
    --repo) repo=$2; shift 2 ;;
    --app-dir) app=$2; shift 2 ;;
    --k8s-dir) k8s=$2; shift 2 ;;
    --port) port=$2; shift 2 ;;
    --health) health=$2; shift 2 ;;
    --branch) branch=$2; shift 2 ;;
    --worker) worker=1; shift ;;
    *) echo "모르는 인자: $1"; exit 2 ;;
  esac
done
[ -n "$service" ] && [ -n "$repo" ] && [ -n "$app" ] && [ -n "$k8s" ] || { sed -n 4,6p "$0"; exit 2; }
[[ "$service" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || { echo "서비스 이름은 소문자, 숫자, - 만 씁니다: $service"; exit 2; }
[ -d "$k8s/deployments" ] && [ -d "$k8s/services" ] || { echo "process-gpt-k8s 경로가 아닙니다: $k8s"; exit 2; }
[ -d "$app/.git" ] || [ -f "$app/.git" ] || { echo "앱 저장소 경로가 아닙니다: $app"; exit 2; }
command -v yq >/dev/null || { echo "yq 가 필요합니다"; exit 2; }

dep="$k8s/deployments/$service.yaml"
svc="$k8s/services/$service-service.yaml"
ci="$app/.github/workflows/deploy.yml"
targets=("$dep" "$ci")
[ "$worker" = 1 ] || targets+=("$svc")
for f in "${targets[@]}"; do [ ! -e "$f" ] || { echo "이미 있습니다: $f"; exit 1; }; done

render() {
  sed -e "s|__SERVICE__|$service|g" -e "s|__REPO__|$repo|g" -e "s|__PORT__|$port|g" \
      -e "s|__HEALTH_PATH__|$health|g" -e "s|__BRANCH__|$branch|g" "$1" > "$2"
}

mkdir -p "$(dirname "$ci")"
render "$here/deployment.yaml" "$dep"
render "$here/deploy.yml" "$ci"
if [ "$worker" = 1 ]; then
  yq eval -i 'del(.spec.template.spec.containers[0].ports) | del(.spec.template.spec.containers[0].readinessProbe) | del(.spec.template.spec.containers[0].livenessProbe)' "$dep"
else
  render "$here/service.yaml" "$svc"
fi

for f in "${targets[@]}"; do
  yq eval '.' "$f" >/dev/null
  if grep -n '__[A-Z_]*__' "$f"; then echo "채우지 못한 자리: $f"; exit 1; fi
  echo "만듦: $f"
done
echo "다음: env·프로브·리소스를 서비스에 맞게 고치고, 머리 주석의 <KEY> 를 채운다."
