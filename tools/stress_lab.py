from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

from buildhub.execution import choose_execution_backend
from buildhub.io import sha256_file
from buildhub.package import create_package, verify_package
from buildhub.payload import validate_payload
from buildhub.receipt import publish_verified
from buildhub.recovery import RecoveryJournal

REPORT = Path(sys.argv[1] if len(sys.argv) > 1 else "lab-report.json")
ITERATIONS = 100

with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    recovery = RecoveryJournal(root / "recovery.json")

    for index in range(ITERATIONS):
        src = root / f"source-{index}.bin"
        dst = root / f"published-{index}.bin"
        receipt = root / f"receipt-{index}.json"
        data = (f"buildhub-stress-{index}\n" * 8).encode("utf-8")
        src.write_bytes(data)

        operation_id = f"stress-{index}"
        first = publish_verified(src, dst, receipt, operation_id=operation_id)
        replay = publish_verified(src, dst, receipt, operation_id=operation_id)
        assert first == replay
        assert sha256_file(src) == sha256_file(dst)

        payload_hash = sha256_file(src)
        recovery.begin(operation_id, payload_hash)
        recovery.commit(operation_id, payload_hash, first["published_sha256"])

    sample = root / "sample.txt"
    sample.write_text("deterministic package\n", encoding="utf-8")
    first_zip = root / "one.zip"
    second_zip = root / "two.zip"
    first_pkg = create_package(root, first_zip, ["sample.txt"])
    second_pkg = create_package(root, second_zip, ["sample.txt"])
    assert first_pkg["sha256"] == second_pkg["sha256"]
    assert verify_package(first_zip)["status"] == "PASS"

    payload_file = root / "payload.bin"
    payload_file.write_bytes(b"payload")
    manifest = root / "payload.json"
    manifest.write_text(json.dumps({
        "schema": "buildhub.payload/v1",
        "files": [{"path": "payload.bin", "sha256": sha256_file(payload_file)}],
        "required_modules": ["json"],
    }), encoding="utf-8")
    assert validate_payload(manifest)["status"] == "PASS"

    for state in ("UNAVAILABLE", "QUOTA_EXHAUSTED", "DISABLED", "ERROR"):
        assert choose_execution_backend(remote_status=state).backend == "LOCAL"

report = {
    "schema": "buildhub.lab-report/v1",
    "status": "PASS",
    "iterations": ITERATIONS,
    "checks": [
        "verified-publication",
        "idempotent-replay",
        "recovery-journal",
        "deterministic-package",
        "package-readback",
        "payload-validation",
        "remote-unavailable-local-fallback"
    ]
}
REPORT.write_text(json.dumps(report, sort_keys=True, indent=2) + "\n", encoding="utf-8")
print(json.dumps(report, sort_keys=True))
