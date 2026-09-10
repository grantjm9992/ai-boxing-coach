#!/usr/bin/env python3
"""Unit tests for the evaluation scorer — run: python3 -m unittest -v (from evaluation/).

Synthetic fixtures only; no labelled data or engine needed.
"""
import unittest

from normalise import (
    Prediction, Truth, load_taxonomy,
    normalise_coaching, normalise_detection, normalise_severity,
)
from scorer import score

TAX = load_taxonomy()


def pred(codes, severity="moderate", category="guard", conf=1.0, source="x"):
    codes = frozenset({codes} if isinstance(codes, str) else codes)
    return Prediction(source=source, candidate_codes=codes, category=category,
                      severity=severity, confidence=conf)


def truth(code, present=True, severity="moderate", confidence="high", category="guard"):
    return Truth(code=code, present=present, severity=severity, confidence=confidence,
                 category=category)


class NormaliseTest(unittest.TestCase):
    def test_severity_mapping(self):
        self.assertEqual(normalise_severity("HIGH"), "major")
        self.assertEqual(normalise_severity("Medium"), "moderate")
        self.assertEqual(normalise_severity("low"), "minor")
        self.assertIsNone(normalise_severity("bogus"))

    def test_detection_expands_family_and_drops_non_faults(self):
        analysis = {"observations": [
            {"ruleId": "hands_up", "severity": "moderate", "timestampMs": 4400},
            {"ruleId": "footwork", "severity": "positive"},          # positive -> dropped
            {"ruleId": "school_adherence", "severity": "minor"},     # not a fault family -> dropped
        ]}
        preds = normalise_detection(analysis, TAX)
        self.assertEqual(len(preds), 1)
        self.assertEqual(preds[0].source, "hands_up")
        self.assertEqual(preds[0].candidate_codes, frozenset({"GUARD_001", "GUARD_002", "GUARD_006"}))
        self.assertEqual(preds[0].timestamps_s, (4.4,))
        self.assertFalse(preds[0].is_fine)

    def test_coaching_keeps_fine_code_and_unknown(self):
        report = {"priority_issues": [
            {"code": "GUARD_002", "severity": "HIGH", "confidence": 0.9, "timestamps": [4.4]},
            {"code": "MADE_UP", "severity": "LOW"},                  # unknown -> singleton, no category
        ]}
        preds = normalise_coaching(report, TAX)
        self.assertEqual(len(preds), 2)
        self.assertEqual(preds[0].candidate_codes, frozenset({"GUARD_002"}))
        self.assertEqual(preds[0].severity, "major")
        self.assertEqual(preds[0].category, "guard")
        self.assertTrue(preds[0].is_fine)
        self.assertIsNone(preds[1].category)


class ScoreTest(unittest.TestCase):
    def test_perfect_fine_match(self):
        r = score([pred("GUARD_002", "major")], [truth("GUARD_002", severity="major")])
        self.assertEqual((r.overall.tp, r.overall.fp, r.overall.fn), (1, 0, 0))
        self.assertEqual(r.overall.f1, 1.0)
        self.assertEqual(r.severity_accuracy, 1.0)

    def test_coarse_family_match(self):
        # hands_up family satisfies a GUARD_002 label.
        r = score([pred({"GUARD_001", "GUARD_002", "GUARD_006"}, source="hands_up")],
                  [truth("GUARD_002")])
        self.assertEqual((r.overall.tp, r.overall.fp, r.overall.fn), (1, 0, 0))

    def test_one_coarse_hit_cannot_cover_two_labels(self):
        # A single hands_up hit must not satisfy BOTH GUARD_001 and GUARD_002.
        r = score([pred({"GUARD_001", "GUARD_002", "GUARD_006"}, source="hands_up")],
                  [truth("GUARD_001"), truth("GUARD_002")])
        self.assertEqual((r.overall.tp, r.overall.fn), (1, 1))

    def test_false_positive_and_contradiction(self):
        preds = [pred("ROT_001", category="rotation")]
        truths = [truth("ROT_001", present=False, category="rotation")]  # coach: rotation was FINE
        r = score(preds, truths)
        self.assertEqual((r.overall.tp, r.overall.fp, r.overall.fn), (0, 1, 0))
        self.assertTrue(r.false_positives[0]["contradicted"])

    def test_per_category_breakdown(self):
        preds = [pred("GUARD_002", category="guard"), pred("FOOT_009", category="footwork")]
        truths = [truth("GUARD_002", category="guard"),
                  truth("FOOT_001", category="footwork")]  # footwork pred is wrong code
        r = score(preds, truths)
        self.assertEqual(r.by_category["guard"].f1, 1.0)
        self.assertEqual((r.by_category["footwork"].tp, r.by_category["footwork"].fp,
                          r.by_category["footwork"].fn), (0, 1, 1))

    def test_weighted_penalises_missing_major(self):
        # Miss a major (weight 5) but nail a minor (weight 1): weighted recall low.
        r = score([pred("FOOT_002", "minor", category="footwork")],
                  [truth("FOOT_002", severity="minor", category="footwork"),
                   truth("FOOT_001", severity="major", category="footwork")])
        self.assertAlmostEqual(r.overall.recall, 0.5)          # 1 of 2 by count
        self.assertAlmostEqual(r.weighted_recall, 1 / 6)       # 1 of (1+5) by weight

    def test_min_confidence_filter(self):
        # Low-confidence truth is dropped from scoring at min_confidence="high".
        r = score([], [truth("GUARD_002", confidence="low")], min_confidence="high")
        self.assertEqual((r.overall.tp, r.overall.fn), (0, 0))
        r2 = score([], [truth("GUARD_002", confidence="low")])
        self.assertEqual(r2.overall.fn, 1)

    def test_severity_accuracy_partial(self):
        r = score([pred("GUARD_001", "minor"), pred("GUARD_002", "major")],
                  [truth("GUARD_001", severity="major"), truth("GUARD_002", severity="major")])
        self.assertEqual(r.overall.tp, 2)
        self.assertEqual(r.severity_accuracy, 0.5)  # only GUARD_002 severity matches

    def test_priority_top1_hit(self):
        preds = [pred({"ROT_001", "ROT_002", "ROT_003", "ROT_004", "ROT_005"}, source="hip_rotation")]
        r = score(preds, [truth("ROT_001", category="rotation")],
                  priority_feedback=["ROT_001"])
        self.assertTrue(r.priority_top1_hit)
        r2 = score([], [truth("ROT_001")], priority_feedback=["ROT_001"])
        self.assertFalse(r2.priority_top1_hit)

    def test_serialisable(self):
        r = score([pred("GUARD_002")], [truth("GUARD_002")])
        d = r.as_dict()
        self.assertIn("overall", d)
        self.assertIn("weighted", d)
        self.assertEqual(d["overall"]["f1"], 1.0)


if __name__ == "__main__":
    unittest.main()
