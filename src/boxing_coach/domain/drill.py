"""DrillContext — what the round was supposed to be working on.

The analyser uses this to decide which rules are relevant and how to phrase
feedback (a jab-focused round cares about retraction; a defence round cares
about head movement). In the app this comes from the session plan; in the
skeleton you pass it on the CLI.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .landmarks import Stance
from .style import Style


@dataclass(frozen=True, slots=True)
class DrillContext:
    """Context for a single recorded round."""

    stance: Stance = Stance.ORTHODOX
    # Fighting style — selects the StyleProfile that tunes/gates the rules.
    style: Style = Style.HIGH_GUARD
    # Free-form focus tags, e.g. {"jab", "defence"}. Empty = run every rule.
    focus: frozenset[str] = field(default_factory=frozenset)
    notes: str = ""

    def is_focused_on(self, *tags: str) -> bool:
        """True if this drill targets any of `tags` (or has no focus set)."""
        return not self.focus or bool(self.focus.intersection(tags))
