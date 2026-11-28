"""The opening cutscene's sound: Ambient 2 under it all, Oda's voiceover and the
dialogue (tools/opening/lines.json, voiced by voice.py), a few quiet effects from
the game's own sounds, desert wind outside and the cruiser's hum in orbit. The
music dips under every line and effect (a sidechain), and gives way to the club
mix in the cantina.

Run after assemble.sh has written test_results/cine2/video_only.mp4:
    python3 tools/opening/mix.py
Shot start times come from the filmed frames (test_results/cine2/sN/f*.png, 30 fps).
Writes test_results/cine2/opening_cut.mp4.
"""
import glob
import json
import os
import re
import subprocess

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
CINE = os.path.join(ROOT, "test_results", "cine2")
FPS = 30
SFXG = 0.6          # every effect, together: under the music, never over it
DISSOLVE = {5: 0.6}  # shot: seconds it dissolves in over the shot before (assemble.sh does the same)
A = os.path.join(ROOT, "assets", "audio")
K = os.path.join(ROOT, "assets", "third_party", "kenney_starter_kit_fps", "sounds")
MUSIC = os.path.expanduser("~/Desktop/Music/Ambient2.mp3")
CLUB = os.path.join(A, "music", "club", "dust_lounge", "06_deep_house_whispers.mp3")
BARGE = os.path.join(A, "music", "club", "salvage_rave", "03_uk_garage.mp3")
ENGINE = os.path.join(A, "sfx", "ship_engine.wav")


def sfx(name):
    return os.path.join(A, "sfx", name + ".wav")


def kenney(name):
    return os.path.join(K, name + ".ogg")


def shot_ts():
    src = open(os.path.join(ROOT, "tools", "opening", "shoot_opening.gd")).read()
    body = re.search(r"const TS := \{([^}]*)\}", src).group(1)
    return {int(k): float(v) for k, v in re.findall(r"(\d+):\s*([0-9.]+)", body)}


def shot_tail():
    src = open(os.path.join(ROOT, "tools", "opening", "shoot_opening.gd")).read()
    body = re.search(r"const TAIL := \{([^}]*)\}", src).group(1)
    return {int(k): float(v) for k, v in re.findall(r"(\d+):\s*([0-9.]+)", body)}


def starts():
    """{shot: start second in the cut}, and the cut's length with the title card."""
    out, at = {}, 0.0
    for s in range(1, 17):
        n = len(glob.glob(os.path.join(CINE, "s%d" % s, "f*.png")))
        at -= DISSOLVE.get(s, 0.0)
        out[s] = at
        at += n / FPS
    return out, at


def seeker_hit(ts7):
    """When the seeker hits in shot 7 (its log, shot time u, made real)."""
    try:
        m = re.search(r"t=([0-9.]+) seeker hit", open(os.path.join(CINE, "log_s7.txt")).read())
        return float(m.group(1)) * ts7
    except (OSError, AttributeError):
        return 4.6


