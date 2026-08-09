"""Punch-type classification and how the rules use it."""

from boxing_coach.adapters import PoseOnlyAdapter
from boxing_coach.analysis.context import AnalysisContext
from boxing_coach.analysis.features import PunchDetector, compute_body_scale
from boxing_coach.analysis.rules import HipRotationRule
from boxing_coach.domain.drill import DrillContext
from boxing_coach.domain.landmarks import Side, Stance
from boxing_coach.domain.punch import PunchType, punch_name

import fixtures


def _only_punch(seq):
    scale = compute_body_scale(seq)
    punches = PunchDetector().detect(seq, scale)
    assert len(punches) == 1, f"expected one punch, got {len(punches)}"
    return punches[0]


# -- classification --------------------------------------------------------

def test_lead_straight_is_a_jab():
    p = _only_punch(fixtures.clean_jab())
    assert p.punch_type is PunchType.STRAIGHT
    assert punch_name(p.punch_type, p.side, Stance.ORTHODOX) == "jab"


def test_rear_straight_is_a_cross():
    p = _only_punch(fixtures.squared_cross())
    assert p.punch_type is PunchType.STRAIGHT
    assert punch_name(p.punch_type, p.side, Stance.ORTHODOX) == "cross"


def test_hook_is_classified_from_bent_arm_and_horizontal_travel():
    p = _only_punch(fixtures.lead_hook())
    assert p.punch_type is PunchType.HOOK
    assert punch_name(p.punch_type, p.side, Stance.ORTHODOX) == "lead hook"


def test_uppercut_is_classified_from_vertical_rise():
    p = _only_punch(fixtures.lead_uppercut())
    assert p.punch_type is PunchType.UPPERCUT
    assert punch_name(p.punch_type, p.side, Stance.ORTHODOX) == "lead uppercut"


# -- naming is stance-relative --------------------------------------------

def test_naming_flips_with_stance():
    # A right-hand straight is a cross for an orthodox fighter, a jab for a southpaw.
    assert punch_name(PunchType.STRAIGHT, Side.RIGHT, Stance.ORTHODOX) == "cross"
    assert punch_name(PunchType.STRAIGHT, Side.RIGHT, Stance.SOUTHPAW) == "jab"


# -- the rules use the type -----------------------------------------------

def test_hip_rotation_only_judges_the_rear_straight():
    # The squared cross (a straight, no rotation) is flagged...
    ctx_cross = AnalysisContext(sequence=fixtures.squared_cross(), drill=DrillContext())
    assert HipRotationRule().evaluate(ctx_cross)
    # ...but a rear hook is not judged against the straight's rotation expectation.
    ctx_hook = AnalysisContext(sequence=fixtures.rear_hook(), drill=DrillContext())
    assert HipRotationRule().evaluate(ctx_hook) == []


def test_punch_mix_is_reported_in_metrics():
    analysis = PoseOnlyAdapter().analyse(fixtures.lead_hook(), DrillContext())
    assert analysis.metrics.punch_mix == {"lead hook": 1}
