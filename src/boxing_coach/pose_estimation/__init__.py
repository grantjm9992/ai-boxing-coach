"""Pose estimation: the swappable video -> keypoints backend."""

from .estimator import PoseEstimator

__all__ = ["PoseEstimator", "load_mediapipe_estimator"]


def load_mediapipe_estimator(**kwargs) -> PoseEstimator:
    """Lazily construct the MediaPipe estimator.

    Kept behind a function so `import boxing_coach.pose_estimation` never pulls
    in mediapipe/opencv. Import cost is paid only when you call this.
    """
    from .mediapipe_estimator import MediaPipePoseEstimator

    return MediaPipePoseEstimator(**kwargs)
