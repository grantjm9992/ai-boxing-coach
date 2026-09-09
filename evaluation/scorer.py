#!/usr/bin/env python3
"""Score predictions against coach ground truth — stdlib only.

Given normalised `Prediction`s (from either engine) and the clip's `Truth`
observations, produce detection metrics (precision / recall / F1), a
per-category breakdown, severity accuracy, a severity-weighted score, and the
lists of false positives / false negatives for failure analysis.

Matching model
--------------
A prediction may match a *present* truth iff the truth's code is in the
prediction's `candidate_codes`. We then compute a maximum 1:1 matching, so a
single coarse rule hit (`hands_up`) can satisfy at most one label — it can't
inflate recall by "covering" several. Exact fine-code edges are preferred over
coarse family edges when both are possible, which keeps severity accuracy fair.

  * matched pair                        -> True Positive
  * unmatched present truth             -> False Negative
  * unmatched prediction                -> False Positive
      (flagged `contradicted` if it hits a present=false "correct technique"
       assertion — a stronger signal of hallucination)
  * present=false truth, unpredicted    -> True Negative
"""
from __future__ import annotations

from dataclasses import dataclass, field

from normalise import Prediction, Truth


def _fbeta(precision: float, recall: float) -> float:
    return 0.0 if precision + recall == 0 else 2 * precision * recall / (precision + recall)


def _ratio(num: float, den: float) -> float:
    return 0.0 if den == 0 else num / den


@dataclass
class CategoryScore:
    tp: int = 0
    fp: int = 0
    fn: int = 0

    @property
    def precision(self) -> float:
        return _ratio(self.tp, self.tp + self.fp)

    @property
    def recall(self) -> float:
        return _ratio(self.tp, self.tp + self.fn)

    @property
    def f1(self) -> float:
        return _fbeta(self.precision, self.recall)

    def as_dict(self) -> dict:
        return {"tp": self.tp, "fp": self.fp, "fn": self.fn,
                "precision": round(self.precision, 4),
                "recall": round(self.recall, 4),
                "f1": round(self.f1, 4)}


@dataclass
class ScoreResult:
    overall: CategoryScore
    by_category: dict[str, CategoryScore]
    severity_accuracy: float
    weighted_precision: float
    weighted_recall: float
    weighted_f1: float
    severity_correct: int = 0                             # TP whose severity matched
    by_severity: dict[str, CategoryScore] = field(default_factory=dict)  # present-truth tp/fn per severity
    contradicted_fp: int = 0                              # FPs the coach labelled present=false
    false_positives: list[dict] = field(default_factory=list)
    false_negatives: list[dict] = field(default_factory=list)
    priority_top1_hit: bool | None = None

    def as_dict(self) -> dict:
        return {
            "overall": self.overall.as_dict(),
            "by_category": {k: v.as_dict() for k, v in sorted(self.by_category.items())},
            "by_severity": {k: v.as_dict() for k, v in sorted(self.by_severity.items())},
            "severity_accuracy": round(self.severity_accuracy, 4),
            "severity_correct": self.severity_correct,
            "contradicted_fp": self.contradicted_fp,
            "weighted": {
                "precision": round(self.weighted_precision, 4),
                "recall": round(self.weighted_recall, 4),
                "f1": round(self.weighted_f1, 4),
            },
            "priority_top1_hit": self.priority_top1_hit,
            "false_positives": self.false_positives,
            "false_negatives": self.false_negatives,
        }


def _edges(predictions: list[Prediction], truths: list[Truth]) -> dict[int, list[int]]:
    """pred index -> present-truth indices it can match, exact-code edges first."""
    edges: dict[int, list[int]] = {}
    for pi, p in enumerate(predictions):
        exact, family = [], []
        for ti, t in enumerate(truths):
            if t.code in p.candidate_codes:
                (exact if p.is_fine else family).append(ti)
        edges[pi] = exact + family
    return edges


