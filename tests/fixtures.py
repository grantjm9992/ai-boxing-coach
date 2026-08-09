"""Synthetic pose sequences for testing rules without video or MediaPipe.

A `PoseScript` starts every frame from a neutral standing-guard base pose and
lets a test script motions readably (hold / move). This is deliberately the
same shape of data MediaPipe produces, so a rule that passes here behaves the
same on real keypoints.

Coordinate reminder (see domain.landmarks): x right, y DOWN, z toward camera
negative. Neutral pose: nose above shoulders above hips above ankles.

Modelling note: punches here extend the wrist in the image plane (x/y), as a
side or 3/4-angle camera would see. A pure head-on jab foreshortens in 2D and
leans on z instead — that's a real limitation of front-view 2D reach, called
out in the punch detector. The fixtures assume the common angled-camera case.
"""

from __future__ import annotations

import sys
from pathlib import Path

_SRC = Path(__file__).resolve().parents[1] / "src"
if str(_SRC) not in sys.path:
    sys.path.insert(0, str(_SRC))

from boxing_coach.domain.landmarks import Landmark  # noqa: E402
from boxing_coach.domain.pose import Keypoint, PoseFrame, PoseSequence  # noqa: E402

# Neutral standing-guard pose. (x, y, z) per landmark.
BASE_POSE: dict[Landmark, tuple[float, float, float]] = {
    Landmark.NOSE: (0.50, 0.30, 0.0),
    Landmark.LEFT_SHOULDER: (0.42, 0.40, 0.0),
    Landmark.RIGHT_SHOULDER: (0.58, 0.40, 0.0),
    Landmark.LEFT_HIP: (0.44, 0.60, 0.0),
    Landmark.RIGHT_HIP: (0.56, 0.60, 0.0),
    Landmark.LEFT_WRIST: (0.47, 0.30, 0.0),   # lead hand at guard (near face)
    Landmark.RIGHT_WRIST: (0.53, 0.30, 0.0),  # rear hand at guard
    Landmark.LEFT_ANKLE: (0.44, 0.95, 0.0),
    Landmark.RIGHT_ANKLE: (0.56, 0.95, 0.0),
}

# Common target positions.
LEAD_GUARD = (0.47, 0.30, 0.0)
LEAD_JAB_EXTENDED = (0.72, 0.38, 0.0)      # arm out across the frame
LEAD_DROPPED = (0.50, 0.60, 0.0)           # hand down at hip level
REAR_GUARD = (0.53, 0.30, 0.0)
REAR_CROSS_EXTENDED = (0.30, 0.38, 0.0)


class PoseScript:
    """Builds a PoseSequence by scripting motion over time."""

    def __init__(self, fps: float = 30.0) -> None:
        self.fps = fps
        self._frame_ms = 1000.0 / fps
        self._current = {lm: tuple(pos) for lm, pos in BASE_POSE.items()}
        self._frames: list[PoseFrame] = []

    def _n_frames(self, ms: float) -> int:
        return max(1, round(ms / self._frame_ms))

    def _emit(self, positions: dict) -> None:
        idx = len(self._frames)
        kps = {
            lm: Keypoint(x=p[0], y=p[1], z=p[2] if len(p) > 2 else 0.0)
            for lm, p in positions.items()
        }
        self._frames.append(PoseFrame(index=idx, timestamp_ms=idx * self._frame_ms, keypoints=kps))

    def hold(self, ms: float, **overrides: tuple) -> "PoseScript":
        """Hold current pose for `ms`, optionally setting some landmarks."""
        for lm, pos in overrides.items():
            self._current[Landmark[lm.upper()] if isinstance(lm, str) else lm] = tuple(pos)
        for _ in range(self._n_frames(ms)):
            self._emit(self._current)
        return self

    def move(self, ms: float, targets: dict[Landmark, tuple]) -> "PoseScript":
        """Linearly interpolate the given landmarks to targets over `ms`."""
        n = self._n_frames(ms)
        starts = {lm: self._current[lm] for lm in targets}
        for step in range(1, n + 1):
            t = step / n
            frame = dict(self._current)
            for lm, target in targets.items():
                s = starts[lm]
                frame[lm] = tuple(s[i] + (target[i] - s[i]) * t for i in range(3))
            self._emit(frame)
        for lm, target in targets.items():
            self._current[lm] = tuple(target)
        return self

    def build(self, source: str = "synthetic") -> PoseSequence:
        return PoseSequence(frames=list(self._frames), fps=self.fps, source=source)


# -- ready-made fixtures ---------------------------------------------------


def clean_jab() -> PoseSequence:
    """One lead jab that snaps back to guard."""
    return (
        PoseScript()
        .hold(500)
        .move(120, {Landmark.LEFT_WRIST: LEAD_JAB_EXTENDED})
        .move(120, {Landmark.LEFT_WRIST: LEAD_GUARD})
        .hold(500)
        .build()
    )


