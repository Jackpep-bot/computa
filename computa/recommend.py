"""Turn a Snapshot into prioritized, plain-English recommendations.

Pure logic (no I/O) so it is easy to unit-test.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import List

from .system import Snapshot
from .util import human_bytes, human_duration

CRITICAL = "critical"
WARNING = "warning"
INFO = "info"

_ORDER = {CRITICAL: 0, WARNING: 1, INFO: 2}

# Tunable thresholds
DISK_CRIT = 92.0
DISK_WARN = 80.0
MEM_CRIT = 90.0
MEM_WARN = 80.0
SWAP_WARN = 40.0
TEMP_WARN_BYTES = 2 * 1024 ** 3       # 2 GB
TEMP_INFO_BYTES = 512 * 1024 ** 2     # 512 MB
PROC_MEM_WARN = 25.0                   # single process using >25% RAM
UPTIME_INFO_DAYS = 7
# Ignore tiny filesystems (pseudo/mount artifacts, read-only system images).
# A "100% full" 768 KB mount is noise, not a real storage problem.
DISK_MIN_TOTAL = 4 * 1024 ** 3         # 4 GB


@dataclass
class Recommendation:
    severity: str
    title: str
    detail: str
    action: str = ""


def analyze(snap: Snapshot) -> List[Recommendation]:
    recs: List[Recommendation] = []

    # --- Disks ---
    for d in snap.disks:
        if d.total < DISK_MIN_TOTAL:
            continue  # skip tiny pseudo/read-only mounts
        if d.percent >= DISK_CRIT:
            recs.append(Recommendation(
                CRITICAL,
                f"Disk {d.mount} is almost full ({d.percent:.0f}%)",
                f"{human_bytes(d.free)} free of {human_bytes(d.total)}. "
                "A nearly-full disk slows everything and can stop apps from saving.",
                "Free space: run `computa clean`, empty the trash, and remove "
                "large unused files.",
            ))
        elif d.percent >= DISK_WARN:
            recs.append(Recommendation(
                WARNING,
                f"Disk {d.mount} is getting full ({d.percent:.0f}%)",
                f"{human_bytes(d.free)} free of {human_bytes(d.total)}.",
                "Consider clearing caches with `computa clean` before it fills up.",
            ))

    # --- Memory ---
    if snap.mem_percent is not None:
        if snap.mem_percent >= MEM_CRIT:
            recs.append(Recommendation(
                CRITICAL,
                f"Memory is nearly exhausted ({snap.mem_percent:.0f}% used)",
                f"{human_bytes(snap.mem_used)} of {human_bytes(snap.mem_total)} in use. "
                "The system is likely swapping, which makes everything sluggish.",
                "Close memory-heavy apps (see `computa top`) or add more RAM.",
            ))
        elif snap.mem_percent >= MEM_WARN:
            recs.append(Recommendation(
                WARNING,
                f"Memory usage is high ({snap.mem_percent:.0f}%)",
                f"{human_bytes(snap.mem_used)} of {human_bytes(snap.mem_total)} in use.",
                "Close apps you are not using; check `computa top` for the biggest.",
            ))

    # --- Swap ---
    if snap.swap_percent is not None and snap.swap_total and snap.swap_percent >= SWAP_WARN:
        recs.append(Recommendation(
            WARNING,
            f"Heavy swap usage ({snap.swap_percent:.0f}%)",
            f"{human_bytes(snap.swap_used)} of swap in use means RAM is overcommitted. "
            "Swapping to disk is much slower than real memory.",
            "Free up RAM by closing apps, or add physical memory.",
        ))

    # --- CPU load (unix load average vs core count) ---
    if snap.load_avg and snap.cpu_count:
        one_min = snap.load_avg[0]
        if one_min > snap.cpu_count * 1.5:
            recs.append(Recommendation(
                WARNING,
                f"CPU is overloaded (load {one_min:.1f} on {snap.cpu_count} cores)",
                "Sustained load well above your core count means processes are "
                "waiting for CPU time.",
                "Check `computa top` for runaway processes you can stop.",
            ))

    # --- Per-process memory hogs ---
    for p in snap.top_mem[:3]:
        if p.mem_percent >= PROC_MEM_WARN:
            recs.append(Recommendation(
                INFO,
                f"'{p.name}' is using a lot of memory ({p.mem_percent:.0f}% / "
                f"{human_bytes(p.mem_bytes)})",
                "A single process holding a large share of RAM can starve others.",
                f"If you are not actively using it, consider closing PID {p.pid}.",
            ))

    # --- Temp / cache bloat ---
    total_temp = sum(t.size for t in snap.temp_dirs)
    if total_temp >= TEMP_WARN_BYTES:
        recs.append(Recommendation(
            WARNING,
            f"Caches and temp files are large ({human_bytes(total_temp)})",
            "Old cache and temporary files accumulate over time and waste disk space.",
            "Reclaim space safely with `computa clean` (preview first, it is dry-run "
            "by default).",
        ))
    elif total_temp >= TEMP_INFO_BYTES:
        recs.append(Recommendation(
            INFO,
            f"Some reclaimable cache/temp space ({human_bytes(total_temp)})",
            "Clearing these is safe and can free disk space.",
            "Run `computa clean` to preview what can be removed.",
        ))

    # --- Uptime ---
    if snap.uptime_seconds and snap.uptime_seconds > UPTIME_INFO_DAYS * 86400:
        recs.append(Recommendation(
            INFO,
            f"Long uptime ({human_duration(snap.uptime_seconds)})",
            "Many small slowdowns (memory fragmentation, leaked handles, pending "
            "updates) clear up with a restart.",
            "Save your work and reboot when convenient.",
        ))

    if not snap.have_psutil:
        recs.append(Recommendation(
            INFO,
            "Install 'psutil' for a deeper scan",
            "Without psutil, computa cannot see live CPU/memory or per-process "
            "detail, so some checks are skipped.",
            "Run: pip install psutil",
        ))

    recs.sort(key=lambda r: _ORDER.get(r.severity, 99))
    return recs
