"""Inspect programs that launch at login / boot.

Cross-platform and defensive: every reader is wrapped so a missing directory,
permission error or malformed file can never crash a scan. Returns an empty
list on unsupported platforms rather than raising.

  * Linux:   XDG autostart .desktop files (~/.config/autostart, /etc/xdg/autostart)
  * macOS:   LaunchAgents / LaunchDaemons plists
  * Windows: HKCU/HKLM ...\\CurrentVersion\\Run keys + Startup folders
"""
from __future__ import annotations

import glob
import os
import platform
from dataclasses import dataclass
from typing import List, Optional


@dataclass
class StartupItem:
    name: str
    command: str
    source: str        # e.g. "autostart", "LaunchAgents", "registry:HKCU Run"
    location: str      # file path or registry key
    enabled: bool = True


# --------------------------------------------------------------------------- #
# Linux
# --------------------------------------------------------------------------- #
def _parse_desktop(path: str) -> Optional[StartupItem]:
    name = os.path.basename(path)
    command = ""
    enabled = True
    try:
        with open(path, "r", errors="ignore") as fh:
            for raw in fh:
                line = raw.strip()
                if line.startswith("Name=") and name == os.path.basename(path):
                    name = line[5:].strip() or name
                elif line.startswith("Exec="):
                    command = line[5:].strip()
                elif line.startswith("Hidden=") and line[7:].strip().lower() == "true":
                    enabled = False
                elif line.startswith("X-GNOME-Autostart-enabled=") and \
                        line.split("=", 1)[1].strip().lower() == "false":
                    enabled = False
    except OSError:
        return None
    return StartupItem(name=name, command=command, source="autostart",
                       location=path, enabled=enabled)


def _linux_startup() -> List[StartupItem]:
    dirs = []
    xdg = os.environ.get("XDG_CONFIG_HOME")
    if xdg:
        dirs.append(os.path.join(xdg, "autostart"))
    dirs.append(os.path.expanduser("~/.config/autostart"))
    dirs.append("/etc/xdg/autostart")

    items: List[StartupItem] = []
    seen = set()
    for d in dirs:
        for path in sorted(glob.glob(os.path.join(d, "*.desktop"))):
            base = os.path.basename(path)
            if base in seen:  # user dir overrides system dir
                continue
            seen.add(base)
            item = _parse_desktop(path)
            if item:
                items.append(item)
    return items


# --------------------------------------------------------------------------- #
# macOS
# --------------------------------------------------------------------------- #
def _macos_startup() -> List[StartupItem]:
    import plistlib

    dirs = [
        (os.path.expanduser("~/Library/LaunchAgents"), "LaunchAgents"),
        ("/Library/LaunchAgents", "LaunchAgents"),
        ("/Library/LaunchDaemons", "LaunchDaemons"),
    ]
    items: List[StartupItem] = []
    for d, source in dirs:
        for path in sorted(glob.glob(os.path.join(d, "*.plist"))):
            try:
                with open(path, "rb") as fh:
                    data = plistlib.load(fh)
            except Exception:
                continue
            label = data.get("Label") or os.path.basename(path)
            program = data.get("Program")
            args = data.get("ProgramArguments")
            if program:
                command = str(program)
            elif isinstance(args, list):
                command = " ".join(str(a) for a in args)
            else:
                command = ""
            enabled = not bool(data.get("Disabled", False))
            items.append(StartupItem(label, command, source, path, enabled))
    return items


# --------------------------------------------------------------------------- #
# Windows
# --------------------------------------------------------------------------- #
def _windows_startup() -> List[StartupItem]:
    items: List[StartupItem] = []
    try:
        import winreg  # type: ignore
    except Exception:
        winreg = None  # type: ignore

    if winreg is not None:
        run_keys = [
            (winreg.HKEY_CURRENT_USER,
             r"Software\Microsoft\Windows\CurrentVersion\Run", "registry:HKCU Run"),
            (winreg.HKEY_LOCAL_MACHINE,
             r"Software\Microsoft\Windows\CurrentVersion\Run", "registry:HKLM Run"),
        ]
        for hive, subkey, source in run_keys:
            try:
                with winreg.OpenKey(hive, subkey) as key:
                    i = 0
                    while True:
                        try:
                            name, value, _ = winreg.EnumValue(key, i)
                        except OSError:
                            break
                        items.append(StartupItem(name, str(value), source, subkey, True))
                        i += 1
            except OSError:
                continue

    folders = []
    appdata = os.environ.get("APPDATA")
    if appdata:
        folders.append(os.path.join(
            appdata, r"Microsoft\Windows\Start Menu\Programs\Startup"))
    programdata = os.environ.get("ProgramData")
    if programdata:
        folders.append(os.path.join(
            programdata, r"Microsoft\Windows\Start Menu\Programs\Startup"))
    for d in folders:
        try:
            for name in sorted(os.listdir(d)):
                if name.lower() in ("desktop.ini",):
                    continue
                items.append(StartupItem(name, os.path.join(d, name),
                                         "Startup folder", d, True))
        except OSError:
            continue
    return items


def collect_startup() -> List[StartupItem]:
    """Return the list of programs configured to launch at login/boot."""
    sysname = platform.system()
    try:
        if sysname == "Windows":
            return _windows_startup()
        if sysname == "Darwin":
            return _macos_startup()
        return _linux_startup()
    except Exception:
        return []
