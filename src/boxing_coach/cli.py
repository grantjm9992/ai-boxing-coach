"""Command-line entry point: analyse one shadow-boxing video.

    python -m boxing_coach.cli shadow.mp4 --stance orthodox --focus jab defence

Prints a human-readable report by default, or `--json` for the structured
`RoundAnalysis` you'd persist. This is the validation loop: record yourself,
run it, check whether the observations match what you actually did.
"""

from __future__ import annotations

import argparse
import dataclasses
import json
import sys

from .adapters import PoseOnlyAdapter
from .domain.analysis import RoundAnalysis
from .domain.drill import DrillContext
from .domain.landmarks import Stance
from .domain.style import Style
from .pipeline import AnalysisPipeline


def _build_drill(args: argparse.Namespace) -> DrillContext:
    return DrillContext(
        stance=Stance[args.stance.upper()],
        style=Style(args.style),
        focus=frozenset(args.focus or []),
        notes=args.notes or "",
    )


def _to_dict(analysis: RoundAnalysis) -> dict:
    def convert(value):
        if dataclasses.is_dataclass(value) and not isinstance(value, type):
            return {k: convert(v) for k, v in dataclasses.asdict(value).items()}
        if isinstance(value, (list, tuple)):
            return [convert(v) for v in value]
        if hasattr(value, "value"):  # Enum
            return value.value
        return value

    return convert(analysis)


def _print_report(analysis: RoundAnalysis, style_label: str | None = None) -> None:
    print("=" * 60)
    print("ROUND ANALYSIS")
    print("=" * 60)
    if style_label:
        print(f"Style: {style_label}")
    print(analysis.overall_summary)
    print()

    m = analysis.metrics
    print(f"Punches thrown: {m.punches_thrown}")
    if m.punch_mix:
        mix = ", ".join(f"{name} x{count}" for name, count in m.punch_mix.items())
        print(f"Punch mix: {mix}")
    if m.guard_return_rate is not None:
        print(f"Guard return rate: {m.guard_return_rate:.0%}")
    print()

    if analysis.correction_priorities:
        print("Corrections (priority order):")
        for c in analysis.correction_priorities:
            when = f"  @ {c.example_timestamp_ms/1000:.1f}s" if c.example_timestamp_ms else ""
            print(f"  {c.priority}. [{c.category.value}] {c.description}{when}")
            if c.suggested_drill:
                print(f"     drill: {c.suggested_drill}")
            if c.still_path:
                print(f"     still: {c.still_path}")
        print()

    if analysis.positive_notes:
        print("Doing well:")
        for note in analysis.positive_notes:
            print(f"  + {note}")
        print()

    if analysis.flagged_moments:
        print("Moments to review:")
        for f in analysis.flagged_moments:
            print(f"  {f.timestamp_ms/1000:5.1f}s  [{f.severity.value}]  {f.reason}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Analyse a shadow-boxing video.")
    parser.add_argument("video", help="path to the video file")
    parser.add_argument(
        "--stance", choices=["orthodox", "southpaw"], default="orthodox"
    )
    parser.add_argument(
        "--style", choices=[s.value for s in Style], default=Style.HIGH_GUARD.value,
        help="fighting style — tunes/gates the rules (e.g. philly_shell keeps the lead hand low)",
    )
    parser.add_argument(
        "--focus", nargs="*", default=[],
        help="drill focus tags, e.g. jab defence footwork (empty = all rules)",
    )
    parser.add_argument("--notes", default="")
    parser.add_argument("--json", action="store_true", help="emit JSON instead of a report")
    parser.add_argument(
        "--sample-every-ms", type=float, default=40.0,
        help="min spacing between analysed frames",
    )
    parser.add_argument(
        "--stills", metavar="DIR", default=None,
        help="write an annotated still (skeleton + highlighted fault) per correction to DIR",
    )
    args = parser.parse_args(argv)

    # Import the estimator lazily so --help and JSON schema work without mediapipe.
    from .pose_estimation import load_mediapipe_estimator

    estimator = load_mediapipe_estimator(sample_every_ms=args.sample_every_ms)
    pipeline = AnalysisPipeline(estimator, PoseOnlyAdapter())

    drill = _build_drill(args)
    sequence = pipeline.estimate(args.video)
    analysis = pipeline.analyse_sequence(sequence, drill)

    if args.stills:
        from .rendering import StillRenderer

        analysis.correction_priorities = StillRenderer().render(
            args.video, sequence, analysis.correction_priorities, args.stills
        )

    if args.json:
        json.dump(_to_dict(analysis), sys.stdout, indent=2)
        sys.stdout.write("\n")
    else:
        from .analysis.style_profiles import profile_for

        _print_report(analysis, style_label=profile_for(drill.style).label)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
