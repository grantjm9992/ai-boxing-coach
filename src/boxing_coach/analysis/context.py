"""AnalysisContext — the single object every rule receives.

It carries the raw pose sequence, the drill context, and the shared derived
features (body scale, punch events) so each rule pulls exactly what it needs
and expensive work (punch detection) happens once, not per rule.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from functools import cached_property

from ..domain.drill import DrillContext
from ..domain.landmarks import Side
from ..domain.pose import PoseSequence
from .features import PunchDetector, PunchDetectorConfig, PunchEvent, compute_body_scale
from .style import DEFAULT_STYLE_PROFILE, StyleProfile


@dataclass
class AnalysisContext:
    """Everything a rule needs to evaluate one round."""

    sequence: PoseSequence
    drill: DrillContext
    punch_config: PunchDetectorConfig = field(default_factory=PunchDetectorConfig)
    #: Tunes/gates the rules for this round's fighting style. Defaults to the
    #: neutral high-guard profile so tests and callers that don't care are
    #: unaffected. The adapter resolves it from `drill.style`.
    style_profile: StyleProfile = DEFAULT_STYLE_PROFILE

    @cached_property
    def body_scale(self) -> float:
        return compute_body_scale(self.sequence)

    @cached_property
    def punches(self) -> list[PunchEvent]:
        return PunchDetector(self.punch_config).detect(self.sequence, self.body_scale)

    def punches_by(self, side: Side) -> list[PunchEvent]:
        return [p for p in self.punches if p.side is side]
