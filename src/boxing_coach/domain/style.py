"""Fighting style — the shape of guard and defence a round is working in.

Like `Stance`, this is a pure selector that lives in the domain: it only names
the style. The analysis layer maps each `Style` to a `StyleProfile` that tunes
which rules run and their thresholds, because "correct" technique is
style-dependent — a Philly shell keeps its lead hand low on purpose, an
out-boxer defends with range and footwork rather than head movement. Judging
every style against a textbook high guard is how you give a shell fighter the
wrong advice.
"""

from __future__ import annotations

from enum import Enum


class Style(Enum):
    """A fighting style. Selects a StyleProfile in the analysis layer."""

    HIGH_GUARD = "high_guard"       # textbook hands-up guard — the default
    PHILLY_SHELL = "philly_shell"   # lead hand low across the body, rear hand high
    PEEK_A_BOO = "peek_a_boo"       # hands high by the cheeks, constant head movement
    OUT_BOXER = "out_boxer"         # range + footwork; defends with distance, not slips
