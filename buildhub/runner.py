from __future__ import annotations

import os
import subprocess
import threading
import time
import uuid
from pathlib import Path
from typing import Sequence

from .heartbeat import write_heartbeat


WINDOWS_CONTROL_C_EXIT = 0xC000013A
WINDOWS_CONTROL_C_EXIT_SIGNED = -1073741510


def classify_returncode(returncode: int) -> str:
    if returncode == 0:
        return "SUCCESS"
    if returncode in (WINDOWS_CONTROL_C_EXIT, WINDOWS_CONTROL_C_EXIT_SIGNED):
        return "EXTERNAL_TERMINATION"
    return "FAILED"


def _terminate_tree(proc: subprocess.Popen[bytes]) -> None:
    if proc.poll() is not None:
        return
    if os.name == "nt":
        subprocess.run(
            ["taskkill", "/PID", str(proc.pid), "/T", "/F"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    else:
        try:
            os.killpg(proc.pid, 15)
        except ProcessLookupError:
            return


def run_process(
    argv: Sequence[str],
    *,
    cwd: str | os.PathLike[str] = ".",
    log_path: str | os.PathLike[str],
    heartbeat_path: str | os.PathLike[str],
    operation_id: str | None = None,
    timeout_seconds: float | None = None,
    heartbeat_seconds: float = 10.0,
) -> dict[str, object]:
    """Run exactly one supervised process.

    argv must be an argument vector, never a shell command string. This preserves
    0/1/N argument boundaries and paths containing spaces.
    """
    if not argv:
        raise ValueError("argv must contain at least one executable")

    operation_id = operation_id or str(uuid.uuid4())
    log = Path(log_path)
    log.parent.mkdir(parents=True, exist_ok=True)

    stop = threading.Event()
    started = time.monotonic()

    with log.open("wb") as stream:
        kwargs: dict[str, object] = {
            "cwd": str(Path(cwd)),
            "stdout": stream,
            "stderr": subprocess.STDOUT,
            "shell": False,
        }
        if os.name == "nt":
            kwargs["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
        else:
            kwargs["start_new_session"] = True

        proc = subprocess.Popen(list(argv), **kwargs)

        def beat() -> None:
            while not stop.wait(max(0.2, heartbeat_seconds)):
                write_heartbeat(
                    heartbeat_path,
                    state="RUNNING",
                    operation_id=operation_id,
                    detail=f"pid={proc.pid}",
                )

        write_heartbeat(
            heartbeat_path,
            state="RUNNING",
            operation_id=operation_id,
            detail=f"pid={proc.pid}",
        )
        thread = threading.Thread(target=beat, name="buildhub-heartbeat", daemon=True)
        thread.start()

        timed_out = False
        try:
            returncode = proc.wait(timeout=timeout_seconds)
        except subprocess.TimeoutExpired:
            timed_out = True
            _terminate_tree(proc)
            try:
                returncode = proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()
                returncode = proc.wait()
        finally:
            stop.set()
            thread.join(timeout=2)

    classification = "TIMEOUT" if timed_out else classify_returncode(returncode)
    write_heartbeat(
        heartbeat_path,
        state=classification,
        operation_id=operation_id,
        detail=f"returncode={returncode}",
    )
    return {
        "operation_id": operation_id,
        "argv": list(argv),
        "returncode": returncode,
        "classification": classification,
        "duration_seconds": round(time.monotonic() - started, 6),
        "log_path": str(log),
    }
