# computa

**A small, safe toolkit to scan your computer and help it run faster.**

`computa` is a cross-platform (Windows / macOS / Linux) command-line tool that
inspects your machine, explains what's slowing it down in plain English, and
safely reclaims wasted space — without touching anything important.

It runs on the **Python standard library alone** (zero dependencies). Installing
the optional [`psutil`](https://pypi.org/project/psutil/) package unlocks live
CPU/memory, swap, uptime and per-process detail.

---

## Quick start

**No terminal? Use the one-click launcher.** It sets everything up on first run,
then opens a simple menu:

| Your OS | Double-click / run |
| ------- | ------------------ |
| macOS   | `Computa.command`  |
| Windows | `Computa.bat`      |
| Linux   | `./computa.sh`     |

**Prefer the terminal?**

```bash
# Option A — run straight from the source folder, no install:
python -m computa scan

# Option B — install it so `computa` is on your PATH:
pip install -e .            # core (stdlib only)
pip install -e ".[full]"   # + psutil for the deeper scan (recommended)
computa scan
```

> Recommended one-liner for the full experience: `pip install psutil`

---

## Commands

| Command            | What it does                                                        |
| ------------------ | ------------------------------------------------------------------- |
| `computa scan`     | Full health snapshot: CPU, memory, swap, disks, top processes, cache/temp size, startup count. Ends with recommendations. |
| `computa doctor`   | Just the prioritized advice (CRIT / WARN / INFO). Exits non-zero if anything is critical, so it's scriptable. |
| `computa top`      | "What's eating my resources right now" — top CPU & memory processes (needs psutil). |
| `computa startup`  | List **or toggle** programs that launch at login/boot (`--enable`/`--disable NAME`). |
| `computa diff`     | Show what changed since your last scan (disk, memory, cache/temp, startup items). |
| `computa clean`    | Reclaim cache/temp space. **Dry-run by default** — shows what *would* be removed. |
| `computa menu`     | Interactive menu — no commands to remember (what the launchers open). |

Every reporting command also accepts **`--json`** for machine-readable output
you can pipe into other tools.

### Examples

```bash
computa scan              # the everyday "how's my machine doing?"
computa scan --fast       # skip the ~0.5s per-process sample
computa doctor            # only the actionable advice
computa doctor --json     # same, as JSON (exit code 2 if anything is critical)
computa startup           # what launches at login
computa startup --disable "Spotify"   # stop it launching at login (reversible)
computa startup --enable  "Spotify"   # turn it back on
computa diff              # what changed since your last scan
computa clean             # PREVIEW reclaimable junk (deletes nothing)
computa clean --yes       # actually delete old cache/temp files
computa clean --min-age 30 --yes   # only files older than 30 days
computa menu              # guided menu, no flags to remember
```

---

## Safety model

`computa clean` is deliberately conservative:

- It only ever looks inside **known cache / temp directories** for your OS
  (e.g. your system temp folder, `~/.cache` on Linux, `~/Library/Caches` on
  macOS, `%TEMP%`/`%LOCALAPPDATA%\Temp` on Windows).
- It only considers files **older than 7 days** by default (`--min-age`), so it
  won't touch anything in active use.
- It is **dry-run unless you pass `--yes`** — you always see the preview first.
- Per-file errors (permissions, file-in-use) are skipped, never fatal.

It never deletes outside those directories and never reads file *contents*.

---

## How it works

```
computa/
  system.py      gather a Snapshot (platform, CPU, memory, disks, processes, temp, startup)
  startup.py     cross-platform login/boot program inspection + enable/disable
  history.py     save scan baselines and compute "what changed since last scan"
  recommend.py   pure logic: Snapshot -> prioritized recommendations
  cleanup.py     safe discovery + removal of old cache/temp files
  serialize.py   convert data objects into JSON-ready dicts (--json output)
  report.py      terminal-friendly formatting (with color on TTYs)
  cli.py         argparse command-line interface + interactive menu
scripts/         install.sh / install.ps1 (one-time environment setup)
Computa.command, Computa.bat, computa.sh   double-clickable launchers
```

The diagnosis logic in `recommend.py` is pure (no I/O), so it's fully unit
tested. Run the suite with:

```bash
pip install pytest
python -m pytest
```

---

## Startup toggling — safety

`computa startup --enable/--disable` is **reversible** and only ever touches
**per-user** locations:

- **Linux** — sets `Hidden=true/false` in a `~/.config/autostart` entry, creating
  a user-level override for system entries rather than editing system files.
- **macOS** — sets the `Disabled` key in your `~/Library/LaunchAgents` plist;
  system-level agents are reported as needing `sudo`, never changed.
- **Windows** — moves the value between `HKCU\...\Run` and a backup key
  (`HKCU\Software\computa\DisabledRun`); `HKLM`/admin items are left untouched.

> The Linux path is verified end-to-end in CI/tests. macOS and Windows toggling
> follow the documented per-OS conventions but should be sanity-checked on those
> platforms.

## Roadmap ideas

- Per-app cache breakdown in `computa clean`
- Optional Windows/macOS native checks (Windows services, Spotlight, etc.)

Contributions and ideas welcome.

## License

MIT
