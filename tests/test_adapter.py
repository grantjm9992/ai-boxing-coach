"""End-to-end: PoseOnlyAdapter turns a sequence into a RoundAnalysis."""

from boxing_coach.adapters import PoseOnlyAdapter
from boxing_coach.domain.drill import DrillContext

import fixtures


def test_dropped_guard_round_produces_correction():
    analysis = PoseOnlyAdapter().analyse(fixtures.dropped_guard_jab(), DrillContext())

    assert analysis.metrics.punches_thrown == 1
    assert analysis.overall_summary
    # A dropped guard should surface as a prioritised correction + a flag.
    assert analysis.correction_priorities
    assert analysis.correction_priorities[0].priority == 1
    assert analysis.correction_priorities[0].suggested_drill is not None
    assert analysis.flagged_moments


def test_clean_round_reports_no_corrections():
    analysis = PoseOnlyAdapter().analyse(fixtures.clean_jab(), DrillContext())
    assert analysis.correction_priorities == []
    assert analysis.positive_notes  # should have something encouraging


def test_corrections_are_deduped_by_category():
    analysis = PoseOnlyAdapter().analyse(fixtures.dropped_guard_jab(), DrillContext())
    categories = [c.category for c in analysis.correction_priorities]
    assert len(categories) == len(set(categories))
