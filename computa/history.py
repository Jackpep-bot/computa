"""Persist scan snapshots and compute "what changed since last scan".

A baseline snapshot is stored as JSON under ~/.computa/. Both `scan` and `diff`
refresh it, so `diff` always compares against your most recent scan.
"""
from __future__ import annotations

import json
import os
import time
from dataclasses import dataclass, field
from typing import List, Optional

from . import serialize
from .system import Snapshot
from .util import human_bytes, human_duration


def state_dir() -> str:
    override = os.environ.get("COMPUTA_HOME")
    base = override if override else os.path.join(os.path.expanduser("~"), ".computa")
    return base


def _state_file() -> str:
    return os.path.join(state_dir(), "last_scan.json")


def save_snapshot(snap: Snapshot, now: Optional[float] = None) -> bool:
    """Write the snapshot as the new baseline. Returns False on failure."""
    payload = {
        "timestamp": now if now is not None else time.time(),
        "snapshot": serialize.snapshot_to_dict(snap),
    }
    try:
        os.makedirs(state_dir(), exist_ok=True)
        with open(_state_file(), "w") as fh:
            json.dump(payload, fh, indent=2, default=str)
        return True
    except OSError:
        return False


def load_last() -> Optional[dict]:
    """Load the previously saved baseline, or None if there isn't one."""
    try:
        with open(_state_file(), "r") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


@dataclass
class DiskDelta:
    mount: str
    free_old: int
    free_new: int
    percent_old: float
    percent_new: float

    @property
    def free_delta(self) -> int:
        return self.free_new - self.free_old


@dataclass
class Diff:
    elapsed_seconds: float
    mem_percent_old: Optional[float] = None
    mem_percent_new: Optional[float] = None
    temp_old: int = 0
    temp_new: int = 0
    disks: List[DiskDelta] = field(default_factory=list)
    startup_added: List[str] = field(default_factory=list)
    startup_removed: List[str] = field(default_factory=list)

    @property
    def temp_delta(self) -> int:
        return self.temp_new - self.temp_old


def compute_diff(previous: dict, current: Snapshot,
                 now: Optional[float] = None) -> Diff:
    old = previous.get("snapshot", {})
    new = serialize.snapshot_to_dict(current)
    now = now if now is not None else time.time()
    elapsed = max(0.0, now - float(previous.get("timestamp", now)))

    diff = Diff(elapsed_seconds=elapsed)
    diff.mem_percent_old = old.get("mem_percent")
    diff.mem_percent_new = new.get("mem_percent")

    diff.temp_old = sum(t.get("size", 0) for t in old.get("temp_dirs", []))
    diff.temp_new = sum(t.get("size", 0) for t in new.get("temp_dirs", []))

    old_disks = {d["mount"]: d for d in old.get("disks", [])}
    for d in new.get("disks", []):
        od = old_disks.get(d["mount"])
        if od is None:
            continue
        diff.disks.append(DiskDelta(
            mount=d["mount"],
            free_old=od.get("free", 0), free_new=d.get("free", 0),
            percent_old=od.get("percent", 0.0), percent_new=d.get("percent", 0.0),
        ))

    old_startup = {s["name"] for s in old.get("startup", [])}
    new_startup = {s["name"] for s in new.get("startup", [])}
    diff.startup_added = sorted(new_startup - old_startup)
    diff.startup_removed = sorted(old_startup - new_startup)
    return diff


def _signed_bytes(n: int) -> str:
    return ("+" if n >= 0 else "-") + human_bytes(abs(n))


def format_diff(diff: Diff) -> str:
    lines = [f"Changes since last scan ({human_duration(diff.elapsed_seconds)} ago):", ""]
    any_change = False

    # Disks
    for d in diff.disks:
        if abs(d.free_delta) < 1024 * 1024:  # ignore sub-MB jitter
            continue
        any_change = True
        arrow = "more free" if d.free_delta > 0 else "less free"
        lines.append(
            f"  Disk {d.mount}: {_signed_bytes(d.free_delta)} ({arrow}), "
            f"now {d.percent_new:.0f}% full (was {d.percent_old:.0f}%)")

    # Temp / cache
    if abs(diff.temp_delta) >= 1024 * 1024:
        any_change = True
        lines.append(f"  Cache/temp: {_signed_bytes(diff.temp_delta)} "
                     f"(now {human_bytes(diff.temp_new)})")

    # Memory
    if diff.mem_percent_old is not None and diff.mem_percent_new is not None:
        delta = diff.mem_percent_new - diff.mem_percent_old
        if abs(delta) >= 2.0:
            any_change = True
            sign = "+" if delta >= 0 else ""
            lines.append(f"  Memory use: {sign}{delta:.0f}% "
                         f"(now {diff.mem_percent_new:.0f}%)")

    # Startup
    if diff.startup_added:
        any_change = True
        lines.append(f"  New startup program(s): {', '.join(diff.startup_added)}")
    if diff.startup_removed:
        any_change = True
        lines.append(f"  Removed startup program(s): {', '.join(diff.startup_removed)}")

    if not any_change:
        lines.append("  No significant changes.")
    return "\n".join(lines)
