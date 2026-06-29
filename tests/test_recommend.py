from computa.recommend import (CRITICAL, INFO, WARNING, analyze)
from computa.system import DiskInfo, ProcInfo, Snapshot, TempInfo


def _snap(**kw) -> Snapshot:
    base = Snapshot(have_psutil=True, cpu_count=4)
    for k, v in kw.items():
        setattr(base, k, v)
    return base


def test_healthy_system_has_no_findings():
    snap = _snap(
        mem_total=16 * 1024**3, mem_used=4 * 1024**3, mem_percent=25.0,
        disks=[DiskInfo("/", 500 * 1024**3, 200 * 1024**3, 300 * 1024**3)],
        temp_dirs=[TempInfo("/tmp", 10 * 1024**2, 5)],
    )
    assert analyze(snap) == []


def test_full_disk_is_critical_and_sorted_first():
    snap = _snap(
        disks=[DiskInfo("/", 100 * 1024**3, 95 * 1024**3, 5 * 1024**3)],
        temp_dirs=[TempInfo("/tmp", 600 * 1024**2, 3)],  # also triggers an INFO
    )
    recs = analyze(snap)
    assert recs[0].severity == CRITICAL
    assert "almost full" in recs[0].title
    # critical sorts before info
    assert [r.severity for r in recs] == sorted(
        [r.severity for r in recs], key=lambda s: {CRITICAL: 0, WARNING: 1, INFO: 2}[s]
    )


def test_high_memory_warns():
    snap = _snap(mem_total=8 * 1024**3, mem_used=7 * 1024**3, mem_percent=87.5)
    recs = analyze(snap)
    assert any(r.severity == WARNING and "Memory" in r.title for r in recs)


def test_memory_exhaustion_is_critical():
    snap = _snap(mem_total=8 * 1024**3, mem_used=int(7.5 * 1024**3), mem_percent=94.0)
    recs = analyze(snap)
    assert any(r.severity == CRITICAL and "Memory" in r.title for r in recs)


def test_large_temp_warns():
    snap = _snap(temp_dirs=[TempInfo("/tmp", 3 * 1024**3, 100)])
    recs = analyze(snap)
    assert any("temp" in r.title.lower() or "cache" in r.title.lower() for r in recs)


def test_process_memory_hog_flagged():
    snap = _snap(top_mem=[ProcInfo(123, "chrome", 0.0, 4 * 1024**3, 30.0)])
    recs = analyze(snap)
    assert any("chrome" in r.title for r in recs)


def test_missing_psutil_suggests_install():
    snap = Snapshot(have_psutil=False)
    recs = analyze(snap)
    assert any("psutil" in r.title for r in recs)


def test_long_uptime_suggests_reboot():
    snap = _snap(uptime_seconds=10 * 86400)
    recs = analyze(snap)
    assert any("uptime" in r.title.lower() for r in recs)
