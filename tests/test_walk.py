import os

from computa.walk import iter_files


def test_iter_files_finds_nested_files(tmp_path):
    (tmp_path / "a.txt").write_text("aaa")
    sub = tmp_path / "sub" / "deep"
    sub.mkdir(parents=True)
    (sub / "b.txt").write_text("bbbbb")

    found = {os.path.basename(e.path) for e in iter_files(str(tmp_path))}
    assert found == {"a.txt", "b.txt"}


def test_iter_files_sizes_match(tmp_path):
    (tmp_path / "x").write_bytes(b"x" * 100)
    (tmp_path / "y").write_bytes(b"y" * 250)
    total = sum(e.stat(follow_symlinks=False).st_size
                for e in iter_files(str(tmp_path)))
    assert total == 350


def test_iter_files_respects_max_entries(tmp_path):
    for i in range(10):
        (tmp_path / f"f{i}").write_text("z")
    got = list(iter_files(str(tmp_path), max_entries=3))
    assert len(got) == 3


def test_iter_files_skips_symlinks(tmp_path):
    target = tmp_path / "real.txt"
    target.write_text("hi")
    link = tmp_path / "link.txt"
    try:
        os.symlink(str(target), str(link))
    except (OSError, NotImplementedError):
        return  # platform without symlink support; nothing to assert
    names = {os.path.basename(e.path) for e in iter_files(str(tmp_path))}
    assert "real.txt" in names
    assert "link.txt" not in names


def test_iter_files_missing_dir_is_empty():
    assert list(iter_files("/no/such/path/here")) == []
