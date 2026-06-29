import os

import computa.bigfiles as bigfiles
from computa.bigfiles import find_large_files, is_protected, delete_files


def test_is_protected_blocks_system_dirs(monkeypatch):
    monkeypatch.setattr(bigfiles, "_protected_roots",
                        lambda: [os.path.abspath(os.path.join(os.sep, "usr")),
                                 os.path.abspath(os.path.join(os.sep, "Windows"))])
    assert is_protected(os.path.join(os.sep, "usr", "bin", "python"))
    assert is_protected(os.path.join(os.sep, "Windows", "System32", "x.dll"))
    assert not is_protected(os.path.join(os.sep, "home", "me", "video.mp4"))


def test_find_large_files_ranks_and_filters(tmp_path):
    (tmp_path / "small.bin").write_bytes(b"x" * 1000)
    (tmp_path / "big.bin").write_bytes(b"x" * 50_000)
    (tmp_path / "huge.bin").write_bytes(b"x" * 200_000)

    files = find_large_files(str(tmp_path), top=10, min_size=10_000)
    names = [os.path.basename(f.path) for f in files]
    assert names == ["huge.bin", "big.bin"]   # biggest first, small excluded


def test_find_large_files_skips_protected(tmp_path, monkeypatch):
    prot = tmp_path / "protected"
    prot.mkdir()
    (prot / "system.bin").write_bytes(b"x" * 200_000)
    (tmp_path / "mine.bin").write_bytes(b"x" * 200_000)

    monkeypatch.setattr(bigfiles, "_protected_roots", lambda: [str(prot)])
    files = find_large_files(str(tmp_path), top=10, min_size=10_000)
    paths = [f.path for f in files]
    assert str(tmp_path / "mine.bin") in paths
    assert str(prot / "system.bin") not in paths


def test_delete_files_refuses_protected(tmp_path, monkeypatch):
    prot = tmp_path / "prot"
    prot.mkdir()
    safe_file = tmp_path / "ok.bin"
    prot_file = prot / "no.bin"
    safe_file.write_bytes(b"x" * 100)
    prot_file.write_bytes(b"x" * 100)

    monkeypatch.setattr(bigfiles, "_protected_roots", lambda: [str(prot)])
    removed, freed, errors, skipped = delete_files([str(safe_file), str(prot_file)])
    assert removed == 1
    assert not safe_file.exists()
    assert prot_file.exists()      # protected file untouched
    assert skipped == 1


def test_delete_files_handles_missing(tmp_path):
    removed, freed, errors, skipped = delete_files([str(tmp_path / "ghost")])
    assert removed == 0 and skipped == 1
