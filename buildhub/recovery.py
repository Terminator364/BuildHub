from __future__ import annotations

from pathlib import Path
from typing import Any

from .io import atomic_write_json, read_json


class StaleRecoveryError(RuntimeError):
    pass


class RecoveryJournal:
    def __init__(self, path: str | Path):
        self.path = Path(path)

    def load(self) -> dict[str, Any]:
        if not self.path.exists():
            return {"schema": "buildhub.recovery/v1", "steps": {}}
        data = read_json(self.path)
        if data.get("schema") != "buildhub.recovery/v1":
            raise ValueError("unsupported recovery schema")
        data.setdefault("steps", {})
        return data

    def begin(self, step_id: str, payload_hash: str) -> dict[str, Any]:
        data = self.load()
        old = data["steps"].get(step_id)
        if old and old.get("status") == "COMMITTED":
            raise StaleRecoveryError(f"step already committed: {step_id}")
        data["steps"][step_id] = {"status": "STARTED", "payload_hash": payload_hash}
        atomic_write_json(self.path, data)
        return data["steps"][step_id]

    def commit(self, step_id: str, payload_hash: str, receipt_sha256: str) -> dict[str, Any]:
        data = self.load()
        old = data["steps"].get(step_id)
        if not old or old.get("status") != "STARTED":
            raise StaleRecoveryError(f"step not in STARTED state: {step_id}")
        if old.get("payload_hash") != payload_hash:
            raise StaleRecoveryError(f"payload changed during recovery step: {step_id}")
        data["steps"][step_id] = {
            "status": "COMMITTED",
            "payload_hash": payload_hash,
            "receipt_sha256": receipt_sha256,
        }
        atomic_write_json(self.path, data)
        return data["steps"][step_id]

    def status(self) -> dict[str, Any]:
        return self.load()
