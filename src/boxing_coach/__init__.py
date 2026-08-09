"""boxing_coach — vision-analysis skeleton for the AI boxing coach.

Offline: video -> pose estimation -> coach rules -> structured observations.
No app, no timer, no sessions. Just the part that decides whether the product
can exist.

Typical wiring:

    from boxing_coach.pose_estimation import load_mediapipe_estimator
    from boxing_coach.adapters import PoseOnlyAdapter
    from boxing_coach.pipeline import AnalysisPipeline
    from boxing_coach.domain import DrillContext, Stance

    pipeline = AnalysisPipeline(load_mediapipe_estimator(), PoseOnlyAdapter())
    analysis = pipeline.analyse_video("shadow.mp4", DrillContext(stance=Stance.ORTHODOX))
"""

from __future__ import annotations

__version__ = "0.1.0"

__all__ = ["__version__"]
