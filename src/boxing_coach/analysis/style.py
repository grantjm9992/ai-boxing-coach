"""StyleProfile — how a fighting Style tunes the rule set for one round.

A profile does two things:

1. **Gate rules** — a rule that would give wrong advice for a style is switched
   off (an out-boxer defends with range, so "your head is on the centre line"
   is not a fault worth raising).
2. **Override rule configs** — thresholds that legitimately differ by style
   (a peek-a-boo fighter should be held to a higher head-movement bar).

Rules and the engine read the resolved profile off the `AnalysisContext`, so
style varies per round without rebuilding the rule set.

This module deliberately imports **no rule configs** — only the neutral default
profile lives here — so `AnalysisContext` can import `StyleProfile` without an
import cycle. The concrete per-style profiles are assembled in
`style_profiles.py`, which is free to import every rule's config.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Mapping, TypeVar

from ..domain.style import Style

_C = TypeVar("_C")


@dataclass(frozen=True)
class StyleProfile:
    """How one fighting style tunes and gates the rules."""

    style: Style
    label: str
    summary: str
    #: Rule ids switched off entirely for this style.
    disabled_rules: frozenset[str] = frozenset()
    #: rule_id -> replacement config for that rule. Missing = rule's own default.
    rule_configs: Mapping[str, object] = field(default_factory=dict)

    def enables(self, rule_id: str) -> bool:
        return rule_id not in self.disabled_rules

    def config_for(self, rule_id: str, default: _C) -> _C:
        """The style's config override for `rule_id`, or `default` if none."""
        return self.rule_configs.get(rule_id, default)  # type: ignore[return-value]


#: The neutral profile: every rule on, every threshold at its own default.
#: Kept here (not in the registry) so `AnalysisContext` has a default without
#: importing any rule config.
DEFAULT_STYLE_PROFILE = StyleProfile(
    style=Style.HIGH_GUARD,
    label="High guard (textbook)",
    summary="Standard hands-up guard. Every rule runs at its default thresholds.",
)
