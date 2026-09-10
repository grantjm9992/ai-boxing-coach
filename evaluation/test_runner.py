#!/usr/bin/env python3
"""Tests for the sweep/aggregate/compare runner — run: python3 -m unittest (from evaluation/)."""
import json
import tempfile
import unittest
from pathlib import Path

import runner


def _clip(root: Path, cid: str, observations, version, detection_obs,
          status="reviewed", priority=None):
    d = root / cid
    (d / "predictions" / version).mkdir(parents=True)
    (d / "ground_truth.json").write_text(json.dumps({
        "video_id": cid, "source_file": f"{cid}.mp4", "split": "development",
        "status": status, "context": {"stance": "orthodox", "exercise": "shadow"},
        "observations": observations, "priority_feedback": priority or [],
    }))
    (d / "predictions" / version / "detection.json").write_text(
        json.dumps({"observations": detection_obs}))


class RunnerTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.ds = Path(self._tmp.name)

    def tearDown(self):
        self._tmp.cleanup()

    def test_run_aggregates_across_clips(self):
        # clip A: rear hand low (major) present -> hands_up catches it (TP).
        _clip(self.ds, "a",
              [{"code": "GUARD_002", "present": True, "severity": "major", "confidence": "high"}],
              "v1", [{"ruleId": "hands_up", "severity": "moderate"}],
              priority=["GUARD_002"])
        # clip B: insufficient rotation (moderate) present but engine misses it (FN),
        #         and engine cries footwork the coach said was fine (contradicted FP).
        _clip(self.ds, "b",
              [{"code": "ROT_001", "present": True, "severity": "moderate", "confidence": "high"},
               {"code": "FOOT_001", "present": False, "severity": "major", "confidence": "high"}],
              "v1", [{"ruleId": "footwork", "severity": "major"}])

        rec = runner.run(self.ds, "v1", "detection", save=False)
        o = rec["metrics"]["overall"]
        self.assertEqual(rec["clip_count"], 2)
        self.assertEqual((o["tp"], o["fp"], o["fn"]), (1, 1, 1))     # A hit, B missed + FP
        # hallucination = contradicted FP / total predictions = 1 / (1 tp + 1 fp)
        self.assertAlmostEqual(rec["metrics"]["hallucination_rate"], 0.5)
        self.assertEqual(rec["metrics"]["priority_hit_rate"], 1.0)   # only A had priority, hit
        self.assertIn("guard", rec["by_category"])
        self.assertIn("footwork", rec["by_category"])

    def test_run_skips_unlabelled_and_missing_predictions(self):
        _clip(self.ds, "good",
              [{"code": "HEAD_001", "present": True, "severity": "minor", "confidence": "high"}],
              "v1", [{"ruleId": "head_movement", "severity": "minor"}])
        _clip(self.ds, "unlab",
              [{"code": "HEAD_001", "present": True, "severity": "minor", "confidence": "high"}],
              "v1", [{"ruleId": "head_movement", "severity": "minor"}], status="unlabelled")
        rec = runner.run(self.ds, "v1", "detection", save=False)
        self.assertEqual(rec["clip_count"], 1)
        self.assertTrue(any("unlab" in s for s in rec["skipped"]))

    def test_run_errors_when_nothing_scorable(self):
        _clip(self.ds, "x",
              [{"code": "HEAD_001", "present": True, "severity": "minor", "confidence": "high"}],
              "v1", [], status="draft")   # draft not allowed by default
        with self.assertRaises(SystemExit):
            runner.run(self.ds, "v1", "detection", save=False)


class CompareTest(unittest.TestCase):
    def _rec(self, f1, wf1, halluc, major_recall, cat_f1):
        return {
            "version": "v", "layer": "detection", "dataset": "d", "git_commit": "abc",
            "metrics": {
                "overall": {"precision": f1, "recall": f1, "f1": f1},
                "weighted": {"precision": wf1, "recall": wf1, "f1": wf1},
                "hallucination_rate": halluc, "severity_accuracy": 0.8,
                "major_recall": major_recall,
            },
            "by_category": {"footwork": {"f1": cat_f1}},
        }

    def test_gate_passes_on_improvement(self):
        base = self._rec(0.80, 0.80, 0.05, 0.80, 0.82)
        cand = self._rec(0.88, 0.86, 0.04, 0.85, 0.88)
        self.assertTrue(runner.compare(base, cand))

    def test_gate_rejects_category_regression(self):
        base = self._rec(0.80, 0.80, 0.05, 0.80, 0.90)
        cand = self._rec(0.85, 0.85, 0.05, 0.80, 0.70)   # footwork 0.90 -> 0.70
        self.assertFalse(runner.compare(base, cand))

    def test_gate_rejects_hallucination_rise(self):
        base = self._rec(0.80, 0.80, 0.04, 0.80, 0.82)
        cand = self._rec(0.90, 0.90, 0.09, 0.80, 0.85)   # halluc up
        self.assertFalse(runner.compare(base, cand))

    def test_gate_rejects_major_recall_drop(self):
        base = self._rec(0.80, 0.80, 0.04, 0.90, 0.82)
        cand = self._rec(0.90, 0.90, 0.04, 0.80, 0.85)   # major recall 0.90 -> 0.80 (>0.02)
        self.assertFalse(runner.compare(base, cand))


if __name__ == "__main__":
    unittest.main()
