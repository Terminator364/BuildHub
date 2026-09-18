from __future__ import annotations

import json
import sys
from pathlib import Path

path = Path(sys.argv[1] if len(sys.argv) > 1 else ".project-memory/ERROR_LEDGER.jsonl")
allowed = {"PLANNED", "EXECUTABLE", "CI_PROVEN", "FIELD_PROVEN"}
required = {"id", "mechanism", "invariant", "regression_status"}

seen: set[str] = set()
count = 0
for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
    if not raw.strip():
        continue
    item = json.loads(raw)
    missing = required - item.keys()
    if missing:
        raise SystemExit(f"ledger line {line_number}: missing {sorted(missing)}")
    if item["id"] in seen:
        raise SystemExit(f"ledger line {line_number}: duplicate id {item['id']}")
    if item["regression_status"] not in allowed:
        raise SystemExit(f"ledger line {line_number}: invalid status {item['regression_status']}")
    seen.add(item["id"])
    count += 1

if count == 0:
    raise SystemExit("ledger is empty")
print(f"LEDGER_PASS entries={count}")
