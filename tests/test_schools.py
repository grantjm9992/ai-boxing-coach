"""National school profiles: classification and coaching-toward-a-school."""

from boxing_coach.adapters import PoseOnlyAdapter
from boxing_coach.analysis.schools import all_profiles, classify_school, profile_for
from boxing_coach.domain.drill import DrillContext
from boxing_coach.domain.school import School

import fixtures


def _school_notes(analysis):
    return [o for o in analysis.specific_observations if o.rule_id == "school_adherence"]


# -- registry & scoring (pure) --------------------------------------------

def test_every_school_has_a_profile_and_is_classified():
    assert set(all_profiles()) == set(School)
    ranked = classify_school({})
    assert {s for s, _ in ranked} == set(School)


def test_match_score_and_unmet_are_consistent():
    profile = profile_for(School.MEXICAN)  # wants high output, body work, crouch
    good = {"output_per_min": 60, "body_shot_ratio": 0.4, "torso_lean_deg": 20}
    poor = {"output_per_min": 5, "body_shot_ratio": 0.0, "torso_lean_deg": 0}
    assert profile.match_score(good) == 1.0
    assert profile.unmet(good) == []
    assert profile.match_score(poor) == 0.0
    assert len(profile.unmet(poor)) == 3


def test_classify_ranks_the_matching_school_first():
    # Upright, jab-heavy, head-hunting, not very mobile -> European.
    values = {
        "torso_lean_deg": 5, "jab_ratio": 0.8, "body_shot_ratio": 0.05,
        "output_per_min": 20, "mobility": 0.1, "ground_coverage": 0.1, "punch_variety": 1,
    }
    assert classify_school(values)[0][0] is School.EUROPEAN


def test_jab_led_mobile_round_leans_soviet_not_american():
    # A busy, mobile, jab-led, head-hunting round (a technical boxer). Because
    # it's jab-led it must NOT read as American (which turns over combinations),
    # and it should top out on Soviet rather than winning by American's low bar.
    values = {
        "output_per_min": 120, "mobility": 2.45, "ground_coverage": 0.04,
        "torso_lean_deg": 15.7, "body_shot_ratio": 0.0, "jab_ratio": 0.54, "punch_variety": 3,
    }
    ranked = classify_school(values)
    assert ranked[0][0] is School.SOVIET
    top_score = ranked[0][1]
    american = dict(ranked)[School.AMERICAN]
    assert american < top_score  # jab-led => not the American catch-all


# -- adherence rule --------------------------------------------------------

def test_no_school_no_school_feedback():
    analysis = PoseOnlyAdapter().analyse(fixtures.clean_jab(), DrillContext())  # school=None
    assert _school_notes(analysis) == []


def test_school_adherence_coaches_toward_the_chosen_game():
    # A single head jab, planted and upright, is not a Mexican round.
    analysis = PoseOnlyAdapter().analyse(fixtures.clean_jab(), DrillContext(school=School.MEXICAN))
    notes = _school_notes(analysis)
    assert notes
    assert any("body" in o.coaching_text.lower() for o in notes)  # told to go downstairs
