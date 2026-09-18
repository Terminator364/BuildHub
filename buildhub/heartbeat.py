from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .io import atomic_write_json


def write_heartbeat(
    path: str | Path,
    *,
    state: str,
    operation_id: str,
    detail: str = "",
) -> dict[str, Any]:
    payload = {
        "schema": "buildhub.heartbeat/v1",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "state": state,
        "operation_id": operation_id,
        "detail": detail,
    }
    atomic_write_json(path, payload)
    return payload
