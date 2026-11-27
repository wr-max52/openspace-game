#!/bin/bash
# assemble.sh: the rough cut. Shots 1-15 (720p30 PNGs), a fade to the title card,
# Ambient 2 under it all, faded in and out.
cd /Users/will/projects/dune-game/.claude/worktrees/entrance-cutscene-shots-229e26/test_results/cine
ins=(); filt=""; i=0
for s in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  [ -f s$s/f0000.png ] || { echo "shot $s missing"; continue; }
  ins+=(-framerate 30 -i s$s/f%04d.png)
  extra=""
  [ $s = 15 ] && extra=",fade=t=out:st=$(echo "$(ls s15/f*.png | wc -l) / 30 - 0.6" | bc -l):d=0.6"
  filt+="[$i:v]scale=1280:720,setsar=1,format=yuv420p$extra[v$i];"
  i=$((i+1))
done
ins+=(-loop 1 -t 3.2 -i s16/still.png)
filt+="[$i:v]scale=1280:720,setsar=1,format=yuv420p,fade=t=in:st=0.3:d=0.7,fade=t=out:st=2.4:d=0.8[v$i];"
n=$((i+1))
for k in $(seq 0 $i); do filt+="[v$k]"; done
filt+="concat=n=$n:v=1:a=0[v]"
ffmpeg -v error -y "${ins[@]}" -filter_complex "$filt" -map "[v]" -r 30 -c:v libx264 -crf 20 -pix_fmt yuv420p video_only.mp4 || exit 1
dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 video_only.mp4)
fo=$(echo "$dur - 3.0" | bc -l)
ffmpeg -v error -y -i video_only.mp4 -i "$HOME/Desktop/Music/Ambient2.mp3" -filter_complex "[1:a]atrim=0:$dur,afade=t=in:st=0:d=1.5,afade=t=out:st=$fo:d=3.0,volume=0.9[a]" -map 0:v -map "[a]" -c:v copy -c:a aac -b:a 192k -shortest rough_cut.mp4 || exit 1
echo "rough_cut.mp4 $(printf %.1f $dur) s"
