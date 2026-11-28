#!/usr/bin/env bash
# Issue #175: stills or a clip of a sandstorm in the town (tools/storm/shoot_storm.gd).
#
#   ./tools/storm/shoot_storm.sh mode=stills shots=gate_approach levels=0,0.5,1
#   ./tools/storm/shoot_storm.sh mode=clip shots=gate_approach    # -> test_results/storm/sandstorm.mp4
#
# Runs at a fixed 30 fps, so a slow renderer still makes a smooth clip.
# macOS: the real GPU (a window opens). Linux without a display: xvfb + Mesa's
# software Vulkan (lavapipe), slow but exact.
set -euo pipefail
cd "$(dirname "$0")/../.."

GODOT_BIN="${GODOT_BIN:-godot}"
SIZE="${SIZE:-1280x720}"
OUT="test_results/storm"
rm -rf "$OUT/clip"
ARGS=(--path . --resolution "$SIZE" --fixed-fps 30 -s res://tools/storm/shoot_storm.gd -- "$@")

if [[ "$(uname)" == "Linux" && -z "${DISPLAY:-}" ]]; then
  # Mesa's lavapipe, when the machine has it (a cloud container): software Vulkan.
  if [[ -f /opt/lavapipe/lvp_icd.json ]]; then export VK_ICD_FILENAMES=/opt/lavapipe/lvp_icd.json; fi
  xvfb-run -a -s "-screen 0 ${SIZE}x24" "$GODOT_BIN" --rendering-driver vulkan "${ARGS[@]}" || true
else
  "$GODOT_BIN" "${ARGS[@]}" || true
fi
# (|| true: Godot can abort while tearing the town down on Linux, after the last frame is saved.)

if ls "$OUT"/clip/f*.png >/dev/null 2>&1; then
  ffmpeg -y -loglevel error -framerate 30 -i "$OUT/clip/f%05d.png" \
    -c:v libx264 -pix_fmt yuv420p -crf 20 -movflags +faststart "$OUT/sandstorm.mp4"
  echo "wrote $OUT/sandstorm.mp4"
fi
ls -1 "$OUT"/*.png "$OUT"/*.mp4 2>/dev/null || true
