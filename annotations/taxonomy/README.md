# Fault taxonomy

`codes.json` is the **single source of truth** for the codes used by the
evaluation platform. Coach ground-truth labels, engine predictions, and the
scorer all key on it.

## Why it exists — two engines, two granularities

Two engines detect faults at **different granularities**, and the benchmark has
to grade both against the same coach labels:

- **Dart app** (`app/lib/analysis/error_codes.dart`) — fine-grained fault codes
  (`GUARD_002` = rear hand low). This is the shipped contract, and the AI
  coaching layer already reuses these codes.
- **Python engine** (`src/boxing_coach/analysis/rules/`) — coarse rule ids
  (`hands_up`), one per rule, each covering a *family* of fine codes.

The fine-grained codes are canonical. The scorer bridges the gap:

- A Dart/coaching prediction carries a fine code directly.
- A coarse Python rule hit (e.g. `hands_up`) counts as a match for **any** label
  in its family — see `python_rules[*].emits_codes`.

`school_adherence` is style coaching, not a fault, so it is excluded from fault
precision/recall (`category: null`).

## Structure

| key | meaning |
|---|---|
| `severities` | `major/moderate/minor/positive` + weights for the weighted score |
| `categories` | the scoring categories every code belongs to |
| `codes` | canonical fine codes: `category`, `label`, `default_severity`, `dart` member name, `python` rule id(s) that can emit it |
| `python_rules` | reverse map: each coarse rule → the family of codes it can satisfy |

## Rules for changing it

- Codes are **identity, not display text**. Once shipped, a code's meaning must
  not drift. Add new codes; never renumber or repurpose.
- Keep in sync with `error_codes.dart` (Dart) and the rule `id`s (Python).
  `evaluation/validate_labels.py --check-taxonomy` cross-checks against the Dart
  source.
