from __future__ import annotations

import os
import platform
import shutil
from pathlib import Path
from typing import Any


def _total_memory_bytes() -> int | None:
    try:
        if os.name == "nt":
            import ctypes

            class MEMORYSTATUSEX(ctypes.Structure):
                _fields_ = [
                    ("dwLength", ctypes.c_ulong),
                    ("dwMemoryLoad", ctypes.c_ulong),
                    ("ullTotalPhys", ctypes.c_ulonglong),
                    ("ullAvailPhys", ctypes.c_ulonglong),
                    ("ullTotalPageFile", ctypes.c_ulonglong),
                    ("ullAvailPageFile", ctypes.c_ulonglong),
                    ("ullTotalVirtual", ctypes.c_ulonglong),
                    ("ullAvailVirtual", ctypes.c_ulonglong),
                    ("ullAvailExtendedVirtual", ctypes.c_ulonglong),
                ]

            s = MEMORYSTATUSEX()
            s.dwLength = ctypes.sizeof(s)
            if ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(s)):
                return int(s.ullTotalPhys)
        if hasattr(os, "sysconf"):
            pages = os.sysconf("SC_PHYS_PAGES")
            size = os.sysconf("SC_PAGE_SIZE")
            return int(pages * size)
    except (OSError, ValueError, AttributeError):
        return None
    return None


def run_doctor(workdir: str | os.PathLike[str] = ".") -> dict[str, Any]:
    root = Path(workdir).resolve()
    usage = shutil.disk_usage(root)
    found = {name: shutil.which(name) for name in ("git", "java", "javac", "gradle", "adb")}
    return {
        "schema": "buildhub.doctor/v1",
        "platform": platform.platform(),
        "python": platform.python_version(),
        "total_memory_bytes": _total_memory_bytes(),
        "disk_free_bytes": usage.free,
        "workdir": str(root),
        "tools": found,
        "policy": {
            "heavy_build_parallelism_default": 1,
            "cache_first": True,
            "offline_capable_target": True,
            "publication_requires_hash_readback": True,
        },
    }
