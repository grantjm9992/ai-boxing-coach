#!/usr/bin/env python3
"""The self-iterating detector optimiser (plan §16, §17, §22-Phase7, §25).

Hill-climbs the detector thresholds declared in `mappings/param_space.py`
against the CoachMe pose benchmark, keeping a change only when it improves the
objective AND passes the promotion gate (no category regression, no
hallucination rise, no major-recall drop). It walks one knob at a time
(coordinate descent — the plan's "propose ONE change, let the benchmark decide")
and keeps sweeping until a full pass accepts nothing: that fixed point is the
"optimal solution" the loop converges to. `--restarts` adds randomised restarts
to escape local optima; left running it stops when no restart beats the best.

Tunes on the TRAIN split and (with --validate) reports the held-out TEST split
so you can see whether a gain generalises or is overfit (§17). The winner is
written as a `TunedProfile` JSON — the portable artifact the on-phone Dart engine
consumes (see PORTING.md) — never edited into engine source here.

    # converge on train, report on held-out test
    python3 optimize.py ../datasets/coachme/train --validate ../datasets/coachme/test

Requires the engine interpreter (numpy). Example:
    ~/.pyenv/versions/3.10.0/bin/python3 optimize.py ../datasets/coachme/train ...
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import random
import sys
from pathlib import Path

from harness import Harness
from mappings.param_space import DEFAULT_PARAM_SPACE, ParamSpec, space
from mappings.tuned_profile import TunedProfile
from runner import compare, git_commit

_ROOT = Path(__file__).resolve().parent.parent
_TUNED_DIR = Path(__file__).resolve().parent / "tuned"


# ---- objective + promotion gate -----------------------------------------

def objective(rec: dict, key: str) -> float:
    m = rec["metrics"]
    if key == "overall_f1":
        return m["overall"]["f1"]
    if key == "weighted_f1":
        return m["weighted"]["f1"]
    if key == "overall_recall":
        return m["overall"]["recall"]
    raise ValueError(f"unknown objective {key!r}")


def passes_gate(baseline: dict, cand: dict, *, category_tol: float,
                major_recall_tol: float) -> tuple[bool, list[str]]:
    """The plan §15 promotion gate: no category regression, no hallucination
    rise, no major-recall drop — measured against the ORIGINAL baseline so the
    climb can't drift into a worse coach even while the objective ticks up."""
    bm, cm = baseline["metrics"], cand["metrics"]
    reasons: list[str] = []
    if cm["hallucination_rate"] > bm["hallucination_rate"] + 1e-9:
        reasons.append(
            f"hallucination {bm['hallucination_rate']:.3f}->{cm['hallucination_rate']:.3f}")
    if (bm["major_recall"] is not None and cm["major_recall"] is not None
            and cm["major_recall"] < bm["major_recall"] - major_recall_tol):
        reasons.append(
            f"major-recall {bm['major_recall']:.3f}->{cm['major_recall']:.3f}")
    for c in set(baseline["by_category"]) | set(cand["by_category"]):
        b = baseline["by_category"].get(c, {}).get("f1", 0.0)
        cf = cand["by_category"].get(c, {}).get("f1", 0.0)
        if cf < b - category_tol:
            reasons.append(f"{c} F1 {b:.3f}->{cf:.3f}")
    return (not reasons), reasons


# ---- the climb -----------------------------------------------------------

def _current_values(profile: TunedProfile, specs) -> dict[str, float]:
    """The profile's value for each knob, or the knob's default if unset."""
    return {s.key: profile.get(s.rule_id, s.field, s.default) for s in specs}


def hill_climb(harness: Harness, specs, *, objective_key: str,
               baseline_rec: dict, start: TunedProfile, category_tol: float,
               major_recall_tol: float, max_rounds: int, eps: float,
               log) -> tuple[TunedProfile, dict]:
    """Coordinate descent from `start` to a per-knob local optimum."""
    best_profile = start
    best_rec = harness.evaluate(best_profile)
    values = _current_values(best_profile, specs)

    for rnd in range(1, max_rounds + 1):
        improved = False
        for spec in specs:
            cur = values[spec.key]
            best_cand = None
            for cand_val in spec.neighbours(cur):
                trial = best_profile.with_override(spec.rule_id, spec.field, cand_val)
                rec = harness.evaluate(trial)
                gain = objective(rec, objective_key) - objective(best_rec, objective_key)
                if gain <= eps:
                    continue
                ok, _ = passes_gate(baseline_rec, rec,
                                    category_tol=category_tol,
                                    major_recall_tol=major_recall_tol)
                if not ok:
                    continue
                if best_cand is None or gain > best_cand[2]:
                    best_cand = (cand_val, trial, gain, rec)
            if best_cand is not None:
                cand_val, trial, gain, rec = best_cand
                best_profile, best_rec = trial, rec
                values[spec.key] = cand_val
                improved = True
                log(f"    accept {spec.key} {cur} -> {cand_val}  "
                    f"{objective_key} +{gain:.4f} -> {objective(best_rec, objective_key):.4f}")
        if not improved:
            log(f"  converged after round {rnd} (no knob improved)")
            break
    return best_profile, best_rec


def _random_start(specs, rng: random.Random) -> TunedProfile:
    """A profile with each knob set to a random legal grid value (for restarts)."""
    prof = TunedProfile("restart")
    for spec in specs:
        prof = prof.with_override(spec.rule_id, spec.field, rng.choice(spec.candidates()))
    return prof


