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
from .knee_bend import KneeBendRule
from .school_adherence import SchoolAdherenceRule

__all__ = [
    "FootworkRule",
    "GuardReturnRule",
    "HandsUpRule",
    "HeadMovementRule",
    "HipRotationRule",
    "KneeBendRule",
    "SchoolAdherenceRule",
    "default_rules",
]


def default_rules() -> list[Rule]:
    """The starter rule set. Order is irrelevant — the engine sorts output.

    KneeBendRule is registered but self-gates on trustworthy 3D input
    (`meta["depth"] == "metric_3d"`), so it stays silent on the monocular 2D
    sequences the app and the golden fixtures use — the frontal-honest set is
    unchanged.
    """
    return [
        GuardReturnRule(),
        HandsUpRule(),
        FootworkRule(),
        HeadMovementRule(),
        HipRotationRule(),
        KneeBendRule(),
        SchoolAdherenceRule(),
    ]
