"""The built-in StyleProfiles — how each fighting Style tunes the rules.

Like the rule thresholds themselves, these are **starting points, not gospel**:
the same "calibrate against your own footage" caveat applies. Adding a style is
a `Style` enum member plus one entry here — nothing else changes.

What each profile encodes (and why):

- **High guard** — the neutral default. Every rule on, default thresholds.
- **Philly shell** — the lead hand rides low across the body on purpose and the
  rear hand stays high. So the guard checks (`hands_up`, `guard_return`) judge
  the rear hand only; flagging the low lead hand would be wrong advice.
- **Peek-a-boo** — hands high by the cheeks with constant head movement. Held to
  a *higher* head-movement bar than the default before it counts as enough.
- **Out-boxer** — defends with range and footwork, not head slips. Head-movement
  is switched off (planting on the centre line isn't the fault it is for a
  pressure fighter), and footwork is held to a higher bar since movement is the
  whole game.
"""

from __future__ import annotations

from dataclasses import replace

from ..domain.school import School
from ..domain.style import Style
from .rules.footwork import FootworkConfig
from .rules.guard_return import GuardReturnConfig
from .rules.hands_up import HandsUpConfig
from .rules.head_movement import HeadMovementConfig
from .style import DEFAULT_STYLE_PROFILE, StyleProfile

_PROFILES: dict[Style, StyleProfile] = {
    Style.HIGH_GUARD: DEFAULT_STYLE_PROFILE,
    Style.PHILLY_SHELL: StyleProfile(
        style=Style.PHILLY_SHELL,
        label="Philly shell",
        summary=(
            "Lead hand low across the body, rear hand high, chin tucked behind "
            "the lead shoulder. The lead hand is meant to be low, so the guard "
            "checks apply to the rear hand only."
        ),
        rule_configs={
            "hands_up": HandsUpConfig(check_lead=False),
            "guard_return": GuardReturnConfig(check_lead=False),
        },
    ),
    Style.PEEK_A_BOO: StyleProfile(
        style=Style.PEEK_A_BOO,
        label="Peek-a-boo",
        summary=(
            "Hands high by the cheeks with constant head movement. Demands more "
            "head movement than the default before it's satisfied."
        ),
        rule_configs={
            "head_movement": HeadMovementConfig(min_lateral_std=0.15),
        },
    ),
    Style.OUT_BOXER: StyleProfile(
        style=Style.OUT_BOXER,
        label="Out-boxer",
        summary=(
            "Defends with range and footwork rather than head movement. The "
            "head-movement rule is off; footwork is held to a higher bar."
        ),
        disabled_rules=frozenset({"head_movement"}),
        rule_configs={
            "footwork": FootworkConfig(min_travel_per_second=0.30),
        },
    ),
}


def profile_for(style: Style) -> StyleProfile:
    """The StyleProfile for `style` (the neutral default if unmapped)."""
    return _PROFILES.get(style, DEFAULT_STYLE_PROFILE)


def all_profiles() -> dict[Style, StyleProfile]:
    """Every built-in profile, keyed by style."""
    return dict(_PROFILES)


# A national School tunes the *frame* guard rules only where its game changes
# what "correct" means; everything else stays at the guard Style's config. Each
# entry is rule_id -> field overrides layered onto that rule's config.
#
# Soviet: an in-and-out range game carries the hands off the textbook chin and
# resets distance by stepping out, so a low hand is judged against the fighter's
# own settled carriage (not the shoulder line) and forgiven while the feet are
# translating — the same spirit as guard_return already judging return to the
# launch position rather than an absolute cheek.
_SCHOOL_RULE_OVERRIDES: dict[School, dict[str, dict[str, object]]] = {
    School.SOVIET: {
        "hands_up": {"relative_to_baseline": True, "excuse_while_moving": True},
        "guard_return": {"excuse_while_moving": True},
    },
}

# The rule's own default, layered under a School override when the Style set no
# config for that rule itself.
_DEFAULT_RULE_CONFIGS: dict[str, object] = {
    "hands_up": HandsUpConfig(),
    "guard_return": GuardReturnConfig(),
}


def resolve_profile(style: Style, school: School | None = None) -> StyleProfile:
    """The StyleProfile for `style`, with any `school` guard-rule tuning layered on.

    Style sets the base rule configs; a School (Soviet, ...) then adjusts the
    guard rules whose notion of "correct" its game changes. Overrides are applied
    field-wise, so a field the Style set (e.g. a Philly shell's check_lead=False)
    survives unless the School overrides that same field.
    """
    profile = profile_for(style)
    overrides = _SCHOOL_RULE_OVERRIDES.get(school) if school is not None else None
    if not overrides:
        return profile
    configs = dict(profile.rule_configs)
    for rule_id, changes in overrides.items():
        base = configs.get(rule_id) or _DEFAULT_RULE_CONFIGS[rule_id]
        configs[rule_id] = replace(base, **changes)
    return replace(profile, rule_configs=configs)
