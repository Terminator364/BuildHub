from __future__ import annotations

from dataclasses import dataclass


REMOTE_UNAVAILABLE = {"UNAVAILABLE", "QUOTA_EXHAUSTED", "DISABLED", "ERROR"}


@dataclass(frozen=True)
class ExecutionPlan:
    backend: str
    reason: str
    local_state_authoritative: bool = True


def choose_execution_backend(
    *,
    remote_status: str,
    local_available: bool = True,
    prefer_remote: bool = True,
) -> ExecutionPlan:
    status = remote_status.upper()
    if prefer_remote and status == "AVAILABLE":
        return ExecutionPlan("REMOTE", "public CI available")
    if local_available and status in REMOTE_UNAVAILABLE:
        return ExecutionPlan("LOCAL", f"remote {status.lower()}; local fallback")
    if local_available and not prefer_remote:
        return ExecutionPlan("LOCAL", "local execution preferred")
    if status == "AVAILABLE":
        return ExecutionPlan("REMOTE", "local unavailable")
    raise RuntimeError("no executable backend available")
