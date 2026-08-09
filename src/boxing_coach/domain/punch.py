"""Punch type — the motion class of a detected punch.

Deliberately the *motion* class (straight / hook / uppercut), not the named
punch: whether a straight is a "jab" or a "cross" depends on which hand threw it
relative to the stance, so naming is a separate step (`punch_name`). This keeps
the classifier stance-free and the naming in one place.
"""

from __future__ import annotations

from enum import Enum

from .landmarks import Side, Stance


class PunchType(Enum):
    """The motion class of a punch. Side + stance turn this into a named punch."""

    STRAIGHT = "straight"   # arm extends toward the target — jab (lead) / cross (rear)
    HOOK = "hook"           # bent arm, horizontal arc
    UPPERCUT = "uppercut"   # bent arm, rising vertically
    UNKNOWN = "unknown"     # detected a punch but couldn't classify it confidently


def punch_name(punch_type: PunchType, side: Side, stance: Stance) -> str:
    """The common name for a punch, e.g. 'jab', 'cross', 'lead hook'."""
    lead = side is stance.lead
    if punch_type is PunchType.STRAIGHT:
        return "jab" if lead else "cross"
    hand = "lead" if lead else "rear"
    if punch_type is PunchType.HOOK:
        return f"{hand} hook"
    if punch_type is PunchType.UPPERCUT:
        return f"{hand} uppercut"
    return "punch"
