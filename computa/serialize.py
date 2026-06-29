"""Convert computa data objects into JSON-ready dicts.

Kept separate from the dataclasses so the ``percent`` properties (which
``dataclasses.asdict`` would omit) are included in machine-readable output.
"""
from __future__ import annotations

from dataclasses import asdict
from typing import List

from .cleanup import CleanResult
from .recommend import Recommendation
from .startup import StartupItem
from .system import Snapshot


def snapshot_to_dict(snap: Snapshot) -> dict:
    d = asdict(snap)
    # asdict drops @property values; re-attach disk usage percent.
    for orig, out in zip(snap.disks, d.get("disks", [])):
        out["percent"] = round(orig.percent, 1)
    return d


def recommendations_to_list(recs: List[Recommendation]) -> List[dict]:
    return [asdict(r) for r in recs]


def clean_to_dict(result: CleanResult) -> dict:
    return asdict(result)


def startup_to_list(items: List[StartupItem]) -> List[dict]:
    return [asdict(i) for i in items]


def big_files_to_list(files) -> List[dict]:
    return [asdict(f) for f in files]


def programs_to_list(progs) -> List[dict]:
    return [asdict(p) for p in progs]


def diff_to_dict(diff) -> dict:
    """Serialize a history.Diff, including its computed delta properties."""
    d = asdict(diff)
    for orig, out in zip(diff.disks, d.get("disks", [])):
        out["free_delta"] = orig.free_delta
    d["temp_delta"] = diff.temp_delta
    return d
