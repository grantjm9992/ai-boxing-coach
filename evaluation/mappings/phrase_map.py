#!/usr/bin/env python3
"""Coach-text -> taxonomy phrase maps (plan §11).

CoachMe gives free-text coach instructions; the benchmark needs taxonomy codes.
That translation is a *mapping* like any other, and the plan is explicit that a
mapping used for scoring must be reviewable and then FROZEN — an improved map is
a new version, not an edit to the one the current numbers were computed against.
So each map is a named, versioned `PhraseMap` in the registry; `import_coachme.py`
loads one by name. Registering v2 can never disturb v1's frozen labels.

A `PhraseMap` is an ordered list of `(regex, code, note)` rules. `code` may be
the sentinel `GUARD_OTHER`, resolved to the non-punching hand from the clip's
motion_type at apply time (Cross -> lead=GUARD_001; Jab -> rear=GUARD_002). The
map is deliberately conservative: a sentence that matches nothing surfaces under
`unmapped_sentences` for human review rather than getting a wrong code.

stdlib only.
"""
from __future__ import annotations

import re
from dataclasses import dataclass

from .registry import Registry

#: Sentinel code resolved to the non-punching hand from motion_type at apply time.
GUARD_OTHER = "GUARD_OTHER"
_GUARD_BY_MOTION = {"Cross": "GUARD_001", "Jab": "GUARD_002"}  # non-punching hand


@dataclass(frozen=True)
class PhraseRule:
    pattern: re.Pattern[str]
    code: str
    note: str


@dataclass(frozen=True)
class PhraseMap:
    """An ordered, frozen set of coach-phrase -> taxonomy-code rules."""

    name: str
    rules: tuple[PhraseRule, ...]

    def resolve(self, code: str, motion_type: str) -> str:
        """Turn the `GUARD_OTHER` sentinel into a concrete hand-specific code."""
        if code == GUARD_OTHER:
            return _GUARD_BY_MOTION.get(motion_type, "GUARD_006")
        return code

    def match(self, sentence: str, motion_type: str):
        """Yield (code, note) for every rule that fires on `sentence`.

        Codes are already resolved for the clip's motion_type. A sentence may
        trip several rules (dedup is the caller's job, keyed by resolved code).
        """
        for rule in self.rules:
            if rule.pattern.search(sentence):
                yield self.resolve(rule.code, motion_type), rule.note


def _compile(rules: list[tuple[str, str, str]]) -> tuple[PhraseRule, ...]:
    return tuple(
        PhraseRule(re.compile(pat, re.I), code, note) for pat, code, note in rules
    )


PHRASE_MAPS: Registry[PhraseMap] = Registry("phrase")


