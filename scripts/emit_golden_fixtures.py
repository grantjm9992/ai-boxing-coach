"""Emit the cross-language golden fixtures.

    python scripts/emit_golden_fixtures.py

Writes, for each synthetic scenario in `tests/fixtures.py`, a pair
`fixtures/golden/<name>/{input.json, expected.json}`. `input.json` is the
`PoseSequence` on the wire; `expected.json` is what the reference engine derives
from it. Both the Python guard test and the Dart port read these files.

`expected.json` grows as more of the engine is ported. Today it carries
`bodyScale` (the normalisation unit every rule divides by); the rule outputs are
added as each rule lands in Dart.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[1]
_SRC = _ROOT / "src"
for path in (_SRC, _ROOT):
    if str(path) not in sys.path:
        sys.path.insert(0, str(path))

from boxing_coach.analysis.context import AnalysisContext  # noqa: E402
from boxing_coach.analysis.engine import RuleEngine  # noqa: E402
from boxing_coach.analysis.features import PunchDetector, compute_body_scale  # noqa: E402
from boxing_coach.analysis.rules import default_rules  # noqa: E402
from boxing_coach.analysis.schools import classify_school, round_feature_values  # noqa: E402
from boxing_coach.analysis.style_profiles import resolve_profile  # noqa: E402
from boxing_coach.domain.drill import DrillContext  # noqa: E402
from boxing_coach.domain.landmarks import Stance  # noqa: E402
from boxing_coach.domain.school import School  # noqa: E402
from boxing_coach.domain.style import Style  # noqa: E402
from boxing_coach.golden_fixtures import round_tripped, sequence_to_json  # noqa: E402
from tests import fixtures as fx  # noqa: E402

# Explicit registry — a stable, curated list rather than reflection, so adding a
# fixture is a deliberate act and the golden set does not shift under us.
SCENARIOS = [
    "clean_jab",
    "dropped_guard_jab",
    "hands_down_idle",
    "low_carry_jab",
    "out_step_dropped_jab",
    "sagging_guard_idle",
    "rear_hand_down_idle",
    "static_feet",
    "moving_feet",
    "drifting_feet",
    "static_head",
    "slipping_head",
    "slight_slipping_head",
    "lead_hook",
    "lead_uppercut",
    "crouched_stance",
    "body_hook",
    "chest_high_hook",
    "rear_hook",
    "rotated_cross",
    "squared_cross",
    "rotated_cross_side_view",
]

OUT_DIR = _ROOT / "fixtures" / "golden"


def _observation_json(o) -> dict:
    return {
        "ruleId": o.rule_id,
        "category": o.category.value,
        "severity": o.severity.value,
        "coachingText": o.coaching_text,
        "timestampMs": round(o.timestamp_ms, 4) if o.timestamp_ms is not None else None,
        "metrics": {k: round(v, 6) for k, v in o.metrics.items()},
        "highlight": [int(lm) for lm in o.highlight_landmarks],
    }


def _expected(sequence) -> dict:
    """What the reference engine derives from the round-tripped sequence."""
    scale = compute_body_scale(sequence)
    punches = PunchDetector().detect(sequence, scale)
    context = AnalysisContext(sequence=sequence, drill=DrillContext())
    observations = RuleEngine(default_rules()).run(context)
    features = round_feature_values(context.round_profile, context.punches, Stance.ORTHODOX)
    ranking = classify_school(features)
    return {
        "bodyScale": scale,
        "punches": [
            {
                "side": p.side.name.lower(),
                "startIndex": p.start_index,
                "peakIndex": p.peak_index,
                "endIndex": p.end_index,
                "peakReach": round(p.peak_reach, 6),
                "punchType": p.punch_type.value,
            }
            for p in punches
        ],
        "observations": [_observation_json(o) for o in observations],
        "roundProfile": context.round_profile.as_dict(),
        "featureValues": {k: round(v, 6) for k, v in features.items()},
        "schoolRanking": [[s.value, round(score, 6)] for s, score in ranking],
    }


# Style / school cases: each exercises the profile plumbing (a gated rule, a
# retuned threshold, a school override or school_adherence) on a chosen fixture.
STYLE_CASES = [
    {"fixture": "sagging_guard_idle", "style": "philly_shell"},
    {"fixture": "rear_hand_down_idle", "style": "philly_shell"},
    {"fixture": "slight_slipping_head", "style": "peek_a_boo"},
    {"fixture": "slight_slipping_head", "style": "out_boxer"},
    {"fixture": "drifting_feet", "style": "out_boxer"},
    {"fixture": "out_step_dropped_jab", "school": "soviet"},
    {"fixture": "clean_jab", "school": "mexican"},
]


def _style_case_result(case: dict) -> dict:
    sequence = round_tripped(getattr(fx, case["fixture"])())
    stance = Stance[case.get("stance", "orthodox").upper()]
    style = Style(case.get("style", "high_guard"))
    school = School(case["school"]) if case.get("school") else None
    drill = DrillContext(stance=stance, style=style, school=school, focus=frozenset())
    context = AnalysisContext(
        sequence=sequence, drill=drill, style_profile=resolve_profile(style, school)
    )
    observations = RuleEngine(default_rules()).run(context)
    return {
        "fixture": case["fixture"],
        "stance": stance.name.lower(),
        "style": style.value,
        "school": school.value if school else None,
        "observations": [_observation_json(o) for o in observations],
    }


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for name in SCENARIOS:
        builder = getattr(fx, name)
        sequence = builder()
        scenario_dir = OUT_DIR / name
        scenario_dir.mkdir(parents=True, exist_ok=True)
        (scenario_dir / "input.json").write_text(
            json.dumps(sequence_to_json(sequence), indent=2) + "\n"
        )
        (scenario_dir / "expected.json").write_text(
            json.dumps(_expected(round_tripped(sequence)), indent=2) + "\n"
        )
    (OUT_DIR / "_style_cases.json").write_text(
        json.dumps({"cases": [_style_case_result(c) for c in STYLE_CASES]}, indent=2)
        + "\n"
    )
    print(
        f"Wrote {len(SCENARIOS)} golden fixtures + {len(STYLE_CASES)} style cases "
        f"to {OUT_DIR.relative_to(_ROOT)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
