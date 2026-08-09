"""StyleProfile: styles should tune and gate the rules per fighting style.

The point of the profiles is that "correct" is style-dependent, so a rule that
fires under the default high guard should stay quiet when the style says the
behaviour is intentional — and vice versa.
"""

from boxing_coach.adapters import PoseOnlyAdapter
from boxing_coach.analysis.context import AnalysisContext
from boxing_coach.analysis.rules import (
    FootworkRule,
    HandsUpRule,
    HeadMovementRule,
)
from boxing_coach.analysis.style_profiles import all_profiles, profile_for
from boxing_coach.domain.drill import DrillContext
from boxing_coach.domain.style import Style

import fixtures


def _ctx(sequence, style: Style) -> AnalysisContext:
    drill = DrillContext(style=style)
    return AnalysisContext(sequence=sequence, drill=drill, style_profile=profile_for(style))


def _faults(observations):
    return [o for o in observations if o.severity.is_fault]


# -- registry --------------------------------------------------------------

def test_every_style_has_a_profile():
    profiles = all_profiles()
    for style in Style:
        assert style in profiles
        assert profiles[style].style is style


def test_high_guard_is_the_neutral_default():
    profile = profile_for(Style.HIGH_GUARD)
    assert profile.disabled_rules == frozenset()
    assert dict(profile.rule_configs) == {}


# -- Philly shell: lead hand allowed low, rear hand still judged -----------

def test_philly_shell_ignores_low_lead_hand():
    # Default high guard flags a hanging lead hand...
    assert _faults(HandsUpRule().evaluate(_ctx(fixtures.hands_down_idle(), Style.HIGH_GUARD)))
    # ...but the Philly shell keeps its lead hand low on purpose.
    assert not _faults(HandsUpRule().evaluate(_ctx(fixtures.hands_down_idle(), Style.PHILLY_SHELL)))


def test_philly_shell_still_flags_low_rear_hand():
    faults = _faults(HandsUpRule().evaluate(_ctx(fixtures.rear_hand_down_idle(), Style.PHILLY_SHELL)))
    assert len(faults) == 1  # the rear hand is not exempt


# -- Out-boxer: head movement is off, footwork bar is higher --------------

def test_out_boxer_disables_head_movement_rule():
    assert not profile_for(Style.OUT_BOXER).enables("head_movement")
    # The static-head fault the default would raise is suppressed end to end.
    analysis = PoseOnlyAdapter().analyse(fixtures.static_head(), DrillContext(style=Style.OUT_BOXER))
    assert all(c.category.value != "head_movement" for c in analysis.correction_priorities)


def test_out_boxer_holds_footwork_to_a_higher_bar():
    # A gentle drift satisfies the default footwork rule...
    assert not _faults(FootworkRule().evaluate(_ctx(fixtures.drifting_feet(), Style.HIGH_GUARD)))
    # ...isn't enough for an out-boxer, who must move more.
    assert _faults(FootworkRule().evaluate(_ctx(fixtures.drifting_feet(), Style.OUT_BOXER)))


# -- Peek-a-boo: demands more head movement -------------------------------

def test_peek_a_boo_demands_more_head_movement():
    # A little slipping passes the default head-movement bar...
    assert not _faults(HeadMovementRule().evaluate(_ctx(fixtures.slight_slipping_head(), Style.HIGH_GUARD)))
    # ...but peek-a-boo wants more, so the same clip is flagged.
    assert _faults(HeadMovementRule().evaluate(_ctx(fixtures.slight_slipping_head(), Style.PEEK_A_BOO)))
    # ...while a genuinely bobbing fighter still satisfies peek-a-boo.
    assert not _faults(HeadMovementRule().evaluate(_ctx(fixtures.slipping_head(), Style.PEEK_A_BOO)))
