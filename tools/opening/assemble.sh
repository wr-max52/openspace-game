#!/bin/bash
# assemble.sh [fps]: the cut. Shots 1-16 (PNG sequences in test_results/cine2/sN),
# a fade from black at the top, a fade to the title card at the end, Ambient 2
# under it all (faded in and out). Writes test_results/cine2/opening_cut.mp4.
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
ins+=(-loop 1 -t 3.5 -i end_card.png)
filt+="[$i:v]scale=${W:-1920}:${H:-1080},setsar=1,format=yuv420p,fade=t=in:st=0.3:d=0.8,fade=t=out:st=2.6:d=0.9[v$i];"
n=$((i+1))
for k in $(seq 0 $i); do filt+="[v$k]"; done
filt+="concat=n=$n:v=1:a=0[v]"
ffmpeg -v error -y "${ins[@]}" -filter_complex "$filt" -map "[v]" -r $FPS -c:v libx264 -crf 18 -pix_fmt yuv420p video_only.mp4 || exit 1
dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 video_only.mp4)
fo=$(echo "$dur - 3.2" | bc -l)
ffmpeg -v error -y -i video_only.mp4 -i "$HOME/Desktop/Music/Ambient2.mp3" -filter_complex "[1:a]atrim=0:$dur,afade=t=in:st=0:d=2.0,afade=t=out:st=$fo:d=3.2,volume=0.9[a]" -map 0:v -map "[a]" -c:v copy -c:a aac -b:a 192k -shortest opening_cut.mp4 || exit 1
echo "opening_cut.mp4 $(printf %.1f $dur) s"
