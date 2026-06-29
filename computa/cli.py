"""Command-line interface for computa."""
from __future__ import annotations

import argparse
import json
import sys

from . import (__version__, bigfiles, cleanup, history, programs, recommend,
               report, serialize, startup, system)


def _print_json(obj) -> None:
    print(json.dumps(obj, indent=2, default=str))


def _cmd_scan(args) -> int:
    snap = system.collect(processes=not getattr(args, "fast", False))
    recs = recommend.analyze(snap)
    if getattr(args, "save", True):
        history.save_snapshot(snap)
    if getattr(args, "json", False):
        _print_json({
            "snapshot": serialize.snapshot_to_dict(snap),
            "recommendations": serialize.recommendations_to_list(recs),
        })
        return 0
    print(report.format_snapshot(snap))
    if getattr(args, "advice", True):
        print()
        print(report.format_recommendations(recs))
    return 0


def _cmd_doctor(args) -> int:
    snap = system.collect(processes=True)
    recs = recommend.analyze(snap)
    if getattr(args, "json", False):
        _print_json(serialize.recommendations_to_list(recs))
    else:
        print(report.format_recommendations(recs))
    return 2 if any(r.severity == recommend.CRITICAL for r in recs) else 0


def _cmd_top(args) -> int:
    snap = system.collect(processes=True)
    if getattr(args, "json", False):
        _print_json(serialize.snapshot_to_dict(snap))
        return 0
    if not snap.have_psutil:
        print("`computa top` needs psutil for process detail. Install it with:\n"
              "  pip install psutil")
        return 1
    print(report.format_snapshot(snap))
    return 0


def _cmd_startup(args) -> int:
    from dataclasses import asdict

    target = getattr(args, "enable", None) or getattr(args, "disable", None)
    if target is not None:
        want_enable = getattr(args, "enable", None) is not None
        result = startup.set_enabled(target, want_enable)
        if getattr(args, "json", False):
            _print_json(asdict(result))
        else:
            print(result.message)
        return 0 if result.ok else 1

    items = startup.collect_startup()
    if getattr(args, "json", False):
        _print_json(serialize.startup_to_list(items))
    else:
        print(report.format_startup(items))
    return 0


def _cmd_diff(args) -> int:
    snap = system.collect(processes=False)
    previous = history.load_last()
    if previous is None:
        history.save_snapshot(snap)
        msg = ("No previous scan found — saved a baseline just now. "
               "Run `computa diff` again later to see what changed.")
        if getattr(args, "json", False):
            _print_json({"baseline_created": True, "message": msg})
        else:
            print(msg)
        return 0
    diff = history.compute_diff(previous, snap)
    if getattr(args, "json", False):
        _print_json(serialize.diff_to_dict(diff))
    else:
        print(history.format_diff(diff))
    if getattr(args, "save", True):
        history.save_snapshot(snap)
    return 0


def _resolve_min_age(args) -> float:
    """Default min-age: 7 days normally, 1 day for a deep sweep."""
    if getattr(args, "min_age", None) is not None:
        return args.min_age
    return 1.0 if getattr(args, "deep", False) else 7.0


def _cmd_clean(args) -> int:
    min_age = _resolve_min_age(args)
    deep = getattr(args, "deep", False)
    result = cleanup.clean(min_age_days=min_age, apply=args.yes, deep=deep)
    if getattr(args, "json", False):
        _print_json(serialize.clean_to_dict(result))
    else:
        print(report.format_clean(result, min_age, deep=deep))
    return 0


def _cmd_sweep(args) -> int:
    """Full sweep: scan + diagnose + deep-clean (preview unless --yes)."""
    snap = system.collect(processes=True)
    recs = recommend.analyze(snap)
    min_age = args.min_age if getattr(args, "min_age", None) is not None else 1.0
    result = cleanup.clean(min_age_days=min_age, apply=args.yes, deep=True)

    if getattr(args, "json", False):
        _print_json({
            "snapshot": serialize.snapshot_to_dict(snap),
            "recommendations": serialize.recommendations_to_list(recs),
            "deep_clean": serialize.clean_to_dict(result),
        })
        return 2 if any(r.severity == recommend.CRITICAL for r in recs) else 0

    print(report.format_snapshot(snap))
    print()
    print(report.format_recommendations(recs))
    print()
    print("=" * 60)
    print(report.format_clean(result, min_age, deep=True))
    history.save_snapshot(snap)
    return 2 if any(r.severity == recommend.CRITICAL for r in recs) else 0


def _cmd_large(args) -> int:
    import os
    root = args.path or os.path.expanduser("~")
    files = bigfiles.find_large_files(
        root, top=args.top, min_size=int(args.min_size * 1024 * 1024))
    if getattr(args, "json", False):
        _print_json(serialize.big_files_to_list(files))
        return 0
    print(report.format_large(files, root))
    if getattr(args, "delete", False) and files:
        _interactive_delete(files)
    return 0


