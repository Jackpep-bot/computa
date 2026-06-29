import os
import time

import computa.cleanup as cleanup
import computa.system as system


def test_deep_includes_extra_locations(monkeypatch, tmp_path):
    # Build a fake Linux home with cache + trash.
    home = tmp_path / "home"
    cache = home / ".cache"
    trash = home / ".local" / "share" / "Trash" / "files"
    cache.mkdir(parents=True)
    trash.mkdir(parents=True)

    monkeypatch.setattr(system.platform, "system", lambda: "Linux")
    monkeypatch.setattr(system.os.path, "expanduser", lambda p: p.replace("~", str(home)))
    monkeypatch.setenv("XDG_CACHE_HOME", str(cache))
    monkeypatch.setenv("XDG_DATA_HOME", str(home / ".local" / "share"))
    monkeypatch.delenv("TMPDIR", raising=False)

    shallow = system._temp_candidates(deep=False)
    deep = system._temp_candidates(deep=True)

    assert str(cache) in shallow
    assert str(trash) not in shallow          # trash only in deep
    assert str(trash) in deep                 # deep widens the set
    assert len(deep) > len(shallow)


def test_deep_clean_finds_more(monkeypatch, tmp_path):
    cache = tmp_path / "cache"
    trash = tmp_path / "trash"
    cache.mkdir()
    trash.mkdir()
    old = time.time() - 30 * 86400
    for d in (cache, trash):
        f = d / "junk.bin"
        f.write_bytes(b"x" * 1000)
        os.utime(str(f), (old, old))

    def fake_candidates(deep=False):
        return [str(cache), str(trash)] if deep else [str(cache)]

    monkeypatch.setattr(cleanup, "_temp_candidates", fake_candidates)

    shallow = cleanup.clean(min_age_days=7, apply=False, deep=False)
    deep = cleanup.clean(min_age_days=7, apply=False, deep=True)

    assert shallow.reclaimable == 1000        # only cache
    assert deep.reclaimable == 2000           # cache + trash
