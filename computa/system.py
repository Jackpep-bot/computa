"""Collect a snapshot of system health.

Everything degrades gracefully: with ``psutil`` installed you get live CPU,
memory, swap, boot time and per-process detail; without it you still get
platform info, disk usage (via ``shutil``) and temp-directory sizing.
"""
from __future__ import annotations

import os
import platform
import shutil
import tempfile
import time
from dataclasses import dataclass, field
from typing import List, Optional

from . import util
from .startup import StartupItem, collect_startup
from .util import HAVE_PSUTIL, psutil


@dataclass
class DiskInfo:
    mount: str
    total: int
    used: int
    free: int

    @property
    def percent(self) -> float:
        return (self.used / self.total * 100.0) if self.total else 0.0


@dataclass
class ProcInfo:
    pid: int
    name: str
    cpu_percent: float
    mem_bytes: int
    mem_percent: float


@dataclass
class TempInfo:
    path: str
    size: int
    files: int


@dataclass
class Snapshot:
    system: str = ""
    release: str = ""
    machine: str = ""
    python: str = ""
    have_psutil: bool = HAVE_PSUTIL
    cpu_count: int = 0
    cpu_percent: Optional[float] = None
    load_avg: Optional[tuple] = None
    uptime_seconds: Optional[float] = None
    mem_total: Optional[int] = None
    mem_used: Optional[int] = None
    mem_percent: Optional[float] = None
    swap_total: Optional[int] = None
    swap_used: Optional[int] = None
    swap_percent: Optional[float] = None
    disks: List[DiskInfo] = field(default_factory=list)
    top_cpu: List[ProcInfo] = field(default_factory=list)
    top_mem: List[ProcInfo] = field(default_factory=list)
    temp_dirs: List[TempInfo] = field(default_factory=list)
    startup: List[StartupItem] = field(default_factory=list)


def _disk_partitions() -> List[str]:
    mounts: List[str] = []
    if HAVE_PSUTIL:
        try:
            for p in psutil.disk_partitions(all=False):
                mounts.append(p.mountpoint)
        except Exception:
            pass
    if not mounts:
        # stdlib fallback: just the root / current drive
        mounts.append(os.path.abspath(os.sep))
        cwd_anchor = os.path.splitdrive(os.path.abspath("."))[0] or os.sep
        if cwd_anchor not in mounts:
            mounts.append(cwd_anchor)
    # de-dup while preserving order
    seen = set()
    out = []
    for m in mounts:
        if m and m not in seen:
            seen.add(m)
            out.append(m)
    return out


def _collect_disks() -> List[DiskInfo]:
    disks: List[DiskInfo] = []
    for mount in _disk_partitions():
        try:
            usage = shutil.disk_usage(mount)
        except (OSError, PermissionError):
            continue
        disks.append(DiskInfo(mount=mount, total=usage.total,
                              used=usage.used, free=usage.free))
    return disks


def _collect_processes(limit: int = 5):
    """Return (top_by_cpu, top_by_mem). Empty lists without psutil."""
    if not HAVE_PSUTIL:
        return [], []
    procs = []
    # Prime cpu_percent (first call returns 0.0 for each process).
    for p in psutil.process_iter(["pid", "name"]):
        try:
            p.cpu_percent(None)
        except Exception:
            continue
    time.sleep(0.4)
    cpu_cores = psutil.cpu_count() or 1
    for p in psutil.process_iter(["pid", "name", "memory_info", "memory_percent"]):
        try:
            info = p.info
            mem = info.get("memory_info")
            mem_bytes = int(mem.rss) if mem else 0
            # normalize cpu by core count so it maps to 0-100 of the whole machine
            cpu = p.cpu_percent(None) / cpu_cores
            procs.append(ProcInfo(
                pid=info.get("pid", 0),
                name=(info.get("name") or "?")[:40],
                cpu_percent=cpu,
                mem_bytes=mem_bytes,
                mem_percent=float(info.get("memory_percent") or 0.0),
            ))
        except Exception:
            continue
    top_cpu = sorted(procs, key=lambda x: x.cpu_percent, reverse=True)[:limit]
    top_mem = sorted(procs, key=lambda x: x.mem_bytes, reverse=True)[:limit]
    return top_cpu, top_mem


def _dir_size(path: str, max_entries: int = 200000):
    """Return (total_bytes, file_count) for a directory tree, robust to errors."""
    total = 0
    count = 0
    try:
        for root, _dirs, files in os.walk(path, onerror=lambda e: None):
            for name in files:
                fp = os.path.join(root, name)
                try:
                    st = os.lstat(fp)
                    total += st.st_size
                    count += 1
                except (OSError, PermissionError):
                    continue
                if count >= max_entries:
                    return total, count
    except (OSError, PermissionError):
        pass
    return total, count


def _temp_candidates() -> List[str]:
    """OS-appropriate temp / cache directories that are safe to *measure*."""
    paths: List[str] = []
    home = os.path.expanduser("~")
    sysname = platform.system()

    paths.append(tempfile.gettempdir())
    for env in ("TEMP", "TMP", "TMPDIR"):
        v = os.environ.get(env)
        if v:
            paths.append(v)

    if sysname == "Windows":
        local = os.environ.get("LOCALAPPDATA")
        if local:
            paths.append(os.path.join(local, "Temp"))
        win = os.environ.get("SystemRoot", r"C:\Windows")
        paths.append(os.path.join(win, "Temp"))
    elif sysname == "Darwin":
        paths.append(os.path.join(home, "Library", "Caches"))
    else:  # Linux / other unix
        xdg = os.environ.get("XDG_CACHE_HOME") or os.path.join(home, ".cache")
        paths.append(xdg)

    # de-dup, keep only existing dirs
    seen = set()
    out = []
    for p in paths:
        ap = os.path.abspath(os.path.expanduser(p))
        if ap not in seen and os.path.isdir(ap):
            seen.add(ap)
            out.append(ap)
    return out


def _collect_temp() -> List[TempInfo]:
    out = []
    for path in _temp_candidates():
        size, files = _dir_size(path)
        out.append(TempInfo(path=path, size=size, files=files))
    return out


def collect(processes: bool = True) -> Snapshot:
    """Gather a full system snapshot."""
    snap = Snapshot()
    snap.system = platform.system()
    snap.release = platform.release()
    snap.machine = platform.machine()
    snap.python = platform.python_version()
    snap.cpu_count = os.cpu_count() or 0

    try:
        snap.load_avg = os.getloadavg()  # not on Windows
    except (OSError, AttributeError):
        snap.load_avg = None

    if HAVE_PSUTIL:
        try:
            snap.cpu_percent = psutil.cpu_percent(interval=0.3)
            snap.cpu_count = psutil.cpu_count() or snap.cpu_count
            vm = psutil.virtual_memory()
            snap.mem_total, snap.mem_used, snap.mem_percent = vm.total, vm.used, vm.percent
            sm = psutil.swap_memory()
            snap.swap_total, snap.swap_used, snap.swap_percent = sm.total, sm.used, sm.percent
            snap.uptime_seconds = time.time() - psutil.boot_time()
        except Exception:
            pass

    snap.disks = _collect_disks()
    if processes:
        snap.top_cpu, snap.top_mem = _collect_processes()
    snap.temp_dirs = _collect_temp()
    snap.startup = collect_startup()
    return snap
