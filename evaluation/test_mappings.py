#!/usr/bin/env python3
"""Tests for the mapping abstractions — stdlib only (bare interpreter OK).

Covers the registry's isolation guarantees, the param-space grid maths, the
TunedProfile (de)serialisation, and the phrase-map resolution — everything that
does NOT need the engine. `test_optimize.py` covers the engine-touching parts.

    python3 -m unittest test_mappings
"""
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from mappings.joints import SMPL22
from mappings.param_space import ParamSpec, space
from mappings.phrase_map import PHRASE_MAPS, DEFAULT_PHRASE_MAP
from mappings.registry import Registry
from mappings.tuned_profile import TunedProfile


class TestRegistry(unittest.TestCase):
    def test_register_get_names(self):
        r: Registry[int] = Registry("thing")
        r.register("a-v1", 1)
        r.register("b-v1", 2)
        self.assertEqual(r.get("a-v1"), 1)
        self.assertEqual(r.names(), ["a-v1", "b-v1"])
        self.assertIn("a-v1", r)

    def test_duplicate_name_rejected(self):
        r: Registry[int] = Registry("thing")
        r.register("x", 1)
        with self.assertRaises(ValueError):
            r.register("x", 2)  # never silently shadow a frozen mapping

    def test_unknown_name_raises(self):
        r: Registry[int] = Registry("thing")
        with self.assertRaises(KeyError):
            r.get("missing")


class TestParamSpace(unittest.TestCase):
    def test_candidates_within_bounds_and_stepped(self):
        s = ParamSpec("r", "f", default=0.10, lo=0.02, hi=0.30, step=0.02)
        cands = s.candidates()
        self.assertEqual(cands[0], 0.02)
        self.assertEqual(cands[-1], 0.30)
        self.assertIn(0.10, cands)              # default present
        self.assertTrue(all(0.02 <= c <= 0.30 for c in cands))

    def test_neighbours_are_one_step_either_side(self):
        s = ParamSpec("r", "f", default=0.10, lo=0.02, hi=0.30, step=0.02)
        self.assertEqual(sorted(s.neighbours(0.10)), [0.08, 0.12])
        self.assertEqual(s.neighbours(0.02), [0.04])   # clamped at the low edge

    def test_int_kind_snaps(self):
        s = ParamSpec("r", "n", default=10, lo=5, hi=15, step=1, kind="int")
        self.assertEqual(s.clamp(10.4), 10)
        self.assertTrue(all(isinstance(c, (int, float)) for c in s.candidates()))

    def test_default_space_registered(self):
        specs = space()
        self.assertTrue(specs)
        keys = {s.key for s in specs}
        self.assertIn("hip_rotation.min_shoulder_drive", keys)


class TestTunedProfile(unittest.TestCase):
    def test_with_override_is_immutable(self):
        base = TunedProfile("t")
        child = base.with_override("hands_up", "drop_margin", 0.2)
        self.assertTrue(base.is_empty())            # original untouched
        self.assertEqual(child.get("hands_up", "drop_margin", 0.1), 0.2)

    def test_json_roundtrip(self):
        tp = TunedProfile("x", {"hip_rotation": {"min_shoulder_drive": 0.28}})
        again = TunedProfile.from_dict(json.loads(json.dumps(tp.to_dict())))
        self.assertEqual(again.flat(), {"hip_rotation.min_shoulder_drive": 0.28})

    def test_save_load(self):
        tp = TunedProfile("x", {"knee_bend": {"straight_deg": 166.0}})
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "sub" / "prof.json"
            tp.save(p)                              # creates parent dirs
            self.assertEqual(TunedProfile.load(p).flat(), tp.flat())

    def test_empty_overrides_dropped_on_serialise(self):
        tp = TunedProfile("x", {"hands_up": {}})
        self.assertEqual(tp.to_dict()["overrides"], {})


class TestPhraseMap(unittest.TestCase):
    def setUp(self):
        self.pm = PHRASE_MAPS.get(DEFAULT_PHRASE_MAP)

    def test_guard_other_resolves_by_motion(self):
        # "keep your other hand up" -> the NON-punching hand.
        cross = dict(self.pm.match("Keep your other hand up.", "Cross"))
        jab = dict(self.pm.match("Keep your other hand up.", "Jab"))
        self.assertIn("GUARD_001", cross)   # cross -> lead guard
        self.assertIn("GUARD_002", jab)     # jab  -> rear guard

    def test_rotation_phrase_maps(self):
        codes = dict(self.pm.match("You're only using your arm strength.", "Cross"))
        self.assertIn("ROT_001", codes)

    def test_unmatched_yields_nothing(self):
        self.assertEqual(list(self.pm.match("The weather is nice today.", "Jab")), [])


class TestJointMap(unittest.TestCase):
    def test_frame_to_keypoints_offsets_and_maps(self):
        joints = [[0.0, 0.0, 0.0]] * SMPL22.source_joint_count
        joints[16] = [0.1, -0.2, 0.3]   # left shoulder -> mp 11
        kp = SMPL22.frame_to_keypoints(joints)
        self.assertIn("11", kp)
        self.assertAlmostEqual(kp["11"][0], 0.1 + SMPL22.offset, places=4)
        self.assertEqual(kp["11"][3], 1.0)   # visibility
        self.assertNotIn("31", kp)           # SMPL feet dropped


if __name__ == "__main__":
    unittest.main()
