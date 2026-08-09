"""Annotated stills — a frame per correction the user can actually see.

For each correction that is tied to a moment, we re-open the source video, grab
the frame at that timestamp, draw the pose skeleton on it, circle the at-fault
body part in red, and caption it with the coaching cue. The path to each saved
PNG is written back onto the `Correction`.

`cv2` is imported lazily inside `StillRenderer.render` (as in the estimator) so
importing this module — and the whole engine + its tests — never requires the
CV stack. The geometry helpers below are pure and testable without it.
"""

from __future__ import annotations

import dataclasses
from pathlib import Path

import numpy as np

from ..domain.analysis import Correction
from ..domain.landmarks import Landmark
from ..domain.pose import PoseFrame, PoseSequence

# Skeleton edges among the landmarks we track. Any edge whose endpoints aren't
# both present in a frame is simply skipped, so partial poses still render.
_EDGES: tuple[tuple[Landmark, Landmark], ...] = (
    (Landmark.LEFT_SHOULDER, Landmark.RIGHT_SHOULDER),
    (Landmark.LEFT_SHOULDER, Landmark.LEFT_ELBOW),
    (Landmark.LEFT_ELBOW, Landmark.LEFT_WRIST),
    (Landmark.RIGHT_SHOULDER, Landmark.RIGHT_ELBOW),
    (Landmark.RIGHT_ELBOW, Landmark.RIGHT_WRIST),
    (Landmark.LEFT_SHOULDER, Landmark.LEFT_HIP),
    (Landmark.RIGHT_SHOULDER, Landmark.RIGHT_HIP),
    (Landmark.LEFT_HIP, Landmark.RIGHT_HIP),
    (Landmark.LEFT_HIP, Landmark.LEFT_KNEE),
    (Landmark.LEFT_KNEE, Landmark.LEFT_ANKLE),
    (Landmark.RIGHT_HIP, Landmark.RIGHT_KNEE),
    (Landmark.RIGHT_KNEE, Landmark.RIGHT_ANKLE),
)

# BGR (OpenCV order).
_SKELETON_COLOR = (210, 210, 210)
_JOINT_COLOR = (0, 220, 120)
_HIGHLIGHT_COLOR = (60, 60, 235)
_CAPTION_BG = (32, 32, 32)
_CAPTION_FG = (245, 245, 245)


def nearest_frame(sequence: PoseSequence, timestamp_ms: float) -> PoseFrame | None:
    """The pose frame whose timestamp is closest to `timestamp_ms`."""
    if not sequence.frames:
        return None
    return min(sequence.frames, key=lambda f: abs(f.timestamp_ms - timestamp_ms))


def to_pixel(x: float, y: float, width: int, height: int) -> tuple[int, int]:
    """Map image-normalised (0..1) coords to integer pixel coords, clamped."""
    px = int(round(min(max(x, 0.0), 1.0) * (width - 1)))
    py = int(round(min(max(y, 0.0), 1.0) * (height - 1)))
    return px, py


def _slug(text: str) -> str:
    return "".join(c if c.isalnum() else "_" for c in text).strip("_").lower()


