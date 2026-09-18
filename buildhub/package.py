from __future__ import annotations

import hashlib
import json
import zipfile
from pathlib import Path
from typing import Any, Iterable

from .io import sha256_file

_FIXED_ZIP_TIME = (1980, 1, 1, 0, 0, 0)


class PackageVerificationError(RuntimeError):
    pass


def _safe_relative(path: Path, root: Path) -> str:
    rel = path.resolve().relative_to(root.resolve())
    return rel.as_posix()


def create_package(
    root: str | Path,
    output_zip: str | Path,
    files: Iterable[str | Path],
) -> dict[str, Any]:
    root_path = Path(root)
    output = Path(output_zip)
    output.parent.mkdir(parents=True, exist_ok=True)

    entries: list[dict[str, Any]] = []
    resolved: list[tuple[str, Path]] = []
    for raw in files:
        target = root_path / Path(raw)
        if not target.is_file():
            raise FileNotFoundError(target)
        rel = _safe_relative(target, root_path)
        resolved.append((rel, target))
    resolved.sort(key=lambda pair: pair[0])

    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for rel, target in resolved:
            data = target.read_bytes()
            info = zipfile.ZipInfo(rel, _FIXED_ZIP_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            zf.writestr(info, data)
            entries.append({
                "path": rel,
                "sha256": hashlib.sha256(data).hexdigest(),
                "size": len(data),
            })

        manifest_bytes = (
            json.dumps(
                {"schema": "buildhub.package/v1", "files": entries},
                ensure_ascii=False,
                sort_keys=True,
                indent=2,
            ) + "\n"
        ).encode("utf-8")
        info = zipfile.ZipInfo("BUILDHUB_MANIFEST.json", _FIXED_ZIP_TIME)
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o644 << 16
        zf.writestr(info, manifest_bytes)

    return {
        "schema": "buildhub.package-result/v1",
        "package": str(output),
        "sha256": sha256_file(output),
        "files": entries,
    }


def verify_package(path: str | Path) -> dict[str, Any]:
    package = Path(path)
    with zipfile.ZipFile(package, "r") as zf:
        try:
            manifest = json.loads(zf.read("BUILDHUB_MANIFEST.json").decode("utf-8"))
        except (KeyError, json.JSONDecodeError, UnicodeDecodeError) as exc:
            raise PackageVerificationError("invalid or missing package manifest") from exc
        if manifest.get("schema") != "buildhub.package/v1":
            raise PackageVerificationError("unsupported package schema")
        for item in manifest.get("files", []):
            try:
                data = zf.read(item["path"])
            except KeyError as exc:
                raise PackageVerificationError(f"missing packaged file: {item.get('path')}") from exc
            if hashlib.sha256(data).hexdigest() != item.get("sha256"):
                raise PackageVerificationError(f"hash mismatch: {item.get('path')}")
            if len(data) != item.get("size"):
                raise PackageVerificationError(f"size mismatch: {item.get('path')}")

    return {
        "schema": "buildhub.package-verification/v1",
        "status": "PASS",
        "package_sha256": sha256_file(package),
        "file_count": len(manifest.get("files", [])),
    }
