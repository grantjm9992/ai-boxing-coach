#!/usr/bin/env python3
"""Joint mappings: a pose *source* -> our internal landmark schema.

The plan (§2, §20) wants the boxing logic to depend on a provider-agnostic pose
schema, never on a source's raw joint indices. This is that seam. Each source
(CoachMe SMPL-22 today; MediaPipe, RTMPose, a multi-cam rig later) registers a
`JointMap` describing how its joints land on our mediapipe landmark indices and
what axis/scale conventions its coordinates follow. Downstream code asks the
registry for a source by name and gets a uniform mapping — adding a source is a
new registration, and it can't disturb an existing one (see `registry.py`).

stdlib only — no numpy/torch. Callers pass in already-decoded coordinate lists
(reading a `.pkl` still needs torch, but that stays in `smpl_to_pose.py`).
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Mapping

from .registry import Registry


@dataclass(frozen=True)
class JointMap:
    """How one pose source maps onto our mediapipe landmark schema.

    `source_to_mediapipe` maps source joint index -> mediapipe landmark index.
    Source joints with no landmark counterpart (SMPL feet, mediapipe eyes/ears)
    are simply absent — the boxing rules use only the joints listed here.
    """

    name: str
    source_joint_count: int
    #: source joint index -> mediapipe landmark index
    source_to_mediapipe: Mapping[int, int]
    #: added to every coordinate to move a body-centred source into positive
    #: frame space (mediapipe's convention). 0.0 for a source already in-frame.
    offset: float = 0.0
    #: default capture frame rate of the source footage.
    default_fps: float = 30.0
    #: `meta` stamped onto every sequence this source produces. `depth` in
    #: particular gates the depth-only rules (knee bend runs only on
    #: `metric_3d`), so a 2D source must NOT claim metric_3d.
    meta: Mapping[str, str] = field(default_factory=dict)

    def frame_to_keypoints(self, joints) -> dict[str, list[float]]:
        """One source frame (indexable by joint) -> {mp_index: [x,y,z,vis]}.

        `joints[i]` must yield an (x, y, z) triple for source joint `i`.
        """
        kp: dict[str, list[float]] = {}
        for src_idx, mp_idx in self.source_to_mediapipe.items():
            x, y, z = (float(v) for v in joints[src_idx])
            kp[str(mp_idx)] = [
                round(x + self.offset, 4),
                round(y + self.offset, 4),
                round(z + self.offset, 4),
                1.0,
            ]
        return kp


JOINT_MAPS: Registry[JointMap] = Registry("joint")


# CoachMe BX 22-joint SMPL skeleton. SMPL order per the CoachMe authors; the
# axis/offset facts (Y already points down like mediapipe; +0.5 into frame
# space; feet 10/11 dropped; head 15 stands in for nose 0) were verified from
# the data in the original smpl_to_pose spike — this preserves them exactly,
# now behind the named registry so a second source can't collide with it.
SMPL22 = JOINT_MAPS.register(
    "smpl22-coachme-v1",
    JointMap(
        name="smpl22-coachme-v1",
        source_joint_count=22,
        source_to_mediapipe={
            15: 0,            # head   -> nose (head reference)
            16: 11, 17: 12,   # shoulders L/R
            18: 13, 19: 14,   # elbows L/R
            20: 15, 21: 16,   # wrists L/R
            1: 23, 2: 24,     # hips L/R
            4: 25, 5: 26,     # knees L/R
            7: 27, 8: 28,     # ankles L/R
            # SMPL feet (10/11) dropped: our Landmark set has no foot index
            # (31/32); ankles carry the footwork signal.
        },
        offset=0.5,
        default_fps=50.0,     # CoachMe / Olympic source footage is 50 fps
        meta={
            "model": "smpl22->mediapipe",
            "root": "pelvis-centred",
            # Real triangulated SMPL 3D — z is trustworthy, so depth-gated rules
            # (knee bend) may run. A monocular 2D source must not set this.
            "depth": "metric_3d",
        },
    ),
)
