"""Terminal-friendly formatting of snapshots, recommendations and cleanup."""
from __future__ import annotations

import sys
from typing import List

from .recommend import CRITICAL, INFO, WARNING, Recommendation
from .system import Snapshot
from .util import human_bytes, human_duration, pct_bar

_USE_COLOR = sys.stdout.isatty() and not sys.platform.startswith("win")

_COLORS = {
    CRITICAL: "\033[91m",  # red
    WARNING: "\033[93m",   # yellow
    INFO: "\033[96m",      # cyan
    "head": "\033[1m",     # bold
    "dim": "\033[2m",
    "reset": "\033[0m",
}
_BADGE = {CRITICAL: "CRIT", WARNING: "WARN", INFO: "INFO"}


def _c(text: str, key: str) -> str:
    if not _USE_COLOR or key not in _COLORS:
        return text
    return f"{_COLORS[key]}{text}{_COLORS['reset']}"


def _head(text: str) -> str:
    return _c(text, "head")


def format_snapshot(snap: Snapshot) -> str:
    lines: List[str] = []
    lines.append(_head("System"))
    lines.append(f"  {snap.system} {snap.release} ({snap.machine}), "
                 f"Python {snap.python}")
    if snap.uptime_seconds is not None:
        lines.append(f"  Uptime: {human_duration(snap.uptime_seconds)}")
    if not snap.have_psutil:
        lines.append("  " + _c("(install psutil for live CPU/memory/process data)", "dim"))

    lines.append("")
    lines.append(_head("CPU"))
    cores = snap.cpu_count or "?"
    if snap.cpu_percent is not None:
        lines.append(f"  Usage: {pct_bar(snap.cpu_percent)}   cores: {cores}")
    else:
        lines.append(f"  cores: {cores}")
    if snap.load_avg:
        la = ", ".join(f"{x:.2f}" for x in snap.load_avg)
        lines.append(f"  Load average (1/5/15m): {la}")

    if snap.mem_total is not None:
        lines.append("")
        lines.append(_head("Memory"))
        lines.append(f"  RAM:  {pct_bar(snap.mem_percent or 0)}   "
                     f"{human_bytes(snap.mem_used)} / {human_bytes(snap.mem_total)}")
        if snap.swap_total:
            lines.append(f"  Swap: {pct_bar(snap.swap_percent or 0)}   "
                         f"{human_bytes(snap.swap_used)} / {human_bytes(snap.swap_total)}")

    lines.append("")
    lines.append(_head("Disks"))
    for d in snap.disks:
        lines.append(f"  {d.mount:<16} {pct_bar(d.percent)}   "
                     f"{human_bytes(d.free)} free / {human_bytes(d.total)}")

    if snap.top_mem:
        lines.append("")
        lines.append(_head("Top memory users"))
        for p in snap.top_mem:
            lines.append(f"  {human_bytes(p.mem_bytes):>9}  "
                         f"({p.mem_percent:4.1f}%)  {p.name}  [pid {p.pid}]")
    if snap.top_cpu and any(p.cpu_percent > 0.1 for p in snap.top_cpu):
        lines.append("")
        lines.append(_head("Top CPU users"))
        for p in snap.top_cpu:
            lines.append(f"  {p.cpu_percent:5.1f}%  {p.name}  [pid {p.pid}]")

    if snap.temp_dirs:
        total = sum(t.size for t in snap.temp_dirs)
        lines.append("")
        lines.append(_head(f"Cache / temp ({human_bytes(total)} total)"))
        for t in snap.temp_dirs:
            lines.append(f"  {human_bytes(t.size):>9}  ({t.files} files)  {t.path}")

    return "\n".join(lines)


def format_recommendations(recs: List[Recommendation]) -> str:
    if not recs:
        return _c("No problems found — your system looks healthy. ✔", INFO)
    lines = [_head(f"{len(recs)} recommendation(s):"), ""]
    for r in recs:
        badge = _c(f"[{_BADGE.get(r.severity, '?')}]", r.severity)
        lines.append(f"{badge} {r.title}")
        lines.append(f"       {r.detail}")
        if r.action:
            lines.append(f"       {_c('→ ' + r.action, 'dim')}")
        lines.append("")
    return "\n".join(lines).rstrip()


def format_clean(result, min_age_days: float) -> str:
    n = len(result.candidates)
    lines = []
    if result.applied:
        lines.append(_head("Cleanup complete"))
        lines.append(f"  Removed {result.removed_files} files, "
                     f"reclaimed {human_bytes(result.removed)}.")
        if result.errors:
            lines.append(f"  Skipped {result.errors} file(s) (in use or no permission).")
    else:
        lines.append(_head("Cleanup preview (dry-run — nothing deleted)"))
        lines.append(f"  {n} file(s) older than {min_age_days:g} days could be removed,")
        lines.append(f"  reclaiming about {human_bytes(result.reclaimable)}.")
        # show the biggest offenders
        biggest = sorted(result.candidates, key=lambda c: c.size, reverse=True)[:8]
        if biggest:
            lines.append("")
            lines.append("  Largest items:")
            for c in biggest:
                lines.append(f"    {human_bytes(c.size):>9}  "
                             f"({c.age_days:.0f}d old)  {c.path}")
        lines.append("")
        lines.append(_c("  Re-run with --yes to actually delete.", "dim"))
    return "\n".join(lines)
