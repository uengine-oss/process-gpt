"""
Deterministic firebase_admin patch for E2E.

- Adds /usr/src/app to sys.path so the real fcm_service modules import.
- Monkey-patches `firebase_admin.messaging.send` to capture outgoing
  messages to /captures/fcm-messages.jsonl (no contact with Google FCM).
- Marks `database.firebase_app` as a truthy sentinel so the real
  `send_fcm_message` skips the credential-loading block.
- Then exec()s the real /usr/src/app/main.py as __main__.
"""
from __future__ import annotations

import json
import os
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path


CAPTURE_PATH = Path(os.environ.get("FCM_CAPTURE_PATH", "/captures/fcm-messages.jsonl"))


def _serialize_message(message) -> dict:
    payload: dict = {"token": getattr(message, "token", None)}

    notif = getattr(message, "notification", None)
    if notif is not None:
        payload["notification"] = {
            "title": getattr(notif, "title", None),
            "body": getattr(notif, "body", None),
        }

    data = getattr(message, "data", None)
    if data is not None:
        payload["data"] = dict(data)

    android = getattr(message, "android", None)
    if android is not None:
        payload["android"] = {"priority": getattr(android, "priority", None)}

    payload["captured_at"] = datetime.now(timezone.utc).isoformat()
    return payload


def _fake_send(message, *args, **kwargs):
    record = _serialize_message(message)
    CAPTURE_PATH.parent.mkdir(parents=True, exist_ok=True)
    with CAPTURE_PATH.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(record, ensure_ascii=False) + "\n")
    print(f"[firebase_patch] captured fcm message token={record.get('token')!r}", flush=True)
    return f"projects/e2e/messages/{uuid.uuid4()}"


def apply_patch() -> None:
    # Patch the messaging.send symbol used by database.send_fcm_message.
    from firebase_admin import messaging  # noqa: WPS433
    messaging.send = _fake_send  # type: ignore[assignment]

    # Mark database.firebase_app truthy so the real send_fcm_message
    # bypasses its credential-loading block. (database.py was already
    # imported by the moment fcm_service is imported.)
    import database  # type: ignore  # noqa: WPS433
    database.firebase_app = object()
    print(
        f"[firebase_patch] messaging.send patched, "
        f"database.firebase_app stubbed, capture path={CAPTURE_PATH}",
        flush=True,
    )


def main() -> None:
    app_dir = "/usr/src/app"
    if app_dir not in sys.path:
        sys.path.insert(0, app_dir)
    os.chdir(app_dir)

    # Pre-import database to get the module loaded so we can stub its
    # module-global `firebase_app` before send_fcm_message is ever called.
    import database  # noqa: F401

    apply_patch()

    sys.argv = ["main.py"]
    main_path = Path("/usr/src/app/main.py")
    code = compile(main_path.read_text(encoding="utf-8"), str(main_path), "exec")
    exec(code, {"__name__": "__main__", "__file__": str(main_path)})


if __name__ == "__main__":
    main()
