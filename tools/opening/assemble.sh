#!/bin/bash
# assemble.sh [fps]: the cut. Shots 1-16 (PNG sequences in test_results/cine2/sN),
# a fade from black at the top, a fade to the title card at the end; then mix.py
# lays the sound under it (Ambient 2, Oda's voiceover, the dialogue, the effects).
# Writes test_results/cine2/opening_cut.mp4.
FPS=${1:-30}
cd "$(dirname "$0")/../../test_results/cine2"
ins=(); filt=""; i=0
for s in $(seq 1 16); do
  [ -f s$s/f0000.png ] || { echo "shot $s missing"; continue; }
  ins+=(-framerate $FPS -i s$s/f%04d.png)
  extra=""
  [ $s = 1 ] && extra=",fade=t=in:st=0:d=1.2"
  [ $s = 16 ] && extra=",fade=t=out:st=$(echo "$(ls s16/f*.png | wc -l) / $FPS - 0.7" | bc -l):d=0.7"
  filt+="[$i:v]scale=${W:-1920}:${H:-1080},setsar=1,format=yuv420p$extra[v$i];"
  i=$((i+1))
done
ins+=(-loop 1 -t 3.0 -i end_card.png)
filt+="[$i:v]scale=${W:-1920}:${H:-1080},setsar=1,format=yuv420p,fade=t=in:st=0.2:d=0.7,fade=t=out:st=2.2:d=0.8[v$i];"
n=$((i+1))
for k in $(seq 0 $i); do filt+="[v$k]"; done
filt+="concat=n=$n:v=1:a=0[v]"
ffmpeg -v error -y "${ins[@]}" -filter_complex "$filt" -map "[v]" -r $FPS -c:v libx264 -crf 18 -pix_fmt yuv420p video_only.mp4 || exit 1
python3 ../../tools/opening/mix.py || exit 1