def cues(hit, tails):
    """[shot, at, file, gain, opts]: opts dur (looped if longer), fi/fo fades,
    rate (pitch), lp (low-pass Hz). A negative `at` counts back from the shot's end."""
    pass_by = {"dur": 3.6, "fi": 1.0, "fo": 1.8}
    far = {"dur": 2.4, "fi": 0.8, "fo": 1.0, "lp": 1400}
    return [
        # 1 space: the ship streaks past us, coughing
        [1, 4.9, ENGINE, 0.6, dict(pass_by, dur=5.6, fi=0.6, fo=3.4)],
        [1, 6.1, sfx("ship_hit"), 0.25, {}],
        [1, 7.4, sfx("ship_hit"), 0.15, {"lp": 2000}],
        [1, 11.6, sfx("ship_hit"), 0.12, {"lp": 1800}],
        # 2 the wreck: it goes over
        [2, 0.6, ENGINE, 0.4, pass_by],
        [2, 2.4, sfx("ship_hit"), 0.15, {"lp": 2500}],
        # 3 the nomad's steps in the sand, the ship somewhere above
        [3, 0.0, kenney("walking"), 0.3, {"dur": 2.4, "fo": 0.4, "lp": 1800}],
        [3, 2.2, ENGINE, 0.22, dict(far, dur=2.4)],
        # 4 his view: the ship, far off and sputtering
        [4, 0.0, ENGINE, 0.28, {"dur": 3.64, "fi": 0.4, "fo": 0.8, "lp": 2200}],
        [4, 1.7, sfx("ship_hit"), 0.15, {"lp": 2000}],
        # 5 the barge: its party music carries, the ship goes over
        [4, -1.4, BARGE, 0.2, {"dur": 7.6, "fi": 1.2, "fo": 0.5, "lp": 700, "skip": 38.6}],
        [5, 1.2, ENGINE, 0.3, pass_by],
        # 6 the outpost: one shot; the ship rumbles over as we find it
        [6, 6.14, kenney("blaster"), 0.6, {}],
        [6, 6.2, ENGINE, 0.22, far],
        # 7 the race: three speeders tear past, the seeker, the leader goes up
        [7, 0.36, sfx("jet_loop"), 0.55, {"dur": 1.5, "fi": 0.3, "fo": 0.9}],
        [7, 0.66, sfx("jet_loop"), 0.5, {"dur": 1.5, "fi": 0.3, "fo": 0.9, "rate": 1.08}],
        [7, 1.02, sfx("jet_loop"), 0.5, {"dur": 1.6, "fi": 0.3, "fo": 1.0, "rate": 0.94}],
        [7, 1.8, sfx("jet_loop"), 0.18, {"dur": 2.6, "fi": 0.2, "fo": 1.6, "lp": 1600}],
        [7, 4.2, sfx("ship_missile"), 0.35, {"lp": 3000}],
        [7, hit, sfx("vehicle_boom_2"), 0.35, {"lp": 3000}],
        [7, 7.0, ENGINE, 0.22, dict(far, dur=1.1, fo=0.3)],
        # 9, 10 the bridge: the holo chirps, the guard's steps
        [9, 0.4, sfx("droid_beep_1"), 0.12, {"rate": 1.3}],
        [9, 2.2, sfx("droid_beep_2"), 0.1, {"rate": 1.3}],
        [10, 0.0, kenney("walking"), 0.22, {"dur": 1.8, "fo": 0.4}],
        # 11, 12 the cantina: the drink set down, the coins
        [11, 0.45, sfx("slide_scuff"), 0.5, {}],
        [12, 3.15, sfx("coin_spend"), 0.35, {}],
        # 13 out of the club, the ship over the roofs
        [13, 2.8, ENGINE, 0.3, dict(far, dur=1.7, fo=0.4)],
        # 14, 15 the general's walk
        [14, 0.0, kenney("walking"), 0.32, {"dur": 2.7, "fi": 0.2, "fo": 0.2}],
        [15, 0.0, kenney("walking"), 0.24, {"dur": 4.4, "fo": 1.6}],
        [15, 2.4, ENGINE, 0.3, dict(far, dur=1.3, fo=0.3)],
        # 16 the pit: T-89's torch, his chirps, the ship roaring in
        [16, 0.0, sfx("droid_fix"), 0.35, {"dur": 1.75, "fo": 0.3}],
        [16, 0.0, kenney("walking"), 0.18, {"dur": 3.0, "fi": 0.5, "fo": 0.6}],
        [16, 2.0, sfx("droid_beep_2"), 0.3, {}],
        [16, 3.3, sfx("droid_beep_1"), 0.3, {"rate": 0.9}],
        [16, 3.0, ENGINE, 0.55, {"dur": 10.6, "fi": 3.0, "fo": 2.0}],
    ] + [
        # Every hold on the ship: its engine, far off and sputtering, under the push.
        [s, -tl, ENGINE, 0.2, {"dur": tl, "fi": 0.8, "fo": 1.0, "lp": 1600}]
        for s, tl in tails.items() if s != 16
    ]


def env(segs, total):
    """A volume expression: gain inside each [a, b, gain, ramp], 0 outside."""
    terms = ["%.3f*clip((t-%.3f)/%.3f,0,1)*clip((%.3f-t)/%.3f,0,1)" % (g, a, r, b, r) for a, b, g, r in segs]
    return "+".join(terms) if terms else "0"


def chain(src, length, opts):
    """An input's filter: format, pitch, trim, fades, low-pass."""
    f = ["aresample=48000", "aformat=sample_fmts=fltp:channel_layouts=stereo"]
    if opts.get("skip"):
        f.append("atrim=start=%.3f" % opts["skip"])
        f.append("asetpts=PTS-STARTPTS")
    if opts.get("rate"):
        f += ["asetrate=%d" % int(48000 * opts["rate"]), "aresample=48000"]
    dur = opts.get("dur", length)
    f.append("atrim=0:%.3f" % dur)
    if opts.get("fi"):
        f.append("afade=t=in:st=0:d=%.3f" % opts["fi"])
    if opts.get("fo"):
        f.append("afade=t=out:st=%.3f:d=%.3f" % (max(0.0, dur - opts["fo"]), opts["fo"]))
    if opts.get("lp"):
        f.append("lowpass=f=%d" % opts["lp"])
    return f


def length(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                         capture_output=True, text=True).stdout.strip()
    return float(out or 0)


