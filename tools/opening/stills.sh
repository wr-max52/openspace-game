#!/bin/bash
# stills.sh <secs> <shot>...   one still per shot at <secs> in (a fraction 0..1 of the shot if < 1 and suffixed f, e.g. 0.5f)
cd "$(dirname "$0")/../.."
T=$1; shift
for s in "$@"; do
  echo "== still $s @ $T"
  bash tools/opening/still.sh $s $T | grep -E "CINE (setup|camp|wreck|cruiser|oda|t=)|ERROR|Error" | head -12
done
