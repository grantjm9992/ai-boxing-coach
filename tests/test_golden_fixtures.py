"""The Python half of the cross-language golden contract.

For every `fixtures/golden/<name>/` this loads `input.json`, runs the reference
engine, and asserts it still produces `expected.json`. The Dart suite reads the
same files and asserts the same. If a threshold moves, regenerate with
`python scripts/emit_golden_fixtures.py`; this test then documents the new
expectation and the Dart suite goes red until the port catches up.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from boxing_coach.analysis.context import AnalysisContext
from boxing_coach.analysis.features import PunchDetector, compute_body_scale
from boxing_coach.analysis.rules.guard_return import GuardReturnRule
from boxing_coach.domain.drill import DrillContext
from boxing_coach.golden_fixtures import sequence_from_json

GOLDEN_DIR = Path(__file__).resolve().parents[1] / "fixtures" / "golden"

TOLERANCE = 1e-9


def _scenarios() -> list[str]:
    if not GOLDEN_DIR.exists():
        return []
    return sorted(p.name for p in GOLDEN_DIR.iterdir() if (p / "input.json").exists())


def test_golden_fixtures_exist() -> None:
    assert _scenarios(), (
        "no golden fixtures — run `python scripts/emit_golden_fixtures.py`"
    )


@pytest.mark.parametrize("name", _scenarios())
def test_body_scale_matches_golden(name: str) -> None:
    scenario = GOLDEN_DIR / name
    sequence = sequence_from_json(json.loads((scenario / "input.json").read_text()))
    expected = json.loads((scenario / "expected.json").read_text())

    assert compute_body_scale(sequence) == pytest.approx(
        expected["bodyScale"], abs=TOLERANCE
    )


@pytest.mark.parametrize("name", _scenarios())
def test_punches_match_golden(name: str) -> None:
    scenario = GOLDEN_DIR / name
    sequence = sequence_from_json(json.loads((scenario / "input.json").read_text()))
    expected = json.loads((scenario / "expected.json").read_text())

    scale = compute_body_scale(sequence)
    punches = PunchDetector().detect(sequence, scale)
    got = [
        {
            "side": p.side.name.lower(),
            "startIndex": p.start_index,
            "peakIndex": p.peak_index,
            "endIndex": p.end_index,
            "punchType": p.punch_type.value,
        }
        for p in punches
    ]
    want = [{k: e[k] for k in ("side", "startIndex", "peakIndex", "endIndex", "punchType")} for e in expected["punches"]]
    assert got == want


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


@pytest.mark.parametrize("name", _scenarios())
def test_guard_return_matches_golden(name: str) -> None:
    scenario = GOLDEN_DIR / name
    sequence = sequence_from_json(json.loads((scenario / "input.json").read_text()))
    expected = json.loads((scenario / "expected.json").read_text())

    context = AnalysisContext(sequence=sequence, drill=DrillContext())
    got = [_observation_json(o) for o in GuardReturnRule().evaluate(context)]
    assert got == expected.get("guardReturn", [])

