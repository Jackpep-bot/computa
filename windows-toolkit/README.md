# computa — Windows cleanup & speed-up toolkit (PowerShell)

A set of PowerShell scripts to diagnose, clean up, and speed up an old or
sluggish Windows PC — built around a strict safety model so nothing surprising
ever happens.

## Safety model (applies to every script)

- **Diagnostics/audits are strictly read-only.** They only *look* and write
  reports — they never change your system.
- **Anything destructive defaults to a DRY-RUN.** It shows exactly what *would*
  happen (and how much space would be freed) without touching anything.
- **Actual changes require `-Confirm`.** Only when you add the `-Confirm` flag
  does a destructive script delete/modify anything.
- **Everything is logged** to a timestamped file in `logs\` (created on first
  run; git-ignored).
- **Only known-safe junk paths are ever touched** — system temp, browser
  caches, crash dumps, the Recycle Bin, and the Windows Update download cache.
  Nothing outside that list is deleted.

> The destructive scripts use a plain `-Confirm` switch: **no flag = preview**,
> `-Confirm` = do it.

## How to run

**Easiest:** double-click **`Run-Toolkit.bat`** — it launches the menu with an
execution-policy bypass for that one run, so you don't change any settings.
(For the admin-only steps, right-click it and choose *Run as administrator*.)

**Or from PowerShell:**

1. Copy the `windows-toolkit` folder onto the PC.
2. Open **PowerShell** (some steps need **Run as administrator** — they'll say so).
3. If scripts are blocked, allow them for this session only:
   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   ```
4. Start the menu:
   ```powershell
   .\menu.ps1
   ```

**Or** right-click `menu.ps1` in Explorer and choose **Run with PowerShell**.

The menu runs things in a sensible order (protect → diagnose → audits →
adjustments → cleanup last). Destructive items **preview first**, then ask you
to type **APPLY** before they re-run with `-Confirm`. Before the heavy disk
scans, if SMART disk health is anything other than *Healthy*, the menu **warns
you to back up first**.

## The scripts

### Protect
- **restore-point.ps1** — creates a **System Restore point** (needs admin). Run
  this *first*, before any cleanup/repair/optimize. Warns (with enable steps) if
  System Restore is disabled. `-Label "my label"` to name it.

### Diagnose / audit (read-only)
- **diagnose.ps1** — one readable health report: disk free/total per drive,
  SMART/disk health, RAM total & usage, CPU model, top 10 processes by RAM and
  by CPU, startup count, Windows version, uptime. Console + timestamped `.txt`.
- **health-report.ps1** — a compact combined summary (disk health, space, top
  errors, startup count, drive types) in one dated file you can copy back for
  advice.
- **disk-map.ps1** `[-Path C:\] [-MinFileMB 10]` — the 30 largest files and 20
  largest folders, biggest first. Table + two CSVs. *(Heavy scan.)*
- **profile-bloat.ps1** `[-Path %USERPROFILE%] [-Depth 2]` — largest folders
  inside your user profile, biggest first. Table + CSV.
- **find-clutter.ps1** `[-Path] [-LargeMB 500] [-StaleYears 2] [-MinDuplicateMB 50]`
  — files over 500 MB, files not touched in 2+ years, and likely duplicates
  (same size + matching SHA-256). Three CSVs. Never deletes. *(Heavy scan.)*
- **programs-audit.ps1** — installed programs with install date, estimated size
  and publisher, sorted by size. Table + CSV.
- **services-audit.ps1** — Automatic-start services with status and publisher;
  flags common safe-to-delay ones as *consider Manual* (changes nothing). CSV.
- **startup-audit.ps1** — everything launching at startup (Run keys, startup
  folders, logon scheduled tasks) with name/publisher/path; flags no-publisher
  or Temp/AppData entries as *REVIEW*. Changes nothing. CSV.
- **bloatware-audit.ps1** — Store/preinstalled apps (Appx) with publisher;
  flags common bloat as *review*. Removes nothing. CSV.
- **event-errors.ps1** `[-Days 14]` — recurring errors/critical events from the
  System & Application logs, grouped by source with counts and most-recent time.
  Summary + CSV.

### Adjust (preview by default, `-Confirm` to apply)
- **power-plan.ps1** `[-Plan Balanced|High] [-Confirm]` — reports the active
  power plan and warns if you're on power-saver; switches plan only with
  `-Confirm`.
- **network-reset.ps1** `[-Confirm]` — flushes DNS and reports adapter/IP state
  by default (both harmless); with `-Confirm` also resets Winsock + TCP/IP
  (**needs a reboot**, needs admin).
- **optimize-drives.ps1** `[-Confirm]` — detects SSD vs HDD and reports status;
  with `-Confirm` **TRIMs SSDs and defragments HDDs** — and **never defrags an
  SSD** (skips any drive whose type can't be confirmed). Needs admin to apply.
- **system-repair.ps1** `[-Confirm]` — runs DISM CheckHealth/ScanHealth and
  `SFC /VERIFYONLY` (read-only) and reports whether corruption was found; with
  `-Confirm` runs DISM `/RestoreHealth` and `SFC /SCANNOW`. Needs admin.

### Clean (last)
- **cleanup.ps1** `[-Confirm]` — clears `%TEMP%`, Windows Temp, browser caches,
  Recycle Bin, and the Windows Update download cache. **DRY-RUN by default**
  (shows what would be freed); `-Confirm` actually deletes. Logs everything.
- **app-uninstall.ps1** `[-Confirm] [-Only <patterns>] [-Keep <patterns>] [-NukeSteamLibraries]`
  — automated bulk uninstaller. **DRY-RUN by default** (lists exactly what would
  be removed); `-Confirm` actually uninstalls. A **hard protected list** means it
  can never remove Windows, NVIDIA/Realtek/Intel/AMD drivers, Visual C++/.NET/
  DirectX runtimes, Edge, **Riot Vanguard, VALORANT, Claude, or Google Chrome**.
  MSI apps uninstall silently; some apps may briefly show their own uninstaller.
  `-NukeSteamLibraries` also deletes Steam game files to reclaim that space.
  Use `-Only 'Discord','Spotify'` to target specific apps, or `-Keep 'Discord'`
  to protect extras.

### Shared
- **lib/Common.ps1** — shared helpers (logging, size formatting, SMART health,
  junk-path list, startup/publisher lookups). Dot-sourced by every script; not
  run directly.
- **menu.ps1** — the master menu described above.

## Notes & limits

- Targets **Windows PowerShell 5.1** (built into Windows 10/11). A few features
  (`Get-PhysicalDisk`, `Get-ScheduledTask`, Appx) need Windows 8/10+; scripts
  degrade gracefully if a source isn't available.
- "Not opened in 2+ years" uses last-access time, which Windows sometimes
  doesn't update; `find-clutter.ps1` therefore also requires last-write to be
  old before flagging a file as stale.
- Some steps need **Administrator** (restore point, system repair, drive
  optimize, Winsock reset, and the Windows Update cache in cleanup). Each says
  so and skips safely if not elevated.
- Logs and CSVs are written to `windows-toolkit\logs\`.
