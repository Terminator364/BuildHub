from __future__ import annotations

import importlib.util
from pathlib import Path
from typing import Any

from .io import read_json, sha256_file


class PayloadValidationError(RuntimeError):
    pass


def validate_payload(manifest_path: str | Path) -> dict[str, Any]:
    manifest_file = Path(manifest_path)
    manifest = read_json(manifest_file)
    if manifest.get("schema") != "buildhub.payload/v1":
        raise PayloadValidationError("unsupported payload schema")

    base = manifest_file.parent
    files = manifest.get("files")
    if not isinstance(files, list) or not files:
        raise PayloadValidationError("payload must declare at least one file")

    verified: list[dict[str, Any]] = []
    for item in files:
        if not isinstance(item, dict) or not item.get("path") or not item.get("sha256"):
            raise PayloadValidationError("each payload file needs path and sha256")
        rel = Path(str(item["path"]))
        if rel.is_absolute() or ".." in rel.parts:
            raise PayloadValidationError(f"unsafe payload path: {rel}")
        target = base / rel
        if not target.is_file():
            raise PayloadValidationError(f"missing payload file: {rel}")
        actual = sha256_file(target)
        if actual != item["sha256"]:
            raise PayloadValidationError(f"payload hash mismatch: {rel}")
        verified.append({"path": str(rel), "sha256": actual})

    missing_modules = [
        name for name in manifest.get("required_modules", [])
        if importlib.util.find_spec(str(name)) is None
    ]
    if missing_modules:
        raise PayloadValidationError(
            "missing required modules: " + ", ".join(sorted(map(str, missing_modules)))
        )

    return {
        "schema": "buildhub.payload-validation/v1",
        "status": "PASS",
        "verified_files": verified,
        "required_modules": list(manifest.get("required_modules", [])),
    }
