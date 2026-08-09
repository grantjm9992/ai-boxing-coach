"""Run the analysis on a synthetic round — no video, no MediaPipe required.

    python examples/demo.py

Builds a short shadow-boxing round with deliberate mistakes (a jab whose hand
drops, feet planted, head on the centre line), runs it through the real
PoseOnlyAdapter, and prints the coach report. This is the fastest way to see
the output shape before you record anything.

Once you've installed mediapipe + opencv and recorded a clip, the real entry
point is:

    python -m boxing_coach.cli myround.mp4 --stance orthodox
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from boxing_coach.adapters import PoseOnlyAdapter
from boxing_coach.cli import _print_report
from boxing_coach.domain.drill import DrillContext
from boxing_coach.domain.landmarks import Landmark, Stance
from boxing_coach.domain.pose import Keypoint, PoseFrame, PoseSequence

# A neutral standing-guard pose (see domain.landmarks for the coordinate frame).
BASE = {
    Landmark.NOSE: (0.50, 0.30, 0.0),
    Landmark.LEFT_SHOULDER: (0.42, 0.40, 0.0),
    Landmark.RIGHT_SHOULDER: (0.58, 0.40, 0.0),
    Landmark.LEFT_HIP: (0.44, 0.60, 0.0),
    Landmark.RIGHT_HIP: (0.56, 0.60, 0.0),
    Landmark.LEFT_WRIST: (0.47, 0.30, 0.0),
    Landmark.RIGHT_WRIST: (0.53, 0.30, 0.0),
    Landmark.LEFT_ANKLE: (0.44, 0.95, 0.0),
    Landmark.RIGHT_ANKLE: (0.56, 0.95, 0.0),
}


def build_demo_round(fps: float = 30.0) -> PoseSequence:
    """A ~5s round: two clean jabs, then a jab whose hand drops. Feet planted."""
    frame_ms = 1000.0 / fps
    frames: list[PoseFrame] = []
    current = {lm: list(p) for lm, p in BASE.items()}

    def emit():
        i = len(frames)
        kps = {lm: Keypoint(x=p[0], y=p[1], z=p[2]) for lm, p in current.items()}
        frames.append(PoseFrame(index=i, timestamp_ms=i * frame_ms, keypoints=kps))

    def hold(ms):
        for _ in range(max(1, round(ms / frame_ms))):
            emit()

    def move_wrist(ms, target):
        n = max(1, round(ms / frame_ms))
        start = list(current[Landmark.LEFT_WRIST])
        for s in range(1, n + 1):
            t = s / n
            current[Landmark.LEFT_WRIST] = [start[k] + (target[k] - start[k]) * t for k in range(3)]
            emit()

    guard, extended, dropped = [0.47, 0.30, 0.0], [0.72, 0.38, 0.0], [0.50, 0.60, 0.0]

    hold(600)
    for _ in range(2):  # two clean jabs
        move_wrist(110, extended)
        move_wrist(110, guard)
        hold(500)
    # third jab: hand drops instead of returning
    move_wrist(110, extended)
    move_wrist(120, dropped)
    hold(800)

    return PoseSequence(frames=frames, fps=fps, source="demo")


def main() -> None:
    sequence = build_demo_round()
    analysis = PoseOnlyAdapter().analyse(sequence, DrillContext(stance=Stance.ORTHODOX))
    _print_report(analysis)


if __name__ == "__main__":
    main()
