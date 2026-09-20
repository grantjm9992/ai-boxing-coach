#!/usr/bin/env python3
"""TunedProfile — the optimiser's output artifact AND the engine bridge.

A `TunedProfile` is just `{rule_id: {field: value}}`: the detector-threshold
overrides the optimiser found. It is the concrete, portable thing that improves
the on-phone analysis — a small, reviewable JSON of *which numbers changed and
to what*. Two consumers read it:

  * the Python reference engine, via `to_style_profile()` here, so the benchmark
    can score a tuned profile end-to-end; and
  * the Dart on-phone engine (a parity port), which reads the same JSON to apply
    the same thresholds — see PORTING.md.

(De)serialisation is stdlib-only so the artifact can be produced, diffed and
version-controlled anywhere. Only `to_style_profile()` touches the engine's
config classes, and it imports them lazily — so loading/saving a profile never
drags numpy in.
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Mapping

# rule_id -> (module, config class name). Lazily imported in to_style_profile so
# this module stays stdlib-importable. Adding a tunable rule = one entry here.
_CONFIG_CLASSES: dict[str, tuple[str, str]] = {
    "hands_up": ("boxing_coach.analysis.rules.hands_up", "HandsUpConfig"),
    "guard_return": ("boxing_coach.analysis.rules.guard_return", "GuardReturnConfig"),
    "hip_rotation": ("boxing_coach.analysis.rules.hip_rotation", "HipRotationConfig"),
    "knee_bend": ("boxing_coach.analysis.rules.knee_bend", "KneeBendConfig"),
    "footwork": ("boxing_coach.analysis.rules.footwork", "FootworkConfig"),
    "head_movement": ("boxing_coach.analysis.rules.head_movement", "HeadMovementConfig"),
}


@dataclass(frozen=True)
class TunedProfile:
    """Detector-threshold overrides: rule_id -> {field: value}."""

    name: str = "tuned"
    overrides: Mapping[str, Mapping[str, float]] = field(default_factory=dict)

    # -- immutable updates -------------------------------------------------
    def with_override(self, rule_id: str, field_name: str, value: float) -> "TunedProfile":
        """A copy with one knob set (or updated)."""
        new = {r: dict(f) for r, f in self.overrides.items()}
        new.setdefault(rule_id, {})[field_name] = value
        return TunedProfile(self.name, new)

    def get(self, rule_id: str, field_name: str, default: float) -> float:
        return self.overrides.get(rule_id, {}).get(field_name, default)

    def is_empty(self) -> bool:
        return not any(self.overrides.values())

    def flat(self) -> dict[str, float]:
        """`{'rule.field': value}` — handy for diffs and logging."""
        return {
            f"{rule_id}.{fld}": val
            for rule_id, fields in sorted(self.overrides.items())
            for fld, val in sorted(fields.items())
        }

    # -- serialisation (stdlib only) --------------------------------------
    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "overrides": {r: dict(f) for r, f in self.overrides.items() if f},
        }

    @classmethod
    def from_dict(cls, data: dict) -> "TunedProfile":
        return cls(data.get("name", "tuned"), data.get("overrides", {}))

    def save(self, path: Path) -> None:
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(self.to_dict(), indent=2) + "\n")

    @classmethod
    def load(cls, path: Path) -> "TunedProfile":
        return cls.from_dict(json.loads(Path(path).read_text()))

    # -- engine bridge (imports config classes lazily) --------------------
    def to_style_profile(self, base=None):
        """Build a `StyleProfile` that applies these overrides on top of `base`.

        `base` is an existing StyleProfile to layer onto (e.g. a Philly shell);
        default None means the neutral profile. For each overridden rule the
        overrides are applied field-wise onto the base's config for that rule
        (or the rule's own default if the base sets none) via
        `dataclasses.replace`, exactly like the School layering in
        `style_profiles.resolve_profile` — so a field the base set survives
        unless we override that same field.
        """
        import importlib
        from dataclasses import replace

        from boxing_coach.analysis.style import DEFAULT_STYLE_PROFILE, StyleProfile

        base = base or DEFAULT_STYLE_PROFILE
        configs = dict(base.rule_configs)
        for rule_id, fields in self.overrides.items():
            if not fields:
                continue
            if rule_id not in _CONFIG_CLASSES:
                raise KeyError(f"no config class registered for rule {rule_id!r}")
            existing = configs.get(rule_id)
            if existing is None:
                module_name, cls_name = _CONFIG_CLASSES[rule_id]
                cls = getattr(importlib.import_module(module_name), cls_name)
                existing = cls()
            configs[rule_id] = replace(existing, **dict(fields))
        return StyleProfile(
            style=base.style,
            label=f"{base.label} + {self.name}",
            summary=f"{base.summary} Tuned thresholds: {self.name}.",
            disabled_rules=base.disabled_rules,
            rule_configs=configs,
        )
