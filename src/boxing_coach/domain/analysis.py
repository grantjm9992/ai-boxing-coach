"""The structured output of a round analysis.

These types mirror the shapes sketched in the spec (`Observation`,
`Correction`, `RoundAnalysis`, `RoundMetrics`, `FlaggedMoment`) so the skeleton
speaks the same language as the eventual app and DB schema.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum

from .landmarks import Landmark


class Severity(str, Enum):
    """How much a given observation matters. Ordered worst-first via `rank`."""

    POSITIVE = "positive"  # something done well — surfaced as encouragement
    MINOR = "minor"
    MODERATE = "moderate"
    MAJOR = "major"

    @property
    def rank(self) -> int:
        return {"major": 3, "moderate": 2, "minor": 1, "positive": 0}[self.value]

    @property
    def is_fault(self) -> bool:
        return self is not Severity.POSITIVE


class SkillCategory(str, Enum):
    """Skill areas from the spec's category tracking. Each observation maps to one."""

    CARDIO = "cardiovascular_endurance"
    MUSCULAR_ENDURANCE = "muscular_endurance"
    POWER = "power"
    FOOTWORK = "footwork"
    DEFENCE = "defence"
    JAB = "offence_jab"
    STRAIGHT = "offence_straight"
    HOOKS = "offence_hooks"
    UPPERCUTS = "offence_uppercuts"
    COMBINATIONS = "combinations"
    HEAD_MOVEMENT = "head_movement"
    DISTANCE = "distance_management"
    RHYTHM = "rhythm_timing"


@dataclass(frozen=True, slots=True)
class Observation:
    """A single specific thing the analysis noticed, tied to a moment in time.

    `coaching_text` is deliberately written in coach voice, not technical voice:
    "you're leaving your hand hanging after the jab", not "wrist-jaw distance
    exceeded 0.6 body-lengths for 480ms".
    """

    rule_id: str
    category: SkillCategory
    severity: Severity
    coaching_text: str
    timestamp_ms: float | None = None
    metrics: dict[str, float] = field(default_factory=dict)
    # Body parts a rule wants emphasised when this moment is shown to the user
    # (e.g. the wrist that dropped). Drives the highlight on annotated stills.
    highlight_landmarks: tuple[Landmark, ...] = ()


@dataclass(frozen=True, slots=True)
class Correction:
    """A prioritised, actionable correction distilled from the observations."""

    priority: int  # 1 = most important
    category: SkillCategory
    description: str
    suggested_drill: str | None = None
    example_timestamp_ms: float | None = None
    # Body parts to emphasise on the still for this correction.
    highlight_landmarks: tuple[Landmark, ...] = ()
    # Path to a rendered annotated still for this correction, if one was made.
    still_path: str | None = None


@dataclass(frozen=True, slots=True)
class FlaggedMoment:
    """A timestamp worth surfacing to the user for frame-by-frame review."""

    timestamp_ms: float
    reason: str
    severity: Severity


@dataclass(frozen=True, slots=True)
class RoundMetrics:
    """Quantitative round summary. Extend freely as rules add signals."""

    punches_thrown: int = 0
    guard_return_rate: float | None = None  # 0..1, None if no punches
    values: dict[str, float] = field(default_factory=dict)


@dataclass(slots=True)
class RoundAnalysis:
    """Everything the analysis produced for one recorded round."""

    overall_summary: str
    specific_observations: list[Observation] = field(default_factory=list)
    positive_notes: list[str] = field(default_factory=list)
    correction_priorities: list[Correction] = field(default_factory=list)
    metrics: RoundMetrics = field(default_factory=RoundMetrics)
    flagged_moments: list[FlaggedMoment] = field(default_factory=list)
