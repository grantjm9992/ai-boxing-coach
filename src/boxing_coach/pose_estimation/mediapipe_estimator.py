"""MediaPipe-backed pose estimator.

`mediapipe` and `opencv-python` are imported lazily inside the constructor so
that importing this module — or running the rule engine and its tests — never
requires the heavy CV stack. You only pay for MediaPipe when you actually
process a real video.
"""

from __future__ import annotations

from ..domain.landmarks import Landmark
from ..domain.pose import Keypoint, PoseFrame, PoseSequence
from .estimator import PoseEstimator

# The landmark indices we care about (see domain.landmarks). We only keep these
# from MediaPipe's 33 to keep frames small and analysis explicit.
_WANTED = tuple(Landmark)


class MediaPipePoseEstimator(PoseEstimator):
    """Pose estimation via Google MediaPipe Pose.

    Args:
        sample_every_ms: minimum spacing between analysed frames. The spec
            suggests ~100ms; punches are fast, so 33-50ms (i.e. keep most
            frames of 30fps footage) is usually better for retraction timing.
        min_detection_confidence / min_tracking_confidence: passed through.
        model_complexity: 0/1/2 — MediaPipe's speed/accuracy trade-off.
    """

    def __init__(
        self,
        *,
        sample_every_ms: float = 40.0,
        min_detection_confidence: float = 0.5,
        min_tracking_confidence: float = 0.5,
        model_complexity: int = 1,
    ) -> None:
        try:
            import cv2  # noqa: F401
            import mediapipe as mp
        except ImportError as exc:  # pragma: no cover - depends on optional deps
            raise ImportError(
                "MediaPipePoseEstimator needs 'mediapipe' and 'opencv-python'. "
                "Install with: pip install mediapipe opencv-python"
            ) from exc

        self._cv2 = cv2
        self._mp_pose = mp.solutions.pose
        self._sample_every_ms = sample_every_ms
        self._pose_kwargs = dict(
            static_image_mode=False,
            model_complexity=model_complexity,
            enable_segmentation=False,
            min_detection_confidence=min_detection_confidence,
            min_tracking_confidence=min_tracking_confidence,
        )

    def estimate(self, video_path: str) -> PoseSequence:  # pragma: no cover - needs real video + deps
        cv2 = self._cv2
        capture = cv2.VideoCapture(video_path)
        if not capture.isOpened():
            raise FileNotFoundError(f"could not open video: {video_path}")

        fps = capture.get(cv2.CAP_PROP_FPS) or 30.0
        frames: list[PoseFrame] = []
        last_kept_ms = -1e9
        kept_index = 0

        with self._mp_pose.Pose(**self._pose_kwargs) as pose:
            raw_index = 0
            while True:
                ok, image = capture.read()
                if not ok:
                    break
                timestamp_ms = (raw_index / fps) * 1000.0
                raw_index += 1
                if timestamp_ms - last_kept_ms < self._sample_every_ms:
                    continue
                last_kept_ms = timestamp_ms

                result = pose.process(cv2.cvtColor(image, cv2.COLOR_BGR2RGB))
                if not result.pose_landmarks:
                    continue

                keypoints: dict[Landmark, Keypoint] = {}
                landmarks = result.pose_landmarks.landmark
                for lm in _WANTED:
                    p = landmarks[int(lm)]
                    keypoints[lm] = Keypoint(x=p.x, y=p.y, z=p.z, visibility=p.visibility)

                frames.append(
                    PoseFrame(index=kept_index, timestamp_ms=timestamp_ms, keypoints=keypoints)
                )
                kept_index += 1

        capture.release()
        return PoseSequence(frames=frames, fps=fps, source=video_path)
