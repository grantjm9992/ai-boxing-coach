"""Rule: is the boxer moving, or rooted to the spot?

Cheap and reliable from pose alone. We measure total ankle travel across the
round (normalised by body scale and time). Near-zero movement across a whole
round means the fighter is planted — a stationary target.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from ...domain.analysis import Observation, Severity, SkillCategory
from ...domain.landmarks import Side
from .. import geometry as geo
from ..context import AnalysisContext
from ..rule import Rule


@dataclass(frozen=True, slots=True)
class FootworkConfig:
    # Minimum mean ankle travel (torso-lengths per second) to count as "moving".
    min_travel_per_second: float = 0.15
    # Require at least this many seconds of data before judging.
    min_duration_ms: float = 3000.0


class FootworkRule(Rule):
    id = "footwork"
    focus_tags = frozenset({"footwork", "movement", "defence"})

    def __init__(self, config: FootworkConfig | None = None) -> None:
        self._cfg = config or FootworkConfig()

    def evaluate(self, context: AnalysisContext) -> list[Observation]:
        seq = context.sequence
        duration_s = seq.duration_ms / 1000.0
        if seq.duration_ms < self._cfg.min_duration_ms or duration_s <= 0:
            return []

        travel = self._mean_ankle_travel_per_second(context, duration_s)
        if travel is None:
            return []

        if travel < self._cfg.min_travel_per_second:
            return [
                Observation(
                    rule_id=self.id,
                    category=SkillCategory.FOOTWORK,
                    severity=Severity.MODERATE,
                    coaching_text=(
                        "You're flat-footed this round — barely moving. Stay light, "
                        "step in and out, work angles instead of standing square."
                    ),
                    metrics={"travel_per_second": round(travel, 3)},
                    highlight_landmarks=(Side.LEFT.ankle, Side.RIGHT.ankle),
                )
            ]
        return [
            Observation(
                rule_id=self.id,
                category=SkillCategory.FOOTWORK,
                severity=Severity.POSITIVE,
                coaching_text="Good movement — you're staying light on your feet, not rooted.",
                metrics={"travel_per_second": round(travel, 3)},
            )
        ]

    def _mean_ankle_travel_per_second(
        self, context: AnalysisContext, duration_s: float
    ) -> float | None:
        seq = context.sequence
        scale = context.body_scale
        totals: list[float] = []
        for side in (Side.LEFT, Side.RIGHT):
            traj = seq.trajectory(side.ankle)[:, :2]  # xy only
            steps = np.diff(traj, axis=0)
            dists = np.linalg.norm(steps, axis=1)
            valid = dists[~np.isnan(dists)]
            if valid.size:
                totals.append(float(valid.sum()) / scale)
        if not totals:
            return None
        # Average the two ankles, per second.
        return (sum(totals) / len(totals)) / duration_s
