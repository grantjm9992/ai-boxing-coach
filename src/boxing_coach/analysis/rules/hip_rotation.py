"""Rule: is the rear hand punched with rotation, or arm-only?

A cross/rear straight should be driven by hip and shoulder rotation — the rear
shoulder comes forward. Punching arm-only ("squared up") is both weak and
telegraphed.

We look at how far the rear shoulder travels *relative to the hip centre* from
punch start to peak, taking whichever is larger of:

- the **in-plane** swing (x/y) — how a side or 3/4 camera sees the shoulder come
  across; and
- the **depth** (z) drive — how a front camera sees it come toward the lens.

Measuring relative to the hips means a step forward isn't mistaken for rotation.
Taking the max of the two axes is what stops a fully-rotated punch on a side-on
camera (little z change) from being wrongly flagged as squared up.

HONESTY CAVEAT: still the least certain of the starter rules. z is only
estimated, and from a pure head-on view a rotated and a squared punch can look
alike. A second angle or the VLM layer is the real answer; this is a robust-ish
proxy, not solved rotation detection.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from ...domain.analysis import Observation, Severity, SkillCategory
from ...domain.landmarks import Side
from ...domain.punch import PunchType
from .. import geometry as geo
from ..context import AnalysisContext
from ..rule import Rule


@dataclass(frozen=True, slots=True)
class HipRotationConfig:
    # Minimum rear-shoulder travel relative to the hips (torso-lengths), taken
    # as the max of the in-plane swing and the depth drive, for the punch to
    # count as "rotated".
    min_shoulder_drive: float = 0.12
    # Only judge punches that actually reached extension.
    min_peak_reach: float = 0.9


class HipRotationRule(Rule):
    id = "hip_rotation"
    focus_tags = frozenset({"straight", "power", "combinations"})

    def __init__(self, config: HipRotationConfig | None = None) -> None:
        self._cfg = config or HipRotationConfig()

    def evaluate(self, context: AnalysisContext) -> list[Observation]:
        cfg = context.style_profile.config_for(self.id, self._cfg)
        rear = context.drill.stance.rear
        seq = context.sequence
        observations: list[Observation] = []

        for punch in context.punches_by(rear):
            # Only the rear straight (cross) is driven by rotation this way; a
            # rear hook or uppercut turns over differently, so don't judge them
            # against a straight's shoulder-drive expectation.
            if punch.punch_type is not PunchType.STRAIGHT:
                continue
            if punch.peak_reach < cfg.min_peak_reach:
                continue
            drive = self._shoulder_drive(context, rear, punch.start_index, punch.peak_index)
            if drive is None:
                continue
            if drive < cfg.min_shoulder_drive:
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
        """Rear-shoulder travel relative to the hips, in torso-lengths.

        The max of the in-plane swing (x/y, what a side camera sees) and the
        depth drive (z, what a front camera sees). Relative to the hip centre so
        a step isn't counted as rotation. None if neither axis is measurable.
        """
        seq = context.sequence
        scale = context.body_scale
        start_f, peak_f = seq.frames[start_index], seq.frames[peak_index]

        # In-plane swing of the shoulder about the torso.
        s0 = geo.frame_point(start_f, side.shoulder)
        s1 = geo.frame_point(peak_f, side.shoulder)
        h0 = geo.hip_center(start_f)
        h1 = geo.hip_center(peak_f)
        inplane = np.nan
        if not any(np.any(np.isnan(p)) for p in (s0, s1, h0, h1)):
            inplane = geo.distance(s1 - h1, s0 - h0) / scale

        # Depth drive (front camera): MediaPipe z toward the lens.
        z0 = geo.frame_point(start_f, side.shoulder, use_z=True)[2]
        z1 = geo.frame_point(peak_f, side.shoulder, use_z=True)[2]
        depth = abs(z1 - z0) / scale if not (np.isnan(z0) or np.isnan(z1)) else np.nan

        drives = [d for d in (inplane, depth) if not np.isnan(d)]
        return max(drives) if drives else None
