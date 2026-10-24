FROM python:3.12-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src ./src
COPY main.py .

ENV PYTHONUNBUFFERED=1 PORT=8500
EXPOSE 8500

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS http://localhost:8500/health || exit 1

CMD ["uvicorn", "src.mcp_hub.api:app", "--host", "0.0.0.0", "--port", "8500"]
