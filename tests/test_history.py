from computa import history
from computa.startup import StartupItem
from computa.system import DiskInfo, Snapshot, TempInfo


def _snap(**kw):
    base = Snapshot()
    for k, v in kw.items():
        setattr(base, k, v)
    return base


def test_save_and_load_roundtrip(tmp_path, monkeypatch):
    monkeypatch.setenv("COMPUTA_HOME", str(tmp_path / "state"))
    snap = _snap(disks=[DiskInfo("/", 100, 40, 60)])
    assert history.save_snapshot(snap, now=1000.0) is True
    loaded = history.load_last()
    assert loaded is not None
    assert loaded["timestamp"] == 1000.0
    assert loaded["snapshot"]["disks"][0]["mount"] == "/"


def test_load_last_none_when_absent(tmp_path, monkeypatch):
    monkeypatch.setenv("COMPUTA_HOME", str(tmp_path / "nope"))
    assert history.load_last() is None


def test_compute_diff_detects_changes(tmp_path, monkeypatch):
    monkeypatch.setenv("COMPUTA_HOME", str(tmp_path / "state"))
    old = _snap(
        disks=[DiskInfo("/", 100 * 1024**3, 40 * 1024**3, 60 * 1024**3)],
        mem_percent=50.0,
        temp_dirs=[TempInfo("/tmp", 100 * 1024**2, 5)],
        startup=[StartupItem("Old", "o", "autostart", "/o", True)],
    )
    history.save_snapshot(old, now=1000.0)
    previous = history.load_last()

    new = _snap(
        disks=[DiskInfo("/", 100 * 1024**3, 30 * 1024**3, 70 * 1024**3)],  # used more
        mem_percent=65.0,
        temp_dirs=[TempInfo("/tmp", 600 * 1024**2, 9)],
        startup=[StartupItem("New", "n", "autostart", "/n", True)],
    )
    diff = history.compute_diff(previous, new, now=1000.0 + 3600)

    assert diff.elapsed_seconds == 3600
    assert diff.disks[0].free_delta == 10 * 1024**3  # 10 GB more free
    assert diff.mem_percent_new - diff.mem_percent_old == 15.0
    assert diff.temp_delta == 500 * 1024**2
    assert diff.startup_added == ["New"]
    assert diff.startup_removed == ["Old"]

    text = history.format_diff(diff)
    assert "New startup program" in text
    assert "Removed startup program" in text


def test_format_diff_no_changes():
    diff = history.Diff(elapsed_seconds=60)
    assert "No significant changes" in history.format_diff(diff)
