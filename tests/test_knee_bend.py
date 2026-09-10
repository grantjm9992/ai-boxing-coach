"""KneeBendRule — 3D-gated detection of locked-out legs (POS_006)."""

from boxing_coach.analysis.context import AnalysisContext
from boxing_coach.analysis.rules.knee_bend import KneeBendRule
from boxing_coach.domain.drill import DrillContext
from boxing_coach.domain.landmarks import Landmark
from boxing_coach.domain.pose import Keypoint, PoseFrame, PoseSequence

# A leg is three points: hip, knee, ankle. Straight = hip/knee/ankle colinear
# (angle ~180); bent = knee pushed forward in z so the angle closes.
_STRAIGHT = {
    Landmark.LEFT_HIP: (0.44, 0.60, 0.0), Landmark.RIGHT_HIP: (0.56, 0.60, 0.0),
    Landmark.LEFT_KNEE: (0.44, 0.775, 0.0), Landmark.RIGHT_KNEE: (0.56, 0.775, 0.0),
    Landmark.LEFT_ANKLE: (0.44, 0.95, 0.0), Landmark.RIGHT_ANKLE: (0.56, 0.95, 0.0),
    Landmark.LEFT_SHOULDER: (0.42, 0.40, 0.0), Landmark.RIGHT_SHOULDER: (0.58, 0.40, 0.0),
}
_BENT = {
    **_STRAIGHT,
    Landmark.LEFT_KNEE: (0.44, 0.775, 0.15), Landmark.RIGHT_KNEE: (0.56, 0.775, 0.15),
}


def _sequence(positions, *, depth_3d: bool, n: int = 15) -> PoseSequence:
    frames = [
        PoseFrame(
            index=i, timestamp_ms=i * 33.3,
            keypoints={lm: Keypoint(x=p[0], y=p[1], z=p[2]) for lm, p in positions.items()},
        )
        for i in range(n)
    ]
    meta = {"depth": "metric_3d"} if depth_3d else {}
    return PoseSequence(frames=frames, fps=30.0, source="test", meta=meta)


def _run(seq) -> list:
    ctx = AnalysisContext(sequence=seq, drill=DrillContext())
    return KneeBendRule().evaluate(ctx)


def test_flags_locked_legs_on_3d_input():
    obs = _run(_sequence(_STRAIGHT, depth_3d=True))
    assert len(obs) == 1
    o = obs[0]
    assert o.rule_id == "knee_bend"
    assert o.metrics["knee_angle_deg"] > 173  # near-straight -> moderate
    assert o.severity.value == "moderate"


def test_bent_knees_are_not_flagged():
    assert _run(_sequence(_BENT, depth_3d=True)) == []


def test_silent_on_monocular_2d_even_when_legs_straight():
    # Same locked-out legs, but no metric_3d marker -> depth gate keeps it quiet
    # (brief §12/§35: knee bend is not read from a frontal 2D view).
    assert _run(_sequence(_STRAIGHT, depth_3d=False)) == []
