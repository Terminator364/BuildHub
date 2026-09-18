from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Sequence

from .doctor import run_doctor
from .io import atomic_write_json, sha256_file
from .receipt import publish_verified
from .recovery import RecoveryJournal
from .runner import run_process


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="buildhub", description="BuildHub generic public core")
    sub = p.add_subparsers(dest="command")

    d = sub.add_parser("doctor", help="Inspect local build prerequisites")
    d.add_argument("--json", dest="json_path")

    h = sub.add_parser("hash", help="SHA-256 one or more files")
    h.add_argument("paths", nargs="+")

    pub = sub.add_parser("publish", help="Atomically publish with SHA-256/readback evidence")
    pub.add_argument("source")
    pub.add_argument("destination")
    pub.add_argument("--receipt", required=True)
    pub.add_argument("--operation-id")

    r = sub.add_parser("recover-status", help="Read recovery journal")
    r.add_argument("journal")

    run = sub.add_parser("run", help="Run one supervised process without shell argument re-parsing")
    run.add_argument("--log", required=True)
    run.add_argument("--heartbeat", required=True)
    run.add_argument("--timeout", type=float)
    run.add_argument("--operation-id")
    run.add_argument("argv", nargs=argparse.REMAINDER)

    return p


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not args.command:
        parser.print_help()
        return 0

    if args.command == "doctor":
        result = run_doctor()
        if args.json_path:
            atomic_write_json(args.json_path, result)
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
        return 0

    if args.command == "hash":
        print(json.dumps(
            [{"path": str(Path(p)), "sha256": sha256_file(p)} for p in args.paths],
            ensure_ascii=False,
            sort_keys=True,
        ))
        return 0

    if args.command == "publish":
        result = publish_verified(
            args.source,
            args.destination,
            args.receipt,
            operation_id=args.operation_id,
        )
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
        return 0

    if args.command == "recover-status":
        print(json.dumps(RecoveryJournal(args.journal).status(), ensure_ascii=False, sort_keys=True))
        return 0

    if args.command == "run":
        command = list(args.argv)
        if command and command[0] == "--":
            command = command[1:]
        if not command:
            parser.error("run requires an executable after --")
        result = run_process(
            command,
            log_path=args.log,
            heartbeat_path=args.heartbeat,
            timeout_seconds=args.timeout,
            operation_id=args.operation_id,
        )
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
        return 0 if result["classification"] == "SUCCESS" else 1

    return 2


if __name__ == "__main__":
    raise SystemExit(main())
