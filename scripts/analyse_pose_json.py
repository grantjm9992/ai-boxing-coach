"""Run the reference engine over a PoseSequence JSON exported from the phone.

    python scripts/analyse_pose_json.py round.pose.json --stance orthodox

This is the real calibration loop (docs/v0.5-pose-integration.md §0.35): record a
round on the phone, export its pose data (Review -> Export pose data -> AirDrop /
email — a few KB, no video), then run it here against the reference engine and
check whether the calls match what actually happened. Tune thresholds in the
rules, regenerate the goldens (`scripts/emit_golden_fixtures.py`), and the Dart
port goes red until it is brought back in step.

The phone writes exactly the wire format `golden_fixtures` defines, so the same
`sequence_from_json` loads it with no translation.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[1]
_SRC = _ROOT / "src"
if str(_SRC) not in sys.path:
    sys.path.insert(0, str(_SRC))

from boxing_coach.adapters import PoseOnlyAdapter  # noqa: E402
from boxing_coach.analysis.style_profiles import profile_for  # noqa: E402
from boxing_coach.cli import _print_report  # noqa: E402
from boxing_coach.domain.drill import DrillContext  # noqa: E402
from boxing_coach.domain.landmarks import Stance  # noqa: E402
from boxing_coach.domain.style import Style  # noqa: E402
from boxing_coach.golden_fixtures import sequence_from_json  # noqa: E402


def analyse(path: Path, drill: DrillContext):
    sequence = sequence_from_json(json.loads(path.read_text()))
    return sequence, PoseOnlyAdapter().analyse(sequence, drill)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Run the reference engine over an exported pose JSON."
    )
    parser.add_argument("pose_json", type=Path, help="path to the exported .pose.json")
    parser.add_argument("--stance", choices=["orthodox", "southpaw"], default="orthodox")
    parser.add_argument(
        "--style", choices=[s.value for s in Style], default=Style.HIGH_GUARD.value
    )
    parser.add_argument(
        "--focus", nargs="*", default=[], help="drill focus tags (empty = all rules)"
    )
    parser.add_argument("--json", action="store_true", help="emit the summary line only")
    args = parser.parse_args(argv)

    drill = DrillContext(
        stance=Stance[args.stance.upper()],
        style=Style(args.style),
        focus=frozenset(args.focus or []),
    )
    sequence, analysis = analyse(args.pose_json, drill)

    if args.json:
        print(analysis.overall_summary)
    else:
        print(f"Source: {sequence.source}  ({len(sequence)} frames, {sequence.fps:g} fps)")
        _print_report(analysis, style_label=profile_for(drill.style).label)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
