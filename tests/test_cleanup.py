import os
import time

import computa.cleanup as cleanup
import computa.system as system
from computa.util import human_bytes, human_duration


def _make_file(path, size, age_days):
    with open(path, "wb") as fh:
        fh.write(b"x" * size)
    when = time.time() - age_days * 86400
    os.utime(path, (when, when))


def test_find_candidates_respects_age(tmp_path, monkeypatch):
    old = tmp_path / "old.tmp"
    new = tmp_path / "new.tmp"
    _make_file(str(old), 1000, age_days=30)
    _make_file(str(new), 1000, age_days=1)

    monkeypatch.setattr(system, "_temp_candidates", lambda deep=False: [str(tmp_path)])
    monkeypatch.setattr(cleanup, "_temp_candidates", lambda deep=False: [str(tmp_path)])

    cands = cleanup.find_candidates(min_age_days=7)
    paths = {c.path for c in cands}
    assert str(old) in paths
    assert str(new) not in paths


def test_dry_run_deletes_nothing(tmp_path, monkeypatch):
    f = tmp_path / "junk.tmp"
    _make_file(str(f), 2048, age_days=30)
    monkeypatch.setattr(cleanup, "_temp_candidates", lambda deep=False: [str(tmp_path)])

    result = cleanup.clean(min_age_days=7, apply=False)
    assert result.applied is False
    assert result.removed == 0
    assert os.path.exists(str(f))
    assert result.reclaimable >= 2048


def test_apply_removes_old_files(tmp_path, monkeypatch):
    f = tmp_path / "junk.tmp"
    _make_file(str(f), 4096, age_days=30)
    monkeypatch.setattr(cleanup, "_temp_candidates", lambda deep=False: [str(tmp_path)])

    result = cleanup.clean(min_age_days=7, apply=True)
    assert result.applied is True
    assert result.removed_files == 1
    assert not os.path.exists(str(f))


def test_human_bytes():
    assert human_bytes(0) == "0 B"
    assert human_bytes(1023) == "1023 B"
    assert human_bytes(1024) == "1.0 KB"
    assert human_bytes(1024**3) == "1.0 GB"


def test_human_duration():
    assert human_duration(0) == "0m"
    assert human_duration(90) == "1m"
    assert human_duration(3 * 86400 + 4 * 3600 + 12 * 60) == "3d 4h 12m"
