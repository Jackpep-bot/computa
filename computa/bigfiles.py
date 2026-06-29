"""Find the largest files eating disk space, and delete them *safely*.

Deletion here is more powerful than ``clean`` (it can remove large files
anywhere the user can reach), so it is guarded hard:

  * ``is_protected`` blocks anything inside OS/system/program directories, so
    this can never delete Windows, Program Files, /usr, /System, etc.
  * The finder only returns non-protected files, and every delete re-checks
    ``is_protected`` and ``isfile`` at the moment of removal.
  * The CLI never deletes without an explicit typed confirmation.
"""
from __future__ import annotations

import heapq
import os
import platform
import time
from dataclasses import dataclass
from typing import List

from .walk import iter_files


@dataclass
class BigFile:
    path: str
    size: int
    age_days: float


def _protected_roots() -> List[str]:
    """Directories we must never offer to delete from."""
    sysname = platform.system()
    roots: List[str] = []
    if sysname == "Windows":
        drive = os.environ.get("SystemDrive", "C:") + os.sep
        roots += [
            os.environ.get("SystemRoot", r"C:\Windows"),
            os.environ.get("ProgramFiles", os.path.join(drive, "Program Files")),
            os.environ.get("ProgramFiles(x86)",
                           os.path.join(drive, "Program Files (x86)")),
            os.environ.get("ProgramW6432", ""),
            os.environ.get("ProgramData", os.path.join(drive, "ProgramData")),
        ]
    elif sysname == "Darwin":
        roots += ["/System", "/Library", "/Applications", "/usr", "/bin",
                  "/sbin", "/private", "/Network"]
    else:
        roots += ["/usr", "/bin", "/sbin", "/lib", "/lib64", "/etc", "/boot",
                  "/proc", "/sys", "/dev", "/run", "/var"]
    return [r for r in roots if r]


def is_protected(path: str) -> bool:
    """True if ``path`` is inside a system/program directory (never delete)."""
    try:
        ap = os.path.normcase(os.path.abspath(path))
    except (OSError, ValueError):
        return True
    for root in _protected_roots():
        r = os.path.normcase(os.path.abspath(root))
        if ap == r or ap.startswith(r + os.sep):
            return True
    return False


def find_large_files(root: str = None, top: int = 25,
                     min_size: int = 100 * 1024 ** 2,
                     max_entries: int = 500000) -> List[BigFile]:
    """Return the ``top`` largest deletable files under ``root``.

    ``root`` defaults to the user's home directory. Protected/system files are
    skipped so they're never listed as deletable.
    """
    if root is None:
        root = os.path.expanduser("~")
    now = time.time()
    heap = []  # min-heap of (size, path, mtime), keeps the top N largest
    for entry in iter_files(root, max_entries):
        try:
            st = entry.stat(follow_symlinks=False)
        except (OSError, PermissionError):
            continue
        if st.st_size < min_size:
            continue
        if is_protected(entry.path):
            continue
        item = (st.st_size, entry.path, st.st_mtime)
        if len(heap) < top:
            heapq.heappush(heap, item)
        elif item[0] > heap[0][0]:
            heapq.heapreplace(heap, item)
    heap.sort(reverse=True)
    return [BigFile(path=p, size=s, age_days=(now - m) / 86400.0)
            for s, p, m in heap]


def delete_files(paths: List[str]):
    """Delete the given files, skipping anything protected or missing.

    Returns (removed_count, freed_bytes, errors, skipped).
    """
    removed = freed = errors = skipped = 0
    for p in paths:
        if is_protected(p) or not os.path.isfile(p) or os.path.islink(p):
            skipped += 1
            continue
        try:
            size = os.path.getsize(p)
            os.remove(p)
            removed += 1
            freed += size
        except (OSError, PermissionError):
            errors += 1
    return removed, freed, errors, skipped


def empty_recycle_bin():
    """Empty the Recycle Bin / Trash. Returns (ok, message)."""
    sysname = platform.system()
    if sysname == "Windows":
        try:
            import ctypes
            # SHERB_NOCONFIRMATION | SHERB_NOPROGRESSUI | SHERB_NOSOUND
            flags = 0x01 | 0x02 | 0x04
            res = ctypes.windll.shell32.SHEmptyRecycleBinW(None, None, flags)
            # 0 = success, -2147418113 = already empty
            if res == 0:
                return True, "Recycle Bin emptied."
            if res in (-2147418113, 0x8000FFFF):
                return True, "Recycle Bin was already empty."
            return False, f"Could not empty Recycle Bin (code {res})."
        except Exception as exc:
            return False, f"Could not empty Recycle Bin: {exc}"
    else:
        # Linux/macOS: clear the user trash directories.
        home = os.path.expanduser("~")
        trash_dirs = [
            os.path.join(os.environ.get("XDG_DATA_HOME",
                                        os.path.join(home, ".local", "share")),
                         "Trash", "files"),
            os.path.join(home, ".Trash"),
        ]
        freed = 0
        removed = 0
        for d in trash_dirs:
            for entry in iter_files(d, 200000):
                try:
                    freed += entry.stat(follow_symlinks=False).st_size
                    os.remove(entry.path)
                    removed += 1
                except (OSError, PermissionError):
                    continue
        return True, f"Cleared {removed} trashed file(s)."