# v1: the conservative map the current CoachMe ground-truth labels were built
# with. Kept verbatim from the original import_coachme `_RULES` so those frozen
# labels reproduce exactly. DO NOT edit these patterns — register a v2 instead.
_COACHME_V1_RULES: list[tuple[str, str, str]] = [
    # Rotation / kinetic chain
    (r"body.{0,20}(isn'?t|is not|not|should).{0,20}rotat", "ROT_001", "body not rotating"),
    (r"\b(only|just).{0,15}arm(\s+strength)?\b", "ROT_001", "arm-only, no rotation"),
    (r"not.{0,20}(using|drawing).{0,20}(power|force).{0,20}(lower body|legs?|hips?)", "ROT_001", "no lower-body power"),
    (r"\b(turn|rotate|drive).{0,15}(the|your)?\s*(hip|shoulder|waist|torso|body)\b", "ROT_001", "cue to rotate"),
    (r"\bhips?\b.{0,20}rotat", "ROT_001", "hips not rotating"),
    (r"rotat.{0,20}\bhips?\b", "ROT_001", "cue to rotate hips"),
    (r"(isn'?t|is not|not|aren'?t)\s+rotat", "ROT_001", "not rotating"),
    (r"squared? up", "ROT_001", "squared up on the shot"),
    (r"\b(back|rear)\s+(foot|heel)\b.{0,20}(isn'?t|is not|not)\s+lift|lift.{0,15}(the\s+)?heel", "ROT_001", "rear heel not pivoting (kinetic chain)"),
    # Guard — non-punching hand up (resolved by motion_type)
    (r"(keep|hold|get|bring|put).{0,20}\bhand\b.{0,12}\bup\b", GUARD_OTHER, "keep hand up"),
    (r"other hand.{0,10}up", GUARD_OTHER, "other hand up for defence"),
    (r"\bguard\b.{0,10}up", GUARD_OTHER, "guard up"),
    (r"protect.{0,10}(your )?(face|chin|jaw)", GUARD_OTHER, "protect the chin"),
    (r"\bhands?\b.{0,15}(too )?(low|down|dropping|drops)", "GUARD_006", "hand(s) low"),
    (r"lead hand.{0,20}(higher|\bhigh\b|\blow\b|up)", "GUARD_001", "lead hand low / raise lead"),
    # Recovery / hand return
    (r"(return|bring|snap).{0,20}(hand|it).{0,10}(back|to)", "REC_002", "return the hand"),
    (r"hand.{0,15}(back to|returns? to).{0,10}(guard|cheek|face)", "REC_002", "hand back to guard"),
    # Balance
    (r"(off|not).{0,12}balanc", "BAL_001", "off balance"),
    (r"cent(er|re) of gravity", "BAL_001", "centre of gravity"),
    (r"weight.{0,20}(even|balanced|both feet|distribut)", "BAL_001", "weight not even"),
    (r"weight.{0,15}(too )?(far )?forward", "BAL_003", "weight forward"),
    (r"weight.{0,15}(too )?(far )?back", "BAL_004", "weight backward"),
    # Lean
    (r"lean(ing)?.{0,12}forward", "LEAN_001", "leaning forward"),
    (r"lean(ing)?.{0,12}back", "LEAN_002", "leaning backward"),
    (r"lean(ing)?.{0,12}left", "LEAN_003", "leaning left"),
    (r"lean(ing)?.{0,12}right", "LEAN_004", "leaning right"),
    # Footwork / stance
    (r"stance.{0,12}(too )?narrow|feet.{0,12}(too )?close", "FOOT_002", "stance narrow"),
    (r"stance.{0,12}(too )?wide|feet.{0,12}(too )?wide", "FOOT_003", "stance wide"),
    (r"feet.{0,12}square|squared?.{0,10}stance|(too|body|standing|you'?re)\s+.{0,6}square|body is.{0,10}square", "FOOT_004", "feet/body too square"),
    (r"flat.?footed|stay.{0,12}(light|on your toes)|not moving.{0,12}(your )?feet", "FOOT_009", "flat-footed"),
    # Body position
    (r"too upright|standing.{0,12}(too )?(tall|straight)", "POS_003", "too upright"),
    (r"head.{0,15}(too far )?forward", "POS_001", "head too far forward"),
    (r"(knee|leg)s?.{0,15}(too )?straight|lock.{0,10}(out )?(your )?(front )?(leg|knee)|(not|aren'?t).{0,15}half.?squat|bend.{0,10}(your )?knees", "POS_006", "knees too straight / no bend"),
    # Chin
    (r"chin.{0,15}(isn'?t|is not|not).{0,10}tuck|tuck.{0,10}(your |the )?chin|chin.{0,6}(up|out|exposed)|keep.{0,10}chin.{0,10}down", "GUARD_007", "chin not tucked"),
    # Muscular tension
    (r"(too )?(stiff|tense|rigid|tight)\b|relax.{0,15}(your )?(body|shoulders|arms)", "TENSE_001", "upper-body tension"),
]

COACHME_V1 = PHRASE_MAPS.register(
    "coachme-v1", PhraseMap("coachme-v1", _compile(_COACHME_V1_RULES))
)

#: The map `import_coachme.py` uses unless told otherwise. Frozen: the current
#: CoachMe labels were computed with it. Bump this only alongside a re-import.
DEFAULT_PHRASE_MAP = "coachme-v1"
