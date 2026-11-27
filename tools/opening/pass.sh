#!/bin/bash
# pass.sh "shot:t,t shot:t ..."   stills at those times, quietly; errors only
cd "$(dirname "$0")/../.."
for st in $1; do
  s=${st%%:*}; ts=${st#*:}
  for t in ${ts//,/ }; do
    bash tools/opening/still.sh $s $t | grep -E "ERROR|Error|wreck|camp|clearances|hit" | head -6 | sed "s/^/[$s@$t] /"
  done
done
echo PASS DONE
