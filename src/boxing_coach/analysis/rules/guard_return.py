"""Rule: does the hand come back to guard after a punch?

The flagship check from the conversation. For each detected punch we ask whether
the wrist came back to **where it launched the punch from** — the fighter's own
guard — within a short window. Measuring against the launch position rather than
an absolute head/cheek position means a deliberately low or extended lead carry
(a range-finder, a Philly shell) isn't flagged as a drop; only a hand that ends
up somewhere it didn't start is. We describe *how* it failed so the correction
is specific.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from ...domain.analysis import Observation, Severity, SkillCategory
from ...domain.landmarks import Side
from .. import geometry as geo
from ..context import AnalysisContext
from ..rule import Rule


@dataclass(frozen=True, slots=True)
class GuardReturnConfig:
    # The hand counts as "returned" if it comes back within this many
    # torso-lengths of where it launched the punch from (its own guard).
    return_radius: float = 0.5
    # After the window, a wrist this far below its launch height reads as dropped.
    drop_margin: float = 0.15
    # ...and a wrist still this far from its shoulder reads as left hanging out.
    extended_reach: float = 1.0
    # How long after retraction the hand has to get back.
    return_window_ms: float = 500.0
    # Below this fraction of returning punches, flag it as a round-level fault.
    healthy_return_rate: float = 0.8
    # Which hands to judge. A Philly shell returns its lead hand low on purpose,
    # so that style checks the rear hand only (check_lead=False).
    check_lead: bool = True
    check_rear: bool = True


class GuardReturnRule(Rule):
    id = "guard_return"
    focus_tags = frozenset({"jab", "straight", "combinations", "defence"})

    def __init__(self, config: GuardReturnConfig | None = None) -> None:
        self._cfg = config or GuardReturnConfig()

    def evaluate(self, context: AnalysisContext) -> list[Observation]:
        cfg = context.style_profile.config_for(self.id, self._cfg)
        seq = context.sequence
        checked = self._checked_sides(context, cfg)
        observations: list[Observation] = []
        returned = 0
        total = 0

        for punch in context.punches:
            if punch.side not in checked:
                continue
            total += 1
            verdict = self._classify_return(context, punch, cfg)
            if verdict is None:  # returned cleanly
                returned += 1
                continue
            failure_mode, worst_frame = verdict
            observations.append(
                Observation(
                    rule_id=self.id,
                    category=SkillCategory.DEFENCE,
                    severity=Severity.MODERATE,
                    coaching_text=self._coaching_text(
                        context.drill.stance, punch.side, failure_mode
                    ),
                    timestamp_ms=seq.frames[worst_frame].timestamp_ms,
                    metrics={"peak_reach": punch.peak_reach},
                    highlight_landmarks=(punch.side.wrist,),
                )
            )

        # Round-level summary: praise or flag depending on the rate.
        if total:
            rate = returned / total
            if rate >= cfg.healthy_return_rate and not observations:
                observations.append(
                    Observation(
                        rule_id=self.id,
                        category=SkillCategory.DEFENCE,
                        severity=Severity.POSITIVE,
                        coaching_text="Clean guard return all round — hands came straight back to guard.",
                        metrics={"guard_return_rate": rate},
                    )
                )
        return observations

    @staticmethod
    def _checked_sides(context: AnalysisContext, cfg: GuardReturnConfig) -> set[Side]:
        stance = context.drill.stance
        sides: set[Side] = set()
        if cfg.check_lead:
            sides.add(stance.lead)
        if cfg.check_rear:
            sides.add(stance.rear)
        return sides

    def _classify_return(
        self, context: AnalysisContext, punch, cfg: GuardReturnConfig
    ) -> tuple[str, int] | None:
        """None if the hand returns to its launch guard in time; else (mode, frame)."""
        seq = context.sequence
        scale = context.body_scale
        # The guard reference is where the hand launched the punch from.
        ref = geo.frame_point(seq.frames[punch.start_index], punch.side.wrist)
        if np.any(np.isnan(ref)):
            return None  # no usable guard reference — don't judge

        deadline = seq.frames[punch.end_index].timestamp_ms + cfg.return_window_ms

        best_dist = np.inf
        worst_dist = -np.inf
        worst_frame = punch.peak_index
        for i in range(punch.peak_index, len(seq)):
            frame = seq.frames[i]
            if frame.timestamp_ms > deadline:
                break
            wrist = geo.frame_point(frame, punch.side.wrist)
            if np.any(np.isnan(wrist)):
                continue
            dist = geo.distance(wrist, ref) / scale
            best_dist = min(best_dist, dist)
            if dist > worst_dist:  # most out-of-position moment, for the flag
                worst_dist = dist
                worst_frame = i

        if best_dist <= cfg.return_radius:
            return None

        # It didn't get back to guard — figure out how it failed for the cue.
        end_frame = seq.frames[min(punch.end_index, len(seq) - 1)]
        wrist = geo.frame_point(end_frame, punch.side.wrist)
        shoulder = geo.frame_point(end_frame, punch.side.shoulder)

        if not np.any(np.isnan(wrist)):
            # Ended below where it launched from -> dropped.
            if wrist[1] > ref[1] + cfg.drop_margin:
                return ("dropped", worst_frame)
            # Still far out from the shoulder -> left hanging out there.
            if not np.any(np.isnan(shoulder)):
                reach = geo.distance(wrist, shoulder) / scale
                if reach > cfg.extended_reach:
                    return ("extended", worst_frame)
        return ("slow", worst_frame)

    @staticmethod
    def _coaching_text(stance, side: Side, failure_mode: str) -> str:
        hand = "lead" if side is stance.lead else "rear"
        if failure_mode == "dropped":
            return f"Your {hand} hand drops after the punch — bring it back up to your guard, don't let it sink."
        if failure_mode == "extended":
            return f"You're leaving the {hand} hand hanging out there after the punch. Snap it back to guard every time."
        return f"Your {hand} hand is slow getting back to guard. The return should be as fast as the punch went out."
