#!/usr/bin/env python3
"""In-process benchmark harness — score a TunedProfile over a pose dataset fast.

`runner.py` scores prediction files written to disk by `predict.py` (one engine
subprocess per clip). That is right for a one-off comparison but far too slow for
the optimiser, which scores hundreds of candidate threshold sets. This harness
runs the engine **in-process**: it loads every clip's pose + ground truth once,
then `evaluate(tuned_profile)` re-runs only the rule engine (with the candidate
thresholds injected via `TunedProfile.to_style_profile`) and scores it through
the SAME normalise + scorer + `runner.aggregate` path the disk runner uses. So
the numbers are identical to `runner.py run`, just produced ~1000x faster.

Requires the engine interpreter (numpy + `src` on the path). A full CoachMe
split (~160 clips) evaluates in well under a second.
"""
from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path

# Make the engine importable and keep flat eval-module imports working.
_HERE = Path(__file__).resolve().parent
_ROOT = _HERE.parent
for p in (str(_HERE), str(_ROOT / "src")):
    if p not in sys.path:
        sys.path.insert(0, p)

from boxing_coach.analysis.context import AnalysisContext
from boxing_coach.analysis.engine import RuleEngine
from boxing_coach.analysis.rules import default_rules
from boxing_coach.analysis.style_profiles import resolve_profile
from boxing_coach.domain.drill import DrillContext
from boxing_coach.domain.landmarks import Stance
from boxing_coach.domain.school import School
from boxing_coach.domain.style import Style
from boxing_coach.golden_fixtures import sequence_from_json

import json

from mappings.tuned_profile import TunedProfile
from normalise import load_taxonomy, normalise_detection, parse_ground_truth
from runner import aggregate
from scorer import score

# Same validity gates predict.py uses: a context value outside these falls back
# to the engine default rather than erroring.
_STANCES = {"orthodox": Stance.ORTHODOX, "southpaw": Stance.SOUTHPAW}
_STYLES = {s.value: s for s in Style}
_SCHOOLS = {s.value: s for s in School}


def _drill_from_context(ctx: dict) -> DrillContext:
    stance = _STANCES.get(ctx.get("stance"), Stance.ORTHODOX)
    style = _STYLES.get(ctx.get("style"), Style.HIGH_GUARD)
    school = _SCHOOLS.get(ctx.get("school"))
    return DrillContext(stance=stance, style=style, school=school)


def _observations_payload(observations) -> dict:
    """Serialise engine observations into the `boxing-coach --json` detection
    shape `normalise_detection` consumes (rule_id / severity / timestamp_ms)."""
    return {
        "specific_observations": [
            {
                "rule_id": o.rule_id,
                "category": o.category.value,
                "severity": o.severity.value,
                "timestamp_ms": o.timestamp_ms,
                "metrics": dict(o.metrics),
            }
            for o in observations
        ]
    }


@dataclass
class _Clip:
    video_id: str
    sequence: object          # PoseSequence
    drill: DrillContext
    base_profile: object      # StyleProfile before tuning (style+school resolved)
    ground_truth: dict        # raw gt dict (for parse_ground_truth + priority)
    # Pose-derived features that DON'T depend on the tuned thresholds — punch
    # detection especially is the heavy numpy step. Computed once per clip and
    # seeded into every candidate's context so tuning only re-runs the rules.
    body_scale: float = 0.0
    punches: object = None
    stance_speed: object = None
    round_profile: object = None


class Harness:
    """Loads a pose dataset once; scores any number of TunedProfiles in-process."""

    def __init__(self, dataset_dir: Path, *, allow_draft: bool = False,
                 min_confidence: str | None = None) -> None:
        self.dataset_dir = Path(dataset_dir)
        self.min_confidence = min_confidence
        self.taxonomy = load_taxonomy()
        self._engine = RuleEngine(default_rules())
        ok_status = {"reviewed", "draft"} if allow_draft else {"reviewed"}
        self.clips: list[_Clip] = []
        self.skipped: list[str] = []
        for gt_path in sorted(self.dataset_dir.glob("*/ground_truth.json")):
            gt = json.loads(gt_path.read_text())
            vid = gt.get("video_id", gt_path.parent.name)
            if gt.get("status") not in ok_status:
                self.skipped.append(f"{vid} (status={gt.get('status')})")
                continue
            pose_path = gt_path.parent / "pose.json"
            if not pose_path.is_file():
                self.skipped.append(f"{vid} (no pose.json)")
                continue
            drill = _drill_from_context(gt.get("context", {}))
            sequence = sequence_from_json(json.loads(pose_path.read_text()))
            # Warm the threshold-independent features once (body scale, punch
            # events, stance speed, round profile) via a throwaway context.
            warm = AnalysisContext(sequence=sequence, drill=drill)
            self.clips.append(_Clip(
                video_id=vid,
                sequence=sequence,
                drill=drill,
                base_profile=resolve_profile(drill.style, drill.school),
                ground_truth=gt,
                body_scale=warm.body_scale,
                punches=warm.punches,
                stance_speed=warm.stance_speed,
                round_profile=warm.round_profile,
            ))
        if not self.clips:
            raise SystemExit(
                f"no scorable clips in {self.dataset_dir}. skipped: {self.skipped or 'none'}"
            )

    def evaluate(self, tuned: TunedProfile | None = None) -> dict:
        """Run the engine over every clip with `tuned` thresholds; aggregate.

        Returns the same metric-bearing record shape as `runner.aggregate`
        (overall / by_category / by_severity / weighted / hallucination_rate),
        so `runner.compare` can diff two of these directly.
        """
        tuned = tuned or TunedProfile("baseline")
        results = []
        per_clip = []
        for clip in self.clips:
            profile = tuned.to_style_profile(base=clip.base_profile)
            context = AnalysisContext(
                sequence=clip.sequence, drill=clip.drill, style_profile=profile
            )
            # Seed the pre-warmed cached_property values so only the rules re-run
            # (punch detection etc. don't depend on the tuned thresholds).
            context.__dict__["body_scale"] = clip.body_scale
            context.__dict__["punches"] = clip.punches
            context.__dict__["stance_speed"] = clip.stance_speed
            context.__dict__["round_profile"] = clip.round_profile
            observations = self._engine.run(context)
            preds = normalise_detection(_observations_payload(observations), self.taxonomy)
            r = score(
                preds,
                parse_ground_truth(clip.ground_truth, self.taxonomy),
                min_confidence=self.min_confidence,
                priority_feedback=clip.ground_truth.get("priority_feedback"),
            )
            results.append(r)
            per_clip.append({"video_id": clip.video_id, **r.overall.as_dict()})
        rec = aggregate(results, per_clip)
        rec["tuned_profile"] = tuned.to_dict()
        rec["skipped"] = self.skipped
        return rec
