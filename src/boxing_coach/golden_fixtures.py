"""JSON codec for `PoseSequence`, shared by the cross-language golden fixtures.

The Dart port (v0.5, the shipping runtime) has to produce the same
`RoundAnalysis` as this reference engine. The mechanism that keeps them honest
is a set of golden fixtures: a `{input.json, expected.json}` pair per scenario,
read by *both* test suites. Python asserts it still produces `expected.json`;
Dart asserts it produces the same. A threshold change regenerates the goldens
and turns the Dart suite red until it is ported — drift becomes a failing test
rather than a discovered surprise.

This module owns the wire format. It is deliberately tiny and dependency-free
(domain types only) so the encoding is the single source of truth on both sides.

Wire format (see docs/v0.5-pose-integration.md §3.1) — landmark index as key,
fixed field order, coordinates rounded to 4 decimals so the fixtures stay
diffable and both languages compute from identical inputs:

    {
      "fps": 30.0,
      "source": "synthetic/clean_jab",
      "meta": {"model": "synthetic"},
      "frames": [
        {"i": 0, "t": 0.0, "kp": {"11": [0.42, 0.40, 0.0, 1.0], ...}}
      ]
    }
"""

from __future__ import annotations

from typing import Any

from .domain.landmarks import Landmark
from .domain.pose import Keypoint, PoseFrame, PoseSequence

# Decimal places every coordinate is rounded to before it is written. Both
# languages then compute from the same rounded numbers, so a match is a match.
COORD_DP = 4


def _round(value: float) -> float:
    return round(float(value), COORD_DP)


def keypoint_to_list(kp: Keypoint) -> list[float]:
    """[x, y, z, visibility], rounded. Fixed order, matched in Dart."""
    return [_round(kp.x), _round(kp.y), _round(kp.z), _round(kp.visibility)]


def sequence_to_json(sequence: PoseSequence) -> dict[str, Any]:
    return {
        "fps": sequence.fps,
        "source": sequence.source,
        "meta": dict(sequence.meta),
        "frames": [
            {
                "i": frame.index,
                "t": _round(frame.timestamp_ms),
                "kp": {
                    str(int(lm)): keypoint_to_list(kp)
                    for lm, kp in frame.keypoints.items()
                },
            }
            for frame in sequence.frames
        ],
    }


def sequence_from_json(data: dict[str, Any]) -> PoseSequence:
    frames: list[PoseFrame] = []
    for frame in data["frames"]:
        keypoints = {
            Landmark(int(index)): Keypoint(
                x=values[0], y=values[1], z=values[2], visibility=values[3]
            )
            for index, values in frame["kp"].items()
        }
        frames.append(
            PoseFrame(
                index=int(frame["i"]),
                timestamp_ms=float(frame["t"]),
                keypoints=keypoints,
            )
        )
    return PoseSequence(
        frames=frames,
        fps=float(data["fps"]),
        source=str(data.get("source", "unknown")),
        meta=dict(data.get("meta", {})),
    )


def round_tripped(sequence: PoseSequence) -> PoseSequence:
    """The sequence as it exists *after* going through the wire format.

    Golden `expected.json` values are computed from this, not from the raw
    fixture, so the recorded expectation is what both languages actually see
    (the rounded numbers) rather than full-precision values only Python holds.
    """
    return sequence_from_json(sequence_to_json(sequence))
