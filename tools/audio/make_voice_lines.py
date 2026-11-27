"""Record the scripted (non-AI) lines so they have voices without an ElevenLabs key.

Every fixed line a character can say with the AI off (card greetings and canned
replies, story beats, T-89, the general, the dark master, the guards' and locals'
barks, the speeder shops, the race crews) is rendered once per voice that can say it and saved
as assets/audio/voice/<key>.mp3. NpcVoice plays a bundled clip before it tries
the player's cache or the API, so these need no key at all.

key = first 16 hex of sha256("<line>|<voice_id>"), the same as
NpcVoice.bundled_path(). Lines with a runtime fill (%s, %d, {name}) can not be
recorded ahead and still go through the API when the player has a key.

An inline audio tag ("... [scared] sometimes ...") is spoken but never shown:
the clip is keyed by the line without it (as the game shows it) and rendered
with the tag by the profiles' model, which reads tags (the quick one does not).

Speakers in a role pool (guards, locals, Odas on other planets, racers) get a
stable pick by id in game, so their lines are rendered in every voice of the pool.

A speaker whose soldier profile sets a `voice_mood` (the racers: "menacing") is
rendered with that mood's tag from voice_profiles.json, as the game would ask
for it live, by the tag-reading model; the clip is still keyed by the bare line.

Run: python3 tools/audio/make_voice_lines.py [--list] [--cache-only] [--model eleven_flash_v2_5] [--voices a,b]
Key: $ELEVENLABS_API_KEY, else the game's own user://llm/keys.cfg.
Existing clips are kept; delete one to re-record it. A line the game already
rendered while it was played is copied from user://npc_voice_cache first (free).
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
import re
import shutil
import sys
import urllib.request

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio", "voice")
CORE = os.path.join(ROOT, "content", "core")
USER_DIR = os.path.expanduser("~/Library/Application Support/Godot/app_userdata/Desert Spaceport Slice")
KEYS_CFG = os.path.join(USER_DIR, "llm", "keys.cfg")
CACHE_DIR = os.path.join(USER_DIR, "npc_voice_cache")
API_URL = "https://api.elevenlabs.io/v1/text-to-speech/%s?output_format=mp3_44100_64"
FILL = re.compile(r"%[sd]|\{[a-z_]+\}")
TAG = re.compile(r"\[[^\]]*\]\s*")


def shown(line):
    """The line as the game shows (and keys) it: audio tags taken out."""
    return TAG.sub("", line).strip()


def read(rel):
    with open(os.path.join(CORE, rel)) as f:
        return json.load(f)


PROFILES = read("npcs/voice_profiles.json")
LIBRARY = read("npcs/voice_library.json")["voices"]
POOLS = PROFILES["role_profiles"]
DEFAULT = PROFILES["default"]


def named(npc_id):
    return [PROFILES["npc_profiles"].get(npc_id, DEFAULT)]


def strings(node):
    """Every string under a JSON node (lists and dicts walked)."""
    if isinstance(node, str):
        yield node
    elif isinstance(node, list):
        for v in node:
            yield from strings(v)
    elif isinstance(node, dict):
        for v in node.values():
            yield from strings(v)


def card_lines(card):
    """What a conversation card says aloud: greetings, canned replies, the recap
    frame, deflections, the hints' lines and Skrugs's ship-buy lines."""
    yield from strings(card.get("greetings", {}))
    yield from strings(card.get("canned", {}))
    yield from strings(card.get("stall_barks", []))
    yield from strings(card.get("meta_deflections", []))
    recap = card.get("recap", {})
    yield from strings([recap.get("open", []), recap.get("close", [])])
    for h in card.get("hints", []):
        yield from strings(h.get("line", ""))
    yield from strings(card.get("ship_buy", {}).get("lines", {}))


# What a race crew's leader and racers say aloud (src/systems/racing/race_crew.gd
# _say): every key below, and the leader's word when you beat them, which is
# leader_lost and next_crew joined by a space. A crew's own line wins over the
# shared one in racing/rules.json; {crew} is filled with the crew's label.
RACE_SAID = ["challenge", "not_yet", "no_speeder", "slips_not_yours", "no_room", "slips_accept",
             "too_poor", "accept", "comms", "rematch_accept", "taunts", "jeers", "leader_won", "no_show"]


def race_lines():
    """{crew id: [lines]} for every race crew."""
    shared = read("racing/rules.json").get("lines", {})
    out = {}
    for name in sorted(os.listdir(os.path.join(CORE, "racing", "crews"))):
        if not name.endswith(".json"):
            continue
        crew = read("racing/crews/" + name)
        own = crew.get("lines", {})

        def pick(k):
            v = own.get(k, shared.get(k, ""))
            return v if isinstance(v, list) else [v]

        lines = [l for k in RACE_SAID for l in pick(k)]
        lines += ["%s %s" % (a, b) for a in pick("leader_lost") for b in pick("next_crew")]
        label = crew.get("label", crew.get("id", ""))
        out[crew.get("id", name[:-5])] = [l.replace("{crew}", label) for l in lines if l]
    return out


def soldier_voice(soldier_id):
    """(voice pool, delivery tag) for a soldier profile: its voice_role's pool
    (else its role's) and its voice_mood's tag ("" when none)."""
    s = read("soldiers/%s.json" % soldier_id)
    base = read("soldiers/%s.json" % s["base"]) if s.get("base") else {}
    role = s.get("voice_role", base.get("voice_role", s.get("role", base.get("role", ""))))
    mood = s.get("voice_mood", base.get("voice_mood", ""))
    return POOLS.get(role, [DEFAULT]), PROFILES["mood_tags"].get(mood, "")


def collect():
    """[(line, profile, tag)] for every fixed spoken line, deduplicated; tag is
    a delivery tag spoken before it ("" for none)."""
    said = []          # (line, [profiles]) or (line, [profiles], tag)
    oda = named("cantina_owner") + POOLS["planet_owner"]
    said.append((card_lines(read("npcs/cantina_owner_card.json")), oda))
    said.append((strings(read("dialogue/cantina_owner_fallback.json")), oda))
    said.append((card_lines(read("npcs/skrugs_card.json")), named("skrugs")))
    said.append((card_lines(read("npcs/t89_card.json")), named("t89")))
    fence = read("npcs/fence_card.json")
    said.append((card_lines(fence), [fence.get("voice_profile", DEFAULT)]))
    # The general and the dark master talk as cards (default voice) and as
    # soldiers over their heads (a guard voice when the profile is the Remnant's).
    officer = [DEFAULT] + POOLS["guard"]
    said.append((card_lines(read("npcs/general_card.json")), officer))
    said.append((card_lines(read("npcs/dark_master_card.json")), officer))
    said.append((strings(read("npcs/general.json").get("lines", {})), officer))
    said.append((strings(read("npcs/dark_master.json").get("lines", {})), officer))
    t89 = read("npcs/t89.json")
    said.append((strings([t89.get("greeting", ""), t89.get("returning", []), t89.get("tutorial", []),
                          t89.get("remnant_story", []), t89.get("lines", {})]), named("t89")))
    said.append((strings([l["line"] for l in read("dialogue/fixer_lines.json")]), named("fixer")))
    said.append((strings(read("dialogue/gate_guard_lines.json")["lines"]), POOLS["guard"]))
    locals_pool = sorted(set(POOLS["guard"] + POOLS["local"] + POOLS["merchant"]))
    said.append((strings(read("dialogue/locals_lines.json")["lines"]), locals_pool))
    said.append((strings(read("planets/port_desert.json")["natives"].get("locals_say", [])), locals_pool))
    for ch in read("story/main.json")["chapters"]:
        teller = ch.get("teller", "")
        if teller:
            beats = [ch.get(k, "") for k in ("intro", "intro_dark", "remind", "jetpack_hint")]
            said.append((strings(beats), named(teller)))
    shops = read("vehicles/speeder_upgrades.json")
    for shop in [shops["mechanic"]] + list(shops["shops"].values()):
        said.append((strings(shop.get("lines", {})), named(shop.get("voice", "mechanic"))))
    for crew_id, lines in race_lines().items():
        profile = read("racing/crews/%s.json" % crew_id).get("profile", "local_racer")
        pool, tag = soldier_voice(profile)
        said.append((lines, pool, tag))

    out, seen = [], set()
    for entry in said:
        lines, profiles = list(entry[0]), entry[1]
        tag = entry[2] if len(entry) > 2 else ""
        for line in lines:
            line = line.strip()
            if line == "" or FILL.search(line):
                continue
            for p in profiles:
                if p in LIBRARY and (line, p) not in seen:
                    seen.add((line, p))
                    out.append((line, p, tag))
    return out


def clip_name(line, voice_id):
    return hashlib.sha256(("%s|%s" % (line, voice_id)).encode("utf-8")).hexdigest()[:16] + ".mp3"


def api_key():
    key = os.environ.get("ELEVENLABS_API_KEY", "")
    if key == "" and os.path.exists(KEYS_CFG):
        for row in open(KEYS_CFG):
            m = re.match(r'\s*elevenlabs\s*=\s*"(.*)"', row)
            if m:
                key = m.group(1)
    return key


def cached(line, voice):
    """A clip the game already rendered for this line and voice while it was
    played (user://npc_voice_cache, named by NpcVoice.cache_key): the line with
    no tag, a mood tag or a shout, at normal speed, any model it has used."""
    tags = [""] + sorted(set(PROFILES["mood_tags"].values())) + ["[shouts]"]
    for model in (PROFILES.get("model_id", "eleven_v4"), "eleven_v3"):
        for tag in tags:
            spoken = " ".join(t for t in (voice.get("style_tag", ""), tag, line) if t)
            key = "%s|%s|%s|%.2f|%.2f" % (spoken, voice["voice_id"], model, 1.0,
                                          float(voice.get("stability", 0.55)))
            path = os.path.join(CACHE_DIR, hashlib.sha256(key.encode("utf-8")).hexdigest() + ".mp3")
            if os.path.exists(path):
                return path
    return ""


def record(key, model, line, profile, tag=""):
    voice = LIBRARY[profile]
    path = os.path.join(OUT, clip_name(shown(line), voice["voice_id"]))
    if os.path.exists(path):
        return "kept"
    found = cached(shown(line), voice) if shown(line) == line else ""
    if found:
        shutil.copyfile(found, path)
        return "from_cache"
    if key == "":
        return "skipped"
    spoken = ("%s %s" % (tag, line)) if tag else line
    body = json.dumps({
        "text": spoken,
        "model_id": model if shown(spoken) == spoken else PROFILES.get("model_id", "eleven_v4"),
        "voice_settings": {"speed": 1.0, "stability": float(voice.get("stability", 0.55)),
                           "similarity_boost": 0.75},
    }).encode("utf-8")
    req = urllib.request.Request(API_URL % voice["voice_id"], data=body, method="POST",
                                 headers={"xi-api-key": key, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        audio = r.read()
    with open(path, "wb") as f:
        f.write(audio)
    return "new"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true", help="print the lines, record nothing")
    ap.add_argument("--model", default="eleven_flash_v2_5", help="quick by default")
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--cache-only", action="store_true", help="copy from the game's cache, no API calls")
    ap.add_argument("--voices", default="", help="only these voice profiles, comma separated (racer pool: man_dark_tough,man_harsh,man_menacing,woman_cold)")
    args = ap.parse_args()
    lines = collect()
    if args.voices:
        only = set(args.voices.split(","))
        lines = [x for x in lines if x[1] in only]
    if args.list:
        for line, p, tag in lines:
            print("%-16s %s%s" % (p, (tag + " ") if tag else "", line))
        print("%d clips, %d characters" % (len(lines), sum(len(l) for l, _, _ in lines)), file=sys.stderr)
        return
    key = "" if args.cache_only else api_key()
    if key == "" and not args.cache_only:
        print("No ElevenLabs key (ELEVENLABS_API_KEY or the game's F10 panel): cache only.", file=sys.stderr)
    os.makedirs(OUT, exist_ok=True)
    counts = {"new": 0, "from_cache": 0, "kept": 0, "skipped": 0, "failed": 0}
    with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
        jobs = {pool.submit(record, key, args.model, l, p, t): (l, p) for l, p, t in lines}
        for job in concurrent.futures.as_completed(jobs):
            try:
                counts[job.result()] += 1
            except Exception as e:      # one bad line never stops the batch
                counts["failed"] += 1
                print("failed: %s %r: %s" % (jobs[job][1], jobs[job][0], e), file=sys.stderr)
    print(counts)


if __name__ == "__main__":
    main()
