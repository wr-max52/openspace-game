#!/bin/bash
# clip.sh <shot>...   full clips at 720p30 (RES=1080 for 1080p) into test_results/cine2/sN/f*.png
cd /Users/will/projects/dune-game/.claude/worktrees/entrance-cutscene-shots-229e26
SP=/private/tmp/claude-501/-Users-will-projects-dune-game--claude-worktrees-entrance-cutscene-shots-229e26/6ba5fbdb-43c8-45d5-a150-44b914cc73c3/scratchpad
for s in "$@"; do
  rm -f test_results/cine2/s$s/f*.png
  echo "== clip $s $(date +%T)"
  HOME=$SP/home caffeinate -d -i perl -e 'alarm 900; exec @ARGV' godot --path . --rendering-driver vulkan --always-on-top --fixed-fps 60 --resolution 1152x648 --quit-after 60000 res://tools/opening/shoot_opening.tscn -- shot=$s fps=30 res=${RES:-720} 2>&1 | grep -E "CINE (setup|seeker)|SCRIPT ERROR|Parse Error" | head -20
  echo "   $(ls test_results/cine2/s$s/f*.png 2>/dev/null | wc -l) frames"
done
