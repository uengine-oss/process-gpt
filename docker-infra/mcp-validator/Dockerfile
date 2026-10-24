# mcp-validator 용 Dockerfile.
#
# services/mcp-validator 는 별도 git 서브모듈이라 이미지 정의가 없었고,
# 그래서 지금까지 어디에도 배포되지 않은 채 방치돼 있었다. 서브모듈을
# 건드리지 않고 부모 레포만으로 빌드할 수 있도록 여기에 둔다.
# (compose 에서 context 는 서브모듈, dockerfile 은 이 파일을 가리킨다.)
FROM python:3.12-slim

WORKDIR /app

RUN apt-get update \
 && apt-get install -y --no-install-recommends curl nodejs npm \
 && rm -rf /var/lib/apt/lists/*

# stdio MCP 서버를 spawn 하는 쪽이 이 컨테이너다 — uvx/npx 가 필요하다.
RUN pip install --no-cache-dir uv

RUN pip install --no-cache-dir \
      "fastapi>=0.116.1" \
      "uvicorn[standard]>=0.35.0" \
      "pydantic>=2.11.7" \
      "langchain-mcp-adapters>=0.1.9" \
      "mcp>=1.13.0,<2"

COPY src ./src

ENV PYTHONUNBUFFERED=1
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS http://localhost:8000/health || exit 1

CMD ["uvicorn", "src.mcp_validator.api:app", "--host", "0.0.0.0", "--port", "8000"]
