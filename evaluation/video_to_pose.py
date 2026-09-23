#!/usr/bin/env python3
"""Own-video 2D benchmark ingestion: raw video -> monocular pose.json.

The CoachMe benchmark is trustworthy 3D SMPL pose; the plan's §19-B "own raw
video" benchmark is the OTHER axis — real footage through the phone's actual
monocular pipeline (video -> mediapipe -> the same engine). This tool runs that
first stage once per clip and writes a `pose.json` next to the clip's
`ground_truth.json`, so the in-process `harness`/`optimize` loop then runs on it
exactly like it does on CoachMe — the harness never needs the video again.

Crucially the pose it writes is stamped `meta.depth = "image_2d"` (NOT
metric_3d): monocular z is unreliable, so the depth-gated rules (knee bend) stay
silent and rotation is judged in the 2D image plane — i.e. this measures the
detectors as they actually behave on the phone, which is the whole point of
re-tuning rotation here rather than trusting the 3D CoachMe number.

Shells out to `boxing-coach <video> --dump-pose` (needs mediapipe + the pose
model — the `boxing-coach` console script has them). Example:

    boxing-coach ...            # sanity-check it's on PATH
    python3 video_to_pose.py ../datasets/development
"""
from __future__ import annotations

import argparse
import json
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def _resolve_video(gt: dict, gt_path: Path, videos_dir: Path) -> Path | None:
    """Find the clip's source video: absolute, next to the labels, or in videos_dir."""
    src = gt.get("source_file")
    if not src:
        return None
    for candidate in (Path(src), gt_path.parent / src, videos_dir / src):
        if candidate.is_file():
            return candidate
    return None


def _rel(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def ingest(dataset_dir: Path, *, engine_cmd: list[str], videos_dir: Path,
           view: str, sample_every_ms: float, force: bool, only: set[str] | None) -> int:
    gt_paths = sorted(dataset_dir.glob("*/ground_truth.json"))
    if not gt_paths:
        print(f"no ground_truth.json under {dataset_dir}", file=sys.stderr)
        return 2

    wrote: list[str] = []
    skipped: list[str] = []
    failed: list[str] = []
    for gt_path in gt_paths:
        gt = json.loads(gt_path.read_text())
        clip = gt.get("video_id", gt_path.parent.name)
        if only and clip not in only:
            continue
        pose_path = gt_path.parent / "pose.json"
        if pose_path.exists() and not force:
            skipped.append(f"{clip} (pose.json exists; --force to redo)")
            continue
        video = _resolve_video(gt, gt_path, videos_dir)
        if video is None:
            failed.append(f"{clip} (source_file {gt.get('source_file')!r} not found)")
            continue

        cmd = [*engine_cmd, str(video), "--dump-pose", "-",
               "--sample-every-ms", str(sample_every_ms)]
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode != 0:
            tail = proc.stderr.strip().splitlines()[-1] if proc.stderr.strip() else "no stderr"
            failed.append(f"{clip} (dump-pose exit {proc.returncode}: {tail})")
            continue
        try:
            pose = json.loads(proc.stdout)
        except json.JSONDecodeError as e:
            failed.append(f"{clip} (dump-pose stdout not JSON: {e})")
            continue

        # Tag provenance + the 2D depth marker. image_2d keeps the depth-gated
        # rules silent and rotation in the image plane (phone-honest).
        meta = dict(pose.get("meta") or {})
        meta.update({"model": meta.get("model", "mediapipe"),
                     "depth": "image_2d", "view": view,
                     "source": "ownvideo"})
        pose["meta"] = meta
        pose_path.write_text(json.dumps(pose) + "\n")
        wrote.append(f"{clip} ({len(pose.get('frames', []))} frames)")

    for label, items in (("wrote", wrote), ("skipped", skipped), ("failed", failed)):
        if items:
            print(f"{label}: " + ", ".join(items))
    print(f"\n{len(wrote)} written, {len(skipped)} skipped, {len(failed)} failed "
          f"-> {_rel(dataset_dir)}/<clip>/pose.json")
    return 1 if failed else 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dataset", type=Path, help="own-video split dir, e.g. ../datasets/development")
    ap.add_argument("--engine-cmd", default="boxing-coach",
                    help='pose-dump command (default: "boxing-coach")')
    ap.add_argument("--videos-dir", type=Path, default=ROOT,
                    help="where source_file videos live (default: repo root)")
    ap.add_argument("--view", default="front", choices=["front", "side", "45"],
                    help="camera view of the footage, recorded into pose meta")
    ap.add_argument("--sample-every-ms", type=float, default=40.0)
    ap.add_argument("--only", nargs="*", metavar="VIDEO_ID")
    ap.add_argument("--force", action="store_true", help="overwrite existing pose.json")
    args = ap.parse_args(argv)

    engine_cmd = shlex.split(args.engine_cmd)
    if not shutil.which(engine_cmd[0]):
        print(f"warning: '{engine_cmd[0]}' not on PATH (needs mediapipe + pose model); "
              f"override with --engine-cmd", file=sys.stderr)
    return ingest(args.dataset, engine_cmd=engine_cmd, videos_dir=args.videos_dir,
                  view=args.view, sample_every_ms=args.sample_every_ms,
                  force=args.force, only=set(args.only) if args.only else None)


if __name__ == "__main__":
    raise SystemExit(main())