def optimise(train_dir: Path, *, objective_key: str, param_space: str,
             allow_draft: bool, min_confidence: str | None, category_tol: float,
             major_recall_tol: float, max_rounds: int, restarts: int, eps: float,
             seed: int, resume: Path | None, quiet: bool) -> tuple[TunedProfile, dict, dict]:
    def log(msg: str) -> None:
        if not quiet:
            print(msg)

    specs = space(param_space)
    harness = Harness(train_dir, allow_draft=allow_draft, min_confidence=min_confidence)
    baseline_rec = harness.evaluate(TunedProfile("baseline"))
    log(f"loaded {len(harness.clips)} clips from {train_dir}")
    log(f"baseline  {objective_key} {objective(baseline_rec, objective_key):.4f}  "
        f"(overall F1 {baseline_rec['metrics']['overall']['f1']:.3f})")

    rng = random.Random(seed)

    log("\n=== climb 0 (from baseline defaults) ===")
    start0 = TunedProfile.load(resume) if resume else TunedProfile("tuned")
    best_profile, best_rec = hill_climb(
        harness, specs, objective_key=objective_key, baseline_rec=baseline_rec,
        start=start0, category_tol=category_tol, major_recall_tol=major_recall_tol,
        max_rounds=max_rounds, eps=eps, log=log)
    best_obj = objective(best_rec, objective_key)

    for r in range(1, restarts + 1):
        log(f"\n=== restart {r}/{restarts} (random start) ===")
        prof, rec = hill_climb(
            harness, specs, objective_key=objective_key, baseline_rec=baseline_rec,
            start=_random_start(specs, rng), category_tol=category_tol,
            major_recall_tol=major_recall_tol, max_rounds=max_rounds, eps=eps, log=log)
        obj = objective(rec, objective_key)
        if obj > best_obj + eps:
            log(f"  restart {r} improved best {best_obj:.4f} -> {obj:.4f}")
            best_profile, best_rec, best_obj = prof, rec, obj
        else:
            log(f"  restart {r} did not beat {best_obj:.4f}")

    best_profile = TunedProfile("coachme-tuned", best_profile.overrides)
    return best_profile, baseline_rec, best_rec


# ---- reporting -----------------------------------------------------------

def _stamp(rec: dict, version: str, dataset: Path) -> dict:
    """Add the provenance keys `runner.compare` expects to a harness record."""
    return {**rec, "version": version, "layer": "detection",
            "dataset": str(dataset), "git_commit": git_commit()}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("train", type=Path, help="train split dir, e.g. ../datasets/coachme/train")
    ap.add_argument("--validate", type=Path, default=None,
                    help="held-out split to report the winner on (e.g. ../datasets/coachme/test)")
    ap.add_argument("--objective", default="weighted_f1",
                    choices=["weighted_f1", "overall_f1", "overall_recall"])
    ap.add_argument("--param-space", default=DEFAULT_PARAM_SPACE)
    ap.add_argument("--allow-draft", action="store_true")
    ap.add_argument("--min-confidence", choices=["low", "medium", "high"])
    ap.add_argument("--category-tol", type=float, default=0.05,
                    help="max per-category F1 drop the gate tolerates (plan §15)")
    ap.add_argument("--major-recall-tol", type=float, default=0.02)
    ap.add_argument("--max-rounds", type=int, default=20,
                    help="max coordinate-descent passes per climb")
    ap.add_argument("--restarts", type=int, default=0,
                    help="random restarts to escape local optima")
    ap.add_argument("--eps", type=float, default=1e-4, help="min objective gain to accept")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--resume", type=Path, default=None,
                    help="seed the climb from an existing TunedProfile JSON")
    ap.add_argument("--out", type=Path, default=None,
                    help="where to write the winning TunedProfile "
                         "(default evaluation/tuned/coachme-<ts>.json)")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args(argv)

    best, baseline_rec, best_rec = optimise(
        args.train, objective_key=args.objective, param_space=args.param_space,
        allow_draft=args.allow_draft, min_confidence=args.min_confidence,
        category_tol=args.category_tol, major_recall_tol=args.major_recall_tol,
        max_rounds=args.max_rounds, restarts=args.restarts, eps=args.eps,
        seed=args.seed, resume=args.resume, quiet=args.quiet)

    print("\n" + "=" * 60)
    print("TRAIN: baseline -> tuned")
    compare(_stamp(baseline_rec, "baseline", args.train),
            _stamp(best_rec, best.name, args.train),
            category_tol=args.category_tol)

    print("\nWinning thresholds:")
    if best.is_empty():
        print("  (none — baseline defaults were already optimal on this objective)")
    for key, val in best.flat().items():
        print(f"  {key} = {val}")

    if args.validate:
        val_harness = Harness(args.validate, allow_draft=args.allow_draft,
                              min_confidence=args.min_confidence)
        val_base = val_harness.evaluate(TunedProfile("baseline"))
        val_tuned = val_harness.evaluate(best)
        print("\n" + "=" * 60)
        print(f"HELD-OUT VALIDATION ({args.validate}): baseline -> tuned")
        compare(_stamp(val_base, "baseline", args.validate),
                _stamp(val_tuned, best.name, args.validate),
                category_tol=args.category_tol)

    out = args.out or (_TUNED_DIR / f"coachme-{dt.datetime.now():%Y%m%dT%H%M%S}.json")
    best.save(out)
    try:
        rel = out.resolve().relative_to(_ROOT)
    except ValueError:
        rel = out
    print(f"\nwrote tuned profile -> {rel}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
