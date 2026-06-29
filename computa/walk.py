"""Fast, robust directory traversal shared by sizing and cleanup.

Uses ``os.scandir`` instead of ``os.walk`` + per-file ``lstat``: the directory
entry already carries type and (on Windows) size/time info, so this avoids a
second syscall per file. That makes scanning large cache trees noticeably
faster, which is where ``scan`` and ``clean`` spend most of their time.

Every entry is yielded as an ``os.DirEntry`` whose ``.stat(follow_symlinks=
False)`` is cached. Symlinks are never followed and symlinked files are skipped,
matching the previous behaviour. All per-entry errors are swallowed.
"""
from __future__ import annotations

import os
from typing import Iterator


def iter_files(base: str, max_entries: int = 200000) -> Iterator["os.DirEntry"]:
    """Yield regular (non-symlink) files under ``base``, depth-first.

    Stops after ``max_entries`` files. Unreadable directories/entries are
    silently skipped rather than raising.
    """
    if max_entries <= 0:
        return
    count = 0
    stack = [base]
    while stack:
        current = stack.pop()
        try:
            scanner = os.scandir(current)
        except (OSError, PermissionError):
            continue
        with scanner:
            for entry in scanner:
                try:
                    # follow_symlinks=False: don't descend symlinked dirs and
                    # don't treat symlinked files as regular files.
                    if entry.is_dir(follow_symlinks=False):
                        stack.append(entry.path)
                    elif entry.is_file(follow_symlinks=False):
                        yield entry
                        count += 1
                        if count >= max_entries:
                            return
                except (OSError, PermissionError):
                    continue
