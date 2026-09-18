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


class CommitConflict(RuntimeError):
    pass


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _existing_commit(
    src: Path,
    dst: Path,
    receipt_path: Path,
    operation_id: str,
) -> dict[str, Any] | None:
    if not receipt_path.exists():
        return None
    existing = read_json(receipt_path)
    if existing.get("status") != "COMMITTED":
        return None

    current_source_hash = sha256_file(src)
    same_operation = existing.get("operation_id") == operation_id
    same_source = existing.get("source_sha256") == current_source_hash
    same_destination = (
        dst.is_file()
        and existing.get("published_sha256") == sha256_file(dst)
        and existing.get("readback_verified") is True
    )

    if same_operation and same_source and same_destination:
        return existing

    if same_operation:
        raise CommitConflict("operation_id already committed with different evidence")

    raise CommitConflict("receipt path already contains a committed operation")


def publish_verified(
    source: str | os.PathLike[str],
    destination: str | os.PathLike[str],
    receipt_path: str | os.PathLike[str],
    *,
    operation_id: str | None = None,
) -> dict[str, Any]:
    """Publish only when staging, destination readback and receipt readback verify.

    Replaying the same committed operation with identical source/destination
    evidence returns the existing receipt without rewriting the destination.
    Once COMMITTED, a receipt path is immutable and cannot be reused by another
    operation.
    """
    src = Path(source)
    dst = Path(destination)
    receipt_file = Path(receipt_path)
    if not src.is_file():
        raise FileNotFoundError(src)

    operation_id = operation_id or str(uuid.uuid4())
    previous = _existing_commit(src, dst, receipt_file, operation_id)
    if previous is not None:
        return previous

    source_hash = sha256_file(src)
    dst.parent.mkdir(parents=True, exist_ok=True)

    stage_fd, stage_name = tempfile.mkstemp(
        prefix=dst.name + ".", suffix=".partial", dir=str(dst.parent)
    )
    os.close(stage_fd)
    stage = Path(stage_name)

    backup: Path | None = None
    replaced = False
    try:
        shutil.copyfile(src, stage)
        if sha256_file(stage) != source_hash:
            raise IOError("staging hash mismatch")

        if dst.exists():
            backup_fd, backup_name = tempfile.mkstemp(
                prefix=dst.name + ".", suffix=".rollback", dir=str(dst.parent)
            )
            os.close(backup_fd)
            backup = Path(backup_name)
            shutil.copyfile(dst, backup)

        os.replace(stage, dst)
        replaced = True

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
        atomic_write_json(receipt_file, receipt)
        check = read_json(receipt_file)
        if (
            check.get("status") != "COMMITTED"
            or check.get("published_sha256") != source_hash
            or check.get("readback_verified") is not True
        ):
            raise IOError("receipt readback verification failed")

        if backup is not None:
            backup.unlink(missing_ok=True)
        return receipt
    except Exception:
        if replaced:
            if backup is not None and backup.exists():
                os.replace(backup, dst)
            else:
                dst.unlink(missing_ok=True)
        raise
    finally:
        stage.unlink(missing_ok=True)
        if backup is not None:
            backup.unlink(missing_ok=True)
