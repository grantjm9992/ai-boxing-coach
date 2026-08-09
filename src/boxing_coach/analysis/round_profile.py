"""Round-level descriptive features — the raw material for national schools.

The guard `Style` (high guard, shell, ...) describes defensive *shape*. National
schools (Soviet, Mexican, European, American) are tactical *tendencies*, and
those live in a handful of round-level measurements rather than any single
frame:

- **output_per_min** — work rate. Mexican/pressure volume vs a economical
  Soviet points game.
- **mobility** — how much the feet travel (torso-lengths/sec).
- **ground_coverage** — net hip displacement / total hip travel (0 = bouncing on
  the spot, 1 = ranging in a straight line). Separates in-and-out / circling
  from a planted bounce, without needing an orientation reference (there's no
  opponent in a shadow round, so "forward" isn't well defined).
- **torso_lean_deg** — posture, measured off vertical. Small = the upright
  European/classical stance; large = a crouched pressure stance.
- **body_shot_ratio** — fraction of punches thrown at body height (the thrower's
  fist finishing low), a proxy for body work. We only see the thrower, not the
  target, so this is a proxy, not a landed-target count.

These are descriptive, not pass/fail — a School profile reads them to judge
adherence to a chosen game. All are NaN-tolerant and scale-invariant.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from ..domain.landmarks import Landmark, Side
from ..domain.pose import PoseSequence
from . import geometry as geo


@dataclass(frozen=True, slots=True)
class RoundProfile:
    """Descriptive, style-relevant measurements for one round."""

    output_per_min: float
    mobility: float          # torso-lengths/sec of foot travel
    ground_coverage: float   # 0..1, net/gross hip displacement
    torso_lean_deg: float    # angle of the torso off vertical; lower = upright
    body_shot_ratio: float   # 0..1 of punches thrown at body height

    def as_dict(self) -> dict[str, float]:
        return {
            "output_per_min": round(self.output_per_min, 2),
            "mobility": round(self.mobility, 3),
            "ground_coverage": round(self.ground_coverage, 3),
            "torso_lean_deg": round(self.torso_lean_deg, 1),
            "body_shot_ratio": round(self.body_shot_ratio, 3),
        }


def compute_round_profile(sequence: PoseSequence, punches, scale: float) -> RoundProfile:
    duration_s = sequence.duration_ms / 1000.0
    return RoundProfile(
        output_per_min=(len(punches) / duration_s * 60.0) if duration_s > 0 else 0.0,
        mobility=_mobility(sequence, scale, duration_s),
        ground_coverage=_ground_coverage(sequence),
        torso_lean_deg=_torso_lean_deg(sequence),
        body_shot_ratio=_body_shot_ratio(sequence, punches),
    )


def _mobility(sequence: PoseSequence, scale: float, duration_s: float) -> float:
    if duration_s <= 0:
        return 0.0
    totals: list[float] = []
    for side in (Side.LEFT, Side.RIGHT):
        traj = sequence.trajectory(side.ankle)[:, :2]
        dists = np.linalg.norm(np.diff(traj, axis=0), axis=1)
        valid = dists[~np.isnan(dists)]
        if valid.size:
            totals.append(float(valid.sum()) / scale)
    if not totals:
        return 0.0
    return (sum(totals) / len(totals)) / duration_s


def _ankle_center(frame) -> np.ndarray:
    return geo.midpoint(
        geo.frame_point(frame, Landmark.LEFT_ANKLE),
        geo.frame_point(frame, Landmark.RIGHT_ANKLE),
    )


def stance_speed_series(sequence: PoseSequence, scale: float) -> np.ndarray:
    """Per-frame speed of the stance centre (ankle midpoint), torso-lengths/sec.

    The in-and-out signal a rule reads to tell "planted" from "stepping in/out":
    ~0 where the feet are rooted, high while the fighter is translating. Aligned
    to `sequence.frames` — element i is the speed of the step *into* frame i;
    frame 0 is 0.0, and gaps (a missing ankle either side) yield NaN so callers
    treat "unknown" as not-moving rather than fabricating motion.
    """
    frames = sequence.frames
    n = len(frames)
    speeds = np.zeros(n, dtype=np.float64)
    if n < 2 or scale <= 0:
        return speeds
    centres = np.vstack([_ankle_center(f) for f in frames])
    ts = sequence.timestamps_ms()
    for i in range(1, n):
        step = centres[i] - centres[i - 1]
        dt = (ts[i] - ts[i - 1]) / 1000.0
        if np.any(np.isnan(step)) or dt <= 0:
            speeds[i] = np.nan
            continue
        speeds[i] = (float(np.linalg.norm(step)) / scale) / dt
    return speeds


def _ground_coverage(sequence: PoseSequence) -> float:
    """Net displacement / total path length of the stance (ankle centre), 0..1.

    Uses the feet, so it's consistent with `mobility`: bouncing on the spot
    nets ~0 (high travel, no displacement), ranging in a line nets ~1.
    """
    centres = []
    for frame in sequence.frames:
        c = _ankle_center(frame)
        if not np.any(np.isnan(c)):
            centres.append(c)
    if len(centres) < 2:
        return 0.0
    pts = np.vstack(centres)
    steps = np.linalg.norm(np.diff(pts, axis=0), axis=1)
    total = float(steps.sum())
    if total == 0:
        return 0.0
    net = float(np.linalg.norm(pts[-1] - pts[0]))
    return min(net / total, 1.0)


def _torso_lean_deg(sequence: PoseSequence) -> float:
    """Mean torso inclination off vertical, in degrees (0 = bolt upright)."""
    up = np.array([0.0, -1.0])  # image y grows downward, so "up" is -y
    angles: list[float] = []
    for frame in sequence.frames:
        v = geo.shoulder_center(frame) - geo.hip_center(frame)
        norm = float(np.linalg.norm(v))
        if np.any(np.isnan(v)) or norm == 0:
            continue
        cosine = float(np.dot(v / norm, up))
        angles.append(float(np.degrees(np.arccos(np.clip(cosine, -1.0, 1.0)))))
    return float(np.mean(angles)) if angles else 0.0


def _body_shot_ratio(sequence: PoseSequence, punches) -> float:
    """Fraction of punches whose fist finishes at body height.

    "Body height" is measured against the fighter's own mid-torso (the midpoint
    of the shoulder and hip on the punching side), not the shoulder line. A
    straight punch extended forward routinely dips just below the shoulder in a
    single 2D view even when it's a head shot, so a shoulder cutoff wildly
    over-counts; requiring the fist below mid-torso is far more conservative.
    Still a proxy — we see the thrower, not where the punch would land.
    """
    if not punches:
        return 0.0
    body = 0
    counted = 0
    for punch in punches:
        frame = sequence.frames[punch.peak_index]
        wrist = geo.frame_point(frame, punch.side.wrist)
        shoulder = geo.frame_point(frame, punch.side.shoulder)
        hip = geo.frame_point(frame, punch.side.hip)
        if np.any(np.isnan(wrist)) or np.any(np.isnan(shoulder)) or np.any(np.isnan(hip)):
            continue
        counted += 1
        mid_torso_y = (shoulder[1] + hip[1]) / 2.0
        if wrist[1] > mid_torso_y:  # y grows downward -> fist below mid-torso
            body += 1
    return (body / counted) if counted else 0.0