def _max_matching(edges: dict[int, list[int]], n_left: int) -> dict[int, int]:
    """Maximum bipartite matching via augmenting paths. Returns left->right."""
    match_right: dict[int, int] = {}

    def augment(u: int, visited: set[int]) -> bool:
        for v in edges.get(u, []):
            if v in visited:
                continue
            visited.add(v)
            if v not in match_right or augment(match_right[v], visited):
                match_right[v] = u
                return True
        return False

    for u in range(n_left):
        augment(u, set())
    return {u: v for v, u in match_right.items()}


def score(
    predictions: list[Prediction],
    truths: list[Truth],
    *,
    weights: dict[str, int] | None = None,
    min_confidence: str | None = None,
    priority_feedback: list[str] | None = None,
) -> ScoreResult:
    """Score `predictions` against `truths`.

    weights: severity -> weight for the weighted score (defaults 5/3/1).
    min_confidence: drop truths below this coach confidence ("high"/"medium").
    priority_feedback: ordered truth codes; enables the top-1 priority check.
    """
    weights = weights or {"major": 5, "moderate": 3, "minor": 1, "positive": 0}
    conf_rank = {"low": 0, "medium": 1, "high": 2}
    floor = conf_rank.get(min_confidence or "low", 0)

    kept = [t for t in truths if conf_rank.get(t.confidence, 2) >= floor]
    present = [t for t in kept if t.present]
    absent_codes = {t.code for t in kept if not t.present}

    edges = _edges(predictions, present)
    left_to_right = _max_matching(edges, len(predictions))
    matched_preds = set(left_to_right)
    matched_truths = set(left_to_right.values())

    overall = CategoryScore()
    by_cat: dict[str, CategoryScore] = {}
    by_sev: dict[str, CategoryScore] = {}

    def cat(name: str | None) -> CategoryScore:
        key = name or "unknown"
        return by_cat.setdefault(key, CategoryScore())

    def sev(name: str) -> CategoryScore:
        return by_sev.setdefault(name, CategoryScore())

    fps: list[dict] = []
    fns: list[dict] = []
    sev_correct = 0
    contradicted_fp = 0

    # True positives.
    for pi, ti in left_to_right.items():
        p, t = predictions[pi], present[ti]
        overall.tp += 1
        cat(t.category).tp += 1
        sev(t.severity).tp += 1
        if p.severity == t.severity:
            sev_correct += 1

    # False negatives (missed present truths).
    for ti, t in enumerate(present):
        if ti not in matched_truths:
            overall.fn += 1
            cat(t.category).fn += 1
            sev(t.severity).fn += 1
            fns.append({"code": t.code, "category": t.category, "severity": t.severity,
                        "confidence": t.confidence})

    # False positives (unmatched predictions).
    for pi, p in enumerate(predictions):
        if pi in matched_preds:
            continue
        overall.fp += 1
        cat(p.category).fp += 1
        contradicted = bool(p.candidate_codes & absent_codes)
        if contradicted:
            contradicted_fp += 1
        fps.append({"source": p.source, "category": p.category, "severity": p.severity,
                    "candidate_codes": sorted(p.candidate_codes),
                    "contradicted": contradicted})

    # Weighted metrics.
    w_tp = sum(weights.get(present[ti].severity, 1) for ti in matched_truths)
    w_fn = sum(weights.get(t.severity, 1) for i, t in enumerate(present) if i not in matched_truths)
    w_fp = sum(weights.get(predictions[pi].severity, 1)
               for pi in range(len(predictions)) if pi not in matched_preds)
    w_prec = _ratio(w_tp, w_tp + w_fp)
    w_rec = _ratio(w_tp, w_tp + w_fn)

    # Priority: was the single most-important truth predicted at all?
    top1 = None
    if priority_feedback:
        top = priority_feedback[0]
        top1 = any(top in p.candidate_codes for p in predictions)

    return ScoreResult(
        overall=overall,
        by_category=by_cat,
        severity_accuracy=_ratio(sev_correct, overall.tp),
        weighted_precision=w_prec,
        weighted_recall=w_rec,
        weighted_f1=_fbeta(w_prec, w_rec),
        severity_correct=sev_correct,
        by_severity=by_sev,
        contradicted_fp=contradicted_fp,
        false_positives=fps,
        false_negatives=fns,
        priority_top1_hit=top1,
    )