def main():
    ts = shot_ts()
    st, total_shots = starts()
    video = os.path.join(CINE, "video_only.mp4")
    total = length(video)
    lines = json.load(open(os.path.join(ROOT, "tools", "opening", "lines.json")))["lines"]
    ins, filt, vo_tags, fx_tags = [], [], [], []

    ins_paths = []

    def inp(path, loop=False):
        ins_paths.append(path)
        ins.extend((["-stream_loop", "-1"] if loop else []) + ["-i", path])
        return len(ins_paths)       # input 0 is the video

    for ln in lines:
        path = os.path.join(CINE, "vo", ln["id"] + ".mp3")
        k = inp(path)
        at = st[ln["shot"]] + float(ln["at"])
        f = chain(path, length(path), {})
        f.append("volume=2.6")         # the clips come in ~8 dB under the music
        f.append("adelay=%d:all=1" % int(at * 1000))
        filt.append("[%d:a]%s[vo%d]" % (k, ",".join(f), k))
        vo_tags.append("[vo%d]" % k)

    for shot, at, path, gain, opts in cues(seeker_hit(ts.get(7, 1.0)), shot_tail()):
        if at < 0:
            at += (st[shot + 1] if shot < 16 else total_shots) - st[shot]
        L = length(path)
        k = inp(path, loop=opts.get("dur", L) + opts.get("skip", 0.0) > L)
        f = chain(path, L, opts)
        f.append("volume=%.3f" % (gain * SFXG))
        f.append("adelay=%d:all=1" % int((st[shot] + at) * 1000))
        filt.append("[%d:a]%s[fx%d]" % (k, ",".join(f), k))
        fx_tags.append("[fx%d]" % k)

    def span(a, b):
        return st[a], (st[b + 1] if b < 16 else total_shots)

    # The desert wind outside (brown noise, low and slow), the cruiser's hum in orbit.
    wind = [(*span(2, 7), 0.5, 0.6), (*span(13, 16), 0.3, 0.5)]
    filt.append("anoisesrc=color=brown:amplitude=0.5:sample_rate=48000:duration=%.2f,highpass=f=60,lowpass=f=420,"
                "tremolo=f=0.11:d=0.55,aformat=sample_fmts=fltp:channel_layouts=stereo,"
                "volume=eval=frame:volume='%s'[wind]" % (total, env(wind, total)))
    k = inp(ENGINE, loop=True)
    hum = [(*span(1, 1), 0.16, 1.5), (*span(8, 10), 0.22, 0.4)]
    filt.append("[%d:a]aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo,asetrate=19200,aresample=48000,"
                "lowpass=f=220,atrim=0:%.2f,volume=eval=frame:volume='%s'[hum]" % (k, total, env(hum, total)))

    # Music: Ambient 2 the whole way (out at the end), giving way to the club mix in the cantina.
    k = inp(MUSIC)
    c0, c1 = span(11, 13)
    amb = [(0.0, c0 + 0.3, 0.85, 0.01), (c0, c1, 0.22, 0.5), (c1 - 0.3, total + 5.0, 0.85, 0.8)]
    filt.append("[%d:a]aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo,atrim=0:%.2f,"
                "afade=t=in:st=0:d=2.0,afade=t=out:st=%.2f:d=3.0,volume=eval=frame:volume='%s'[amb]"
                % (k, total, total - 3.0, env(amb, total)))
    k = inp(CLUB)
    filt.append("[%d:a]aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo,atrim=start=30:end=%.2f,"
                "asetpts=PTS-STARTPTS,volume=eval=frame:volume='%s',adelay=%d:all=1[club]"
                % (k, 30 + (c1 - c0) + 0.5, env([(0.0, c1 - c0 + 0.4, 0.42, 0.5)], 0), int(c0 * 1000)))
    filt.append("[amb][club]amix=inputs=2:normalize=0:duration=first[music]")

    # The buses, and the dip: every line (and, less, every effect) pushes the music down.
    filt.append("%samix=inputs=%d:normalize=0:duration=longest,apad=whole_dur=%.2f,atrim=0:%.2f[vo]"
                % ("".join(vo_tags), len(vo_tags), total, total))
    filt.append("%samix=inputs=%d:normalize=0:duration=longest,apad=whole_dur=%.2f,atrim=0:%.2f[fx]"
                % ("".join(fx_tags), len(fx_tags), total, total))
    filt.append("[vo]asplit=2[vo_a][vo_b]")
    filt.append("[fx]asplit=2[fx_a][fx_b]")
    filt.append("[fx_b]volume=0.5[fx_sc]")
    filt.append("[vo_b][fx_sc]amix=inputs=2:normalize=0[sc]")
    filt.append("[music][sc]sidechaincompress=threshold=0.02:ratio=6:attack=40:release=550:makeup=1[ducked]")
    filt.append("[ducked][vo_a][fx_a][wind][hum]amix=inputs=5:normalize=0:duration=first,"
                "alimiter=limit=0.95:level=false[aout]")
    graph = os.path.join(CINE, "mix_graph.txt")
    open(graph, "w").write(";\n".join(filt))
    out = os.path.join(CINE, "opening_cut.mp4")
    cmd = ["ffmpeg", "-v", "error", "-y", "-i", video] + ins + ["-/filter_complex", graph,
           "-map", "0:v", "-map", "[aout]", "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-t", "%.3f" % total, out]
    subprocess.run(cmd, check=True)
    print("opening_cut.mp4 %.1f s; shots start %s" % (total, {k: round(v, 2) for k, v in st.items()}))


if __name__ == "__main__":
    main()
