"""List installed programs by size (Windows), to spot big things to uninstall.

Read-only: this never uninstalls anything — removing programs should go through
the OS uninstaller (Add or remove programs). It just reveals which installed
programs are largest so you know what to remove there.
"""
from __future__ import annotations

import platform
from dataclasses import dataclass
from typing import List


@dataclass
class Program:
    name: str
    size_bytes: int       # 0 if unknown
    location: str
    uninstall: str


def _windows_programs() -> List[Program]:
    import winreg

    out: List[Program] = []
    seen = set()
    roots = [
        (winreg.HKEY_LOCAL_MACHINE,
         r"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"),
        (winreg.HKEY_LOCAL_MACHINE,
         r"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"),
        (winreg.HKEY_CURRENT_USER,
         r"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"),
    ]
    for hive, subkey in roots:
        try:
            root = winreg.OpenKey(hive, subkey)
        except OSError:
            continue
        with root:
            i = 0
            while True:
                try:
                    name = winreg.EnumKey(root, i)
                except OSError:
                    break
                i += 1
                try:
                    with winreg.OpenKey(root, name) as k:
                        def val(key, default=""):
                            try:
                                return winreg.QueryValueEx(k, key)[0]
                            except OSError:
                                return default
                        display = val("DisplayName")
                        if not display or val("SystemComponent", 0) == 1:
                            continue
                        if display in seen:
                            continue
                        seen.add(display)
                        size_kb = val("EstimatedSize", 0) or 0
                        out.append(Program(
                            name=str(display),
                            size_bytes=int(size_kb) * 1024,
                            location=str(val("InstallLocation")),
                            uninstall=str(val("UninstallString")),
                        ))
                except OSError:
                    continue
    out.sort(key=lambda p: p.size_bytes, reverse=True)
    return out


def list_programs() -> List[Program]:
    """Return installed programs sorted largest-first (Windows only)."""
    if platform.system() != "Windows":
        return []
    try:
        return _windows_programs()
    except Exception:
        return []
