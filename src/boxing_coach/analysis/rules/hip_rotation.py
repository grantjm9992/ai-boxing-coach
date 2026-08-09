"""Rule: is the rear hand punched with rotation, or arm-only?

A cross/rear straight should be driven by hip and shoulder rotation — the rear
shoulder comes forward. Punching arm-only ("squared up") is both weak and
telegraphed.

HONESTY CAVEAT: this is the least reliable of the starter rules from a single
front-facing camera. Rotation mostly shows up in depth (z), which MediaPipe
only estimates. We use the rear-shoulder z travel from punch start to peak as a
proxy and keep the threshold conservative. This rule is the first candidate for
the VLM layer or a second camera angle. It's included to prove the punch-scoped
rule pattern, not because front-view rotation detection is solved.
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
class HipRotationConfig:
    # Minimum rear-shoulder forward travel (torso-lengths, in z) from start to
    # peak for the punch to count as "rotated".
    min_shoulder_drive: float = 0.12
    # Only judge punches that actually reached extension.
    min_peak_reach: float = 0.9


class HipRotationRule(Rule):
    id = "hip_rotation"
    focus_tags = frozenset({"straight", "power", "combinations"})

    def __init__(self, config: HipRotationConfig | None = None) -> None:
        self._cfg = config or HipRotationConfig()

    def evaluate(self, context: AnalysisContext) -> list[Observation]:
        rear = context.drill.stance.rear
        seq = context.sequence
        observations: list[Observation] = []

        for punch in context.punches_by(rear):
            if punch.peak_reach < self._cfg.min_peak_reach:
                continue
            drive = self._shoulder_drive(context, rear, punch.start_index, punch.peak_index)
            if drive is None:
                continue
            if drive < self._cfg.min_shoulder_drive:
                observations.append(
                    Observation(
                        rule_id=self.id,
                        category=SkillCategory.STRAIGHT,
                        severity=Severity.MODERATE,
                        coaching_text=(
                            "You're squared up on the rear straight — punching with the arm. "
                            "Turn the hip and shoulder over; let the rotation drive the shot."
                        ),
                        timestamp_ms=punch.peak_timestamp_ms(seq),
                        metrics={"shoulder_drive": round(drive, 3)},
                        highlight_landmarks=(rear.shoulder,),
                    )
                )
        return observations

    def _shoulder_drive(
        self, context: AnalysisContext, side: Side, start_index: int, peak_index: int
    ) -> float | None:
        """Forward (toward-camera) travel of the rear shoulder, in torso-lengths.

        MediaPipe z decreases toward the camera, so a rotating-in shoulder gives
        a negative delta; we return its magnitude.
        """
        seq = context.sequence
        scale = context.body_scale
        start = geo.frame_point(seq.frames[start_index], side.shoulder, use_z=True)
        peak = geo.frame_point(seq.frames[peak_index], side.shoulder, use_z=True)
        if np.isnan(start[2]) or np.isnan(peak[2]):
            return None
        return abs(peak[2] - start[2]) / scale
