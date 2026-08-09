"""The composition root: video path in, RoundAnalysis out.

This is the only place that knows about both a concrete `PoseEstimator` and a
concrete `VisionAnalysisAdapter`. Wire different implementations here without
touching anything else.
"""

from __future__ import annotations

from .adapters.base import VisionAnalysisAdapter
from .domain.analysis import RoundAnalysis
from .domain.drill import DrillContext
from .pose_estimation.estimator import PoseEstimator


class AnalysisPipeline:
    def __init__(self, estimator: PoseEstimator, adapter: VisionAnalysisAdapter) -> None:
        self._estimator = estimator
        self._adapter = adapter

    def analyse_video(self, video_path: str, drill: DrillContext | None = None) -> RoundAnalysis:
        sequence = self._estimator.estimate(video_path)
        return self._adapter.analyse(sequence, drill or DrillContext())
