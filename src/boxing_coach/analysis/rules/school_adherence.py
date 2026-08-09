"""Rule: is the round being boxed in the chosen national school's game?

Only runs when the drill names a `School`. It reads the round-level features
(work rate, mobility, ground coverage, posture, body work, punch selection) and
surfaces the school's expectations the round falls short of — coaching *toward*
the game the fighter says they're training, in that school's language.

This is guidance, not a technique fault, so its observations are MINOR: real
faults (a dropped guard) outrank a school nudge in the correction list.
"""

from __future__ import annotations

from ...domain.analysis import Observation, Severity
from ..context import AnalysisContext
from ..rule import Rule
from ..schools import profile_for, round_feature_values


class SchoolAdherenceRule(Rule):
    id = "school_adherence"

    def applies_to(self, context: AnalysisContext) -> bool:
        return context.drill.school is not None

    def evaluate(self, context: AnalysisContext) -> list[Observation]:
        school = context.drill.school
        if school is None:
            return []

        profile = profile_for(school)
        values = round_feature_values(
            context.round_profile, context.punches, context.drill.stance
        )
        unmet = profile.unmet(values)

        if not unmet:
            return [
                Observation(
                    rule_id=self.id,
                    category=profile.expectations[0].category,
                    severity=Severity.POSITIVE,
                    coaching_text=f"Boxing a clean {profile.label} round — the game's all there.",
                )
            ]

        return [
            Observation(
                rule_id=self.id,
                category=exp.category,
                severity=Severity.MINOR,
                coaching_text=exp.cue,
            )
            for exp in unmet
        ]
