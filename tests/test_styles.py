"""StyleProfile: styles should tune and gate the rules per fighting style.

The point of the profiles is that "correct" is style-dependent, so a rule that
fires under the default high guard should stay quiet when the style says the
behaviour is intentional — and vice versa.
"""

from boxing_coach.adapters import PoseOnlyAdapter
from boxing_coach.analysis.context import AnalysisContext
from boxing_coach.analysis.rules import (
    FootworkRule,
    GuardReturnRule,
    HandsUpRule,
    HeadMovementRule,
)
from boxing_coach.analysis.rules.guard_return import GuardReturnConfig
from boxing_coach.analysis.rules.hands_up import HandsUpConfig
from boxing_coach.analysis.style_profiles import all_profiles, profile_for, resolve_profile
from boxing_coach.domain.drill import DrillContext
from boxing_coach.domain.school import School
from boxing_coach.domain.style import Style

import fixtures


def _ctx(sequence, style: Style) -> AnalysisContext:
    drill = DrillContext(style=style)
    return AnalysisContext(sequence=sequence, drill=drill, style_profile=profile_for(style))


def _soviet_ctx(sequence, style: Style = Style.HIGH_GUARD) -> AnalysisContext:
    drill = DrillContext(style=style, school=School.SOVIET)
    return AnalysisContext(sequence=sequence, drill=drill,
                           style_profile=resolve_profile(style, School.SOVIET))


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


# -- Soviet school: "low hand" judged by own carriage + in/out, not the chin --

def test_resolve_profile_layers_soviet_guard_overrides():
    profile = resolve_profile(Style.HIGH_GUARD, School.SOVIET)
    hands_up = profile.config_for("hands_up", HandsUpConfig())
    assert hands_up.relative_to_baseline and hands_up.excuse_while_moving
    guard_return = profile.config_for("guard_return", GuardReturnConfig())
    assert guard_return.excuse_while_moving


def test_resolve_profile_without_school_is_the_plain_style_profile():
    assert resolve_profile(Style.PHILLY_SHELL) is profile_for(Style.PHILLY_SHELL)


def test_soviet_overrides_preserve_style_set_fields():
    # Philly shell already sets check_lead=False on the guard rules; the Soviet
    # layer must keep that while adding its own fields on top.
    profile = resolve_profile(Style.PHILLY_SHELL, School.SOVIET)
    hands_up = profile.config_for("hands_up", HandsUpConfig())
    assert hands_up.check_lead is False           # from the style
    assert hands_up.relative_to_baseline is True   # from the school


def test_soviet_allows_a_consistently_low_carry_between_punches():
    # Default high guard nags a hand hanging low all round...
    assert _faults(HandsUpRule().evaluate(_ctx(fixtures.hands_down_idle(), Style.HIGH_GUARD)))
    # ...but the Soviet game judges "low" against the fighter's own carriage, so a
    # consistent low carry isn't read as a drop.
    assert not _faults(HandsUpRule().evaluate(_soviet_ctx(fixtures.hands_down_idle())))


def test_soviet_still_flags_a_hand_sagging_below_its_own_carriage():
    # A hand that starts at guard then sinks (feet planted) is a real drop — the
    # Soviet allowance is for a low *carry*, not a sag below it.
    assert _faults(HandsUpRule().evaluate(_soviet_ctx(fixtures.sagging_guard_idle())))


def test_soviet_excuses_a_low_hand_while_stepping_out():
    # Default: the hand ends low after the jab -> dropped-guard fault...
    assert _faults(GuardReturnRule().evaluate(_ctx(fixtures.out_step_dropped_jab(), Style.HIGH_GUARD)))
    # ...but under Soviet the feet step out through the return, so the low finish
    # is distance management, not a dropped guard.
    assert not _faults(GuardReturnRule().evaluate(_soviet_ctx(fixtures.out_step_dropped_jab())))


def test_soviet_still_flags_a_planted_dropped_guard():
    # A drop with the feet planted has no in/out to explain it -> still flagged.
    assert _faults(GuardReturnRule().evaluate(_soviet_ctx(fixtures.dropped_guard_jab())))
