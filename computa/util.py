"""Shared helpers: optional psutil detection, size humanizing, and small utils."""
from __future__ import annotations

try:  # optional, gives richer data when present
    import psutil  # type: ignore
    HAVE_PSUTIL = True
except Exception:  # pragma: no cover - depends on environment
    psutil = None  # type: ignore
    HAVE_PSUTIL = False


def human_bytes(num: float) -> str:
    """Format a byte count as a human-readable string (e.g. '1.4 GB')."""
    if num is None:
        return "?"
    num = float(num)
    sign = "-" if num < 0 else ""
    num = abs(num)
    for unit in ("B", "KB", "MB", "GB", "TB", "PB"):
        if num < 1024.0 or unit == "PB":
            if unit == "B":
                return f"{sign}{int(num)} {unit}"
            return f"{sign}{num:.1f} {unit}"
        num /= 1024.0
    return f"{sign}{num:.1f} PB"  # pragma: no cover


def human_duration(seconds: float) -> str:
    """Format a duration in seconds as e.g. '3d 4h 12m'."""
    seconds = int(max(0, seconds))
    days, rem = divmod(seconds, 86400)
    hours, rem = divmod(rem, 3600)
    minutes, _ = divmod(rem, 60)
    parts = []
    if days:
        parts.append(f"{days}d")
    if hours:
        parts.append(f"{hours}h")
    if minutes or not parts:
        parts.append(f"{minutes}m")
    return " ".join(parts)


def pct_bar(percent: float, width: int = 20) -> str:
    """Return a simple text progress bar for a 0-100 percentage."""
    percent = max(0.0, min(100.0, float(percent)))
    filled = int(round(width * percent / 100.0))
    return "[" + "#" * filled + "-" * (width - filled) + f"] {percent:4.1f}%"
