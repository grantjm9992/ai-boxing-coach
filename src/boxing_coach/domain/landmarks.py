"""Body landmarks used by the analysis engine.

We only model the subset of MediaPipe Pose's 33 landmarks that the boxing
rules actually need. The integer values are the *canonical MediaPipe indices*
so a MediaPipe-backed estimator can populate them directly, but nothing in the
domain or analysis layers depends on MediaPipe being installed.

Coordinate convention (documented once, relied on everywhere):
    - x increases to the right of the *image*
    - y increases *downward* (image convention — so "higher up" means smaller y)
    - z is an optional depth estimate; smaller/more-negative means closer to camera
All coordinates are image-normalised to roughly [0, 1] unless a specific
estimator documents otherwise.
"""

from __future__ import annotations

from enum import IntEnum


class Landmark(IntEnum):
    """A body keypoint. Values match MediaPipe Pose landmark indices."""

    NOSE = 0
    LEFT_EYE = 2
    RIGHT_EYE = 5
    LEFT_EAR = 7
    RIGHT_EAR = 8
    LEFT_SHOULDER = 11
    RIGHT_SHOULDER = 12
    LEFT_ELBOW = 13
    RIGHT_ELBOW = 14
    LEFT_WRIST = 15
    RIGHT_WRIST = 16
    LEFT_HIP = 23
    RIGHT_HIP = 24
    LEFT_KNEE = 25
    RIGHT_KNEE = 26
    LEFT_ANKLE = 27
    RIGHT_ANKLE = 28


class Side(IntEnum):
    """Which side of the body a limb belongs to."""

    LEFT = 0
    RIGHT = 1

    @property
    def wrist(self) -> Landmark:
        return Landmark.LEFT_WRIST if self is Side.LEFT else Landmark.RIGHT_WRIST

    @property
    def shoulder(self) -> Landmark:
        return Landmark.LEFT_SHOULDER if self is Side.LEFT else Landmark.RIGHT_SHOULDER

    @property
    def elbow(self) -> Landmark:
        return Landmark.LEFT_ELBOW if self is Side.LEFT else Landmark.RIGHT_ELBOW

    @property
    def hip(self) -> Landmark:
        return Landmark.LEFT_HIP if self is Side.LEFT else Landmark.RIGHT_HIP

    @property
    def ankle(self) -> Landmark:
        return Landmark.LEFT_ANKLE if self is Side.LEFT else Landmark.RIGHT_ANKLE


class Stance(IntEnum):
    """Boxing stance. Determines which hand is lead vs rear."""

    ORTHODOX = 0  # left hand/foot forward -> lead = LEFT, rear = RIGHT
    SOUTHPAW = 1  # right hand/foot forward -> lead = RIGHT, rear = LEFT

    @property
    def lead(self) -> Side:
        return Side.LEFT if self is Stance.ORTHODOX else Side.RIGHT

    @property
    def rear(self) -> Side:
        return Side.RIGHT if self is Stance.ORTHODOX else Side.LEFT
