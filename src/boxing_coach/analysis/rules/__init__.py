"""The coach rule library.

Adding a rule: write a `Rule` subclass in this package and add it to
`default_rules()`. Nothing else in the system needs to change.

The five starter rules map onto the spec's "Detectable in v1" list:
    guard_return   -> return to guard after punching
    hands_up       -> guard position between punches
    footwork       -> basic footwork / rooted detection
    head_movement  -> head-movement presence
    hip_rotation   -> stance/power (front-view proxy; see its docstring)
"""

from __future__ import annotations

from ..rule import Rule
from .footwork import FootworkRule
from .guard_return import GuardReturnRule
from .hands_up import HandsUpRule
from .head_movement import HeadMovementRule
from .hip_rotation import HipRotationRule
from .school_adherence import SchoolAdherenceRule

__all__ = [
    "FootworkRule",
    "GuardReturnRule",
    "HandsUpRule",
    "HeadMovementRule",
    "HipRotationRule",
    "SchoolAdherenceRule",
    "default_rules",
]


def default_rules() -> list[Rule]:
    """The starter rule set. Order is irrelevant — the engine sorts output."""
    return [
        GuardReturnRule(),
        HandsUpRule(),
        FootworkRule(),
        HeadMovementRule(),
        HipRotationRule(),
        SchoolAdherenceRule(),
    ]
