"""The `Rule` seam — the other axis of change the spec calls out.

Building 20-30 of these is where the boxing domain expertise lives. Adding a
rule = one subclass; the engine discovers nothing implicitly and nothing else
changes. Each rule declares which drill focus tags it applies to so the engine
can skip irrelevant rules for a given round.
"""

from __future__ import annotations

from abc import ABC, abstractmethod

from ..domain.analysis import Observation
from .context import AnalysisContext


class Rule(ABC):
    """A single technique check over a round's pose sequence."""

    #: Stable identifier, e.g. "guard_return". Appears on every Observation.
    id: str = ""

    #: Drill focus tags this rule is relevant to. A rule with an empty set is
    #: always run; otherwise it runs only when the drill targets one of them.
    focus_tags: frozenset[str] = frozenset()

    def applies_to(self, context: AnalysisContext) -> bool:
        if not self.focus_tags:
            return True
        return context.drill.is_focused_on(*self.focus_tags)

    @abstractmethod
    def evaluate(self, context: AnalysisContext) -> list[Observation]:
        """Return zero or more observations. Empty means nothing to report."""
        raise NotImplementedError
