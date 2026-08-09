"""Classify a detected punch into a motion class (straight / hook / uppercut).

Works from the wrist's path between the punch's start and peak, plus the elbow
angle at the peak when the elbow landmark is available (real MediaPipe footage
always has it; the synthetic fixtures may not, so there's a reach-based
fallback). All lengths are in torso-lengths, like the rest of the engine.

HONESTY CAVEAT: single-view 2D separates these unevenly. An uppercut (vertical
rise) and a straight (arm extension) read clearly; a hook depends on seeing the
horizontal arc and a bent elbow, which foreshortens on a head-on camera. The
punch *detector* itself keys off wrist->shoulder reach, so hooks and uppercuts
only register if they push the wrist away from the shoulder. Treat the type as
a useful signal, not ground truth — the reason it's a swappable step.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from ..domain.landmarks import Side
from ..domain.pose import PoseSequence
from ..domain.punch import PunchType
from . import geometry as geo


@dataclass(frozen=True, slots=True)
class PunchClassifierConfig:
    # Upward wrist travel (torso-lengths) for the punch to read as an uppercut.
    uppercut_min_rise: float = 0.55
    # Horizontal wrist travel (torso-lengths) for a bent-arm punch to read as a hook.
    hook_min_horiz: float = 0.45
    # Elbow angle (degrees) at/above which the arm counts as extended -> straight.
    extended_elbow_deg: float = 150.0
    # Fallback when the elbow landmark is missing: reach at/above this = extended.
    extended_reach: float = 1.2


def classify_punch(
    sequence: PoseSequence,
    side: Side,
    start_index: int,
    peak_index: int,
    peak_reach: float,
    scale: float,
    config: PunchClassifierConfig | None = None,
) -> PunchType:
    """Motion class of one punch, from its start->peak wrist path and elbow angle."""
    cfg = config or PunchClassifierConfig()
    start = sequence.frames[start_index]
    peak = sequence.frames[peak_index]

    w0 = geo.frame_point(start, side.wrist)
    w1 = geo.frame_point(peak, side.wrist)
    if np.any(np.isnan(w0)) or np.any(np.isnan(w1)):
        return PunchType.UNKNOWN

    dx = (w1[0] - w0[0]) / scale
    dy = (w1[1] - w0[1]) / scale
    rise = -dy            # y grows downward, so upward travel is positive rise
    horiz = abs(dx)

    # Is the arm extended at the peak? Elbow angle if we have it, else reach.
    elbow_angle = geo.angle_deg(
        geo.frame_point(peak, side.shoulder),
        geo.frame_point(peak, side.elbow),
        geo.frame_point(peak, side.wrist),
    )
    if not np.isnan(elbow_angle):
        extended = elbow_angle >= cfg.extended_elbow_deg
    else:
        extended = peak_reach >= cfg.extended_reach

    # A clear vertical rise that outweighs horizontal travel is an uppercut,
    # bent arm or not.
    if rise >= cfg.uppercut_min_rise and rise >= horiz:
        return PunchType.UPPERCUT
    if extended:
        return PunchType.STRAIGHT
    if horiz >= cfg.hook_min_horiz:
        return PunchType.HOOK
    return PunchType.UNKNOWN
