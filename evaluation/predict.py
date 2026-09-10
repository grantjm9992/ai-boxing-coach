#!/usr/bin/env python3
"""Step 1 of the eval loop: run an engine over a dataset and write raw predictions.

For each clip in <dataset_dir> that has a ground_truth.json and a resolvable
source video, run the analysis engine and write its output to

    datasets/<split>/<clip>/predictions/<version>/<layer>.json

which `runner.py run --version <version> --layer <layer>` then scores against the
clip's ground_truth.json. Prediction files hold the UNMODIFIED engine output
(normalise.py adapts them at score time), so they also serve as a provenance
record of exactly what a given version produced.

Layers
------
  detection : runs the Python engine (`boxing-coach <video> --json`), passing the
              clip's stance / style / school from its ground-truth context so the
              rules are gated the same way they would be in the app.
  coaching  : the Dart AiCoachReport has no headless CLI yet, so this ingests
              pre-exported reports from --import-dir/<video_id>.json rather than
              generating them.

Examples
--------
  # write real detection predictions for every clip in the dev set
  python3 predict.py ../datasets/development --version coach-v31 --layer detection

  # preview the engine commands without running them
  python3 predict.py ../datasets/development --version coach-v31 --dry-run

  # bring in manually exported Dart coaching reports
  python3 predict.py ../datasets/development --version coach-v31 \
      --layer coaching --import-dir /path/to/exported_reports

The engine defaults to the `boxing-coach` console script; override with
--engine-cmd (e.g. "python3 -m boxing_coach.cli") if it is not on PATH.
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

# Valid engine argument values (from boxing_coach.cli). Context fields that are
# null, "unknown", or outside these sets are simply not passed — the engine then
# falls back to its own defaults.
ENGINE_STANCES = {"orthodox", "southpaw"}
ENGINE_STYLES = {"high_guard", "philly_shell", "peek_a_boo", "out_boxer"}
ENGINE_SCHOOLS = {"soviet", "mexican", "european", "american"}


def _detection_cmd(engine_cmd: list[str], video: Path, ctx: dict) -> list[str]:
    """Build the `boxing-coach --json` invocation for one clip."""
    cmd = [*engine_cmd, str(video), "--json"]
    stance = ctx.get("stance")
    if stance in ENGINE_STANCES:
        cmd += ["--stance", stance]
    style = ctx.get("style")
    if style in ENGINE_STYLES:
        cmd += ["--style", style]
    school = ctx.get("school")
    if school in ENGINE_SCHOOLS:
        cmd += ["--school", school]
    return cmd


def _resolve_video(gt: dict, gt_path: Path, videos_dir: Path) -> Path | None:
    """Find the clip's source video: absolute, next to the labels, or in videos_dir."""
    src = gt.get("source_file")
    if not src:
        return None
    for candidate in (Path(src), gt_path.parent / src, videos_dir / src):
        if candidate.is_file():
            return candidate
    return None


def _write(pred_path: Path, payload: dict) -> None:
    pred_path.parent.mkdir(parents=True, exist_ok=True)
    pred_path.write_text(json.dumps(payload, indent=2) + "\n")


def predict(dataset_dir: Path, version: str, layer: str, *,
            engine_cmd: list[str], videos_dir: Path, import_dir: Path | None,
            force: bool, dry_run: bool, only: set[str] | None) -> int:
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
        pred_path = gt_path.parent / "predictions" / version / f"{layer}.json"
        if pred_path.exists() and not force:
            skipped.append(f"{clip} (exists; use --force)")
            continue

        if layer == "detection":
            video = _resolve_video(gt, gt_path, videos_dir)
            if video is None:
                failed.append(f"{clip} (video {gt.get('source_file')!r} not found)")
                continue
            cmd = _detection_cmd(engine_cmd, video, gt.get("context", {}))
            if dry_run:
                print(f"{clip}: {shlex.join(cmd)} -> {_rel(pred_path)}")
                continue
            proc = subprocess.run(cmd, capture_output=True, text=True)
            if proc.returncode != 0:
                failed.append(f"{clip} (engine exit {proc.returncode}: "
                              f"{proc.stderr.strip().splitlines()[-1] if proc.stderr.strip() else 'no stderr'})")
                continue
            try:
                payload = json.loads(proc.stdout)
            except json.JSONDecodeError as e:
                failed.append(f"{clip} (engine stdout not JSON: {e})")
                continue
            _write(pred_path, payload)
            wrote.append(clip)

        elif layer == "coaching":
            if import_dir is None:
                failed.append(f"{clip} (coaching layer needs --import-dir; "
                              f"no headless Dart runner)")
                continue
            src = import_dir / f"{clip}.json"
            if not src.is_file():
                failed.append(f"{clip} (no exported report at {_rel(src)})")
                continue
            try:
                payload = json.loads(src.read_text())
            except json.JSONDecodeError as e:
                failed.append(f"{clip} ({_rel(src)} not JSON: {e})")
                continue
            if dry_run:
                print(f"{clip}: import {_rel(src)} -> {_rel(pred_path)}")
                continue
            _write(pred_path, payload)
            wrote.append(clip)

    _report("wrote", wrote)
    _report("skipped", skipped)
    _report("failed", failed)
    if not dry_run:
        print(f"\n{len(wrote)} written, {len(skipped)} skipped, {len(failed)} failed "
              f"-> predictions/{version}/{layer}.json")
    return 1 if failed else 0


def _rel(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def _report(label: str, items: list[str]) -> None:
    if items:
        print(f"{label}: " + ", ".join(items))


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dataset", type=Path, help="dataset split dir, e.g. ../datasets/development")
    ap.add_argument("--version", required=True, help="predictions namespace, e.g. coach-v31")
    ap.add_argument("--layer", default="detection", choices=["detection", "coaching"])
    ap.add_argument("--engine-cmd", default="boxing-coach",
                    help='detection engine command (default: "boxing-coach")')
    ap.add_argument("--videos-dir", type=Path, default=ROOT,
                    help="where source_file videos live (default: repo root)")
    ap.add_argument("--import-dir", type=Path, default=None,
                    help="coaching layer: dir of exported <video_id>.json reports")
    ap.add_argument("--only", nargs="*", metavar="VIDEO_ID",
                    help="restrict to these clip ids")
    ap.add_argument("--force", action="store_true", help="overwrite existing prediction files")
    ap.add_argument("--dry-run", action="store_true", help="show what would run, write nothing")
    args = ap.parse_args(argv)

    engine_cmd = shlex.split(args.engine_cmd)
    if args.layer == "detection" and not shutil.which(engine_cmd[0]):
        print(f"warning: engine '{engine_cmd[0]}' not found on PATH; "
              f"override with --engine-cmd", file=sys.stderr)

    return predict(
        args.dataset, args.version, args.layer,
        engine_cmd=engine_cmd, videos_dir=args.videos_dir, import_dir=args.import_dir,
        force=args.force, dry_run=args.dry_run,
        only=set(args.only) if args.only else None,
    )


if __name__ == "__main__":
    raise SystemExit(main())
