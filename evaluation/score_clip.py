#!/usr/bin/env python3
"""Score one clip's engine output against its ground truth — stdlib only.

    python3 score_clip.py GROUND_TRUTH.json --detection analysis.json
    python3 score_clip.py GROUND_TRUTH.json --coaching report.json --json

--detection : Python engine JSON (`boxing-coach VIDEO --json`)
--coaching  : Dart AiCoachReport JSON
Provide either or both; with both, each is scored separately so you can compare
the detection layer and the coaching layer on the same truth.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from normalise import (
    load_taxonomy, normalise_coaching, normalise_detection, parse_ground_truth,
)
from scorer import ScoreResult, score


def _score_one(preds, truths, gt) -> ScoreResult:
    return score(preds, truths, priority_feedback=gt.get("priority_feedback"))


def _print_report(name: str, r: ScoreResult) -> None:
    o = r.overall
    print(f"\n=== {name} ===")
    print(f"  precision {o.precision:.3f}  recall {o.recall:.3f}  f1 {o.f1:.3f}"
          f"   (tp {o.tp} fp {o.fp} fn {o.fn})")
    print(f"  weighted  precision {r.weighted_precision:.3f}  recall {r.weighted_recall:.3f}"
          f"  f1 {r.weighted_f1:.3f}")
    print(f"  severity accuracy {r.severity_accuracy:.3f}"
          f"   priority top-1 hit {r.priority_top1_hit}")
    if r.by_category:
        print("  by category:")
        for cat, cs in sorted(r.by_category.items()):
            print(f"    {cat:<14} f1 {cs.f1:.3f}  (tp {cs.tp} fp {cs.fp} fn {cs.fn})")
    if r.false_negatives:
        print("  missed (FN): " + ", ".join(f"{f['code']}[{f['severity']}]"
                                             for f in r.false_negatives))
    if r.false_positives:
        print("  invented (FP): " + ", ".join(
            f"{f['source']}{'!' if f['contradicted'] else ''}" for f in r.false_positives))


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("ground_truth", help="path to a ground_truth.json")
    ap.add_argument("--detection", help="Python engine JSON")
    ap.add_argument("--coaching", help="Dart AiCoachReport JSON")
    ap.add_argument("--json", action="store_true", help="emit JSON instead of a report")
    args = ap.parse_args(argv)

    if not args.detection and not args.coaching:
        ap.error("provide --detection and/or --coaching")

    tax = load_taxonomy()
    gt = json.loads(Path(args.ground_truth).read_text())
    if gt.get("status") == "unlabelled":
        print(f"WARNING: {args.ground_truth} is status=unlabelled — scores are meaningless "
              f"until it is labelled and reviewed.", file=sys.stderr)
    truths = parse_ground_truth(gt, tax)

    results: dict[str, ScoreResult] = {}
    if args.detection:
        preds = normalise_detection(json.loads(Path(args.detection).read_text()), tax)
        results["detection"] = _score_one(preds, truths, gt)
    if args.coaching:
        preds = normalise_coaching(json.loads(Path(args.coaching).read_text()), tax)
        results["coaching"] = _score_one(preds, truths, gt)

    if args.json:
        print(json.dumps({"video_id": gt.get("video_id"),
                          **{k: v.as_dict() for k, v in results.items()}}, indent=2))
    else:
        print(f"clip: {gt.get('video_id')}   status: {gt.get('status')}")
        for name, r in results.items():
            _print_report(name, r)
    return 0


if __name__ == "__main__":
    sys.exit(main())
