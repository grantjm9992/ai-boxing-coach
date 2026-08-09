"""Pose data model — the output of pose estimation, the input to analysis.

This is deliberately estimator-agnostic. A `PoseSequence` is just keypoints
over time; whether they came from MediaPipe, MMPose, or a synthetic test
fixture is irrelevant to everything downstream.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Iterable, Iterator

import numpy as np

from .landmarks import Landmark


@dataclass(frozen=True, slots=True)
class Keypoint:
    """A single landmark position in image-normalised coordinates."""

    x: float
    y: float
    z: float = 0.0
    visibility: float = 1.0

    @property
    def xy(self) -> np.ndarray:
        return np.array([self.x, self.y], dtype=np.float64)

    @property
    def xyz(self) -> np.ndarray:
        return np.array([self.x, self.y, self.z], dtype=np.float64)


@dataclass(frozen=True, slots=True)
class PoseFrame:
    """All landmarks detected in a single video frame, with a timestamp."""

    index: int
    timestamp_ms: float
    keypoints: dict[Landmark, Keypoint]

    def get(self, landmark: Landmark) -> Keypoint | None:
        return self.keypoints.get(landmark)

    def require(self, landmark: Landmark) -> Keypoint:
        kp = self.keypoints.get(landmark)
        if kp is None:
            raise KeyError(f"frame {self.index} missing landmark {landmark.name}")
        return kp

    def has(self, *landmarks: Landmark, min_visibility: float = 0.0) -> bool:
        return all(
            (kp := self.keypoints.get(lm)) is not None and kp.visibility >= min_visibility
            for lm in landmarks
        )


@dataclass(frozen=True, slots=True)
class PoseSequence:
    """An ordered sequence of pose frames plus capture metadata."""

    frames: list[PoseFrame]
    fps: float
    source: str = "unknown"
    meta: dict[str, object] = field(default_factory=dict)

    def __post_init__(self) -> None:
        if self.fps <= 0:
            raise ValueError("fps must be positive")

    def __len__(self) -> int:
        return len(self.frames)

    def __iter__(self) -> Iterator[PoseFrame]:
        return iter(self.frames)

    @property
    def duration_ms(self) -> float:
        if not self.frames:
            return 0.0
        return self.frames[-1].timestamp_ms - self.frames[0].timestamp_ms

    def trajectory(self, landmark: Landmark) -> np.ndarray:
        """(N, 3) array of xyz for `landmark` across every frame.

        Frames missing the landmark contribute NaN rows so callers can decide
        how to handle gaps rather than silently shifting indices.
        """
        rows: list[np.ndarray] = []
        for frame in self.frames:
            kp = frame.get(landmark)
            rows.append(kp.xyz if kp is not None else np.full(3, np.nan))
        return np.vstack(rows) if rows else np.empty((0, 3))

    def timestamps_ms(self) -> np.ndarray:
        return np.array([f.timestamp_ms for f in self.frames], dtype=np.float64)

    @classmethod
    def from_frames(cls, frames: Iterable[PoseFrame], fps: float, source: str = "unknown") -> "PoseSequence":
        return cls(frames=list(frames), fps=fps, source=source)
