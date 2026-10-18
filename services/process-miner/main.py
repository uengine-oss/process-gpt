"""process-miner 진입점. 실행: ./.venv/bin/python main.py (기본 :8014)"""
import os
import uvicorn

if __name__ == "__main__":
    uvicorn.run(
        "app.server:app",
        host=os.environ.get("HOST", "127.0.0.1"),
        port=int(os.environ.get("PORT", "8014")),
        log_level="info",
    )
