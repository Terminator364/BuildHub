from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
SKIP_DIRS = {".git", ".venv", "venv", "__pycache__", "build", "dist"}
FORBIDDEN_NAMES = {".env", "local.properties"}
FORBIDDEN_SUFFIXES = {
    ".keystore", ".jks", ".p12", ".pfx", ".pem", ".key",
    ".apk", ".aab", ".exe", ".msi"
}

violations: list[str] = []
for path in ROOT.rglob("*"):
    if not path.is_file():
        continue
    if any(part in SKIP_DIRS for part in path.parts):
        continue
    if path.name in FORBIDDEN_NAMES or path.suffix.lower() in FORBIDDEN_SUFFIXES:
        violations.append(str(path.relative_to(ROOT)))

if violations:
    for item in sorted(violations):
        print(f"PUBLIC_BOUNDARY_FAIL {item}")
    raise SystemExit(1)

print("PUBLIC_BOUNDARY_PASS")
