#!/usr/bin/env python3
"""Validate ground-truth label files against the taxonomy — stdlib only.

Checks every datasets/**/ground_truth.json:
  * required keys present, enums valid (status/split/stance/exercise/severity/confidence)
  * every observation `code` exists in annotations/taxonomy/codes.json
  * severity matches the code's category is not required, but severity must be valid
  * priority_feedback only references codes that appear in observations
  * video_id matches its directory name

With --check-taxonomy, also cross-checks codes.json against the Dart source
(app/lib/analysis/error_codes.dart) so the canonical list can't silently drift.

Exit code 0 = clean, 1 = problems found. No third-party deps (runs anywhere).
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TAXONOMY = ROOT / "annotations" / "taxonomy" / "codes.json"
DART_CODES = ROOT / "app" / "lib" / "analysis" / "error_codes.dart"
LABELS_GLOB = "datasets/**/ground_truth.json"

STATUS = {"unlabelled", "draft", "reviewed"}
SPLIT = {"development", "validation", "golden", "regression"}
STANCE = {"orthodox", "southpaw", "unknown"}
EXERCISE = {"shadow", "bag", "drill", "combination", "unknown"}
SKILL = {"beginner", "intermediate", "advanced", "unknown"}
SEVERITY = {"major", "moderate", "minor", "positive"}
CONFIDENCE = {"high", "medium", "low"}


def load_taxonomy() -> dict:
    return json.loads(TAXONOMY.read_text())


def validate_label(path: Path, codes: set[str]) -> list[str]:
    errs: list[str] = []
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError as e:
        return [f"invalid JSON: {e}"]

    def enum(key: str, value, allowed: set[str]):
        if value not in allowed:
            errs.append(f"{key}={value!r} not in {sorted(allowed)}")

    for key in ("video_id", "source_file", "split", "status", "context", "observations"):
        if key not in data:
            errs.append(f"missing required key {key!r}")
    if errs:
        return errs

    if data["video_id"] != path.parent.name:
        errs.append(f"video_id {data['video_id']!r} != directory {path.parent.name!r}")
    if not re.fullmatch(r"[a-z0-9_]+", data["video_id"]):
        errs.append(f"video_id {data['video_id']!r} is not snake_case")
    enum("split", data["split"], SPLIT)
    enum("status", data["status"], STATUS)

    ctx = data["context"]
    enum("context.stance", ctx.get("stance"), STANCE)
    enum("context.exercise", ctx.get("exercise"), EXERCISE)
    if "skill_level" in ctx:
        enum("context.skill_level", ctx["skill_level"], SKILL)

    seen_codes: set[str] = set()
    for i, obs in enumerate(data["observations"]):
        where = f"observations[{i}]"
        code = obs.get("code")
        if code not in codes:
            errs.append(f"{where}.code {code!r} not in taxonomy")
        else:
            seen_codes.add(code)
        if "severity" in obs:
            enum(f"{where}.severity", obs["severity"], SEVERITY)
        if "confidence" in obs:
            enum(f"{where}.confidence", obs["confidence"], CONFIDENCE)
        if not isinstance(obs.get("present"), bool):
            errs.append(f"{where}.present must be a boolean")

    for code in data.get("priority_feedback", []):
        if code not in seen_codes:
            errs.append(f"priority_feedback code {code!r} not among this clip's observations")

    # A reviewed clip should actually carry judgements.
    if data["status"] == "reviewed" and not data["observations"]:
        errs.append("status=reviewed but observations is empty")

    return errs


def check_taxonomy(tax: dict) -> list[str]:
    errs: list[str] = []
    codes = tax["codes"]
    cats = set(tax["categories"])
    sevs = set(tax["severities"])
    for code, spec in codes.items():
        if spec["category"] not in cats:
            errs.append(f"{code}: category {spec['category']!r} not defined")
        if spec["default_severity"] not in sevs:
            errs.append(f"{code}: default_severity {spec['default_severity']!r} invalid")

    # Cross-check against the Dart FaultCode source.
    if DART_CODES.exists():
        dart_members = set(re.findall(r"static const (\w+) =", DART_CODES.read_text()))
        yaml_members = {spec["dart"] for spec in codes.values()}
        for missing in sorted(dart_members - yaml_members):
            errs.append(f"Dart FaultCode.{missing} has no taxonomy entry")
        for extra in sorted(yaml_members - dart_members):
            errs.append(f"taxonomy references Dart member {extra!r} that no longer exists")

    # Every python_rules family code must be a real canonical code.
    for rule, spec in tax["python_rules"].items():
        for c in spec.get("emits_codes", []):
            if c not in codes:
                errs.append(f"python_rules.{rule} emits undefined code {c!r}")
    return errs


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check-taxonomy", action="store_true",
                    help="also validate codes.json and cross-check the Dart source")
    args = ap.parse_args(argv)

    tax = load_taxonomy()
    codes = set(tax["codes"])
    total_errs = 0

    if args.check_taxonomy:
        errs = check_taxonomy(tax)
        if errs:
            total_errs += len(errs)
            print(f"✗ taxonomy codes.json ({len(errs)})")
            for e in errs:
                print(f"    {e}")
        else:
            print("✓ taxonomy codes.json")

    labels = sorted(ROOT.glob(LABELS_GLOB))
    if not labels:
        print(f"(no label files matched {LABELS_GLOB})")
    for path in labels:
        rel = path.relative_to(ROOT)
        errs = validate_label(path, codes)
        if errs:
            total_errs += len(errs)
            print(f"✗ {rel} ({len(errs)})")
            for e in errs:
                print(f"    {e}")
        else:
            print(f"✓ {rel}")

    print(f"\n{'FAIL' if total_errs else 'OK'} — {total_errs} problem(s)")
    return 1 if total_errs else 0


if __name__ == "__main__":
    sys.exit(main())
