#!/bin/bash
# run.sh <shot> [still seconds]   (HOME in the scratchpad: the real saves are never touched)
cd /Users/will/projects/dune-game/.claude/worktrees/entrance-cutscene-shots-229e26
SP=/private/tmp/claude-501/-Users-will-projects-dune-game--claude-worktrees-entrance-cutscene-shots-229e26/6ba5fbdb-43c8-45d5-a150-44b914cc73c3/scratchpad
ARGS="shot=$1"; [ -n "$2" ] && ARGS="$ARGS still=$2"
HOME=$SP/home caffeinate -d -i perl -e 'alarm 400; exec @ARGV' godot --path . --rendering-driver vulkan --always-on-top --fixed-fps 60 --resolution 1152x648 --quit-after 30000 res://tools/opening/shoot_opening.tscn -- $ARGS 2>&1 | grep -E "CINE|SCRIPT ERROR|Parse Error|ERROR: " | grep -v -E "Condition|shader instance variables" | head -60
