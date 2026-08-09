"""National / tactical school — an axis orthogonal to the guard `Style`.

`Style` is the defensive *shape* (high guard, Philly shell, ...). A `School` is
the tactical *game* a fighter is playing — a fighter is "Mexican pressure with a
high guard" or "Soviet in-and-out behind an out-boxer's range". So it's a
separate, optional dimension on the drill, not another value of `Style`.

Schools are read off the round-level tendencies (`RoundProfile`): work rate,
mobility, ground coverage, posture, body work, punch selection. Much of what
truly defines a school (feints, ring IQ, willingness to trade, and — with no
opponent in a shadow round — body-vs-head *targeting*) isn't reachable from this
input yet, so the profiles judge only the detectable tendencies and are
starting characterisations to calibrate, not doctrine.
"""

from __future__ import annotations

from enum import Enum


class School(Enum):
    """A national/tactical school. Optional, orthogonal to Style."""

    SOVIET = "soviet"       # technical, in-and-out, educated jab, economical
    MEXICAN = "mexican"     # pressure, high volume, body work, comes forward
    EUROPEAN = "european"   # upright classical stance, long-range jab, points
    AMERICAN = "american"   # athletic, fast and varied combinations
