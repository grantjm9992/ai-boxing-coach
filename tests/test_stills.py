"""Still-rendering helpers and highlight propagation.

The cv2 drawing path needs the CV stack and a real video, so it isn't unit
tested here; the pure geometry helpers and the rule->correction highlight
wiring are, since those are where the logic lives.
"""

from boxing_coach.adapters import PoseOnlyAdapter
from boxing_coach.domain.drill import DrillContext
from boxing_coach.domain.landmarks import Landmark
from boxing_coach.rendering import nearest_frame, to_pixel

import fixtures


# -- nearest_frame ---------------------------------------------------------

def test_nearest_frame_picks_closest_timestamp():
    seq = fixtures.dropped_guard_jab()
    target = seq.frames[3].timestamp_ms + 1.0  # just past frame 3
    assert nearest_frame(seq, target).index == 3


def test_nearest_frame_none_on_empty():
    from boxing_coach.domain.pose import PoseSequence

    assert nearest_frame(PoseSequence(frames=[], fps=30.0), 100.0) is None


# -- to_pixel --------------------------------------------------------------

def test_to_pixel_maps_normalised_to_pixels():
    # Maps onto the [0, size-1] pixel grid: 0.5 * 99 -> 50, 0.5 * 199 -> 100.
    assert to_pixel(0.5, 0.5, 100, 200) == (50, 100)
    assert to_pixel(0.0, 1.0, 100, 200) == (0, 199)


def test_to_pixel_clamps_out_of_range():
    assert to_pixel(-1.0, 2.0, 100, 200) == (0, 199)


# -- highlight propagation -------------------------------------------------

def test_correction_carries_highlight_landmark():
    # Orthodox lead hand is LEFT; a dropped guard should highlight that wrist.
    analysis = PoseOnlyAdapter().analyse(fixtures.dropped_guard_jab(), DrillContext())
    top = analysis.correction_priorities[0]
    assert top.highlight_landmarks == (Landmark.LEFT_WRIST,)
    assert top.still_path is None  # not rendered unless --stills is used
