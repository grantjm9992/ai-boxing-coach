"""Pluggable, versioned mapping abstractions for the eval platform.

Every translation the platform depends on is a *named, versioned* entry in a
`Registry` here, so iterating on one mapping never disturbs another (the plan's
"freeze the mapping the benchmark trusts; a better one is a new version"):

  * joints      — pose source (SMPL, MediaPipe, ...) -> internal landmark schema
  * phrase_map  — coach free-text -> taxonomy codes
  * param_space — which detector thresholds the optimiser may move
  * tuned_profile — the optimiser's output overrides + the engine bridge

stdlib-only to import; only `TunedProfile.to_style_profile()` touches the engine.
"""
from __future__ import annotations

from .joints import JOINT_MAPS, JointMap
from .param_space import DEFAULT_PARAM_SPACE, PARAM_SPACES, ParamSpec, space
from .phrase_map import DEFAULT_PHRASE_MAP, PHRASE_MAPS, PhraseMap
from .registry import Registry
from .tuned_profile import TunedProfile

__all__ = [
    "Registry",
    "JOINT_MAPS", "JointMap",
    "PHRASE_MAPS", "PhraseMap", "DEFAULT_PHRASE_MAP",
    "PARAM_SPACES", "ParamSpec", "space", "DEFAULT_PARAM_SPACE",
    "TunedProfile",
]
