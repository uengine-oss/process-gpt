# context-router (services/context-router): POST /chat/stream, /route, /decide on :8895.
# Built by .github/workflows/context-router.yml; settings come from the environment (.env.example).
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PORT=8895
WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY server.py .
COPY decide/ ./decide/
COPY router/ ./router/

RUN useradd --create-home --uid 10001 router
USER 10001

EXPOSE 8895
HEALTHCHECK --interval=30s --timeout=5s CMD python -c "import os,urllib.request; urllib.request.urlopen(f'http://127.0.0.1:{os.environ.get(\"PORT\",\"8895\")}/router/health', timeout=4)"
CMD ["python", "server.py"]
