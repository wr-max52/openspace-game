#!/bin/bash
# sheet.sh out.png img...   a 3-wide contact sheet (640x360 tiles) with ffmpeg
out=$1; shift
n=$#; ins=(); f=""; lay=""
for i in $(seq 0 $((n-1))); do
  ins+=(-i "${@:$((i+1)):1}")
  f+="[$i:v]scale=640:360,setsar=1[t$i];"
  x=$(( (i % 3) * 640 )); y=$(( (i / 3) * 360 ))
  lay+="${x}_${y}|"
done
for i in $(seq 0 $((n-1))); do f+="[t$i]"; done
f+="xstack=inputs=$n:layout=${lay%|}:fill=black[o]"
ffmpeg -v error -y "${ins[@]}" -filter_complex "$f" -map "[o]" -frames:v 1 "$out"
