import os

import computa.startup as startup


def _write(d, name, body):
    p = os.path.join(str(d), name)
    with open(p, "w") as fh:
        fh.write(body)
    return p


def test_disable_then_enable_user_autostart(tmp_path, monkeypatch):
    cfg = tmp_path / "config"
    auto = cfg / "autostart"
    auto.mkdir(parents=True)
    _write(auto, "spotify.desktop",
           "[Desktop Entry]\nName=Spotify\nExec=spotify\n")
    monkeypatch.setenv("XDG_CONFIG_HOME", str(cfg))
    monkeypatch.setattr(startup.platform, "system", lambda: "Linux")

    # initially enabled
    assert any(i.name == "Spotify" and i.enabled
               for i in startup.collect_startup())

    res = startup.set_enabled("Spotify", False)
    assert res.ok and res.changed
    assert any(i.name == "Spotify" and not i.enabled
               for i in startup.collect_startup())

    res2 = startup.set_enabled("Spotify", True)
    assert res2.ok and res2.changed
    assert any(i.name == "Spotify" and i.enabled
               for i in startup.collect_startup())


def test_toggle_unknown_item_reports_not_found(tmp_path, monkeypatch):
    cfg = tmp_path / "config"
    (cfg / "autostart").mkdir(parents=True)
    monkeypatch.setenv("XDG_CONFIG_HOME", str(cfg))
    monkeypatch.setattr(startup.platform, "system", lambda: "Linux")

    res = startup.set_enabled("DoesNotExist", False)
    assert res.ok is False
    assert "No startup program" in res.message


def test_toggle_noop_when_already_in_state(tmp_path, monkeypatch):
    cfg = tmp_path / "config"
    auto = cfg / "autostart"
    auto.mkdir(parents=True)
    _write(auto, "x.desktop", "[Desktop Entry]\nName=X\nExec=x\n")
    monkeypatch.setenv("XDG_CONFIG_HOME", str(cfg))
    monkeypatch.setattr(startup.platform, "system", lambda: "Linux")

    res = startup.set_enabled("X", True)  # already enabled
    assert res.ok is True
    assert res.changed is False
    assert "already" in res.message


def test_disabling_system_item_creates_user_override(tmp_path, monkeypatch):
    # System file lives outside the user autostart dir; disabling must create a
    # user-level override rather than touching the system file.
    sysdir = tmp_path / "xdg"
    sysdir.mkdir()
    sys_file = _write(sysdir, "svc.desktop", "[Desktop Entry]\nName=Svc\nExec=svc\n")

    cfg = tmp_path / "config"
    (cfg / "autostart").mkdir(parents=True)
    monkeypatch.setenv("XDG_CONFIG_HOME", str(cfg))
    monkeypatch.setattr(startup.platform, "system", lambda: "Linux")
    # Make collect see the system file by pointing the system dir at it.
    monkeypatch.setattr(startup, "_linux_startup",
                        lambda: [startup.StartupItem("Svc", "svc", "autostart",
                                                     sys_file, True)])

    res = startup.set_enabled("Svc", False)
    assert res.ok and res.changed
    override = cfg / "autostart" / "svc.desktop"
    assert override.exists()
    # original system file is untouched
    with open(sys_file) as fh:
        assert "Hidden=true" not in fh.read()
    with open(override) as fh:
        assert "Hidden=true" in fh.read()
