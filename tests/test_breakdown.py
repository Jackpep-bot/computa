import os

from computa.cleanup import CleanCandidate, breakdown_by_app, clean


def test_breakdown_groups_by_top_level_folder():
    base = os.path.abspath(os.path.join(os.sep, "cache"))
    cands = [
        CleanCandidate(os.path.join(base, "google-chrome", "a"), 1000, 30),
        CleanCandidate(os.path.join(base, "google-chrome", "sub", "b"), 500, 30),
        CleanCandidate(os.path.join(base, "spotify", "c"), 4000, 30),
        CleanCandidate(os.path.join(base, "loose.tmp"), 200, 30),  # directly in base
    ]
    usage = breakdown_by_app(cands, bases=[base])
    by_name = {u.name: u for u in usage}

    assert by_name["spotify"].size == 4000
    assert by_name["google-chrome"].size == 1500
    assert by_name["google-chrome"].files == 2
    assert by_name["(loose files)"].size == 200
    # sorted biggest-first
    assert usage[0].name == "spotify"


def test_breakdown_handles_paths_outside_bases():
    usage = breakdown_by_app(
        [CleanCandidate(os.path.abspath(os.path.join(os.sep, "elsewhere", "x")), 10, 1)],
        bases=[os.path.abspath(os.path.join(os.sep, "cache"))],
    )
    assert usage[0].name == "(other)"


def test_clean_populates_breakdown(tmp_path, monkeypatch):
    import computa.cleanup as cleanup
    import time

    app = tmp_path / "google-chrome"
    app.mkdir()
    f = app / "cache.bin"
    f.write_bytes(b"x" * 5000)
    old = time.time() - 30 * 86400
    os.utime(str(f), (old, old))

    monkeypatch.setattr(cleanup, "_temp_candidates", lambda: [str(tmp_path)])
    result = cleanup.clean(min_age_days=7, apply=False)
    assert result.breakdown
    assert result.breakdown[0].name == "google-chrome"
    assert result.breakdown[0].size >= 5000
