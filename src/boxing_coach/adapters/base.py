"""The vision-analysis adapter seam from the spec.

The spec defines `VisionAnalysisAdapter` with local/API/pose-only variants. The
skeleton implements the pose-only one — the MVP path — and leaves the VLM
variants as a clearly-marked extension point. Everything above this interface
(app, CLI) depends only on `analyse_round`.
"""

from __future__ import annotations

from abc import ABC, abstractmethod

from ..domain.analysis import RoundAnalysis
from ..domain.drill import DrillContext
from ..domain.pose import PoseSequence


class VisionAnalysisAdapter(ABC):
    """Analyses a round's poses into structured, coach-voiced feedback."""

    @abstractmethod
    def analyse(self, sequence: PoseSequence, drill: DrillContext) -> RoundAnalysis:
        """Produce the round analysis from an already-estimated pose sequence.

        Kept pose-in rather than video-in so the estimator is chosen once at the
        composition root and adapters stay focused on *analysis*.
        """
        raise NotImplementedError