def dropped_guard_jab() -> PoseSequence:
    """A jab where the hand drops to the hip instead of returning to guard."""
    return (
        PoseScript()
        .hold(500)
        .move(120, {Landmark.LEFT_WRIST: LEAD_JAB_EXTENDED})
        .move(120, {Landmark.LEFT_WRIST: LEAD_DROPPED})
        .hold(600, left_wrist=LEAD_DROPPED)
        .build()
    )


def hands_down_idle() -> PoseSequence:
    """Standing with the lead hand hanging low the whole time (no punches)."""
    return PoseScript().hold(4000, left_wrist=LEAD_DROPPED).build()


def rear_hand_down_idle() -> PoseSequence:
    """Standing with the *rear* hand hanging low the whole time (no punches).

    The mirror of `hands_down_idle` — used to check that styles which stop
    judging the lead hand (Philly shell) still flag a dropped rear hand.
    """
    rear_dropped = (0.53, 0.60, 0.0)  # rear (right) wrist down at hip level
    return PoseScript().hold(4000, right_wrist=rear_dropped).build()


def static_feet() -> PoseSequence:
    """A whole round rooted to the spot."""
    return PoseScript().hold(5000).build()


def moving_feet() -> PoseSequence:
    """Feet stepping in and out throughout the round."""
    s = PoseScript()
    la, ra = list(BASE_POSE[Landmark.LEFT_ANKLE]), list(BASE_POSE[Landmark.RIGHT_ANKLE])
    for i in range(16):  # 16 * 250ms = 4s, past the footwork min-duration gate
        dx = 0.06 if i % 2 == 0 else -0.06
        s.move(250, {
            Landmark.LEFT_ANKLE: (la[0] + dx, la[1], 0.0),
            Landmark.RIGHT_ANKLE: (ra[0] + dx, ra[1], 0.0),
        })
    return s.build()


def drifting_feet() -> PoseSequence:
    """Feet moving gently — enough for a textbook guard, not for an out-boxer.

    A modest, steady drift whose travel-per-second sits between the default
    footwork bar and the higher one an out-boxer is held to.
    """
    s = PoseScript()
    la, ra = list(BASE_POSE[Landmark.LEFT_ANKLE]), list(BASE_POSE[Landmark.RIGHT_ANKLE])
    for i in range(16):  # 16 moves clears the footwork min-duration gate (>3s)
        step = 0.010 * (i + 1)
        s.move(250, {
            Landmark.LEFT_ANKLE: (la[0] + step, la[1], 0.0),
            Landmark.RIGHT_ANKLE: (ra[0] + step, ra[1], 0.0),
        })
    return s.build()


def static_head() -> PoseSequence:
    """Head glued to the centre line."""
    return PoseScript().hold(5000).build()


def slipping_head() -> PoseSequence:
    """Head slipping left and right off the centre line (past the 3s gate)."""
    s = PoseScript()
    nose = list(BASE_POSE[Landmark.NOSE])
    for i in range(14):
        dx = 0.08 if i % 2 == 0 else -0.08
        s.move(250, {Landmark.NOSE: (nose[0] + dx, nose[1], 0.0)})
    return s.build()


def slight_slipping_head() -> PoseSequence:
    """Head slipping a little — enough for a textbook guard, not for peek-a-boo.

    Lateral spread sits between the default head-movement bar and the higher one
    a peek-a-boo fighter is held to.
    """
    s = PoseScript()
    nose = list(BASE_POSE[Landmark.NOSE])
    for i in range(14):  # past the head-movement min-duration gate (>3s)
        dx = 0.035 if i % 2 == 0 else -0.035
        s.move(250, {Landmark.NOSE: (nose[0] + dx, nose[1], 0.0)})
    return s.build()


def lead_hook() -> PoseSequence:
    """A lead hook: bent arm, wrist arcs horizontally. Elbows included so the
    classifier sees the ~90° bend (a straight would show a near-180° elbow)."""
    chambered_elbow, chambered_wrist = (0.44, 0.52, 0.0), (0.46, 0.42, 0.0)
    hook_elbow, hook_wrist = (0.58, 0.46, 0.0), (0.62, 0.36, 0.0)
    return (
        PoseScript()
        .hold(600, left_elbow=chambered_elbow, left_wrist=chambered_wrist)
        .move(120, {Landmark.LEFT_ELBOW: hook_elbow, Landmark.LEFT_WRIST: hook_wrist})
        .move(120, {Landmark.LEFT_ELBOW: chambered_elbow, Landmark.LEFT_WRIST: chambered_wrist})
        .hold(500)
        .build()
    )


