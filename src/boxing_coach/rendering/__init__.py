"""Rendering: turn analysis output into things a person can look at.

Currently: annotated stills — one frame per correction with the pose skeleton
drawn and the at-fault body part highlighted. Kept separate from the analysis
engine (and behind a lazy cv2 import) so the engine and its tests never need
the CV stack.
"""

from .stills import StillRenderer, nearest_frame, to_pixel

__all__ = ["StillRenderer", "nearest_frame", "to_pixel"]
