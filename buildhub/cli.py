from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Sequence

from .doctor import run_doctor
from .execution import choose_execution_backend
from .io import atomic_write_json, sha256_file
from .package import create_package, verify_package
from .payload import validate_payload
from .receipt import CommitOutcomeUnknown, publish_verified, reconcile_publication
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

    recon = sub.add_parser("reconcile-publish", help="Classify interrupted publication without replay")
    recon.add_argument("source")
    recon.add_argument("destination")
    recon.add_argument("--receipt", required=True)
    recon.add_argument("--operation-id", required=True)

    r = sub.add_parser("recover-status", help="Read recovery journal")
    r.add_argument("journal")

    run = sub.add_parser("run", help="Run one supervised process without shell argument re-parsing")
    run.add_argument("--log", required=True)
    run.add_argument("--heartbeat", required=True)
    run.add_argument("--timeout", type=float)
    run.add_argument("--operation-id")
    run.add_argument("argv", nargs=argparse.REMAINDER)

    payload = sub.add_parser("validate-payload", help="Verify payload files, hashes, and required modules")
    payload.add_argument("manifest")

    package = sub.add_parser("package", help="Create a deterministic BuildHub package")
    package.add_argument("--root", default=".")
    package.add_argument("--output", required=True)
    package.add_argument("files", nargs="+")

    verify = sub.add_parser("verify-package", help="Verify a BuildHub package manifest and hashes")
    verify.add_argument("package")

    plan = sub.add_parser("plan", help="Select remote or local execution without making CI authoritative")
    plan.add_argument("--remote-status", required=True)
    plan.add_argument("--local-unavailable", action="store_true")
    plan.add_argument("--prefer-local", action="store_true")

    return p


def _print(value: object) -> None:
    print(json.dumps(value, ensure_ascii=False, sort_keys=True))


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
        _print(result)
        return 0

    if args.command == "hash":
        _print([{"path": str(Path(p)), "sha256": sha256_file(p)} for p in args.paths])
        return 0

    if args.command == "publish":
        try:
            _print(publish_verified(
                args.source, args.destination, args.receipt, operation_id=args.operation_id
            ))
            return 0
        except CommitOutcomeUnknown as exc:
            _print({
                "status": "COMMIT_OUTCOME_UNKNOWN",
                "operation_id": args.operation_id,
                "error": str(exc),
            })
            return 3

    if args.command == "reconcile-publish":
        state = reconcile_publication(
            args.source,
            args.destination,
            args.receipt,
            operation_id=args.operation_id,
        )
        _print(state)
        return 0 if state["status"] == "COMMITTED" else 3

    if args.command == "recover-status":
        _print(RecoveryJournal(args.journal).status())
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
        _print(result)
        return 0 if result["classification"] == "SUCCESS" else 1

    if args.command == "validate-payload":
        _print(validate_payload(args.manifest))
        return 0

    if args.command == "package":
        _print(create_package(args.root, args.output, args.files))
        return 0

    if args.command == "verify-package":
        _print(verify_package(args.package))
        return 0

    if args.command == "plan":
        plan = choose_execution_backend(
            remote_status=args.remote_status,
            local_available=not args.local_unavailable,
            prefer_remote=not args.prefer_local,
        )
        _print({
            "backend": plan.backend,
            "reason": plan.reason,
            "local_state_authoritative": plan.local_state_authoritative,
        })
        return 0

    return 2


if __name__ == "__main__":
    raise SystemExit(main())
