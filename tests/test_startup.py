import os

import computa.startup as startup
from computa.startup import StartupItem, collect_startup


def test_parse_desktop_reads_name_exec_and_hidden(tmp_path):
    p = tmp_path / "thing.desktop"
    p.write_text(
        "[Desktop Entry]\nType=Application\nName=My Thing\n"
        "Exec=/usr/bin/mything --start\nHidden=true\n"
    )
    item = startup._parse_desktop(str(p))
    assert item is not None
    assert item.name == "My Thing"
    assert item.command == "/usr/bin/mything --start"
    assert item.enabled is False


def test_parse_desktop_enabled_by_default(tmp_path):
    p = tmp_path / "ok.desktop"
    p.write_text("[Desktop Entry]\nName=OK\nExec=ok\n")
    item = startup._parse_desktop(str(p))
    assert item.enabled is True


def test_linux_startup_scans_autostart_dir(tmp_path, monkeypatch):
    auto = tmp_path / "autostart"
    auto.mkdir()
    (auto / "a.desktop").write_text("[Desktop Entry]\nName=Alpha\nExec=alpha\n")
    (auto / "b.desktop").write_text("[Desktop Entry]\nName=Beta\nExec=beta\n")

    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path))
    items = startup._linux_startup()
    names = {i.name for i in items}
    assert {"Alpha", "Beta"} <= names


def test_collect_startup_never_raises(monkeypatch):
    # Force the platform-specific reader to blow up; collect should swallow it.
    monkeypatch.setattr(startup.platform, "system", lambda: "Linux")
    monkeypatch.setattr(startup, "_linux_startup",
                        lambda: (_ for _ in ()).throw(RuntimeError("boom")))
    assert collect_startup() == []


def test_startup_item_is_serializable():
    from dataclasses import asdict
    item = StartupItem("X", "x --go", "autostart", "/p", True)
    d = asdict(item)
    assert d["name"] == "X" and d["enabled"] is True