def lead_uppercut() -> PoseSequence:
    """A lead uppercut: bent arm, wrist drives vertically upward."""
    low_elbow, low_wrist = (0.44, 0.52, 0.0), (0.44, 0.44, 0.0)
    up_elbow, up_wrist = (0.46, 0.40, 0.0), (0.52, 0.22, 0.0)
    return (
        PoseScript()
        .hold(600, left_elbow=low_elbow, left_wrist=low_wrist)
        .move(120, {Landmark.LEFT_ELBOW: up_elbow, Landmark.LEFT_WRIST: up_wrist})
        .move(120, {Landmark.LEFT_ELBOW: low_elbow, Landmark.LEFT_WRIST: low_wrist})
        .hold(500)
        .build()
    )


def crouched_stance() -> PoseSequence:
    """A forward-leaning pressure stance (shoulders ahead of the hips)."""
    ls = (BASE_POSE[Landmark.LEFT_SHOULDER][0] + 0.10, 0.44, 0.0)   # shoulders forward + lower
    rs = (BASE_POSE[Landmark.RIGHT_SHOULDER][0] + 0.10, 0.44, 0.0)
    return PoseScript().hold(3000, left_shoulder=ls, right_shoulder=rs).build()


def body_hook() -> PoseSequence:
    """A lead hook finishing low — a body shot (fist below mid-torso)."""
    chambered_elbow, chambered_wrist = (0.44, 0.52, 0.0), (0.46, 0.44, 0.0)
    hook_elbow, hook_wrist = (0.58, 0.60, 0.0), (0.62, 0.58, 0.0)  # arcs out and low
    return (
        PoseScript()
        .hold(600, left_elbow=chambered_elbow, left_wrist=chambered_wrist)
        .move(120, {Landmark.LEFT_ELBOW: hook_elbow, Landmark.LEFT_WRIST: hook_wrist})
        .move(120, {Landmark.LEFT_ELBOW: chambered_elbow, Landmark.LEFT_WRIST: chambered_wrist})
        .hold(500)
        .build()
    )


def chest_high_hook() -> PoseSequence:
    """A lead hook finishing just below the shoulder but above mid-torso — a
    head/chest-level shot. The old 'below the shoulder' rule wrongly called this
    a body shot; measured against mid-torso it doesn't count."""
    chambered_elbow, chambered_wrist = (0.44, 0.52, 0.0), (0.46, 0.44, 0.0)
    hook_elbow, hook_wrist = (0.58, 0.50, 0.0), (0.62, 0.45, 0.0)
    return (
        PoseScript()
        .hold(600, left_elbow=chambered_elbow, left_wrist=chambered_wrist)
        .move(120, {Landmark.LEFT_ELBOW: hook_elbow, Landmark.LEFT_WRIST: hook_wrist})
        .move(120, {Landmark.LEFT_ELBOW: chambered_elbow, Landmark.LEFT_WRIST: chambered_wrist})
        .hold(500)
        .build()
    )


def rear_hook() -> PoseSequence:
    """A rear hook (right hand), squared/no rotation. Used to check that the
    hip-rotation rule — which only judges the rear *straight* — leaves it be."""
    chambered_elbow, chambered_wrist = (0.56, 0.52, 0.0), (0.54, 0.42, 0.0)
    hook_elbow, hook_wrist = (0.42, 0.46, 0.0), (0.38, 0.36, 0.0)
    return (
        PoseScript()
        .hold(600, right_elbow=chambered_elbow, right_wrist=chambered_wrist)
        .move(120, {Landmark.RIGHT_ELBOW: hook_elbow, Landmark.RIGHT_WRIST: hook_wrist})
        .move(120, {Landmark.RIGHT_ELBOW: chambered_elbow, Landmark.RIGHT_WRIST: chambered_wrist})
        .hold(500)
        .build()
    )


def _cross(*, rotated: bool) -> PoseSequence:
    """A rear straight, with or without shoulder rotation (z drive)."""
    peak_shoulder_z = -0.05 if rotated else 0.0
    rs = BASE_POSE[Landmark.RIGHT_SHOULDER]
    return (
        PoseScript()
        .hold(500)
        .move(120, {
            Landmark.RIGHT_WRIST: REAR_CROSS_EXTENDED,
            Landmark.RIGHT_SHOULDER: (rs[0], rs[1], peak_shoulder_z),
        })
        .move(120, {
            Landmark.RIGHT_WRIST: REAR_GUARD,
            Landmark.RIGHT_SHOULDER: rs,
        })
        .hold(500)
        .build()
    )


def rotated_cross() -> PoseSequence:
    return _cross(rotated=True)


def squared_cross() -> PoseSequence:
    return _cross(rotated=False)
