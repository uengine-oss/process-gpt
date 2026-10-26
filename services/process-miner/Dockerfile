# process-miner — 인계 기록(handover_events)에서 반복 흐름을 찾아 제안하는 서비스 (:8014)
# Process GPT Lite 설치 번들(install/docker-compose.yml 의 mining 프로필)이 이 파일로 빌드한다.
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app ./app
COPY main.py .
ENV HOST=0.0.0.0 PORT=8014 PYTHONUNBUFFERED=1
EXPOSE 8014
HEALTHCHECK --interval=10s --timeout=5s --retries=30 CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8014/health', timeout=4).status == 200 else 1)"
CMD ["python", "main.py"]
