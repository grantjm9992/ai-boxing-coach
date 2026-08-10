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

from boxing_coach.analysis.features import compute_body_scale
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
