"""Rule: are the knees kept bent, or locked straight?

Beginners often box off straight, locked legs — no spring, slow to move, no
base for rotation. The signal is the hip-knee-ankle angle: ~180° is a locked
leg, a good boxing base sits nearer 150-165°.

Knee bend is a SAGITTAL (depth) fault: from a single frontal 2D view the angle
is foreshortened and unreliable, so the brief (§12/§35) deliberately defers it.
This rule therefore runs ONLY on trustworthy 3D input — a sequence whose
`meta["depth"] == "metric_3d"` (e.g. the CoachMe SMPL pose) — and computes the
angle in 3D (`use_z`). On ordinary monocular 2D sequences it emits nothing, so
the frontal-honest app engine is unaffected even with this rule registered.
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
class KneeBendConfig:
    # Median hip-knee-ankle angle (deg) above which a leg is "too straight".
    straight_deg: float = 168.0
    # ...and above which it's moderate rather than minor.
    moderate_deg: float = 173.0
    # Need at least this many frames with a readable leg to judge.
    min_frames: int = 10


class KneeBendRule(Rule):
    id = "knee_bend"
    focus_tags = frozenset()  # always relevant (when 3D is available)

    def __init__(self, config: KneeBendConfig | None = None) -> None:
        self._cfg = config or KneeBendConfig()

    def evaluate(self, context: AnalysisContext) -> list[Observation]:
        # Depth gate: only trustworthy 3D. Monocular 2D can't read knee bend
        # honestly (brief §12/§35), so stay silent there.
        if context.sequence.meta.get("depth") != "metric_3d":
            return []

        cfg = context.style_profile.config_for(self.id, self._cfg)

        # Judge the straighter (more locked) leg; report it.
        worst_side: Side | None = None
        worst_angle = -1.0
        for side in (Side.LEFT, Side.RIGHT):
            median = self._median_knee_angle(context, side, cfg)
            if median is not None and median > worst_angle:
                worst_angle = median
                worst_side = side

        if worst_side is None or worst_angle <= cfg.straight_deg:
            return []

        stance = context.drill.stance
        leg = "lead" if worst_side is stance.lead else "rear"
        severity = Severity.MODERATE if worst_angle > cfg.moderate_deg else Severity.MINOR
        return [
            Observation(
                rule_id=self.id,
                category=SkillCategory.FOOTWORK,
                severity=severity,
                coaching_text=(
                    f"Your {leg} leg is locked out straight. Keep a soft bend in "
                    f"the knees — that's your spring and your base to turn on."
                ),
                timestamp_ms=None,
                metrics={"knee_angle_deg": round(worst_angle, 1)},
                highlight_landmarks=(worst_side.knee,),
            )
        ]

    def _median_knee_angle(
        self, context: AnalysisContext, side: Side, cfg: KneeBendConfig
    ) -> float | None:
        angles: list[float] = []
        for frame in context.sequence.frames:
            hip = geo.frame_point(frame, side.hip, use_z=True)
            knee = geo.frame_point(frame, side.knee, use_z=True)
            ankle = geo.frame_point(frame, side.ankle, use_z=True)
            angle = geo.angle_deg(hip, knee, ankle)
            if not np.isnan(angle):
                angles.append(angle)
        if len(angles) < cfg.min_frames:
            return None
        return float(np.median(angles))
