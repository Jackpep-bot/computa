import json

from computa import serialize
from computa.cleanup import CleanCandidate, CleanResult
from computa.recommend import INFO, Recommendation
from computa.startup import StartupItem
from computa.system import DiskInfo, Snapshot


def test_snapshot_to_dict_includes_disk_percent_and_is_json_safe():
    snap = Snapshot(
        disks=[DiskInfo("/", 100, 90, 10)],
        startup=[StartupItem("X", "x", "autostart", "/p", True)],
    )
    d = serialize.snapshot_to_dict(snap)
    assert d["disks"][0]["percent"] == 90.0
    assert d["startup"][0]["name"] == "X"
    # round-trips through json without error
    json.dumps(d, default=str)


def test_recommendations_to_list():
    recs = [Recommendation(INFO, "t", "d", "a")]
    out = serialize.recommendations_to_list(recs)
    assert out == [{"severity": INFO, "title": "t", "detail": "d", "action": "a"}]


def test_clean_to_dict():
    result = CleanResult(
        candidates=[CleanCandidate("/x", 10, 9.0)],
        reclaimable=10, removed=0, removed_files=0, errors=0, applied=False,
    )
    d = serialize.clean_to_dict(result)
    assert d["reclaimable"] == 10
    assert d["candidates"][0]["path"] == "/x"
    json.dumps(d, default=str)
