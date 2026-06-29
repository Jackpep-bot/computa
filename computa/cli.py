"""Command-line interface for computa."""
from __future__ import annotations

import argparse
import sys

from . import __version__, cleanup, recommend, report, system


def _cmd_scan(args) -> int:
    snap = system.collect(processes=not args.fast)
    print(report.format_snapshot(snap))
    if args.advice:
        print()
        print(report.format_recommendations(recommend.analyze(snap)))
    return 0


def _cmd_doctor(args) -> int:
    snap = system.collect(processes=True)
    recs = recommend.analyze(snap)
    print(report.format_recommendations(recs))
    # exit non-zero if anything critical, so it is scriptable
    return 2 if any(r.severity == recommend.CRITICAL for r in recs) else 0


def _cmd_top(args) -> int:
    snap = system.collect(processes=True)
    if not snap.have_psutil:
        print("`computa top` needs psutil for process detail. Install it with:\n"
              "  pip install psutil")
        return 1
    # Reuse the snapshot formatter but only the process-relevant parts.
    print(report.format_snapshot(snap))
    return 0


def _cmd_clean(args) -> int:
    result = cleanup.clean(min_age_days=args.min_age, apply=args.yes)
    print(report.format_clean(result, args.min_age))
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="computa",
        description="Scan your computer and get help making it run faster.",
    )
    p.add_argument("--version", action="version",
                   version=f"computa {__version__}")
    sub = p.add_subparsers(dest="command")

    s = sub.add_parser("scan", help="Show a full system health snapshot.")
    s.add_argument("--fast", action="store_true",
                   help="Skip per-process scan (quicker, no ~0.5s sample).")
    s.add_argument("--no-advice", dest="advice", action="store_false",
                   help="Don't append recommendations after the snapshot.")
    s.set_defaults(func=_cmd_scan, advice=True)

    d = sub.add_parser("doctor",
                       help="Diagnose issues and print prioritized advice.")
    d.set_defaults(func=_cmd_doctor)

    t = sub.add_parser("top", help="Show what's using CPU/memory right now.")
    t.set_defaults(func=_cmd_top)

    c = sub.add_parser("clean",
                       help="Reclaim cache/temp space (dry-run unless --yes).")
    c.add_argument("--min-age", type=float, default=7.0,
                   help="Only remove files older than N days (default: 7).")
    c.add_argument("--yes", action="store_true",
                   help="Actually delete (default is a safe preview).")
    c.set_defaults(func=_cmd_clean)

    return p


def main(argv=None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not getattr(args, "command", None):
        # default to scan when no subcommand is given
        args = parser.parse_args(["scan"])
    try:
        return args.func(args)
    except KeyboardInterrupt:  # pragma: no cover
        print("\nInterrupted.", file=sys.stderr)
        return 130


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
