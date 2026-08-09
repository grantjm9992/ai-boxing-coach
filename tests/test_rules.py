"""Each rule should fire on the bad fixture and stay quiet on the good one."""

from boxing_coach.analysis.context import AnalysisContext
from boxing_coach.analysis.rules import (
    FootworkRule,
    GuardReturnRule,
    HandsUpRule,
    HeadMovementRule,
    HipRotationRule,
)
from boxing_coach.domain.analysis import Severity, SkillCategory
from boxing_coach.domain.drill import DrillContext

import fixtures


def _ctx(sequence, **drill_kwargs) -> AnalysisContext:
    return AnalysisContext(sequence=sequence, drill=DrillContext(**drill_kwargs))


def _faults(observations):
    return [o for o in observations if o.severity.is_fault]


# -- guard return ----------------------------------------------------------

def test_guard_return_flags_dropped_hand():
    obs = GuardReturnRule().evaluate(_ctx(fixtures.dropped_guard_jab()))
    faults = _faults(obs)
    assert len(faults) == 1
    assert faults[0].category is SkillCategory.DEFENCE
    assert faults[0].severity is Severity.MODERATE
    assert "drop" in faults[0].coaching_text.lower()
    assert faults[0].timestamp_ms is not None


def test_guard_return_clean_jab_has_no_fault():
    obs = GuardReturnRule().evaluate(_ctx(fixtures.clean_jab()))
    assert _faults(obs) == []
    # ...and it should say something positive.
    assert any(o.severity is Severity.POSITIVE for o in obs)


# -- hands up --------------------------------------------------------------

def test_hands_up_flags_low_hand():
    obs = HandsUpRule().evaluate(_ctx(fixtures.hands_down_idle()))
    faults = _faults(obs)
    assert len(faults) == 1
    assert faults[0].category is SkillCategory.DEFENCE


def test_hands_up_quiet_when_guard_held():
    obs = HandsUpRule().evaluate(_ctx(fixtures.clean_jab()))
    assert _faults(obs) == []


# -- footwork --------------------------------------------------------------

def test_footwork_flags_rooted():
    obs = FootworkRule().evaluate(_ctx(fixtures.static_feet()))
    faults = _faults(obs)
    assert len(faults) == 1
    assert faults[0].category is SkillCategory.FOOTWORK


def test_footwork_positive_when_moving():
    obs = FootworkRule().evaluate(_ctx(fixtures.moving_feet()))
    assert _faults(obs) == []
    assert any(o.severity is Severity.POSITIVE for o in obs)


# -- head movement ---------------------------------------------------------

def test_head_movement_flags_static_head():
    obs = HeadMovementRule().evaluate(_ctx(fixtures.static_head()))
    faults = _faults(obs)
    assert len(faults) == 1
    assert faults[0].category is SkillCategory.HEAD_MOVEMENT


def test_head_movement_quiet_when_slipping():
    obs = HeadMovementRule().evaluate(_ctx(fixtures.slipping_head()))
    assert _faults(obs) == []


# -- hip rotation ----------------------------------------------------------

def test_hip_rotation_flags_squared_cross():
    obs = HipRotationRule().evaluate(_ctx(fixtures.squared_cross()))
    faults = _faults(obs)
    assert len(faults) == 1
    assert faults[0].category is SkillCategory.STRAIGHT


def test_hip_rotation_quiet_when_rotated():
    obs = HipRotationRule().evaluate(_ctx(fixtures.rotated_cross()))
    assert _faults(obs) == []


# -- focus gating ----------------------------------------------------------

def test_rule_skipped_when_out_of_focus():
    # footwork rule shouldn't apply to a pure jab drill
    ctx = _ctx(fixtures.static_feet(), focus=frozenset({"jab"}))
    assert not FootworkRule().applies_to(ctx)
    # ...but does when unfocused
    assert FootworkRule().applies_to(_ctx(fixtures.static_feet()))
