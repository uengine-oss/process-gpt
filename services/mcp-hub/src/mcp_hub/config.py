"""환경 설정.

DB 는 psycopg 로 직접 붙는다 — 관측 집계(p95, 오류율)가 SQL 쪽에서
끝나야 해서 PostgREST 경유로는 표현이 안 되기 때문이다.
"""
import os


def _db_url() -> str:
    url = os.getenv("PROCESSGPT_DB_URL") or os.getenv("SUPABASE_DB_URL")
    if url:
        return url
    host = os.getenv("POSTGRES_HOST", "db")
    port = os.getenv("POSTGRES_PORT", "5432")
    db = os.getenv("POSTGRES_DB", "postgres")
    user = os.getenv("POSTGRES_USER", "postgres")
    pw = os.getenv("POSTGRES_PASSWORD", "postgres")
    return f"postgresql://{user}:{pw}@{host}:{port}/{db}"


DB_URL = _db_url()

# 연결 검증과 tools/list 는 mcp-validator 에 위임한다.
# stdio 서버를 spawn 하는 쪽을 전용 컨테이너에 가둬 허브를 깨끗하게 유지한다.
VALIDATOR_URL = os.getenv("MCP_VALIDATOR_URL", "http://mcp-validator:8000")
VALIDATE_TIMEOUT = int(os.getenv("MCP_VALIDATE_TIMEOUT", "15"))

# 헬스 스케줄러
HEALTH_INTERVAL_SEC = int(os.getenv("MCP_HEALTH_INTERVAL_SEC", "300"))
HEALTH_ENABLED = os.getenv("MCP_HEALTH_ENABLED", "true").lower() != "false"
HEALTH_DEGRADED_MS = int(os.getenv("MCP_HEALTH_DEGRADED_MS", "3000"))

# 공식 MCP Registry
REGISTRY_URL = os.getenv("MCP_REGISTRY_URL", "https://registry.modelcontextprotocol.io")
REGISTRY_ENABLED = os.getenv("MCP_REGISTRY_ENABLED", "true").lower() != "false"

PORT = int(os.getenv("PORT", "8500"))
