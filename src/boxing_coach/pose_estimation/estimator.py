"""The pose-estimation seam.

This is the abstraction the spec calls out: "start with MediaPipe, evaluate
MMPose if accuracy insufficient." Everything downstream depends only on this
interface, so swapping the backend is a one-line change at the composition
root and touches no analysis code.
"""

from __future__ import annotations

from abc import ABC, abstractmethod

from ..domain.pose import PoseSequence


class PoseEstimator(ABC):
    """Turns a video into a `PoseSequence`."""

    @abstractmethod
    def estimate(self, video_path: str) -> PoseSequence:
        """Run pose estimation over the whole video and return keypoints/frame."""
        raise NotImplementedError
