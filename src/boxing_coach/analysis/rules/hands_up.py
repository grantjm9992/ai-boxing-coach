"""Rule: are the hands kept up when *not* punching?

Distinct from guard return (which is about the moment after a punch). This is
the baseline habit: between exchanges, do the wrists stay up near the head, or
do they drift down below the shoulder line? We measure the fraction of idle
frames spent with hands down.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from ...domain.analysis import Observation, Severity, SkillCategory
from ...domain.landmarks import Landmark, Side
from .. import geometry as geo
from ..context import AnalysisContext
from ..rule import Rule


@dataclass(frozen=True, slots=True)
class HandsUpConfig:
    # A hand is "down" when the wrist sits this far below the shoulder line
    # (in torso-lengths). Small buffer avoids flagging a hand right at the line.
    drop_margin: float = 0.10
    # Flag the round if a hand is down for more than this fraction of idle time.
    max_down_fraction: float = 0.25
    # Which hands to judge. A Philly shell keeps its lead hand deliberately low,
    # so that style checks the rear hand only (check_lead=False).
    check_lead: bool = True
    check_rear: bool = True
    # Soviet range game: judge "down" against the fighter's *own* settled carriage
    # rather than the shoulder line, so a deliberately low, consistent carry isn't
    # nagged as a drop — only a hand that sinks below where it lives is.
    relative_to_baseline: bool = False
    # Window (from the first idle frame) whose median wrist height defines that
    # baseline carriage. Only used when relative_to_baseline is on.
    baseline_window_ms: float = 1000.0
    # ...and don't count frames where the fighter is stepping in/out: a hand
    # carried low while translating is range management, not a dropped guard.
    excuse_while_moving: bool = False
    # Stance-centre speed (torso-lengths/sec) above which a frame counts as
    # "stepping in/out" for excuse_while_moving.
    moving_speed: float = 0.6


class HandsUpRule(Rule):
    id = "hands_up"
    focus_tags = frozenset()  # always relevant

    def __init__(self, config: HandsUpConfig | None = None) -> None:
        self._cfg = config or HandsUpConfig()

    def evaluate(self, context: AnalysisContext) -> list[Observation]:
        cfg = context.style_profile.config_for(self.id, self._cfg)
        idle = self._idle_frame_indices(context)
        if not idle:
            return []

        stance = context.drill.stance
        checked: set[Side] = set()
        if cfg.check_lead:
            checked.add(stance.lead)
        if cfg.check_rear:
            checked.add(stance.rear)

        observations: list[Observation] = []
        for side in (Side.LEFT, Side.RIGHT):
            if side not in checked:
                continue
            down_fraction, worst_ms = self._down_fraction(context, side, idle, cfg)
            if down_fraction is None:
                continue
            if down_fraction > cfg.max_down_fraction:
                hand = "lead" if side is stance.lead else "rear"
                observations.append(
                    Observation(
                        rule_id=self.id,
                        category=SkillCategory.DEFENCE,
                        severity=Severity.MODERATE if down_fraction > 0.5 else Severity.MINOR,
                        coaching_text=(
                            f"Your {hand} hand keeps drifting down between punches. "
                            f"Glue it to your cheek — you're open to the counter."
                        ),
                        timestamp_ms=worst_ms,
                        metrics={"down_fraction": round(down_fraction, 3)},
                        highlight_landmarks=(side.wrist,),
                    )
                )
        return observations

    def _idle_frame_indices(self, context: AnalysisContext) -> list[int]:
        """Frames that aren't part of any punch (start..end inclusive)."""
        punching = set()
        for p in context.punches:
            punching.update(range(p.start_index, p.end_index + 1))
        return [i for i in range(len(context.sequence)) if i not in punching]

    def _down_fraction(
        self, context: AnalysisContext, side: Side, idle: list[int], cfg: HandsUpConfig
    ) -> tuple[float | None, float | None]:
        seq = context.sequence
        scale = context.body_scale
        speeds = context.stance_speed if cfg.excuse_while_moving else None
        baseline = self._baseline_drop(context, side, idle, cfg) if cfg.relative_to_baseline else 0.0
        considered = 0
        down = 0
        worst_ms: float | None = None
        worst_drop = 0.0
        for i in idle:
            if speeds is not None and speeds[i] > cfg.moving_speed:
                continue  # stepping in/out — a low hand here is range management
            frame = seq.frames[i]
            wrist = geo.frame_point(frame, side.wrist)
            shoulder = geo.frame_point(frame, side.shoulder)
            if np.any(np.isnan(wrist)) or np.any(np.isnan(shoulder)):
                continue
            considered += 1
            # y grows downward, so wrist below shoulder => wrist.y larger. `baseline`
            # is 0 for the shoulder-line default, or the fighter's own carriage.
            drop = (wrist[1] - shoulder[1]) / scale - baseline
            if drop > cfg.drop_margin:
                down += 1
                if drop > worst_drop:
                    worst_drop = drop
                    worst_ms = frame.timestamp_ms
        if considered == 0:
            return None, None
        return down / considered, worst_ms

    def _baseline_drop(
        self, context: AnalysisContext, side: Side, idle: list[int], cfg: HandsUpConfig
    ) -> float:
        """Median wrist-below-shoulder (torso-lengths) over the fighter's settled
        early carriage — the reference a low hand is judged against under Soviet.

        Prefers the first `baseline_window_ms` of idle; falls back to all idle if
        that window is empty, and to 0 (the shoulder line) if there's no data.
        """
        seq = context.sequence
        scale = context.body_scale
        if not idle:
            return 0.0
        t0 = seq.frames[idle[0]].timestamp_ms
        early: list[float] = []
        overall: list[float] = []
        for i in idle:
            frame = seq.frames[i]
            wrist = geo.frame_point(frame, side.wrist)
            shoulder = geo.frame_point(frame, side.shoulder)
            if np.any(np.isnan(wrist)) or np.any(np.isnan(shoulder)):
                continue
            drop = (wrist[1] - shoulder[1]) / scale
            overall.append(drop)
            if frame.timestamp_ms - t0 <= cfg.baseline_window_ms:
                early.append(drop)
        drops = early or overall
        return float(np.median(drops)) if drops else 0.0
