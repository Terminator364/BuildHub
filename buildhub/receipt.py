from __future__ import annotations

import os
import shutil
import tempfile
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .io import atomic_write_json, read_json, sha256_file

RECEIPT_SCHEMA = "buildhub.receipt/v1"


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def publish_verified(
    source: str | os.PathLike[str],
    destination: str | os.PathLike[str],
    receipt_path: str | os.PathLike[str],
    *,
    operation_id: str | None = None,
) -> dict[str, Any]:
    src = Path(source)
    dst = Path(destination)
    if not src.is_file():
        raise FileNotFoundError(src)

    operation_id = operation_id or str(uuid.uuid4())
    source_hash = sha256_file(src)
    dst.parent.mkdir(parents=True, exist_ok=True)

    fd, tmp_name = tempfile.mkstemp(prefix=dst.name + ".", suffix=".partial", dir=str(dst.parent))
    os.close(fd)
    tmp = Path(tmp_name)
    try:
        shutil.copyfile(src, tmp)
        if sha256_file(tmp) != source_hash:
            raise IOError("staging hash mismatch")
        os.replace(tmp, dst)
        readback_hash = sha256_file(dst)
        if readback_hash != source_hash:
            raise IOError("post-publication readback hash mismatch")

        receipt = {
            "schema": RECEIPT_SCHEMA,
            "operation_id": operation_id,
            "status": "COMMITTED",
            "source_sha256": source_hash,
            "published_sha256": readback_hash,
            "readback_verified": True,
            "committed_at": utc_now(),
        }
        atomic_write_json(receipt_path, receipt)
        check = read_json(receipt_path)
        if check.get("status") != "COMMITTED" or check.get("published_sha256") != source_hash:
            raise IOError("receipt readback verification failed")
        return receipt
    finally:
        tmp.unlink(missing_ok=True)