def _interactive_delete(files) -> None:
    """Let the user pick big files to delete, with an explicit confirmation."""
    print()
    print("Enter the numbers of files to DELETE (e.g. 1,3,4), or press Enter "
          "to cancel:")
    try:
        raw = input("> ").strip()
    except EOFError:
        return
    if not raw:
        print("Cancelled — nothing deleted.")
        return
    chosen = []
    for tok in raw.replace(" ", ",").split(","):
        if tok.isdigit():
            idx = int(tok)
            if 1 <= idx <= len(files):
                chosen.append(files[idx - 1])
    if not chosen:
        print("No valid numbers — nothing deleted.")
        return
    total = sum(f.size for f in chosen)
    print()
    print(f"About to delete {len(chosen)} file(s), freeing "
          f"{report.human_bytes(total)}:")
    for f in chosen:
        print(f"   {report.human_bytes(f.size):>9}  {f.path}")
    try:
        confirm = input("\nType 'DELETE' (in capitals) to confirm: ").strip()
    except EOFError:
        return
    if confirm != "DELETE":
        print("Not confirmed — nothing deleted.")
        return
    removed, freed, errors, skipped = bigfiles.delete_files([f.path for f in chosen])
    print(f"\nDeleted {removed} file(s), freed {report.human_bytes(freed)}.")
    if skipped:
        print(f"Skipped {skipped} protected/missing file(s).")
    if errors:
        print(f"{errors} file(s) could not be deleted (in use or no permission).")


def _cmd_programs(args) -> int:
    progs = programs.list_programs()
    if getattr(args, "json", False):
        _print_json(serialize.programs_to_list(progs))
    else:
        print(report.format_programs(progs))
    return 0


def _cmd_recycle(args) -> int:
    if getattr(args, "empty", False):
        ok, msg = bigfiles.empty_recycle_bin()
        print(msg)
        return 0 if ok else 1
    print("Use `computa recycle --empty` to empty the Recycle Bin / Trash.")
    return 0


_MENU = """
computa — what would you like to do?

  1) Scan      full health snapshot + advice
  2) Doctor    just the recommendations
  3) Top       what's using CPU / memory right now
  4) Startup   programs that launch at login
  5) Diff      what changed since your last scan
  6) Clean     PREVIEW reclaimable cache/temp (safe — deletes nothing)
  7) Clean now actually delete old cache/temp (asks to confirm)
  8) Sweep     FULL deep sweep: scan + diagnose + deep-clean preview
  9) Deep clean delete browser caches, crash dumps, logs, trash (confirms)
  b) Big files find the largest files eating your space (and delete, confirmed)
  p) Programs  installed programs by size (to spot what to uninstall)
  r) Recycle   empty the Recycle Bin / Trash
  q) Quit
"""


def _cmd_menu(args) -> int:
    while True:
        print(_MENU)
        try:
            choice = input("Enter choice: ").strip().lower()
        except EOFError:
            return 0
        if choice in ("q", "quit", "exit"):
            return 0
        if choice == "":
            # A stray blank line (e.g. from a paste) shouldn't quit — re-show.
            continue
        print()
        if choice == "1":
            _cmd_scan(argparse.Namespace(json=False, fast=False, advice=True))
        elif choice == "2":
            _cmd_doctor(argparse.Namespace(json=False))
        elif choice == "3":
            _cmd_top(argparse.Namespace(json=False))
        elif choice == "4":
            _cmd_startup(argparse.Namespace(json=False, enable=None, disable=None))
        elif choice == "5":
            _cmd_diff(argparse.Namespace(json=False, save=True))
        elif choice == "6":
            _cmd_clean(argparse.Namespace(json=False, min_age=7.0, yes=False))
        elif choice == "7":
            confirm = input("Delete old cache/temp files? Type 'yes' to confirm: ")
            _cmd_clean(argparse.Namespace(
                json=False, min_age=None, deep=False,
                yes=confirm.strip().lower() == "yes"))
        elif choice == "8":
            _cmd_sweep(argparse.Namespace(json=False, min_age=None, yes=False))
        elif choice == "9":
            print("Deep clean removes browser caches, crash dumps, logs and "
                  "trash older than 1 day.")
            confirm = input("Proceed? Type 'yes' to confirm: ")
            _cmd_clean(argparse.Namespace(
                json=False, min_age=None, deep=True,
                yes=confirm.strip().lower() == "yes"))
        elif choice == "b":
            _cmd_large(argparse.Namespace(
                json=False, path=None, top=25, min_size=100.0, delete=True))
        elif choice == "p":
            _cmd_programs(argparse.Namespace(json=False))
        elif choice == "r":
            confirm = input("Empty the Recycle Bin / Trash? Type 'yes': ")
            if confirm.strip().lower() == "yes":
                _cmd_recycle(argparse.Namespace(empty=True))
            else:
                print("Cancelled.")
        else:
            print(f"Unknown choice: {choice!r}")
        try:
            input("\nPress Enter to return to the menu...")
        except EOFError:
            return 0
        print()


