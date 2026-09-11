#!/usr/bin/env python3
"""Normalise engine outputs into one comparable prediction shape — stdlib only.

The two engines emit faults at different granularities (see
annotations/taxonomy/README.md). This module collapses both into a single
`Prediction`, so the scorer never has to know which engine produced a result:

  * Detection (Python `boxing-coach --json`) — a COARSE rule id (`hands_up`).
    Its `candidate_codes` is the whole family the rule can satisfy.
  * Coaching (Dart `AiCoachReport`)          — a FINE code (`GUARD_002`).
    Its `candidate_codes` is the single code.

A prediction matches a ground-truth observation iff the truth's code is in the
prediction's `candidate_codes` (the scorer then does 1:1 matching so one coarse
hit can't cover several labels).
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

TAXONOMY_PATH = Path(__file__).resolve().parent.parent / "annotations" / "taxonomy" / "codes.json"

# Coaching layer uses HIGH/MEDIUM/LOW; detection + labels use major/moderate/minor.
_SEVERITY = {
    "high": "major", "major": "major",
    "medium": "moderate", "moderate": "moderate",
    "low": "minor", "minor": "minor",
    "positive": "positive",
}


def normalise_severity(raw: object) -> str | None:
    if not isinstance(raw, str):
        return None
    return _SEVERITY.get(raw.strip().lower())


@dataclass(frozen=True)
class Prediction:
    """One predicted fault, engine-agnostic."""
    source: str                       # rule id or fine code, for failure analysis
    candidate_codes: frozenset[str]   # fine codes this prediction can satisfy
    category: str | None
    severity: str                     # major/moderate/minor (positive filtered out upstream)
    timestamps_s: tuple[float, ...] = ()
    confidence: float = 1.0           # model confidence, 0..1

    @property
    def is_fine(self) -> bool:
        """True if this pins a single code (coaching), not a coarse family."""
        return len(self.candidate_codes) == 1


def load_taxonomy(path: Path = TAXONOMY_PATH) -> dict:
    return json.loads(Path(path).read_text())


def normalise_detection(analysis: dict, taxonomy: dict) -> list[Prediction]:
    """Python engine JSON (`boxing-coach --json`) → predictions.

    Uses each rule's `emits_codes` family as the candidate set. Positive
    observations and non-fault rules (e.g. school_adherence, empty family) are
    dropped — they are not faults to score for precision/recall.
    """
    rules = taxonomy["python_rules"]
    out: list[Prediction] = []
    # The live engine emits `specific_observations` with snake_case keys; older
    # fixtures use `observations`/`ruleId`/`timestampMs`. Accept both spellings.
    obs_list = analysis.get("specific_observations")
    if obs_list is None:
        obs_list = analysis.get("observations", [])
    for obs in obs_list:
        rule = obs.get("rule_id") or obs.get("ruleId")
        severity = normalise_severity(obs.get("severity"))
        if severity is None or severity == "positive":
            continue
        spec = rules.get(rule)
        if not spec or not spec.get("emits_codes"):
            continue  # not a scorable fault family
        ts_ms = obs.get("timestamp_ms", obs.get("timestampMs"))
        out.append(Prediction(
            source=rule,
            candidate_codes=frozenset(spec["emits_codes"]),
            category=spec.get("category") or obs.get("category"),
            severity=severity,
            timestamps_s=() if ts_ms is None else (float(ts_ms) / 1000.0,),
            confidence=float(obs.get("confidence", 1.0)),
        ))
    return out


def normalise_coaching(report: dict, taxonomy: dict) -> list[Prediction]:
    """Dart `AiCoachReport` JSON → predictions.

    Each `priority_issues` entry already carries a fine code; unknown codes are
    kept as singletons (they simply never match → counted as false positives).
    """
    codes = taxonomy["codes"]
    out: list[Prediction] = []
    for issue in report.get("priority_issues", []):
        code = issue.get("code")
        severity = normalise_severity(issue.get("severity"))
        if not isinstance(code, str) or not code or severity is None or severity == "positive":
            continue
        spec = codes.get(code)
        ts = issue.get("timestamps") or issue.get("timestamps_s") or []
        out.append(Prediction(
            source=code,
            candidate_codes=frozenset({code}),
            category=spec["category"] if spec else None,
            severity=severity,
            timestamps_s=tuple(float(t) for t in ts if isinstance(t, (int, float))),
            confidence=float(issue.get("confidence", 1.0)),
        ))
    return out


def normalise_dart_detection(analysis: dict, taxonomy: dict) -> list[Prediction]:
    """Dart `RoundAnalysis.toJson()` → predictions.

    The Dart engine (the shipping app) emits `specificObservations`, each already
    carrying a FINE code (e.g. GUARD_001) plus camelCase keys. Scored on the fine
    code directly, like the coaching layer — this is how you benchmark the actual
    app engine (which has rules the Python reference lacks, e.g. balance/lean).
    Positive notes carry no fault code and are skipped.
    """
    codes = taxonomy["codes"]
    out: list[Prediction] = []
    for obs in analysis.get("specificObservations", []):
        code = obs.get("code")
        severity = normalise_severity(obs.get("severity"))
        if not isinstance(code, str) or not code or severity is None or severity == "positive":
            continue
        spec = codes.get(code)
        ts_ms = obs.get("timestampMs")
        out.append(Prediction(
            source=code,
            candidate_codes=frozenset({code}),
            category=spec["category"] if spec else obs.get("category"),
            severity=severity,
            timestamps_s=() if ts_ms is None else (float(ts_ms) / 1000.0,),
            confidence=float(obs.get("confidence", 1.0)),
        ))
    return out


@dataclass(frozen=True)
class Truth:
    """One ground-truth observation, enriched with its taxonomy category."""
    code: str
    present: bool
    severity: str
    confidence: str          # high/medium/low (coach's confidence)
    category: str | None
    timestamps_s: tuple[float, ...] = ()


def parse_ground_truth(gt: dict, taxonomy: dict) -> list[Truth]:
    codes = taxonomy["codes"]
    out: list[Truth] = []
    for obs in gt.get("observations", []):
        code = obs["code"]
        spec = codes.get(code)
        out.append(Truth(
            code=code,
            present=bool(obs.get("present", True)),
            severity=obs.get("severity", "moderate"),
            confidence=obs.get("confidence", "high"),
            category=spec["category"] if spec else None,
            timestamps_s=tuple(float(t) for t in obs.get("timestamps_s", [])),
        ))
    return out
