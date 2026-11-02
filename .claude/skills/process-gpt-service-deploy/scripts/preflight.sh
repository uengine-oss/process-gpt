#!/bin/bash
# 배포 전 현재 상태를 읽기만 한다. 푸시·수정·fetch 를 하지 않는다.
# 사용법: preflight.sh            전체
#         WS=/path preflight.sh   저장소들이 ~/ws 가 아닌 곳에 있을 때
# 필요: gh(로그인), git
ORG=uengine-oss
K8S=$ORG/process-gpt-k8s
WS=${WS:-$HOME/ws}

command -v gh >/dev/null || { echo "gh 가 없습니다"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh 로그인이 필요합니다"; exit 1; }

# 저장소  로컬 경로
LOCAL="process-gpt-lite:$WS/process-gpt-lite
process-gpt-vue3:$WS/process-gpt-vue3
process-gpt-k8s:$WS/infra/process-gpt-k8s
process-gpt-deepagents:$WS/process-gpt-deepagents
process-gpt-completion:$WS/process-gpt-completion"

# 저장소  매니페스트  이미지 이름의 일부(한 파일에 이미지가 여럿일 때 고른다)
SERVICES="process-gpt-lite deployments/process-gpt-lite.yaml process-gpt-lite-server
process-gpt-vue3 deployments/frontend-deployment.yaml uengine-oss/process-gpt:
process-gpt-vue3 deployments/gateway.yaml process-gpt-gateway
process-gpt-deepagents deployments/process-gpt-deepagents.yaml process-gpt-deepagents
process-gpt-completion deployments/completion-deployment.yaml :
process-gpt-completion deployments/polling-service-deployment.yaml :
process-gpt-memento deployments/memento-deployment.yaml :
process-gpt-office-mcp deployments/process-gpt-office-mcp-deployment.yaml :
process-gpt-agent-feedback deployments/agent-feedback.yaml :"

echo "== 로컬 저장소 =="
printf '%s\n' "$LOCAL" | while IFS=: read -r name path; do
  if [ ! -d "$path/.git" ] && [ ! -f "$path/.git" ]; then echo "  $name: 없음 ($path)"; continue; fi
  branch=$(git -C "$path" rev-parse --abbrev-ref HEAD)
  counts=$(git -C "$path" rev-list --left-right --count "@{u}...HEAD" 2>/dev/null | awk '{print "뒤 "$1" 앞 "$2}')
  dirty=$(git -C "$path" status --porcelain | wc -l | tr -d ' ')
  echo "  $name: $branch ${counts:-추적 브랜치 없음}, 변경 $dirty"
done

echo "== 운영 태그와 기본 브랜치의 차이 =="
printf '%s\n' "$SERVICES" | while read -r repo file match; do
  yaml=$(gh api "repos/$K8S/contents/$file" --jq .content 2>/dev/null | base64 -d)
  tag=$(printf '%s\n' "$yaml" | grep -E '^\s*image:\s*ghcr' | grep -F "$match" | head -1 | sed -E 's/.*:([^:]+)$/\1/')
  branch=$(gh api "repos/$ORG/$repo" --jq .default_branch 2>/dev/null)
  if [ -z "$tag" ] || [ -z "$branch" ]; then echo "  $file: 확인 못 함"; continue; fi
  behind=$(gh api "repos/$ORG/$repo/compare/$tag...$branch" --jq .ahead_by 2>/dev/null)
  echo "  $(basename "$file" .yaml): $tag, $repo/$branch 가 ${behind:-?}커밋 앞섬"
done

echo "== 최근 배포 실행 =="
for spec in process-gpt-lite:deploy.yml process-gpt-vue3:deploy.yaml process-gpt-deepagents:deploy.yml; do
  repo=${spec%%:*}; wf=${spec##*:}
  line=$(gh run list -R "$ORG/$repo" --workflow "$wf" -L 3 --json conclusion,status,createdAt \
    --jq 'map((.conclusion // .status) + " " + (.createdAt | .[0:10])) | join(", ")' 2>/dev/null)
  echo "  $repo: ${line:-확인 못 함}"
done

echo "== 이미지 공개 여부 =="
for image in process-gpt-lite-web process-gpt-lite-server process-gpt-lite-office-host; do
  echo "  $image: $(gh api "/orgs/$ORG/packages/container/$image" --jq .visibility 2>/dev/null || echo '확인 못 함')"
done

echo "== Lite 저장소 Secret =="
gh secret list -R "$ORG/process-gpt-lite" --json name --jq '.[].name' 2>/dev/null | sed 's/^/  /'

echo "== 운영 DB 적용 상태 =="
echo "  사용자에게 조회를 부탁한다: select name from lite_migrations order by 1;"
