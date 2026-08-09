"""Derived features computed once per sequence and shared across rules.

Two things live here:

1. `body_scale` — a person-and-camera-invariant length unit (median torso
   length). Every distance a rule uses is divided by this, so thresholds are
   expressed in "torso-lengths" and hold across people and camera distances
   rather than pixels.

2. `PunchDetector` — segments each hand's motion into discrete punch events.
   Several rules (guard return, hip rotation) operate on punches rather than
   raw frames, so detection happens once here instead of in every rule.

Punch detection is intentionally *adaptive*: a punch is a prominent local
maximum in normalised wrist reach relative to that boxer's own idle baseline,
not a hard-coded pixel threshold.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from ..domain.landmarks import Side
from ..domain.pose import PoseSequence
from ..domain.punch import PunchType
from . import geometry as geo
from .punch_classifier import PunchClassifierConfig, classify_punch


@dataclass(frozen=True, slots=True)
class PunchEvent:
    """One detected punch by one hand."""

    side: Side
    start_index: int   # frame where reach began rising past baseline
    peak_index: int    # frame of maximum extension
    end_index: int     # frame where the hand had retracted back to baseline
    peak_reach: float  # normalised wrist->shoulder distance at peak
    punch_type: PunchType = PunchType.UNKNOWN  # motion class (straight/hook/uppercut)

    def peak_timestamp_ms(self, sequence: PoseSequence) -> float:
        return sequence.frames[self.peak_index].timestamp_ms


@dataclass(frozen=True, slots=True)
class PunchDetectorConfig:
    # How far above baseline reach must rise (in torso-lengths) to count.
    prominence: float = 0.45
    # Reach must fall back to within this of baseline to close the event.
    retraction_ratio: float = 0.35
    # Ignore blips shorter than this (milliseconds).
    min_duration_ms: float = 60.0
    # Percentile of reach treated as the retracted/guard baseline.
    baseline_percentile: float = 25.0
    # A detected reach bump the classifier can't type (UNKNOWN) whose wrist
    # travelled less than this (torso-lengths) isn't a punch — it's a held-out /
    # range-finding hand or a clip-boundary frame crossing the global baseline,
    # not a stroke. Dropped rather than emitted as a phantom "punch". Real but
    # ambiguous strokes travel further, so they still register (as UNKNOWN).
    min_travel: float = 0.3


class PunchDetector:
    """Detects punch events from normalised wrist-reach signals."""

    def __init__(
        self,
        config: PunchDetectorConfig | None = None,
        classifier_config: PunchClassifierConfig | None = None,
    ) -> None:
        self._config = config or PunchDetectorConfig()
        self._classifier_config = classifier_config or PunchClassifierConfig()

    def detect(self, sequence: PoseSequence, body_scale: float) -> list[PunchEvent]:
        events: list[PunchEvent] = []
        for side in (Side.LEFT, Side.RIGHT):
            events.extend(self._detect_side(sequence, side, body_scale))
        events.sort(key=lambda e: e.peak_index)
        return events

    def reach_signal(self, sequence: PoseSequence, side: Side, body_scale: float) -> np.ndarray:
        """Normalised wrist->shoulder distance per frame (NaN where missing)."""
        out = np.full(len(sequence), np.nan)
        for i, frame in enumerate(sequence.frames):
            wrist = geo.frame_point(frame, side.wrist)
            shoulder = geo.frame_point(frame, side.shoulder)
            if np.any(np.isnan(wrist)) or np.any(np.isnan(shoulder)):
                continue
            out[i] = geo.distance(wrist, shoulder) / body_scale
        return out

    def _detect_side(self, sequence: PoseSequence, side: Side, body_scale: float) -> list[PunchEvent]:
        reach = self.reach_signal(sequence, side, body_scale)
        if np.all(np.isnan(reach)):
            return []

        # Baseline = the boxer's retracted/guard reach, estimated as a low
        # percentile. Using the median breaks down when a hand lingers extended
        # or dropped (that inflates the median and swallows the punch); the
        # retracted state is reliably at the low end of the distribution.
        baseline = float(np.nanpercentile(reach, self._config.baseline_percentile))
        rise_level = baseline + self._config.prominence
        close_level = baseline + self._config.prominence * self._config.retraction_ratio

        events: list[PunchEvent] = []
        i = 0
        n = len(reach)
        while i < n:
            if np.isnan(reach[i]) or reach[i] < rise_level:
                i += 1
                continue

            # Entered a punch: walk back to where it left baseline...
            start = i
            while start > 0 and (np.isnan(reach[start - 1]) or reach[start - 1] > close_level):
                start -= 1
            # ...forward to where it returns to baseline.
            end = i
            while end < n - 1 and (np.isnan(reach[end + 1]) or reach[end + 1] > close_level):
                end += 1

            window = reach[start : end + 1]
            peak_offset = int(np.nanargmax(window))
            peak = start + peak_offset

            duration = sequence.frames[end].timestamp_ms - sequence.frames[start].timestamp_ms
            if duration >= self._config.min_duration_ms:
                punch_type = classify_punch(
                    sequence, side, start, peak, float(reach[peak]), body_scale,
                    self._classifier_config,
                )
                # Drop phantom detections: a bump we can't classify AND whose wrist
                # barely moved is a held-out hand or a boundary frame, not a stroke.
                travel = self._wrist_travel(sequence, side, start, peak, body_scale)
                phantom = punch_type is PunchType.UNKNOWN and travel < self._config.min_travel
                if not phantom:
                    events.append(
                        PunchEvent(
                            side=side,
                            start_index=start,
                            peak_index=peak,
                            end_index=end,
                            peak_reach=float(reach[peak]),
                            punch_type=punch_type,
                        )
                    )
            i = end + 1
        return events

    @staticmethod
    def _wrist_travel(
        sequence: PoseSequence, side: Side, start_index: int, peak_index: int, body_scale: float
    ) -> float:
        """Total wrist path length over the out-stroke (start->peak), torso-lengths.

        The actual travelled path, not just the endpoints, so a real punch that
        arcs still reads as travel while a near-motionless bump reads as ~0.
        """
        total = 0.0
        prev: np.ndarray | None = None
        for j in range(start_index, peak_index + 1):
            w = geo.frame_point(sequence.frames[j], side.wrist)
            if prev is not None and not np.any(np.isnan(w)) and not np.any(np.isnan(prev)):
                total += float(np.linalg.norm(w - prev)) / body_scale
            prev = w
        return total


def compute_body_scale(sequence: PoseSequence) -> float:
    """Median torso length across frames — our normalisation unit.

    Raises if the sequence never yields a usable torso measurement, since every
    rule's thresholds depend on it.
    """
    lengths = [geo.torso_length(f) for f in sequence.frames]
    scale = geo.nanmedian(lengths)
    if not np.isfinite(scale) or scale <= 0:
        raise ValueError(
            "could not establish body scale — no frame had both shoulders and hips visible"
        )
    return scale
