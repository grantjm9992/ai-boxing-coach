"""RuleEngine — runs the rule set over one round and collects observations.

Deliberately dumb: it decides which rules apply, runs each, and gathers the
results. It is isolated from a single failing rule so one bad rule can't take
down a whole analysis (important once there are 30 of them).
"""

from __future__ import annotations

import logging

from ..domain.analysis import Observation
from .context import AnalysisContext
from .rule import Rule

logger = logging.getLogger(__name__)


class RuleEngine:
    def __init__(self, rules: list[Rule]) -> None:
        self._rules = list(rules)

    @property
    def rules(self) -> list[Rule]:
        return list(self._rules)

    def run(self, context: AnalysisContext) -> list[Observation]:
        observations: list[Observation] = []
        for rule in self._rules:
            if not context.style_profile.enables(rule.id):
                continue
            if not rule.applies_to(context):
                continue
            try:
                observations.extend(rule.evaluate(context))
            except Exception:  # one rule failing must not sink the round
                logger.exception("rule %s failed; skipping", rule.id or type(rule).__name__)
        # Worst faults first; positives last.
        observations.sort(key=lambda o: o.severity.rank, reverse=True)
        return observations
