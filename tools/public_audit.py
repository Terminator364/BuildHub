from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
SKIP_DIRS = {".git", ".venv", "venv", "__pycache__", "build", "dist"}
FORBIDDEN_NAMES = {".env", "local.properties"}
FORBIDDEN_SUFFIXES = {
    ".keystore", ".jks", ".p12", ".pfx", ".pem", ".key",
    ".apk", ".aab", ".exe", ".msi"
}
TEXT_SCAN_LIMIT = 2_000_000

# Construct high-confidence signatures without embedding a usable credential example.
PRIVATE_KEY_MARKERS = (
    "-----BEGIN " + "PRIVATE KEY-----",
    "-----BEGIN " + "RSA PRIVATE KEY-----",
    "-----BEGIN " + "EC PRIVATE KEY-----",
    "-----BEGIN " + "OPENSSH PRIVATE KEY-----",
)
TOKEN_PATTERNS = (
    ("github-token", re.compile(r"gh" + r"[pousr]_[A-Za-z0-9_]{30,}")),
    ("aws-access-key", re.compile(r"AK" + r"IA[0-9A-Z]{16}")),
    ("google-api-key", re.compile(r"AI" + r"za[0-9A-Za-z_-]{30,}")),
)

violations: list[str] = []
for path in ROOT.rglob("*"):
    if not path.is_file():
        continue
    if any(part in SKIP_DIRS for part in path.parts):
        continue

    rel = str(path.relative_to(ROOT))
    if path.name in FORBIDDEN_NAMES or path.suffix.lower() in FORBIDDEN_SUFFIXES:
        violations.append(f"{rel}: forbidden public artifact")
        continue

    try:
        if path.stat().st_size > TEXT_SCAN_LIMIT:
            continue
        raw = path.read_bytes()
        if b"\x00" in raw:
            continue
        text = raw.decode("utf-8", errors="ignore")
    except OSError:
        continue

    for marker in PRIVATE_KEY_MARKERS:
        if marker in text:
            violations.append(f"{rel}: private-key marker")
            break

    for name, pattern in TOKEN_PATTERNS:
        if pattern.search(text):
            violations.append(f"{rel}: {name}")

if violations:
    for item in sorted(set(violations)):
        print(f"PUBLIC_BOUNDARY_FAIL {item}")
    raise SystemExit(1)

print("PUBLIC_BOUNDARY_PASS")
