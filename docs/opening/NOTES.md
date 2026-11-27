# Opening cutscene

## v3: Oda tells it, with sound (about 90 s)

> "The voiceover needs to be Oda. Don't "call themselves" the remnant say rather "they are hardly even a remnant of what they once were, but still have a hold". Need dialogue for the shots and sound fx. Each shot needs to pan a bit slower and be more patient. It can be 90 seconds max. The zoom in on the ship after each shot of just waiting still while the ship is in the background" (the user, on the v2 cut)

- **Oda narrates.** Her own game voice (`woman_relaxed`, ElevenLabs, the model the
  game uses live), wry and unhurried. The lines live in `tools/opening/lines.json`
  (shot, start second, voice, delivery tag, text); `voice.py` records them into
  `test_results/cine2/vo/` and notes where each clip's pauses fall, and the
  subtitles follow those pauses, a caption per sentence.
- **Dialogue in the speakers' voices:** the trooper (`man_gruff`), the bridge guard
  (`man_serious`), the cruiser general (`man_shady`, his profile's voice), Oda at
  the bar, and T-89 (`robot_retro`) with the last word.
- **Slower, more patient:** each shot's action is authored in its own time and
  slowed by a factor per shot (`TS`, 1.05 to 1.6): the camera, the ship, the
  walkers and the race all together, so nothing drifts apart.
- **The push in on the ship:** instead of holding still at the end of an exterior,
  the last second or so turns onto the ship and closes the lens on it (`TAIL`;
  shots 1, 2, 5, 6, 7, 13, 15, 16; 4 is already one).
- **Sound (`mix.py`):** Ambient 2 the whole way, dipping under every line and
  effect (a sidechain), giving way to the club mix in the cantina; desert wind
  outside, the cruiser's hum in orbit; a few quiet effects from the game's own
  sounds (the ship's engine passing, its sputter, the nomad's steps, the barge's
  music, the trooper's shot, the speeders, the seeker and the blast, the holo's
  chirps, the drink, the coins, the general's walk, T-89's torch and beeps).

| # | Shot | Line (Oda's voiceover unless named) |
|---|---|---|
| 1 | Space, one move: stars, the tilt onto the lit planet and the Remnant cruiser; the ship streaks past and dives; push in on it. | "For fifty years, the Hegemony ruled this world." / "Then its heart gave out, and the whole thing came apart." |
| 2 | Under the buried star cruiser wreck, craning up as the ship goes over; push in on it. | "Their great ships came down like rain. Nobody ever cleaned them up." |
| 3 | The nomad walks toward us, stops, looks up; the camera tilts with him. | |
| 4 | His view: the long-lens push on the ship. | |
| 5 | The party barge on the dunes, its music carrying; push in on the ship. | "The rich still throw their parties out on the dunes." |
| 6 | Wide on the Remnant outpost, in to the gate; the trooper turns a local back, then shoots him; push in on the ship. | "What's left of their army still holds the desert." / Trooper: "Halt! Back in the dirt, sand rat." |
| 7 | The Basin Run past the beast's head; the seeker lands on "home"; push in on the ship. | "Out in the basin, folk race for coin. Not all of them make it home." |
| 8 | Over the cruiser's hull to the bridge tower. | "They are hardly even a remnant of what they once were. But they still have a hold." |
| 9 | The holo of the planet, pulling back to the general. | |
| 10 | Close on the general; the guard reports; he turns to camera. | Guard: "Sir, a ship has just entered orbit. They are landing at the port." / General: "And who do we have here?" |
| 11 | On the counter: Oda sets the drink down. | |
| 12 | End of the bar. | Oda: "Dust ale. That'll be four credits." |
| 13 | Backing out of the club; push in on the ship over the roofs. | "And now somebody new just fell out of our sky." |
| 14 | The general and his guards walk to the pit, camera in front. | |
| 15 | The same from behind and above; push in on the ship. | "Wonder whose side they'll pick." |
| 16 | The pit: T-89 welding, turning to the general, then up at the ship; push in on it. | T-89: "Oh my. That one is going to need a lot of work." |
| 17 | The OPENSPACE title card. | |

Tools: `voice.py` (the lines), `pass.sh "shot:t,t ..."` (stills), `sheet.sh`
(contact sheets), `clip.sh <shots>` (clips; `RES=1080`), `assemble.sh` (the cut,
then `mix.py` for the sound).

## v2: the one-minute cut

> "start making the much better version of this cutscene with all the improvements. it should be exceptional and basically demo the world and show the depth we have here." (the user)

The crashing ship ties it together; the captions tell who the Remnant are (the
lore is the cards': the Hegemony ruled this planet for fifty years, its centre has
collapsed, what is left of its army holds the port and the desert). About 66 s.

| # | Time | Shot | Caption / line |
|---|---|---|---|
| 1 | 10 s | Space, one move: the stars, a tilt down onto the lit planet with the Remnant's star cruiser hanging over it, a slow push in; the ship streaks in past the camera, over the cruiser, down at the planet. | "For fifty years the Hegemony ruled this world." / "Now its heart has fallen." |
| 2 | 4 s | Low on the sand under the buried star cruiser wreck; the camera cranes up the hull as the ship streaks over, smoking. | "Its fleets lie broken in the sand." |
| 3 | 4 s | A Red Wind nomad (no flag) walks out of camp toward the camera, stops, looks up; the camera tilts up with his look to the ship. | |
| 4 | 2.5 s | His view: a slow long-lens push on the ship (no shake). | |
| 5 | 3 s | The party barge on the dunes, the party on its decks; the ship passes over. | |
| 6 | 5 s | Wide on the Remnant outpost and its quantonium refinery, pushing in to the gate: the trooper turns a local back, then shoots him. Ship far behind. | "What is left of its army still holds the desert." / "Halt! Back in the dirt, sand rat." |
| 7 | 6 s | The Basin Run: the beast crawls across the racing line, the racers' outpost behind it. The race passes the camera and swings round in front of its head (never through it); the last racer's seeker blows up the leader. Ship in the sky. | |
| 8 | 4 s | Gliding over the Remnant cruiser's hull to the bridge tower, the planet below. | "They call themselves the Remnant." |
| 9 | 3 s | On the bridge: close on the holo of the homeworld, pulling back to the general at the window. | |
| 10 | 6 s | Close on the general, the holo over his left shoulder; the guard walks up. He turns to camera for his line. | "Sir, a ship has just entered orbit. They are landing at the port." / "And who do we have here?" |
| 11 | 1 s | On the bar counter: Oda sets a drink down. | |
| 12 | 3 s | End of the bar, patrons one side, Oda the other. | "Dust ale. That'll be four credits." |
| 13 | 2.5 s | Backing out of the club through its door; the ship over the roofs. | |
| 14 | 2 s | The general and two gate guards walk the main street toward the pit; camera in front. | |
| 15 | 2 s | The same walk from behind and above. | |
| 16 | 4.5 s | The pit: T-89 welding the frigate in the left foreground; the general and guards come down the ramp; T-89 turns to them, then up at the ship coming in. | |
| 17 | 3.5 s | Fade to the OPENSPACE title card, then the existing landing. | |

What changed from the rough cut, against the notes below:
- **No shake:** a fixed 60 Hz step (`--fixed-fps 60`); every camera is a keyframed
  Hermite path, eased at both ends; follows are damped points, never a body.
- **The ship in every exterior:** its own straight track per shot, placed from that
  shot's framing so it always reads in the sky (not the bridge or cantina).
- **The beast:** the race passes in front of its head while its body trails off
  the other side; the probe logs the closest pass (7.5 m at worst).
- **The cantina crowd:** every body gets its own animation clock (probe only for
  now; the game has the same unison idles, worth a fix of its own).
- **Exposition:** captions drawn in the shot (AnonymousPro, lower third), and the
  cruiser, the wreck, the outposts, the barge and the race all on screen.
- The cruiser's hull is moved for the exterior shots (1, 8) to hang over the sunlit
  side; its real orbit is over the night side at golden hour.

Tools: `tools/opening/pass.sh "shot:t,t ..."` (stills), `sheet.sh` (contact
sheets), `clip.sh <shots>` (720p30 clips), `assemble.sh` (the cut, with Ambient 2).

# Notes after the first rough cut

(2026-11-27)

The rough cut is `test_results/cine/rough_cut.mp4` (47 s, 720p30, Ambient 2 only:
no sound effects, voices or subtitles). It was filmed in-engine with
`tools/opening/shoot_opening.gd` (`still.sh <shot> <secs>`, `clip.sh <shots...>`,
`assemble.sh`), always under a scratch `HOME` so the real saves are never touched.

Plan: the finished cut ships as a pre-rendered video in the build, played when a
story game starts, skippable by holding E, then into the existing landing (the
ambient music fades out, the DJ mix fades in).

## Storyboard as it stands (about 47 s)

| # | Time | Shot |
|---|---|---|
| 1-3 | 8 s | Space: stars, tilt down to the planet, hold on it, the damaged ship flies in past the camera toward it. **Must be one seamless move** (see below). |
| 4 | 2 s | A Red Wind nomad (no flag) walks toward the camera, looks up; the camera pans up with him to the ship. |
| 5 | 2 s | His view: a push-in on the ship coming down, smoking. |
| 6 | 3 s | Remnant outpost and refinery: the trooper: "Halt! Back in the dirt, sand rat." He shoots a local. |
| 7 | 5 s | The beast close, the racers' outpost behind it on the Basin Run. The race dodges round it (never through it); the last racer puts a seeker into the leader, who blows up; the camera cranes up after the race. |
| 8 | 3 s | Cruiser bridge: the planet through the side window, pulling back to the general. |
| 9 | 6 s | Close on the general, holo map over his left shoulder. Guard: "Sir, a ship has just entered orbit, they are landing at the port." General: "And who do we have here?" |
| 10 | 1 s | Camera on the bar counter: Oda sets a drink down. |
| 11 | 3 s | End of the bar, patrons one side, Oda the other: "Dust ale. That'll be four credits." |
| 12 | 2.5 s | Backing out of the club through the door. |
| 13 | 2 s | The general and the gate guards walk the main street toward the pit; camera in front, moving with them. |
| 14 | 2 s | Same walk from behind and above. |
| 15 | 4 s | T-89 welding the frigate in the pit; the general and his guards come down the ramp; T-89 looks at them, then up at the ship in the sky. No cargo droid in shot. |
| 16 | 3 s | Fade to the OPENSPACE title card, then the existing landing. |

## What is wrong (the user's notes)

- **Too shaky, nearly every shot.** Movement must be smooth. No handheld shake
  unless a shot asks for it.
- **The framing (cropping) is wrong on many shots.**
- **Pans and zooms must feel much smoother.**
- **The speeders drive through the beast, not round it.**
- **The cantina NPCs move in unison.** It looks wrong; their idles need different timing.
- **Shots 1-3 are wrong.** They should be one seamless move from space: the pan
  down to the planet, then the ship flying in.
- **The ship flies in the sky in the background of every shot**, except the
  bridge (8, 9) and the cantina (10, 11). That is 4, 5, 6, 7, 12 (outside), 13,
  14 and 15, on one path coming down toward the port across the cut.
- **The nomad walks toward the camera**, then looks up, and the shot pans up with him.

## What is wrong (from reviewing the frames)

- **Shot 6 (outpost):** the trooper and the local are out of frame; it shows a
  dune with the refinery in the corner. The two-shot camera needs placing again.
- **Shot 15 (pit):** T-89 and the frigate are out of frame, and the end is just
  sky. T-89 must be in the shot the whole time.
- **Shot 8 (bridge):** opens on a dark wall, with the planet squeezed into the
  edge of the side window.
- **Shot 9:** the guard walking up behind the general barely reads.
- **Shot 3:** the ship passes too far from the camera to feel like a flyby.
- **Shot 7:** the seeker's explosion is small at 75 m; the racers are small once
  the camera cranes up.
- **Shot 11:** Oda is still small at the far end of the counter.
- **Shots 13-14:** the general walks at about 3.2 m/s, a brisk jog; a general
  should stride slower.
- **Not built yet:** sound effects, voiced lines, subtitles, the music dip
  under dialogue and effects, the in-game player, hold-E skip, and the 1080p60
  final render.

## Likely causes and fixes (for the next pass)

- **Shake.** The probe runs the game in real time, not at a fixed step, so
  every frame steps by a different dt. Cameras also lock straight onto moving
  bodies (NPC bob, the beast's head). Fixes:
  - Film with a fixed 60 Hz step.
  - Author each camera as its own smooth path (eased spline, position and
    target), never glued to an actor.
  - Where a camera must follow something, follow a heavily damped point.
  - Drop the hand-made shake in shot 5.
- **Speeders through the beast.** The dodge only clears the beast's head
  (`beast.global_position`), but its body trails 50 m behind along its path.
  Clear every segment (`beast._trail`): the racers' lateral offset must exceed
  the closest segment's distance plus the beast's width. Better still, have
  the beast cross the course and the racers swing round its head.
- **Cantina NPCs in unison.** They share one animation phase. Give each body
  its own start offset and speed (the same stagger the NPC rings use).
- **Seamless space opening.** Make shots 1-3 one camera path: start on the
  stars, tilt down onto the planet, settle, then the ship enters from behind
  the camera and flies away toward the ball. Cut only after the ship is small.
- **The ship in every exterior.** Use one shared flight path for the ship
  (world positions over cutscene time), sampled in each shot at that shot's
  start time in the cut, so it keeps coming down across the cuts.
