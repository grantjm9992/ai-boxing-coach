"""Tiny geometry helpers used by feature extraction and rules.

All functions are NaN-tolerant where it matters: pose estimation drops
landmarks, and we'd rather propagate NaN than crash or silently fabricate a
position.
"""

from __future__ import annotations

import numpy as np

from ..domain.landmarks import Landmark
from ..domain.pose import PoseFrame


def midpoint(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    return (a + b) / 2.0


def distance(a: np.ndarray, b: np.ndarray) -> float:
    return float(np.linalg.norm(a - b))


def frame_point(frame: PoseFrame, landmark: Landmark, *, use_z: bool = False) -> np.ndarray:
    kp = frame.get(landmark)
    dims = 3 if use_z else 2
    if kp is None:
        return np.full(dims, np.nan)
    return kp.xyz if use_z else kp.xy


def shoulder_center(frame: PoseFrame, *, use_z: bool = False) -> np.ndarray:
    return midpoint(
        frame_point(frame, Landmark.LEFT_SHOULDER, use_z=use_z),
        frame_point(frame, Landmark.RIGHT_SHOULDER, use_z=use_z),
    )


def hip_center(frame: PoseFrame, *, use_z: bool = False) -> np.ndarray:
    return midpoint(
        frame_point(frame, Landmark.LEFT_HIP, use_z=use_z),
        frame_point(frame, Landmark.RIGHT_HIP, use_z=use_z),
    )


def torso_length(frame: PoseFrame) -> float:
    """Distance from shoulder-center to hip-center (2D). Our scale unit.

    More stable than shoulder width, which foreshortens as the boxer turns.
    """
    return distance(shoulder_center(frame), hip_center(frame))


def nanmedian(values: list[float]) -> float:
    arr = np.array(values, dtype=np.float64)
    if arr.size == 0 or np.all(np.isnan(arr)):
        return float("nan")
    return float(np.nanmedian(arr))
