"""School profiles — each national school as expectations on round features.

A school is characterised by a handful of expectations on the `RoundProfile`
(plus two punch-selection features): each is a feature, a wanted direction, a
threshold, and the coaching cue to give when the round falls short. The same
expectations serve two jobs:

- **classify** a round ("this read as Mexican") by how many expectations it meets;
- **coach toward** a chosen school by surfacing the expectations it misses.

Thresholds are deliberately explicit and modest — starting characterisations to
calibrate against real footage, not doctrine. American is the loosest, because
"fast and varied" has the least distinct pose signature.
"""

from __future__ import annotations

from dataclasses import dataclass

from ..domain.analysis import SkillCategory
from ..domain.landmarks import Stance
from ..domain.punch import PunchType, punch_name
from ..domain.school import School
from .round_profile import RoundProfile

# Feature keys an expectation can reference: the RoundProfile fields plus two
# punch-selection features computed from the detected punches.
#   jab_ratio      — fraction of punches that are jabs (lead straights)
#   punch_variety  — number of distinct named punches used in the round


@dataclass(frozen=True, slots=True)
class Expectation:
    feature: str
    want: str          # "high" (value >= threshold) or "low" (value <= threshold)
    threshold: float
    cue: str           # coaching text when the expectation is missed
    category: SkillCategory

    def met_by(self, value: float) -> bool:
        return value >= self.threshold if self.want == "high" else value <= self.threshold


@dataclass(frozen=True, slots=True)
class SchoolProfile:
    school: School
    label: str
    summary: str
    expectations: tuple[Expectation, ...]

    def unmet(self, values: dict[str, float]) -> list[Expectation]:
        return [e for e in self.expectations if e.feature in values and not e.met_by(values[e.feature])]

    def match_score(self, values: dict[str, float]) -> float:
        """Fraction of (measurable) expectations the round meets, 0..1."""
        applicable = [e for e in self.expectations if e.feature in values]
        if not applicable:
            return 0.0
        met = sum(1 for e in applicable if e.met_by(values[e.feature]))
        return met / len(applicable)


_C = SkillCategory
_SCHOOL_PROFILES: dict[School, SchoolProfile] = {
    School.MEXICAN: SchoolProfile(
        school=School.MEXICAN,
        label="Mexican",
        summary="Pressure and volume, built on body work, coming forward.",
        expectations=(
            Expectation("output_per_min", "high", 40.0,
                        "Mexican pressure lives on volume — up the work rate, throw in bunches.", _C.RHYTHM),
            Expectation("body_shot_ratio", "high", 0.20,
                        "Go downstairs — the Mexican game is built on body work, not just head-hunting.", _C.HOOKS),
            Expectation("torso_lean_deg", "high", 12.0,
                        "Get low and crowd your man — pressure fighters press forward, they don't stand tall.", _C.FOOTWORK),
        ),
    ),
    School.SOVIET: SchoolProfile(
        school=School.SOVIET,
        label="Soviet",
        summary="Technical in-and-out game behind an educated jab; economical.",
        expectations=(
            Expectation("ground_coverage", "high", 0.35,
                        "The Soviet game is in-and-out — get your work and reset off the line, don't sit there.", _C.FOOTWORK),
            Expectation("mobility", "high", 0.30,
                        "Stay on your feet and move — the Soviet system is built on footwork.", _C.FOOTWORK),
            Expectation("jab_ratio", "high", 0.40,
                        "Lead everything with the jab — it's the spine of the Soviet style.", _C.JAB),
        ),
    ),
    School.EUROPEAN: SchoolProfile(
        school=School.EUROPEAN,
        label="European",
        summary="Upright classical stance, long-range jab, points boxing.",
        expectations=(
            Expectation("torso_lean_deg", "low", 10.0,
                        "Stand tall in the classical stance — European boxing is upright and long.", _C.FOOTWORK),
            Expectation("jab_ratio", "high", 0.40,
                        "Box behind a long jab and hold your range.", _C.JAB),
            Expectation("body_shot_ratio", "low", 0.15,
                        "Keep it upstairs at range — this is a points game, not a body war.", _C.DISTANCE),
        ),
    ),
    School.AMERICAN: SchoolProfile(
        school=School.AMERICAN,
        label="American",
        summary="Athletic, fast and varied combinations. (Loosest to detect.)",
        expectations=(
            Expectation("output_per_min", "high", 40.0,
                        "American boxing is busy — let your hands go in combination.", _C.COMBINATIONS),
            Expectation("punch_variety", "high", 3.0,
                        "Mix your punches — jab, cross, hook, uppercut — not one note.", _C.COMBINATIONS),
            Expectation("mobility", "high", 0.30,
                        "Use your athleticism — move, don't stand flat.", _C.FOOTWORK),
        ),
    ),
}


def profile_for(school: School) -> SchoolProfile:
    return _SCHOOL_PROFILES[school]


def all_profiles() -> dict[School, SchoolProfile]:
    return dict(_SCHOOL_PROFILES)


def classify_school(values: dict[str, float]) -> list[tuple[School, float]]:
    """Rank schools by how well the round's features match each, best first."""
    scored = [(s, p.match_score(values)) for s, p in _SCHOOL_PROFILES.items()]
    scored.sort(key=lambda sp: sp[1], reverse=True)
    return scored


def round_feature_values(profile: RoundProfile, punches, stance: Stance) -> dict[str, float]:
    """The feature dict schools are judged on: round profile + punch selection."""
    total = len(punches)
    jabs = sum(
        1 for p in punches if p.punch_type is PunchType.STRAIGHT and p.side is stance.lead
    )
    variety = len({punch_name(p.punch_type, p.side, stance) for p in punches}) if total else 0
    return {
        "output_per_min": profile.output_per_min,
        "mobility": profile.mobility,
        "ground_coverage": profile.ground_coverage,
        "torso_lean_deg": profile.torso_lean_deg,
        "body_shot_ratio": profile.body_shot_ratio,
        "jab_ratio": (jabs / total) if total else 0.0,
        "punch_variety": float(variety),
    }