def build_parser() -> argparse.ArgumentParser:
    # shared --json flag, attached to every subcommand
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--json", action="store_true",
                        help="Output machine-readable JSON instead of text.")

    p = argparse.ArgumentParser(
        prog="computa",
        description="Scan your computer and get help making it run faster.",
    )
    p.add_argument("--version", action="version",
                   version=f"computa {__version__}")
    sub = p.add_subparsers(dest="command")

    s = sub.add_parser("scan", parents=[common],
                       help="Show a full system health snapshot.")
    s.add_argument("--fast", action="store_true",
                   help="Skip per-process scan (quicker, no ~0.5s sample).")
    s.add_argument("--no-advice", dest="advice", action="store_false",
                   help="Don't append recommendations after the snapshot.")
    s.add_argument("--no-save", dest="save", action="store_false",
                   help="Don't save this scan as the baseline for `computa diff`.")
    s.set_defaults(func=_cmd_scan, advice=True, save=True)

    d = sub.add_parser("doctor", parents=[common],
                       help="Diagnose issues and print prioritized advice.")
    d.set_defaults(func=_cmd_doctor)

    t = sub.add_parser("top", parents=[common],
                       help="Show what's using CPU/memory right now.")
    t.set_defaults(func=_cmd_top)

    u = sub.add_parser("startup", parents=[common],
                       help="List or toggle programs that launch at login/boot.")
    grp = u.add_mutually_exclusive_group()
    grp.add_argument("--enable", metavar="NAME",
                     help="Enable the named startup program.")
    grp.add_argument("--disable", metavar="NAME",
                     help="Disable the named startup program (reversible).")
    u.set_defaults(func=_cmd_startup)

    df = sub.add_parser("diff", parents=[common],
                        help="Show what changed since your last scan.")
    df.add_argument("--no-save", dest="save", action="store_false",
                    help="Compare but don't update the saved baseline.")
    df.set_defaults(func=_cmd_diff, save=True)

    c = sub.add_parser("clean", parents=[common],
                       help="Reclaim cache/temp space (dry-run unless --yes).")
    c.add_argument("--min-age", type=float, default=None,
                   help="Only remove files older than N days "
                        "(default: 7, or 1 with --deep).")
    c.add_argument("--deep", action="store_true",
                   help="Fuller sweep: browser caches, crash dumps, logs, trash.")
    c.add_argument("--yes", action="store_true",
                   help="Actually delete (default is a safe preview).")
    c.set_defaults(func=_cmd_clean)

    lg = sub.add_parser("large", parents=[common],
                        help="Find the largest files eating disk space.")
    lg.add_argument("path", nargs="?", default=None,
                    help="Folder to scan (default: your home folder).")
    lg.add_argument("--top", type=int, default=25,
                    help="How many of the biggest files to show (default: 25).")
    lg.add_argument("--min-size", type=float, default=100.0,
                    help="Ignore files smaller than N megabytes (default: 100).")
    lg.add_argument("--delete", action="store_true",
                    help="After listing, interactively delete chosen files "
                         "(asks for an explicit DELETE confirmation).")
    lg.set_defaults(func=_cmd_large)

    pr = sub.add_parser("programs", parents=[common],
                        help="List installed programs by size (Windows).")
    pr.set_defaults(func=_cmd_programs)

    rc = sub.add_parser("recycle", parents=[common],
                        help="Empty the Recycle Bin / Trash.")
    rc.add_argument("--empty", action="store_true",
                    help="Actually empty it (otherwise just prints how).")
    rc.set_defaults(func=_cmd_recycle)

    sw = sub.add_parser("sweep", parents=[common],
                        help="Full sweep: scan + diagnose + deep-clean preview.")
    sw.add_argument("--min-age", type=float, default=None,
                    help="Only remove files older than N days (default: 1).")
    sw.add_argument("--yes", action="store_true",
                    help="Actually delete the deep-clean items (default preview).")
    sw.set_defaults(func=_cmd_sweep, deep=True)

    m = sub.add_parser("menu",
                       help="Interactive menu (no commands to remember).")
    m.set_defaults(func=_cmd_menu)

    return p


def main(argv=None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not getattr(args, "command", None):
        args = parser.parse_args(["scan"])
    try:
        return args.func(args)
    except KeyboardInterrupt:  # pragma: no cover
        print("\nInterrupted.", file=sys.stderr)
        return 130


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
