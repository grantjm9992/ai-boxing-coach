"""Round-level descriptive features — the raw material for national schools."""

from boxing_coach.analysis.context import AnalysisContext
from boxing_coach.domain.drill import DrillContext

import fixtures


def _profile(sequence):
    return AnalysisContext(sequence=sequence, drill=DrillContext()).round_profile


# -- output rate -----------------------------------------------------------

def test_output_rate_counts_punches_per_minute():
    assert _profile(fixtures.clean_jab()).output_per_min > 0
    assert _profile(fixtures.static_feet()).output_per_min == 0.0


# -- mobility --------------------------------------------------------------

def test_mobility_orders_by_foot_travel():
    still = _profile(fixtures.static_feet()).mobility
    gentle = _profile(fixtures.drifting_feet()).mobility
    busy = _profile(fixtures.moving_feet()).mobility
    assert still == 0.0 < gentle < busy


# -- ground coverage: ranging vs bouncing on the spot ----------------------

def test_ground_coverage_distinguishes_ranging_from_bouncing():
    # Steady drift covers ground (net ≈ gross)...
    assert _profile(fixtures.drifting_feet()).ground_coverage > 0.8
    # ...bouncing in place returns to the start (net ≈ 0).
    assert _profile(fixtures.moving_feet()).ground_coverage < 0.2


# -- posture ---------------------------------------------------------------

def test_torso_lean_detects_a_crouched_stance():
    assert _profile(fixtures.crouched_stance()).torso_lean_deg > 20
    assert _profile(fixtures.clean_jab()).torso_lean_deg < 5  # upright


# -- body work -------------------------------------------------------------

def test_body_shot_ratio_flags_low_finishing_punches():
    assert _profile(fixtures.body_hook()).body_shot_ratio == 1.0
    assert _profile(fixtures.lead_hook()).body_shot_ratio == 0.0  # head-height hook


def test_body_shot_ratio_uses_mid_torso_not_the_shoulder_line():
    # A hook finishing below the shoulder but above mid-torso is NOT a body shot
    # — this is the false positive that inflated the ratio on real footage.
    assert _profile(fixtures.chest_high_hook()).body_shot_ratio == 0.0
