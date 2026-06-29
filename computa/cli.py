"""Command-line interface for computa."""
from __future__ import annotations

import argparse
import json
import sys

from . import (__version__, cleanup, history, recommend, report, serialize,
               startup, system)


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


def _cmd_clean(args) -> int:
    result = cleanup.clean(min_age_days=args.min_age, apply=args.yes)
    if getattr(args, "json", False):
        _print_json(serialize.clean_to_dict(result))
    else:
        print(report.format_clean(result, args.min_age))
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
  q) Quit
"""


def _cmd_menu(args) -> int:
    while True:
        print(_MENU)
        try:
            choice = input("Enter choice: ").strip().lower()
        except EOFError:
            return 0
        if choice in ("q", "quit", "exit", ""):
            return 0
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
                json=False, min_age=7.0, yes=confirm.strip().lower() == "yes"))
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
    c.add_argument("--min-age", type=float, default=7.0,
                   help="Only remove files older than N days (default: 7).")
    c.add_argument("--yes", action="store_true",
                   help="Actually delete (default is a safe preview).")
    c.set_defaults(func=_cmd_clean)

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
