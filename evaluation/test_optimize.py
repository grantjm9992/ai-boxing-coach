#!/usr/bin/env python3
"""Tests for the in-process harness + optimiser — needs the ENGINE interpreter.

These import boxing_coach (numpy), so run them with the pyenv engine python, not
the bare sandbox one:

    ~/.pyenv/versions/3.10.0/bin/python3 -m unittest test_optimize

They score against the real CoachMe test split, so they double as an end-to-end
smoke test of the pose -> engine -> normalise -> score path.
"""
from __future__ import annotations

import unittest
from pathlib import Path

from harness import Harness
from mappings.tuned_profile import TunedProfile
from optimize import objective, passes_gate, hill_climb
from mappings.param_space import space

_TEST_SPLIT = Path(__file__).resolve().parent.parent / "datasets" / "coachme" / "test"


@unittest.skipUnless(_TEST_SPLIT.is_dir(), "CoachMe test split not present")
class TestHarness(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.h = Harness(_TEST_SPLIT)

    def test_loads_clips(self):
        self.assertGreater(len(self.h.clips), 0)

    def test_baseline_reproduces_known_metrics(self):
        # The disk runner's frozen CoachMe baseline (memory): P0.333/R0.107/F1 0.163.
        rec = self.h.evaluate(TunedProfile("baseline"))
        o = rec["metrics"]["overall"]
        self.assertAlmostEqual(o["precision"], 0.333, places=2)
        self.assertAlmostEqual(o["recall"], 0.107, places=2)
        self.assertAlmostEqual(o["f1"], 0.163, places=2)

    def test_tuned_profile_changes_output(self):
        base = self.h.evaluate(TunedProfile("baseline"))
        # Loosening the rotation bar hard must flag more rotation faults.
        loose = TunedProfile("loose", {"hip_rotation": {"min_shoulder_drive": 0.30}})
        rec = self.h.evaluate(loose)
        self.assertNotEqual(
            base["by_category"].get("rotation", {}).get("tp", 0),
            rec["by_category"].get("rotation", {}).get("tp", 0),
        )


class TestGateAndObjective(unittest.TestCase):
    def _rec(self, *, f1, whalluc=0.0, major=None, cats=None):
        return {
            "metrics": {
                "overall": {"f1": f1, "precision": f1, "recall": f1},
                "weighted": {"f1": f1, "precision": f1, "recall": f1},
                "hallucination_rate": whalluc,
                "major_recall": major,
            },
            "by_category": cats or {},
        }

    def test_objective_keys(self):
        rec = self._rec(f1=0.4)
        self.assertEqual(objective(rec, "overall_f1"), 0.4)
        self.assertEqual(objective(rec, "weighted_f1"), 0.4)

    def test_gate_rejects_category_regression(self):
        base = self._rec(f1=0.2, cats={"guard": {"f1": 0.5}})
        cand = self._rec(f1=0.3, cats={"guard": {"f1": 0.3}})  # guard fell 0.2
        ok, reasons = passes_gate(base, cand, category_tol=0.05, major_recall_tol=0.02)
        self.assertFalse(ok)
        self.assertTrue(any("guard" in r for r in reasons))

    def test_gate_rejects_hallucination_rise(self):
        base = self._rec(f1=0.2, whalluc=0.0)
        cand = self._rec(f1=0.9, whalluc=0.1)
        ok, _ = passes_gate(base, cand, category_tol=0.05, major_recall_tol=0.02)
        self.assertFalse(ok)

    def test_gate_passes_clean_improvement(self):
        base = self._rec(f1=0.2, cats={"guard": {"f1": 0.5}})
        cand = self._rec(f1=0.3, cats={"guard": {"f1": 0.55}})
        ok, reasons = passes_gate(base, cand, category_tol=0.05, major_recall_tol=0.02)
        self.assertTrue(ok, reasons)


@unittest.skipUnless(_TEST_SPLIT.is_dir(), "CoachMe test split not present")
class TestHillClimb(unittest.TestCase):
    def test_climb_improves_or_holds_objective(self):
        h = Harness(_TEST_SPLIT)
        baseline = h.evaluate(TunedProfile("baseline"))
        best, rec = hill_climb(
            h, space(), objective_key="weighted_f1", baseline_rec=baseline,
            start=TunedProfile("t"), category_tol=0.05, major_recall_tol=0.02,
            max_rounds=5, eps=1e-4, log=lambda _m: None)
        # A climb never returns something worse than where it started.
        self.assertGreaterEqual(
            objective(rec, "weighted_f1"), objective(baseline, "weighted_f1"))


if __name__ == "__main__":
    unittest.main()
