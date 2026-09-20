#!/usr/bin/env python3
"""The tuning search space: which detector thresholds the optimiser may move.

Plan §17 is emphatic — thresholds must be EMPIRICAL, learned from the benchmark
distributions, not hand-picked constants. This module declares, per rule, the
numeric config fields that are legitimately tunable and the range/step the
optimiser is allowed to explore. It is pure data (no engine import), so it is
stdlib-testable and can't drag numpy in.

Only *thresholds* live here. Structural/style flags (`check_lead`,
`relative_to_baseline`, ...) are deliberately excluded: those encode a fighting
style's intent, not a value to fit, and are owned by the StyleProfile layer.

A `ParamSpec` is one knob:
    rule_id . field  in  [min, max]  stepped by `step`  (default = the rule's own)
The optimiser hill-climbs each knob independently (coordinate descent), which is
exactly the plan's "propose ONE change, let the benchmark decide" loop (§16/§25).
"""
from __future__ import annotations

from dataclasses import dataclass

from .registry import Registry


@dataclass(frozen=True)
class ParamSpec:
    rule_id: str
    field: str
    default: float
    lo: float
    hi: float
    step: float
    kind: str = "float"  # "float" | "int"

    @property
    def key(self) -> str:
        return f"{self.rule_id}.{self.field}"

    def clamp(self, value: float) -> float:
        value = min(max(value, self.lo), self.hi)
        return round(value) if self.kind == "int" else round(value, 6)

    def candidates(self) -> list[float]:
        """Every legal grid value lo..hi, snapped to the field's kind."""
        out: list[float] = []
        v = self.lo
        # Guard against fp drift accumulating across many steps.
        n = int(round((self.hi - self.lo) / self.step))
        for i in range(n + 1):
            out.append(self.clamp(self.lo + i * self.step))
        # Always include the default even if it's off-grid.
        d = self.clamp(self.default)
        if d not in out:
            out.append(d)
        return sorted(set(out))

    def neighbours(self, value: float) -> list[float]:
        """The grid values one step either side of `value` (for hill-climbing)."""
        v = self.clamp(value)
        out = [self.clamp(v - self.step), self.clamp(v + self.step)]
        return [c for c in out if c != v and self.lo <= c <= self.hi]


PARAM_SPACES: Registry[tuple[ParamSpec, ...]] = Registry("param-space")


# v1 — the four detectors that actually fire on CoachMe pose and have taxonomy
# coverage there (guard, defence/recovery, rotation, body-position). Ranges
# bracket each rule's own default generously enough to trade precision against
# recall in both directions, without wandering into nonsense.
_SPACE_V1: tuple[ParamSpec, ...] = (
    # --- hands_up (guard between punches; over-fires on CoachMe -> tighten) ---
    ParamSpec("hands_up", "drop_margin", 0.10, 0.02, 0.30, 0.02),
    ParamSpec("hands_up", "max_down_fraction", 0.25, 0.10, 0.60, 0.05),
    # --- guard_return (hand back to guard after a punch) ---
    ParamSpec("guard_return", "return_radius", 0.50, 0.20, 0.90, 0.05),
    ParamSpec("guard_return", "drop_margin", 0.15, 0.05, 0.40, 0.05),
    ParamSpec("guard_return", "healthy_return_rate", 0.80, 0.50, 0.95, 0.05),
    # --- hip_rotation (cross driven by rotation; under-fires on 3D -> loosen) ---
    ParamSpec("hip_rotation", "min_shoulder_drive", 0.12, 0.04, 0.30, 0.02),
    ParamSpec("hip_rotation", "min_peak_reach", 0.90, 0.60, 1.10, 0.05),
    # --- knee_bend (locked legs; 3D-gated, so it runs on CoachMe SMPL) ---
    ParamSpec("knee_bend", "straight_deg", 168.0, 158.0, 176.0, 1.0),
    ParamSpec("knee_bend", "moderate_deg", 173.0, 165.0, 179.0, 1.0),
)

SPACE_V1 = PARAM_SPACES.register("coachme-detectors-v1", _SPACE_V1)

#: The space the optimiser tunes unless told otherwise.
DEFAULT_PARAM_SPACE = "coachme-detectors-v1"


def space(name: str = DEFAULT_PARAM_SPACE) -> tuple[ParamSpec, ...]:
    return PARAM_SPACES.get(name)
