"""The composition root: video path in, RoundAnalysis out.

This is the only place that knows about both a concrete `PoseEstimator` and a
concrete `VisionAnalysisAdapter`. Wire different implementations here without
touching anything else.
"""

from __future__ import annotations

from .adapters.base import VisionAnalysisAdapter
from .domain.analysis import RoundAnalysis
from .domain.drill import DrillContext
from .domain.pose import PoseSequence
from .pose_estimation.estimator import PoseEstimator


class AnalysisPipeline:
    def __init__(self, estimator: PoseEstimator, adapter: VisionAnalysisAdapter) -> None:
        self._estimator = estimator
        self._adapter = adapter

    def analyse_video(self, video_path: str, drill: DrillContext | None = None) -> RoundAnalysis:
        return self.analyse_sequence(self.estimate(video_path), drill)

    def estimate(self, video_path: str) -> PoseSequence:
        """Video -> keypoints. Exposed so callers that also need the pose data
        (e.g. to render stills) don't have to estimate twice."""
        return self._estimator.estimate(video_path)

    def analyse_sequence(
        self, sequence: PoseSequence, drill: DrillContext | None = None
    ) -> RoundAnalysis:
        return self._adapter.analyse(sequence, drill or DrillContext())
