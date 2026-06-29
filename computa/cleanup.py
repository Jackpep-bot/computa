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


@dataclass
class CleanCandidate:
    path: str
    size: int
    age_days: float


@dataclass
class CleanResult:
    candidates: List[CleanCandidate]
    reclaimable: int
    removed: int          # bytes actually removed (0 in dry-run)
    removed_files: int
    errors: int
    applied: bool


def find_candidates(min_age_days: float = 7.0,
                    max_entries: int = 200000) -> List[CleanCandidate]:
    """Find old files in known cache/temp dirs that are safe to remove."""
    now = time.time()
    cutoff = now - min_age_days * 86400
    out: List[CleanCandidate] = []
    seen = 0
    for base in _temp_candidates():
        for root, _dirs, files in os.walk(base, onerror=lambda e: None):
            for name in files:
                fp = os.path.join(root, name)
                try:
                    st = os.lstat(fp)
                except (OSError, PermissionError):
                    continue
                # skip symlinks; only count regular files
                if not os.path.isfile(fp) or os.path.islink(fp):
                    continue
                mtime = st.st_mtime
                if mtime > cutoff:
                    continue
                age_days = (now - mtime) / 86400.0
                out.append(CleanCandidate(path=fp, size=st.st_size, age_days=age_days))
                seen += 1
                if seen >= max_entries:
                    return out
    return out


def clean(min_age_days: float = 7.0, apply: bool = False) -> CleanResult:
    """Preview (default) or apply cleanup of old cache/temp files."""
    candidates = find_candidates(min_age_days=min_age_days)
    reclaimable = sum(c.size for c in candidates)
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
    )
