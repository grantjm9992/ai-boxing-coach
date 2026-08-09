"""Punch detection and body-scale feature tests."""

from boxing_coach.analysis.features import PunchDetector, compute_body_scale
from boxing_coach.domain.landmarks import Side

import fixtures


def test_body_scale_is_torso_length():
    scale = compute_body_scale(fixtures.clean_jab())
    # Neutral pose: shoulder-center y=0.40, hip-center y=0.60 -> 0.20.
    assert abs(scale - 0.20) < 1e-6


def test_detects_single_lead_jab():
    seq = fixtures.clean_jab()
    scale = compute_body_scale(seq)
    punches = PunchDetector().detect(seq, scale)
    assert len(punches) == 1
    assert punches[0].side is Side.LEFT
    assert punches[0].peak_reach > 0.9  # clearly extended


def test_no_punches_when_static():
    seq = fixtures.static_feet()
    scale = compute_body_scale(seq)
    assert PunchDetector().detect(seq, scale) == []


def test_detects_rear_cross():
    seq = fixtures.squared_cross()
    scale = compute_body_scale(seq)
    punches = PunchDetector().detect(seq, scale)
    assert len(punches) == 1
    assert punches[0].side is Side.RIGHT
