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
        considered = 0
        down = 0
        worst_ms: float | None = None
        worst_drop = 0.0
        for i in idle:
            frame = seq.frames[i]
            wrist = geo.frame_point(frame, side.wrist)
            shoulder = geo.frame_point(frame, side.shoulder)
            if np.any(np.isnan(wrist)) or np.any(np.isnan(shoulder)):
                continue
            considered += 1
            # y grows downward, so wrist below shoulder => wrist.y larger.
            drop = (wrist[1] - shoulder[1]) / scale
            if drop > cfg.drop_margin:
                down += 1
                if drop > worst_drop:
                    worst_drop = drop
                    worst_ms = frame.timestamp_ms
        if considered == 0:
            return None, None
        return down / considered, worst_ms
