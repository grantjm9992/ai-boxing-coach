#!/usr/bin/env python3
"""Convert CoachMe BX 22-joint SMPL skeletons (.pkl) into our pose wire format.

CoachMe ships each clip's pose as a (T, 66) tensor — T frames x 22 SMPL joints x
(x, y, z), pelvis-centred — inside `BX_{train,test}.pkl`. This maps those joints
onto our mediapipe landmark schema and writes one `pose.json` per clip (the same
golden-fixture wire format `golden_fixtures.sequence_to_json` emits), so the
existing engine path (dump_round_analysis.dart / analyse_sequence) runs on these
clips unchanged — the whole rest of the pipeline never needs torch or the pkl.

Axis note (verified from the data): SMPL Y here already points DOWN (head y<0,
feet y>0), matching mediapipe, so no flip is needed — only a +0.5 offset to move
the pelvis-centred body into positive frame space. Scale is left alone; the
engine's body_scale normalisation makes the relative features scale-invariant.
The 22 SMPL joints cover every landmark the boxing rules use; joints mediapipe
has but SMPL lacks (eyes/ears/heels) are simply omitted. SMPL head (15) stands
in for the mediapipe nose (0) as the head reference.

Reading the .pkl needs torch (only here); the emitted pose.json needs nothing.

Usage:
    python3 smpl_to_pose.py /path/to/BX_test.json.pkl --split test --out ../datasets/coachme
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from mappings.joints import SMPL22

ROOT = Path(__file__).resolve().parent.parent

# The SMPL-22 -> mediapipe joint mapping (indices, +0.5 offset, 50 fps, the
# metric_3d depth flag) now lives behind the versioned joint registry so a
# second pose source can't collide with it. Kept as module aliases for anyone
# importing them.
JOINT_MAP = SMPL22
SMPL_TO_MP = SMPL22.source_to_mediapipe
OFFSET = SMPL22.offset
FPS = SMPL22.default_fps


def frame_to_kp(joints) -> dict[str, list[float]]:
    """One (22,3) frame -> {mp_index: [x, y, z, visibility]}."""
    return JOINT_MAP.frame_to_keypoints(joints)


def sequence_wire(coords, video_name: str) -> dict:
    """(T,66) coordinates -> our pose wire dict."""
    frames = []
    for i, flat in enumerate(coords):
        joints = [flat[j * 3:j * 3 + 3] for j in range(JOINT_MAP.source_joint_count)]
        frames.append({"i": i, "t": round(i / FPS * 1000.0, 4),
                       "kp": frame_to_kp(joints)})
    # meta carries depth=metric_3d (trustworthy SMPL 3D) so depth-gated rules
    # (knee bend) may run; a 2D source's JointMap would not set it.
    return {"fps": FPS, "source": f"coachme/{video_name}",
            "meta": dict(JOINT_MAP.meta),
            "frames": frames}


def convert_pkl(pkl_path: Path, split: str, out_root: Path) -> int:
    import pickle
    import torch  # noqa: F401 - needed so pickle can rebuild the tensors
    import numpy as np

    entries = pickle.load(open(pkl_path, "rb"))
    n = 0
    for e in entries:
        coords = np.asarray(e["coordinates"]).tolist()
        wire = sequence_wire(coords, e["video_name"])
        clip_dir = out_root / split / e["video_name"]
        clip_dir.mkdir(parents=True, exist_ok=True)
        (clip_dir / "pose.json").write_text(json.dumps(wire) + "\n")
        n += 1
    return n


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("pkl", type=Path, help="BX_train.pkl or BX_test.pkl")
    ap.add_argument("--split", required=True, help="subsplit dir, e.g. train / test")
    ap.add_argument("--out", type=Path, default=ROOT / "datasets" / "coachme")
    args = ap.parse_args(argv)
    n = convert_pkl(args.pkl, args.split, args.out)
    print(f"wrote {n} pose.json -> {args.out}/{args.split}/<video_id>/pose.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
