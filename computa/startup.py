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


@dataclass
class ToggleResult:
    name: str
    enable: bool       # the requested target state
    changed: bool      # did we actually change anything
    ok: bool           # did the operation succeed
    message: str
    location: str = ""


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


def _user_autostart_dir() -> str:
    xdg = os.environ.get("XDG_CONFIG_HOME")
    base = xdg if xdg else os.path.join(os.path.expanduser("~"), ".config")
    return os.path.join(base, "autostart")


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


def _find(name: str) -> Optional[StartupItem]:
    name_l = name.lower()
    for it in collect_startup():
        if it.name.lower() == name_l:
            return it
    return None


# --------------------------------------------------------------------------- #
# Toggling — enable / disable a startup item. Always reversible; only touches
# per-user locations. System-level items are reported, not modified.
# --------------------------------------------------------------------------- #
def _linux_set_enabled(name: str, enable: bool) -> ToggleResult:
    item = _find(name)
    if item is None:
        return ToggleResult(name, enable, False, False,
                            f"No startup program named '{name}' was found.")
    if item.enabled == enable:
        return ToggleResult(name, enable, False, True,
                            f"'{item.name}' is already "
                            f"{'enabled' if enable else 'disabled'}.", item.location)

    autostart_dir = _user_autostart_dir()
    try:
        os.makedirs(autostart_dir, exist_ok=True)
    except OSError as exc:
        return ToggleResult(name, enable, False, False,
                            f"Could not create {autostart_dir}: {exc}")

    target = os.path.join(autostart_dir, os.path.basename(item.location))
    source = target if os.path.exists(target) else item.location
    try:
        with open(source, "r", errors="ignore") as fh:
            lines = fh.read().splitlines()
    except OSError as exc:
        return ToggleResult(name, enable, False, False,
                            f"Could not read {source}: {exc}")

    # Drop any existing enable/disable keys, then set the one we want.
    kept = [ln for ln in lines if not ln.strip().lower().startswith(
        ("hidden=", "x-gnome-autostart-enabled="))]
    if not any(ln.strip() == "[Desktop Entry]" for ln in kept):
        kept.insert(0, "[Desktop Entry]")
    kept.append(f"Hidden={'false' if enable else 'true'}")

    try:
        with open(target, "w") as fh:
            fh.write("\n".join(kept) + "\n")
    except OSError as exc:
        return ToggleResult(name, enable, False, False,
                            f"Could not write {target}: {exc}")

    verb = "Enabled" if enable else "Disabled"
    return ToggleResult(item.name, enable, True, True,
                        f"{verb} '{item.name}' at login.", target)


def _macos_set_enabled(name: str, enable: bool) -> ToggleResult:
    import plistlib

    item = _find(name)
    if item is None:
        return ToggleResult(name, enable, False, False,
                            f"No startup program named '{name}' was found.")
    home = os.path.expanduser("~")
    if not item.location.startswith(home):
        return ToggleResult(name, enable, False, False,
                            f"'{item.name}' is a system-level item; changing it "
                            "needs administrator rights (sudo). Left unchanged.",
                            item.location)
    if item.enabled == enable:
        return ToggleResult(name, enable, False, True,
                            f"'{item.name}' is already "
                            f"{'enabled' if enable else 'disabled'}.", item.location)
    try:
        with open(item.location, "rb") as fh:
            data = plistlib.load(fh)
        data["Disabled"] = not enable
        with open(item.location, "wb") as fh:
            plistlib.dump(data, fh)
    except Exception as exc:
        return ToggleResult(name, enable, False, False,
                            f"Could not update {item.location}: {exc}", item.location)
    verb = "Enabled" if enable else "Disabled"
    return ToggleResult(item.name, enable, True, True,
                        f"{verb} '{item.name}'. Log out and back in (or use "
                        "launchctl) to apply.", item.location)


def _windows_set_enabled(name: str, enable: bool) -> ToggleResult:
    try:
        import winreg  # type: ignore
    except Exception:
        return ToggleResult(name, enable, False, False,
                            "Registry access (winreg) is unavailable.")

    run = r"Software\Microsoft\Windows\CurrentVersion\Run"
    backup = r"Software\computa\DisabledRun"
    HKCU = winreg.HKEY_CURRENT_USER

    def _move(src_key: str, dst_key: str) -> ToggleResult:
        try:
            with winreg.OpenKey(HKCU, src_key, 0, winreg.KEY_ALL_ACCESS) as sk:
                value, vtype = winreg.QueryValueEx(sk, name)
                with winreg.CreateKey(HKCU, dst_key) as dk:
                    winreg.SetValueEx(dk, name, 0, vtype, value)
                winreg.DeleteValue(sk, name)
        except FileNotFoundError:
            return ToggleResult(name, enable, False, False,
                                f"'{name}' was not found among HKCU Run items "
                                "(only those can be toggled safely).")
        except OSError as exc:
            return ToggleResult(name, enable, False, False,
                                f"Registry error: {exc}")
        verb = "Enabled" if enable else "Disabled"
        return ToggleResult(name, enable, True, True, f"{verb} '{name}'.", src_key)

    # Disable = move Run -> backup; Enable = move backup -> Run.
    return _move(run, backup) if not enable else _move(backup, run)


def set_enabled(name: str, enable: bool) -> ToggleResult:
    """Enable or disable a startup program by name. Reversible; user-level only."""
    sysname = platform.system()
    try:
        if sysname == "Windows":
            return _windows_set_enabled(name, enable)
        if sysname == "Darwin":
            return _macos_set_enabled(name, enable)
        return _linux_set_enabled(name, enable)
    except Exception as exc:  # pragma: no cover - safety net
        return ToggleResult(name, enable, False, False, f"Unexpected error: {exc}")
