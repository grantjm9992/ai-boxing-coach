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
import numpy as np

from .features import PunchDetector, PunchDetectorConfig, PunchEvent, compute_body_scale
from .round_profile import RoundProfile, compute_round_profile, stance_speed_series
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

    @cached_property
    def round_profile(self) -> RoundProfile:
        return compute_round_profile(self.sequence, self.punches, self.body_scale)

    @cached_property
    def stance_speed(self) -> np.ndarray:
        """Per-frame stance-centre speed (torso-lengths/sec); the in/out signal.

        Index-aligned to `sequence.frames`. Computed once here so the guard
        rules that read it (excusing a low hand while the feet step in/out)
        share the work.
        """
        return stance_speed_series(self.sequence, self.body_scale)

    def punches_by(self, side: Side) -> list[PunchEvent]:
        return [p for p in self.punches if p.side is side]
