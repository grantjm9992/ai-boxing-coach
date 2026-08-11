"""The calibration script loads an exported pose JSON and runs the engine."""

from __future__ import annotations

import importlib.util
from pathlib import Path

from boxing_coach.domain.drill import DrillContext

_ROOT = Path(__file__).resolve().parents[1]


def _load_script():
    path = _ROOT / "scripts" / "analyse_pose_json.py"
    spec = importlib.util.spec_from_file_location("analyse_pose_json", path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_runs_over_an_exported_pose_json() -> None:
    script = _load_script()
    # The golden input.json is exactly the wire format the phone exports.
    fixture = _ROOT / "fixtures" / "golden" / "dropped_guard_jab" / "input.json"

    sequence, analysis = script.analyse(fixture, DrillContext())

    assert len(sequence) > 0
    # The dropped-guard round should surface a defence correction.
    assert any(c.category.value == "defence" for c in analysis.correction_priorities)
    assert "drops" in analysis.overall_summary
