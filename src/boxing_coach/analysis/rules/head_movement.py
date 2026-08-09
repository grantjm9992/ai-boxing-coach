"""Rule: is there any head movement off the centre line?

The spec only asks for *presence* of head movement in v1 (not quality). We
measure lateral spread of the nose relative to the hip-center line, normalised
by body scale. A head that never leaves the centre line is easy to hit.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from ...domain.analysis import Observation, Severity, SkillCategory
from ...domain.landmarks import Landmark
from .. import geometry as geo
from ..context import AnalysisContext
from ..rule import Rule


@dataclass(frozen=True, slots=True)
class HeadMovementConfig:
    # Std-dev of nose lateral offset (torso-lengths) below which the head is
    # considered static.
    min_lateral_std: float = 0.06
    min_duration_ms: float = 3000.0


class HeadMovementRule(Rule):
    id = "head_movement"
    focus_tags = frozenset({"defence", "head_movement", "movement"})

    def __init__(self, config: HeadMovementConfig | None = None) -> None:
        self._cfg = config or HeadMovementConfig()

    def evaluate(self, context: AnalysisContext) -> list[Observation]:
        cfg = context.style_profile.config_for(self.id, self._cfg)
        seq = context.sequence
        if seq.duration_ms < cfg.min_duration_ms:
            return []

        scale = context.body_scale
        offsets: list[float] = []
        for frame in seq.frames:
            nose = geo.frame_point(frame, Landmark.NOSE)
            center = geo.hip_center(frame)
            if np.any(np.isnan(nose)) or np.any(np.isnan(center)):
                continue
            offsets.append((nose[0] - center[0]) / scale)  # lateral only

        if len(offsets) < 2:
            return []

        lateral_std = float(np.std(offsets))
        if lateral_std < cfg.min_lateral_std:
            return [
                Observation(
                    rule_id=self.id,
                    category=SkillCategory.HEAD_MOVEMENT,
                    severity=Severity.MINOR,
                    coaching_text=(
                        "Your head stayed on the centre line the whole round. "
                        "Add some movement — slip off the line so you're not a fixed target."
                    ),
                    metrics={"lateral_std": round(lateral_std, 3)},
                    highlight_landmarks=(Landmark.NOSE,),
                )
            ]
        return []
