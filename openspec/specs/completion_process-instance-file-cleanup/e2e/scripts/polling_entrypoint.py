"""
PIFC E2E polling entrypoint.

The production polling worker (`services/completion/polling_service/main.py`)
starts a number of unrelated tasks (workitem polling, stale consumer cleanup,
file cleanup). For this E2E suite we want to exercise ONLY
`file_cleanup_polling_task` under coverage.py, with a short polling interval
so the test does not need to wait the production 5-minute cycle.

This entrypoint:
  1. Calls `setting_database()` from the production database module so the
     same supabase_client_var setup runs.
  2. Installs a signal handler for SIGTERM so coverage.py's
     `--save-signal=USR2` and its SIGTERM handling can flush before the
     container exits.
  3. Awaits `file_cleanup_polling_task(shutdown_event, polling_interval=PIFC_POLLING_INTERVAL)`.

It deliberately does NOT touch workitem polling or stale consumer cleanup —
those belong to other E2E suites.
"""

import asyncio
import os
import signal
import sys

# The container runs from /usr/src/app and the production polling_service
# package files are all flat in that directory. Add it to sys.path defensively.
sys.path.insert(0, '/usr/src/app')

from database import setting_database  # noqa: E402
from file_cleanup_service import file_cleanup_polling_task  # noqa: E402


async def main() -> None:
    setting_database()
    print("[pifc-entrypoint] database configured", flush=True)

    shutdown_event = asyncio.Event()
    loop = asyncio.get_running_loop()

    def _signal_handler(signame: str) -> None:
        print(f"[pifc-entrypoint] received {signame}, setting shutdown_event", flush=True)
        shutdown_event.set()

    for signame in ('SIGTERM', 'SIGINT'):
        try:
            loop.add_signal_handler(getattr(signal, signame),
                                    lambda n=signame: _signal_handler(n))
        except NotImplementedError:
            # Windows fallback (not used in container, but harmless)
            pass

    interval = int(os.getenv('PIFC_POLLING_INTERVAL', '3'))
    print(f"[pifc-entrypoint] starting file_cleanup_polling_task with interval={interval}s",
          flush=True)
    await file_cleanup_polling_task(shutdown_event, polling_interval=interval)
    print("[pifc-entrypoint] file_cleanup_polling_task exited", flush=True)


if __name__ == '__main__':
    asyncio.run(main())