class StillRenderer:
    """Draws one annotated still per correction from the source video."""

    def __init__(self, *, joint_radius: int = 4, highlight_radius: int = 16) -> None:
        self._joint_radius = joint_radius
        self._highlight_radius = highlight_radius

    def render(
        self,
        video_path: str,
        sequence: PoseSequence,
        corrections: list[Correction],
        out_dir: str,
    ) -> list[Correction]:
        """Write a still for every correction with a timestamp.

        Returns a new correction list with `still_path` populated where a frame
        was produced; corrections without a timestamp pass through untouched.
        """
        try:
            import cv2
        except ImportError as exc:  # pragma: no cover - depends on optional deps
            raise ImportError(
                "StillRenderer needs 'opencv-python'. Install with: "
                'pip install -e ".[vision]"'
            ) from exc

        out = Path(out_dir)
        out.mkdir(parents=True, exist_ok=True)

        capture = cv2.VideoCapture(video_path)
        if not capture.isOpened():
            raise FileNotFoundError(f"could not open video: {video_path}")

        rendered: list[Correction] = []
        try:
            for correction in corrections:
                ts = correction.example_timestamp_ms
                if ts is None:
                    rendered.append(correction)
                    continue
                image = self._grab_frame(cv2, capture, ts)
                if image is None:
                    rendered.append(correction)
                    continue
                self._annotate(cv2, image, sequence, ts, correction)
                filename = f"correction_{correction.priority}_{_slug(correction.category.value)}.png"
                path = out / filename
                cv2.imwrite(str(path), image)
                rendered.append(dataclasses.replace(correction, still_path=str(path)))
        finally:
            capture.release()
        return rendered

    # -- internals ---------------------------------------------------------

    def _grab_frame(self, cv2, capture, timestamp_ms: float):
        """Seek to a timestamp and read the frame there (None if unavailable)."""
        capture.set(cv2.CAP_PROP_POS_MSEC, float(timestamp_ms))
        ok, image = capture.read()
        if not ok or image is None:
            return None
        return image

    def _annotate(
        self, cv2, image, sequence: PoseSequence, timestamp_ms: float, correction: Correction
    ) -> None:
        height, width = image.shape[:2]
        frame = nearest_frame(sequence, timestamp_ms)
        if frame is not None:
            self._draw_skeleton(cv2, image, frame, width, height)
            self._draw_highlights(cv2, image, frame, correction.highlight_landmarks, width, height)
        self._draw_caption(cv2, image, correction.description, width, height)

    def _draw_skeleton(self, cv2, image, frame: PoseFrame, width: int, height: int) -> None:
        for a, b in _EDGES:
            ka, kb = frame.get(a), frame.get(b)
            if ka is None or kb is None:
                continue
            pa = to_pixel(ka.x, ka.y, width, height)
            pb = to_pixel(kb.x, kb.y, width, height)
            cv2.line(image, pa, pb, _SKELETON_COLOR, 2, lineType=cv2.LINE_AA)
        for kp in frame.keypoints.values():
            p = to_pixel(kp.x, kp.y, width, height)
            cv2.circle(image, p, self._joint_radius, _JOINT_COLOR, -1, lineType=cv2.LINE_AA)

    def _draw_highlights(
        self, cv2, image, frame: PoseFrame, landmarks: tuple[Landmark, ...], width: int, height: int
    ) -> None:
        for lm in landmarks:
            kp = frame.get(lm)
            if kp is None:
                continue
            p = to_pixel(kp.x, kp.y, width, height)
            cv2.circle(image, p, self._highlight_radius, _HIGHLIGHT_COLOR, 3, lineType=cv2.LINE_AA)

    def _draw_caption(self, cv2, image, text: str, width: int, height: int) -> None:
        if not text:
            return
        font = cv2.FONT_HERSHEY_SIMPLEX
        scale = max(0.5, width / 1280.0)
        thickness = max(1, round(scale * 1.5))
        pad = int(12 * scale)
        line_h = int(30 * scale)
        lines = _wrap(cv2, text, font, scale, thickness, width - 2 * pad)

        box_h = line_h * len(lines) + 2 * pad
        y0 = height - box_h
        overlay = image.copy()
        cv2.rectangle(overlay, (0, y0), (width, height), _CAPTION_BG, -1)
        cv2.addWeighted(overlay, 0.6, image, 0.4, 0, image)

        y = y0 + pad + int(line_h * 0.7)
        for line in lines:
            cv2.putText(image, line, (pad, y), font, scale, _CAPTION_FG, thickness, cv2.LINE_AA)
            y += line_h


def _wrap(cv2, text: str, font, scale: float, thickness: int, max_width: int) -> list[str]:
    """Greedy word-wrap using cv2's measured text width."""
    words = text.split()
    lines: list[str] = []
    current = ""
    for word in words:
        candidate = f"{current} {word}".strip()
        (w, _), _ = cv2.getTextSize(candidate, font, scale, thickness)
        if w <= max_width or not current:
            current = candidate
        else:
            lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines
