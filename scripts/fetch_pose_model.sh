#!/usr/bin/env bash
# Fetch the MediaPipe Pose Landmarker model(s) into the app's assets.
#
# The .task files are binary (~6 MB lite, ~9 MB full) and are gitignored, so
# every clone runs this once before building the Android app:
#
#     scripts/fetch_pose_model.sh          # lite only (the v0.5 default)
#     scripts/fetch_pose_model.sh full     # also fetch the full model
#
# The app copies the bundled asset to a file at runtime (PoseModelProvisioner)
# and hands that path to the pose_landmarker plugin.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/app/assets/models"
BASE="https://storage.googleapis.com/mediapipe-models/pose_landmarker"

mkdir -p "$DEST"

fetch() {
  local variant="$1"
  local url="$BASE/pose_landmarker_${variant}/float16/latest/pose_landmarker_${variant}.task"
  local out="$DEST/pose_landmarker_${variant}.task"
  echo "Fetching pose_landmarker_${variant} -> ${out#"$ROOT/"}"
  curl -fSL "$url" -o "$out"
}

fetch lite
if [[ "${1:-}" == "full" ]]; then
  fetch full
fi

echo "Done. Models in ${DEST#"$ROOT/"}"
