#!/bin/bash
# 운영에 넘길 SQL 을 일회용 DB 에서 두 번 돌려 본다. 운영에는 연결하지 않는다.
#   test-prod-sql.sh <schema-dir> <sql 파일>...
# schema-dir: process-gpt-infra-docker/volumes/db (init.sql, migration.sql 이 있는 곳)
# 기준 스키마를 init → migration → init 으로 적용한 뒤, 넘긴 파일을 차례로 두 번 실행한다.
# 끝나면 컨테이너를 지운다. 기준 스키마는 운영과 다를 수 있으니 통과가 운영 성공을 보장하지는 않는다.
set -euo pipefail
IMAGE=${PG_IMAGE:-public.ecr.aws/supabase/postgres:15.8.1.085}
schema=${1:?schema-dir}; shift
[ $# -ge 1 ] || { echo "SQL 파일을 하나 이상 주세요"; exit 2; }
[ -f "$schema/init.sql" ] && [ -f "$schema/migration.sql" ] || { echo "$schema 에 init.sql·migration.sql 이 없습니다"; exit 2; }
for f in "$@"; do [ -f "$f" ] || { echo "없는 파일: $f"; exit 2; }; done

name=pgpt-sql-test-$$
trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT
docker run -d --name "$name" -e POSTGRES_PASSWORD=postgres "$IMAGE" >/dev/null

echo "DB 기다리는 중..."
for _ in $(seq 1 60); do
  docker exec "$name" pg_isready -U postgres -h 127.0.0.1 >/dev/null 2>&1 && break
  sleep 2
done
docker exec "$name" pg_isready -U postgres -h 127.0.0.1 >/dev/null

run() { docker exec -i "$name" psql -U postgres -h 127.0.0.1 -d postgres -q "$@" >/dev/null; }

# 기준 스키마는 순서상 앞 단계 오류가 날 수 있어 멈추지 않는다
echo "기준 스키마 적용"
run < "$schema/init.sql" 2>/dev/null || true
run < "$schema/migration.sql" 2>/dev/null || true
run < "$schema/init.sql" 2>/dev/null || true

for round in 1 2; do
  for f in "$@"; do
    echo "[${round}회차] $f"
    run -v ON_ERROR_STOP=1 < "$f"
  done
done
echo "통과: 두 번 실행해도 오류가 없습니다"
