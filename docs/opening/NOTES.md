# Opening cutscene: notes after the first rough cut (2026-11-27)

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
