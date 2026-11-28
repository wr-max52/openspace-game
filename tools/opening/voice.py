"""Voice the opening cutscene's lines (tools/opening/lines.json) with the game's
ElevenLabs voices, into test_results/cine2/vo/<id>.mp3, and print each clip's length.

Run: python3 tools/opening/voice.py [--redo id,id]
Key: $ELEVENLABS_API_KEY, else the game's own user://llm/keys.cfg (as
tools/audio/make_voice_lines.py). Existing clips are kept unless named in --redo.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import urllib.request

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "audio"))
import make_voice_lines as mvl  # noqa: E402  (the key, the voice library)

ROOT = mvl.ROOT
OUT = os.path.join(ROOT, "test_results", "cine2", "vo")
API = "https://api.elevenlabs.io/v1/text-to-speech/%s?output_format=mp3_44100_128"


def length(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                         capture_output=True, text=True).stdout.strip()
    return float(out or 0)


def spans(path, gap=0.3):
    """Speech spans [[start, end], ...] in a clip: silencedetect's gaps longer than
    `gap` split it (the captions follow these)."""
    err = subprocess.run(["ffmpeg", "-i", path, "-af", "silencedetect=n=-40dB:d=%.2f" % gap, "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    marks = re.findall(r"silence_(start|end): ([0-9.]+)", err)
    out, at, end = [], 0.0, length(path)
    for kind, val in marks:
        if kind == "start":
            if float(val) > at + 0.05:
                out.append([round(at, 3), round(float(val), 3)])
        else:
            at = float(val)
    if at < end - 0.05 and (not marks or marks[-1][0] == "end"):
        out.append([round(at, 3), round(end, 3)])
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--redo", default="")
    args = ap.parse_args()
    redo = set(filter(None, args.redo.split(",")))
    lines = json.load(open(os.path.join(os.path.dirname(__file__), "lines.json")))["lines"]
    key = mvl.api_key()
    os.makedirs(OUT, exist_ok=True)
    for ln in lines:
        path = os.path.join(OUT, ln["id"] + ".mp3")
        if os.path.exists(path) and ln["id"] not in redo:
            print("%-3s %5.2f s kept  %s" % (ln["id"], length(path), ln["text"]))
            continue
        if key == "":
            sys.exit("No ElevenLabs key.")
        voice = mvl.LIBRARY[ln["voice"]]
        spoken = " ".join(t for t in (voice.get("style_tag", ""), ln.get("tag", ""), ln["text"]) if t)
        body = json.dumps({
            "text": spoken,
            "model_id": mvl.PROFILES.get("model_id", "eleven_v4"),
            "voice_settings": {"speed": 1.0, "stability": float(voice.get("stability", 0.55)),
                               "similarity_boost": 0.75},
        }).encode("utf-8")
        req = urllib.request.Request(API % voice["voice_id"], data=body, method="POST",
                                     headers={"xi-api-key": key, "Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=90) as r:
            open(path, "wb").write(r.read())
        print("%-3s %5.2f s new   %s" % (ln["id"], length(path), ln["text"]))
    for ln in lines:
        # A take that opens with a stray word: keep it whole as .raw, use the rest.
        if float(ln.get("skip", 0.0)) > 0.0:
            path = os.path.join(OUT, ln["id"] + ".mp3")
            raw = os.path.join(OUT, ln["id"] + ".raw.mp3")
            if not os.path.exists(raw) or ln["id"] in redo:
                os.replace(path, raw)
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", "%.3f" % float(ln["skip"]), "-i", raw,
                            "-af", "afade=t=in:d=0.04", path], check=True)
            print("%-3s %5.2f s after skipping %.2f s" % (ln["id"], length(path), float(ln["skip"])))
    found = {ln["id"]: spans(os.path.join(OUT, ln["id"] + ".mp3")) for ln in lines}
    json.dump(found, open(os.path.join(OUT, "spans.json"), "w"), indent=1)
    for k, sp in found.items():
        print(k, sp)


if __name__ == "__main__":
    main()
