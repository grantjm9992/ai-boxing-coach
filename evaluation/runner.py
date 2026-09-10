#!/usr/bin/env python3
"""Sweep a clip set, aggregate metrics, stamp an experiment, diff candidates.

Two modes — stdlib only.

  run:     score one engine version across every reviewed clip in a dataset,
           write an experiment record, print the aggregate.
  compare: diff two experiment records (baseline vs candidate) into the doc §22
           table and apply the §15 promotion gate.

Prediction files live beside each clip, namespaced by version so several
candidates can coexist:

    datasets/<split>/<clip>/
        ground_truth.json
        predictions/<version>/<layer>.json      # layer = detection | coaching

`<layer>.json` is the raw engine output: Python `boxing-coach --json` for
detection, Dart `AiCoachReport` JSON for coaching.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import subprocess
import sys
from pathlib import Path

from normalise import (
    load_taxonomy, normalise_coaching, normalise_dart_detection,
    normalise_detection, parse_ground_truth,
)
from scorer import CategoryScore, score

ROOT = Path(__file__).resolve().parent.parent
EXPERIMENTS = ROOT / "experiments"
_NORMALISERS = {
    "detection": normalise_detection,        # Python reference engine (coarse rules)
    "dart_detection": normalise_dart_detection,  # Dart app engine (fine codes)
    "coaching": normalise_coaching,          # Dart AiCoachReport
}


def _rel(path: Path) -> str:
    """Path relative to the repo root, or absolute if it lives outside it."""
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def git_commit() -> str:
    try:
        return subprocess.check_output(
            ["git", "-C", str(ROOT), "rev-parse", "--short", "HEAD"],
            text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return "unknown"


def _sum(scores: list[CategoryScore]) -> CategoryScore:
    total = CategoryScore()
    for s in scores:
        total.tp += s.tp
        total.fp += s.fp
        total.fn += s.fn
    return total


def run(dataset_dir: Path, version: str, layer: str, *,
        min_confidence: str | None = None, allow_draft: bool = False,
        save: bool = True) -> dict:
    tax = load_taxonomy()
    normaliser = _NORMALISERS[layer]
    ok_status = {"reviewed", "draft"} if allow_draft else {"reviewed"}

    per_clip: list[dict] = []
    results = []
    skipped: list[str] = []
    for gt_path in sorted(dataset_dir.glob("*/ground_truth.json")):
        gt = json.loads(gt_path.read_text())
        clip = gt["video_id"]
        if gt.get("status") not in ok_status:
            skipped.append(f"{clip} (status={gt.get('status')})")
            continue
        pred_path = gt_path.parent / "predictions" / version / f"{layer}.json"
        if not pred_path.exists():
            skipped.append(f"{clip} (no {version}/{layer}.json)")
            continue
        preds = normaliser(json.loads(pred_path.read_text()), tax)
        r = score(preds, parse_ground_truth(gt, tax),
                  min_confidence=min_confidence,
                  priority_feedback=gt.get("priority_feedback"))
        results.append(r)
        per_clip.append({"video_id": clip, **r.overall.as_dict(),
                         "severity_accuracy": round(r.severity_accuracy, 4),
                         "priority_top1_hit": r.priority_top1_hit})

    if not results:
        raise SystemExit(f"no scorable clips in {dataset_dir} for {version}/{layer}. "
                         f"skipped: {skipped or 'none found'}")

    overall = _sum([r.overall for r in results])
    cats = {c for r in results for c in r.by_category}
    by_cat = {c: _sum([r.by_category.get(c, CategoryScore()) for r in results]) for c in cats}
    sevs = {s for r in results for s in r.by_severity}
    by_sev = {s: _sum([r.by_severity.get(s, CategoryScore()) for r in results]) for s in sevs}

    sev_correct = sum(r.severity_correct for r in results)
    contradicted = sum(r.contradicted_fp for r in results)
    total_preds = overall.tp + overall.fp
    prio = [r.priority_top1_hit for r in results if r.priority_top1_hit is not None]

    def r4(x): return round(x, 4)
    record = {
        "experiment_id": f"{dt.datetime.now():%Y%m%dT%H%M%S}_{version}_{layer}",
        "timestamp": dt.datetime.now().isoformat(timespec="seconds"),
        "git_commit": git_commit(),
        "dataset": _rel(dataset_dir),
        "version": version,
        "layer": layer,
        "min_confidence": min_confidence,
        "clip_count": len(results),
        "skipped": skipped,
        "metrics": {
            "overall": overall.as_dict(),
            "weighted": None,   # micro-weighted below
            "severity_accuracy": r4(sev_correct / overall.tp) if overall.tp else 0.0,
            "hallucination_rate": r4(contradicted / total_preds) if total_preds else 0.0,
            "major_recall": r4(by_sev["major"].recall) if "major" in by_sev else None,
            "priority_hit_rate": r4(sum(prio) / len(prio)) if prio else None,
        },
        "by_category": {c: s.as_dict() for c, s in sorted(by_cat.items())},
        "by_severity": {s: v.as_dict() for s, v in sorted(by_sev.items())},
        "per_clip": per_clip,
    }
    # Micro weighted P/R/F1 from severity weights.
    w = {"major": 5, "moderate": 3, "minor": 1}
    w_tp = sum(w.get(s, 1) * v.tp for s, v in by_sev.items())
    w_fn = sum(w.get(s, 1) * v.fn for s, v in by_sev.items())
    w_fp = w.get("moderate", 3) * overall.fp  # FPs lack a truth severity; charge the middle weight
    w_prec = w_tp / (w_tp + w_fp) if (w_tp + w_fp) else 0.0
    w_rec = w_tp / (w_tp + w_fn) if (w_tp + w_fn) else 0.0
    w_f1 = 0.0 if w_prec + w_rec == 0 else 2 * w_prec * w_rec / (w_prec + w_rec)
    record["metrics"]["weighted"] = {"precision": r4(w_prec), "recall": r4(w_rec), "f1": r4(w_f1)}

    if save:
        EXPERIMENTS.mkdir(exist_ok=True)
        out = EXPERIMENTS / f"{record['experiment_id']}.json"
        out.write_text(json.dumps(record, indent=2) + "\n")
        record["_saved_to"] = _rel(out)
    return record


def _print_run(rec: dict) -> None:
    m = rec["metrics"]
    o = m["overall"]
    print(f"\n{rec['experiment_id']}  (git {rec['git_commit']}, {rec['clip_count']} clips)")
    print(f"  overall   P {o['precision']:.3f}  R {o['recall']:.3f}  F1 {o['f1']:.3f}"
          f"   (tp {o['tp']} fp {o['fp']} fn {o['fn']})")
    print(f"  weighted  F1 {m['weighted']['f1']:.3f}   halluc {m['hallucination_rate']:.3f}"
          f"   sev-acc {m['severity_accuracy']:.3f}   major-recall {m['major_recall']}")
    for c, s in rec["by_category"].items():
        print(f"    {c:<14} F1 {s['f1']:.3f}  (tp {s['tp']} fp {s['fp']} fn {s['fn']})")
    if rec["skipped"]:
        print(f"  skipped: {', '.join(rec['skipped'])}")
    if "_saved_to" in rec:
        print(f"  saved: {rec['_saved_to']}")


def _arrow(delta: float, eps: float = 1e-9) -> str:
    return "→" if abs(delta) < eps else ("↑" if delta > 0 else "↓")


def compare(base: dict, cand: dict, *, category_tol: float = 0.05,
            halluc_tol: float = 0.0, major_recall_tol: float = 0.02) -> bool:
    bm, cm = base["metrics"], cand["metrics"]

    def row(label: str, b: float, c: float, higher_better: bool = True):
        d = c - b
        arrow = _arrow(d)
        print(f"  {label:<22} {b:6.3f}     {c:6.3f}   {arrow}")

    print(f"\nCandidate: {cand['version']}/{cand['layer']}  vs  Baseline: {base['version']}/{base['layer']}")
    print(f"Dataset: {cand['dataset']}   (base git {base['git_commit']} → cand git {cand['git_commit']})\n")
    print(f"  {'':22} {'BASE':>6}   {'CANDIDATE':>9}")
    row("Overall Precision", bm["overall"]["precision"], cm["overall"]["precision"])
    row("Overall Recall", bm["overall"]["recall"], cm["overall"]["recall"])
    row("Overall F1", bm["overall"]["f1"], cm["overall"]["f1"])
    row("Weighted F1", bm["weighted"]["f1"], cm["weighted"]["f1"])
    row("Hallucination Rate", bm["hallucination_rate"], cm["hallucination_rate"])
    row("Severity Accuracy", bm["severity_accuracy"], cm["severity_accuracy"])
    if bm["major_recall"] is not None and cm["major_recall"] is not None:
        row("Major-error Recall", bm["major_recall"], cm["major_recall"])

    print()
    cats = sorted(set(base["by_category"]) | set(cand["by_category"]))
    regressions: list[str] = []
    for c in cats:
        b = base["by_category"].get(c, {}).get("f1", 0.0)
        cf = cand["by_category"].get(c, {}).get("f1", 0.0)
        row(f"{c} F1", b, cf)
        if cf < b - category_tol:
            regressions.append(f"{c} F1 {b:.3f}→{cf:.3f} (>{category_tol:.2f} drop)")

    # Promotion gate (doc §15).
    reasons: list[str] = []
    if cm["weighted"]["f1"] < bm["weighted"]["f1"] - 1e-9:
        reasons.append(f"weighted F1 regressed {bm['weighted']['f1']:.3f}→{cm['weighted']['f1']:.3f}")
    if cm["hallucination_rate"] > bm["hallucination_rate"] + halluc_tol:
        reasons.append(f"hallucination rate rose {bm['hallucination_rate']:.3f}→{cm['hallucination_rate']:.3f}")
    if (bm["major_recall"] is not None and cm["major_recall"] is not None
            and cm["major_recall"] < bm["major_recall"] - major_recall_tol):
        reasons.append(f"major-error recall dropped {bm['major_recall']:.3f}→{cm['major_recall']:.3f}")
    reasons.extend(regressions)

    print("\n  Major regressions:", "; ".join(regressions) if regressions else "NONE")
    passed = not reasons
    if passed:
        improved = cm["overall"]["f1"] > bm["overall"]["f1"] + 1e-9
        print("\n  Recommendation: " + ("PASS TO HUMAN REVIEW" if improved
                                         else "PASS (no regression; no clear improvement)"))
    else:
        print("\n  Recommendation: REJECT")
        for r in reasons:
            print(f"    - {r}")
    return passed


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    pr = sub.add_parser("run", help="score a version across a dataset")
    pr.add_argument("dataset", help="dataset split dir, e.g. datasets/development")
    pr.add_argument("--version", required=True, help="predictions namespace, e.g. coach-v31")
    pr.add_argument("--layer", required=True, choices=list(_NORMALISERS))
    pr.add_argument("--min-confidence", choices=["low", "medium", "high"])
    pr.add_argument("--allow-draft", action="store_true", help="also score status=draft clips")
    pr.add_argument("--no-save", action="store_true", help="do not write an experiment record")
    pr.add_argument("--json", action="store_true")

    pc = sub.add_parser("compare", help="diff two experiment records")
    pc.add_argument("baseline")
    pc.add_argument("candidate")
    pc.add_argument("--category-tol", type=float, default=0.05)

    args = ap.parse_args(argv)

    if args.cmd == "run":
        rec = run(Path(args.dataset), args.version, args.layer,
                  min_confidence=args.min_confidence, allow_draft=args.allow_draft,
                  save=not args.no_save)
        if args.json:
            print(json.dumps(rec, indent=2))
        else:
            _print_run(rec)
        return 0

    if args.cmd == "compare":
        base = json.loads(Path(args.baseline).read_text())
        cand = json.loads(Path(args.candidate).read_text())
        passed = compare(base, cand, category_tol=args.category_tol)
        return 0 if passed else 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
