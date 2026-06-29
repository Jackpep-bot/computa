"""Safe reclamation of cache / temp space.

Design principles (safety first):
  * Only ever look inside known cache/temp directories (see system._temp_candidates).
  * Only consider files older than ``min_age_days`` (default 7) so we never touch
    something actively in use.
  * Dry-run by default — nothing is deleted unless the caller passes apply=True.
  * Per-file errors (permissions, file-in-use) are skipped, never fatal.
"""
from __future__ import annotations

import os
import time
from dataclasses import dataclass
from typing import List

from .system import _temp_candidates
from .walk import iter_files


@dataclass
class CleanCandidate:
    path: str
    size: int
    age_days: float


@dataclass
class AppUsage:
    name: str         # the app/category (top-level folder under a cache dir)
    size: int
    files: int


@dataclass
class CleanResult:
    candidates: List[CleanCandidate]
    reclaimable: int
    removed: int          # bytes actually removed (0 in dry-run)
    removed_files: int
    errors: int
    applied: bool
    breakdown: List[AppUsage] = None  # per-app reclaimable space


def find_candidates(min_age_days: float = 7.0,
                    max_entries: int = 200000,
                    deep: bool = False) -> List[CleanCandidate]:
    """Find old files in known cache/temp dirs that are safe to remove.

    ``deep=True`` widens the search to extra junk locations (browser caches,
    crash dumps, logs, trash). ``iter_files`` already skips symlinks and
    unreadable entries.
    """
    now = time.time()
    cutoff = now - min_age_days * 86400
    out: List[CleanCandidate] = []
    for base in _temp_candidates(deep=deep):
        for entry in iter_files(base, max_entries - len(out)):
            try:
                st = entry.stat(follow_symlinks=False)
            except (OSError, PermissionError):
                continue
            if st.st_mtime > cutoff:
                continue
            out.append(CleanCandidate(
                path=entry.path, size=st.st_size,
                age_days=(now - st.st_mtime) / 86400.0))
            if len(out) >= max_entries:
                return out
    return out


def breakdown_by_app(candidates: List[CleanCandidate],
                     bases: List[str] = None) -> List[AppUsage]:
    """Group reclaimable space by app/category.

    The "app" is the top-level folder beneath each cache/temp base directory
    (e.g. ``~/.cache/google-chrome`` -> "google-chrome"), which is how apps
    name their caches on every OS. Files sitting directly in a base dir are
    grouped as "(loose files)".
    """
    if bases is None:
        bases = _temp_candidates()
    # longest base first so nested bases match the most specific one
    bases_norm = sorted((os.path.abspath(b) for b in bases), key=len, reverse=True)

    groups = {}  # label -> [size, files]
    for c in candidates:
        path = os.path.abspath(c.path)
        label = "(other)"
        for b in bases_norm:
            if path == b or path.startswith(b + os.sep):
                rel = os.path.relpath(path, b)
                parts = rel.split(os.sep)
                label = parts[0] if len(parts) >= 2 else "(loose files)"
                break
        slot = groups.setdefault(label, [0, 0])
        slot[0] += c.size
        slot[1] += 1

    usage = [AppUsage(name=k, size=v[0], files=v[1]) for k, v in groups.items()]
    usage.sort(key=lambda a: a.size, reverse=True)
    return usage


def clean(min_age_days: float = 7.0, apply: bool = False,
          deep: bool = False) -> CleanResult:
    """Preview (default) or apply cleanup of old cache/temp files.

    ``deep=True`` performs a fuller sweep across browser caches, crash dumps,
    logs and trash in addition to the standard temp/cache locations.
    """
    candidates = find_candidates(min_age_days=min_age_days, deep=deep)
    reclaimable = sum(c.size for c in candidates)
    breakdown = breakdown_by_app(candidates, bases=_temp_candidates(deep=deep))
    removed = 0
    removed_files = 0
    errors = 0

    if apply:
        for c in candidates:
            try:
                os.remove(c.path)
                removed += c.size
                removed_files += 1
            except (OSError, PermissionError):
                errors += 1

    return CleanResult(
        candidates=candidates,
        reclaimable=reclaimable,
        removed=removed,
        removed_files=removed_files,
        errors=errors,
        applied=apply,
        breakdown=breakdown,
    )
