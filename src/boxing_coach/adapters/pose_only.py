"""PoseOnlyAdapter — pose estimation + rules, no VLM.

The spec's fastest/most-private/cheapest option and the whole of the MVP. It
runs the rule engine, then synthesises the observations into the structured
`RoundAnalysis` the app expects: a summary, prioritised corrections, positive
notes, metrics, and flagged moments for review.

Synthesis here is deterministic and template-based on purpose — no model in the
loop. A VLM adapter would subclass `VisionAnalysisAdapter` and either replace or
enrich this synthesis step.
"""

from __future__ import annotations

from ..analysis.context import AnalysisContext
from ..analysis.engine import RuleEngine
from ..analysis.features import PunchDetectorConfig
from ..analysis.rule import Rule
from ..analysis.rules import default_rules
from ..analysis.schools import round_feature_values
from ..analysis.style_profiles import profile_for
from ..domain.analysis import (
    Correction,
    FlaggedMoment,
    Observation,
    RoundAnalysis,
    RoundMetrics,
    Severity,
)
from ..domain.drill import DrillContext
from ..domain.pose import PoseSequence
from ..domain.punch import punch_name
from .base import VisionAnalysisAdapter

# Which drill to suggest for a given fault category. Placeholder mapping — in
# the app this resolves against the exercise catalog.
_SUGGESTED_DRILLS = {
    "defence": "Jab–return shadow drill: throw the jab, snap the hand back to your cheek before resetting.",
    "footwork": "In-and-out drill: two minutes never letting both feet stay planted for more than a beat.",
    "offence_straight": "Rear-hand rotation drill: throw the cross slow, exaggerating the hip/shoulder turn.",
    "head_movement": "Slip-line drill: slip left/right after every jab.",
}


class PoseOnlyAdapter(VisionAnalysisAdapter):
    def __init__(
        self,
        rules: list[Rule] | None = None,
        *,
        punch_config: PunchDetectorConfig | None = None,
    ) -> None:
        self._engine = RuleEngine(rules if rules is not None else default_rules())
        self._punch_config = punch_config or PunchDetectorConfig()

    def analyse(self, sequence: PoseSequence, drill: DrillContext) -> RoundAnalysis:
        context = AnalysisContext(
            sequence=sequence,
            drill=drill,
            punch_config=self._punch_config,
            style_profile=profile_for(drill.style),
        )
        observations = self._engine.run(context)

        faults = [o for o in observations if o.severity.is_fault]
        positives = [o for o in observations if o.severity is Severity.POSITIVE]

        return RoundAnalysis(
            overall_summary=self._summary(context, faults, positives),
            specific_observations=observations,
            positive_notes=[o.coaching_text for o in positives],
            correction_priorities=self._corrections(faults),
            metrics=self._metrics(context, faults),
            flagged_moments=self._flagged(faults),
        )

    # -- synthesis helpers -------------------------------------------------

    def _summary(
        self, context: AnalysisContext, faults: list[Observation], positives: list[Observation]
    ) -> str:
        n_punches = len(context.punches)
        if not faults and positives:
            return f"Clean round — {n_punches} punches thrown and nothing to correct. Keep it there."
        if not faults and not positives:
            return f"{n_punches} punches thrown. Nothing flagged, but not much to work with either."
        top = faults[0]
        extra = f" plus {len(faults) - 1} other point(s)" if len(faults) > 1 else ""
        return f"{n_punches} punches thrown. Main thing to fix: {top.coaching_text}{extra}"

    def _corrections(self, faults: list[Observation]) -> list[Correction]:
        # One correction per category, worst-severity first, de-duplicated.
        seen: set[str] = set()
        corrections: list[Correction] = []
        priority = 1
        for obs in faults:  # already sorted worst-first
            if obs.category.value in seen:
                continue
            seen.add(obs.category.value)
            corrections.append(
                Correction(
                    priority=priority,
                    category=obs.category,
                    description=obs.coaching_text,
                    suggested_drill=_SUGGESTED_DRILLS.get(obs.category.value),
                    example_timestamp_ms=obs.timestamp_ms,
                    highlight_landmarks=obs.highlight_landmarks,
                )
            )
            priority += 1
        return corrections

    def _metrics(self, context: AnalysisContext, faults: list[Observation]) -> RoundMetrics:
        n_punches = len(context.punches)
        guard_returns = [
            o for o in faults if o.rule_id == "guard_return" and o.severity.is_fault
        ]
        guard_rate = None
        if n_punches:
            guard_rate = round(1.0 - min(len(guard_returns), n_punches) / n_punches, 3)
        features = round_feature_values(context.round_profile, context.punches, context.drill.stance)
        return RoundMetrics(
            punches_thrown=n_punches,
            guard_return_rate=guard_rate,
            punch_mix=self._punch_mix(context),
            values={
                "body_scale": round(context.body_scale, 4),
                **{k: round(v, 3) for k, v in features.items()},
            },
        )

    def _punch_mix(self, context: AnalysisContext) -> dict[str, int]:
        stance = context.drill.stance
        mix: dict[str, int] = {}
        for punch in context.punches:
            name = punch_name(punch.punch_type, punch.side, stance)
            mix[name] = mix.get(name, 0) + 1
        return mix

    def _flagged(self, faults: list[Observation]) -> list[FlaggedMoment]:
        moments = [
            FlaggedMoment(timestamp_ms=o.timestamp_ms, reason=o.coaching_text, severity=o.severity)
            for o in faults
            if o.timestamp_ms is not None
        ]
        moments.sort(key=lambda m: m.timestamp_ms)
        return moments
