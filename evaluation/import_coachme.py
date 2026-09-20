#!/usr/bin/env python3
"""Convert the CoachMe BX dataset's coach instructions into our ground_truth.json.

CoachMe (ACL 2025, github.com/MotionXperts/MotionExpert) ships, per clip, THREE
independent free-text coaching instructions from three boxing coaches, plus a
22-joint SMPL pose sequence (`.pkl`). The raw videos are withheld for athlete
privacy, so these clips are pose+label only.

This turns the free text into our taxonomy (`annotations/taxonomy/codes.json`)
with a transparent, conservative phrase map. It is a LABELLING AID, not an
oracle: every clip is written `status: draft`, the verbatim coach sentences are
kept as provenance, unmatched sentences are surfaced under `unmapped_sentences`,
and a coach must review before promoting to `reviewed`. GPT-4 `augmented_labels`
are ignored — only the real coach `labels` are used.

Confidence comes from cross-coach agreement: a code named by >=2 of the 3
coaches is `high`, by one is `medium`. Guard "keep your other hand up" is
resolved to the NON-PUNCHING hand from motion_type (Cross -> lead=GUARD_001;
Jab -> rear=GUARD_002).

Usage:
    python3 import_coachme.py /path/to/BX_train.json --split train  --out ../datasets/coachme
    python3 import_coachme.py /path/to/BX_test.json  --split test   --out ../datasets/coachme
    python3 import_coachme.py BX_test.json --split test --out ../datasets/coachme --dry-run
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from mappings.phrase_map import DEFAULT_PHRASE_MAP, PHRASE_MAPS, PhraseMap

ROOT = Path(__file__).resolve().parent.parent
TAXONOMY = ROOT / "annotations" / "taxonomy" / "codes.json"

# The coach-text -> taxonomy phrase map now lives behind the versioned registry
# (mappings/phrase_map.py) so an improved map is a NEW version and can't disturb
# the frozen one the current labels were built with. Selected by --phrase-map.
_SENTENCE_SPLIT = re.compile(r"(?<=[.!?])\s+")


def _sentences(text: str) -> list[str]:
    return [s.strip() for s in _SENTENCE_SPLIT.split(text.strip()) if s.strip()]


_NOTES = {
    "draft": (
        "DRAFT — coach free-text auto-mapped to taxonomy codes by a conservative "
        "phrase map, NOT verified. The real judgement is in `coach_labels` (3 "
        "independent boxing coaches); `observations` is a best-effort encoding and "
        "`unmapped_sentences` lists text no rule caught. A coach must review before "
        "status='reviewed'. GPT-4 augmented_labels were intentionally excluded."
    ),
    "reviewed": (
        "TRUSTED (good faith) — `coach_labels` are genuine judgement from 3 "
        "independent CoachMe boxing coaches, trusted per the authors' email (the "
        "raw videos can't be shared for privacy). NOTE: `observations` is a "
        "machine phrase-map of that text and may be INCOMPLETE — `unmapped_sentences` "
        "holds coach faults not yet encoded, so the ABSENCE of a code is not a "
        "coach 'all-clear' (it caps recall, not precision). GPT-4 augmented_labels "
        "excluded."
    ),
}
_REVIEWERS = {
    "reviewed": ["CoachMe: 3 boxing coaches (source-trusted per authors' email)"],
}


def convert_entry(entry: dict, valid_codes: set[str], status: str = "draft",
                  phrase_map: PhraseMap | None = None) -> dict:
    phrase_map = phrase_map or PHRASE_MAPS.get(DEFAULT_PHRASE_MAP)
    video_name = entry.get("video_name", "unknown")
    motion = entry.get("motion_type", "unknown")
    coach_labels = [l for l in entry.get("labels", []) if isinstance(l, str)]

    # code -> {coaches: set(coach_idx), phrases: [..], note}
    hits: dict[str, dict] = {}
    unmapped: list[str] = []
    for coach_idx, label in enumerate(coach_labels):
        for sentence in _sentences(label):
            matched = False
            for code, note in phrase_map.match(sentence, motion):
                if code not in valid_codes:
                    continue
                rec = hits.setdefault(code, {"coaches": set(), "phrases": [], "note": note})
                rec["coaches"].add(coach_idx)
                rec["phrases"].append({"coach": coach_idx, "text": sentence})
                matched = True
            if not matched:
                unmapped.append(sentence)

    observations = []
    for code, rec in sorted(hits.items()):
        agree = len(rec["coaches"])
        # A sentence can trip two patterns for the same code; keep each once.
        seen: set[tuple[int, str]] = set()
        phrases = []
        for p in rec["phrases"]:
            key = (p["coach"], p["text"])
            if key not in seen:
                seen.add(key)
                phrases.append(p)
        observations.append({
            "code": code,
            "present": True,
            "severity": "moderate",           # coaches rarely state severity — review
            "confidence": "high" if agree >= 2 else "medium",
            "coach_agreement": agree,          # of 3
            "source_sentences": phrases,
            "map_note": rec["note"],
        })

    # Don't promote a clip to 'reviewed' with no encoded faults — that would
    # assert the coach saw nothing, but they did (it's in coach_labels /
    # unmapped_sentences); the phrase map just caught none. Keep it draft.
    effective_status = status if observations else "draft"

    return {
        "video_id": video_name,
        "source_file": None,
        "source_note": "CoachMe BX (github.com/MotionXperts/MotionExpert, Apache-2.0) "
                       "— raw video withheld for athlete privacy; 22-joint SMPL pose "
                       "in the accompanying .pkl. Provenance in path + labelled_by.",
        "split": "development",
        "status": effective_status,
        "labelled_by": "coachme-phrase-map",
        "reviewers": _REVIEWERS.get(effective_status, []),
        "notes": _NOTES.get(effective_status, _NOTES["draft"]),
        "context": {
            "stance": "unknown",
            "exercise": "drill",
            "skill_level": "beginner",         # CoachMe BX = 10 beginner boxers
            "style": None,
            "school": None,
            "motion_type": motion,
        },
        "coach_labels": coach_labels,
        "observations": observations,
        "unmapped_sentences": sorted(set(unmapped)),
        "positive_observations": [],
        "priority_feedback": [],
    }


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", type=Path, help="BX_train.json or BX_test.json")
    ap.add_argument("--split", required=True, help="subsplit dir name, e.g. train / test")
    ap.add_argument("--out", type=Path, default=ROOT / "datasets" / "coachme",
                    help="output root (default datasets/coachme)")
    ap.add_argument("--status", default="draft", choices=["draft", "reviewed"],
                    help="label status. 'reviewed' trusts the CoachMe coach text in "
                         "good faith (the code mapping stays machine-derived — see the "
                         "note it writes). Default 'draft'.")
    ap.add_argument("--phrase-map", default=DEFAULT_PHRASE_MAP, choices=PHRASE_MAPS.names(),
                    help=f"coach-text->taxonomy map version (default {DEFAULT_PHRASE_MAP})")
    ap.add_argument("--dry-run", action="store_true", help="report stats, write nothing")
    args = ap.parse_args(argv)

    phrase_map = PHRASE_MAPS.get(args.phrase_map)
    valid_codes = set(json.loads(TAXONOMY.read_text())["codes"])
    entries = json.loads(args.input.read_text())

    out_dir = args.out / args.split
    n_obs = 0
    n_unmapped = 0
    code_freq: dict[str, int] = {}
    clips_with_obs = 0
    for entry in entries:
        gt = convert_entry(entry, valid_codes, status=args.status, phrase_map=phrase_map)
        n_obs += len(gt["observations"])
        n_unmapped += len(gt["unmapped_sentences"])
        clips_with_obs += 1 if gt["observations"] else 0
        for o in gt["observations"]:
            code_freq[o["code"]] = code_freq.get(o["code"], 0) + 1
        if not args.dry_run:
            clip_dir = out_dir / gt["video_id"]
            clip_dir.mkdir(parents=True, exist_ok=True)
            (clip_dir / "ground_truth.json").write_text(json.dumps(gt, indent=2, ensure_ascii=False) + "\n")

    print(f"{len(entries)} clips | {clips_with_obs} with >=1 mapped obs | "
          f"{n_obs} observations | {n_unmapped} unmapped sentences")
    print("code frequency:", ", ".join(f"{c}:{n}" for c, n in sorted(code_freq.items(), key=lambda kv: -kv[1])))
    if not args.dry_run:
        print(f"wrote -> {out_dir}/<video_id>/ground_truth.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
