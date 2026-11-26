# Known Issues / Stubs / Fakes

Honest list of what is broken or faked, **worst first**. Each item ends with
where it came from (the issue or work, and the date of the note) and the issue
that fixes it, when there is one.

**How to keep it:**
- A PR that leaves something broken or faked adds a bullet to the section it
  belongs in, placed by how much a player would feel it (worst at the top).
- What a PR checked (suites, probes, numbers) goes in the PR and `CHANGELOG.md`,
  not here.
- When an item is fixed, delete its bullet and say so in the PR. When a note
  turns out to be replaced by later work, move it to
  [`docs/KNOWN_ISSUES_ARCHIVE.md`](docs/KNOWN_ISSUES_ARCHIVE.md);
  `tests/test_docs.gut.gd` fails if this file marks a section as replaced.

The per-PR notes this list was built from (2026-10-26 to 2026-11-25), with what
each PR checked and measured, are in the archive under "The per-PR log".
"Not rechecked" means the note is old and nobody has looked again since.

## 1. Freezes, hitches and crashes

1. **Long frames coming down to a planet, worst flying in from the gas
   giant.** Home loading fresh (a session that has not been home yet) has 42
   frames over the 33 ms budget, worst 384 ms: the rock landforms' meshes and
   trimeshes (~366 ms, one step), the wrecks' boxes and plates (~320 ms piece),
   the town garrison (~225 ms), the decor batch flush (~170 ms) and the first
   native body (~170 ms, pipeline compiles). The descent trace warms home before
   it measures, so it does not show this. With home loaded once already: 21
   frames over, worst ~93 ms, p99 21.6 ms; the switch is ~71 ms (desert, its
   dust, the ship's pilot, 96 far-ball uploads). Single pieces left: the club
   room's booths (~85 ms) and an instrument (~48), the barge's first commit and
   hull skin (~40 each), the cruiser's first hull piece (~38), decor step 7
   (~41), a town box (~34), the player's body (~33), each native pack member
   (21-39), an outpost (~20). Nothing is let go once built, and only the home
   planet builds by sight. *(#573, #574, #693, 2026-11-26; fix: #693)*
2. **A first descent on a fresh install** has ~14 s of ~450 ms frames between
   2.1 and 1.4 km: shader compiles, once per install. Everyone who gets a share
   build hits it. *(#574, 2026-11-24; fix: #693)*
3. **Godot's default Metal driver crashed at launch on this Mac**, inside the GPU
   driver, even for an empty project. Everything since has been rendered with
   `--rendering-driver vulkan`. Not rechecked on Godot 4.7.2; check which driver
   the share builds use. *(the beast's shell, 2026-11-01)*
4. **A LAN guest's game crashed once** (signal 11) right after its town loaded,
   in one of the first two runs of the shared-jobs trace. The next run passed;
   not chased. *(LAN jobs, 2026-11-03)*
5. **Building one NPC is 20–27 ms** (a trooper or droid; the bar 15–22 ms, the
   player's body 12–17 ms). Waking the barge's crowd builds one body a tick for
   about half a second; coming within 220 m of the barge builds one person a
   physics tick for 33 ticks. *(#162, 2026-10-29; the barge, 2026-10-31 and
   2026-11-01; fix: #695)*
6. **Opening the Player page the first time freezes about 2.3 s** (the outfit
   turntable builds a whole character in a new viewport). *(#545, 2026-11-05;
   fix: #696)*
7. **Heavy spots for draw calls.** Frame time swings with where the camera points
   (200 to 17,000 draw calls round town). An NPC is about 74 meshes, the beast
   ~145 mesh nodes. The barge's deck (33 dancers animated at full rate within
   50 m) is the heaviest place to stand. The station's dead stay until you leave
   (~200 more draw calls), and the moon dome's 21 patrons and 4 merchants were
   never timed on screen. *(2026-10-31 to 2026-11-25)*
8. **Speeder:** GPU spikes of 12–17 ms now and then driving fast (SDFGI on, most
   likely its cascades scrolling). Idle physics at the yard is ~9 ms a frame with
   nothing moving; not looked at. *(speeder boost lag, 2026-11-25)*
9. **All 25 outfit textures stay loaded** (2048², up to ~0.5 GB of video memory
   if every colour is used). *(#162, 2026-10-29)*
10. **Small hitches:** one OmniLight3D per burning wreck (several crashes add one
    each, for 25 s); one heavy frame getting out of the ship (~39 ms headless,
    not rechecked); a name costs ~0.3 ms, so a crowd of hundreds spawned in one
    frame would hitch. *(2026-10-26 to 2026-11-24)*

## 2. Wrong behaviour

1. **NPC hitboxes don't match their size.** Every body has the same 1.8 m
   capsule, so a tall trooper's head is above its hitbox and a pack child's
   hitbox is adult-sized. A bigger trooper may poke through a seat, a speeder or
   a door frame (seated and riding NPCs were not looked at). *(NPC sizes,
   2026-11-25; fix: #697)*
2. **Getting out of the ship in the round pit can put you on its wing**, 1.3 m up:
   the exit spot only checks the town's boxes. *(#545, 2026-11-05; fix: #698)*
3. **Guards find bodies through walls:** a body within 16 m in the sight cone is
   "seen". Bodies can't be hidden; they stay where they fall. *(#307,
   2026-10-31; fix: #699)*
4. **The beast goes through things:** rocks, wrecks, packs, buildings, and the
   town walls in a chase. About once every half hour of game time its head pops
   onto a rock. A speeder's touch is a centre-distance check, so a glancing pass
   at the nose or tail may miss. *(#220, #266, 2026-10-30 and 2026-11-01; fix:
   #700)*
6. **Pulled back with no warning:** walk off a floor's roof (no railing) and you
   are put back in the bay; outside on the giant, the same once you drop 40 m
   under the lowest floor. *(the station, 2026-11-03 and 2026-11-04; fix: #702)*
7. **Seven small ones** *(2026-10-29 to 2026-11-05; fix: #703)*:
   - Selling the gun in your hand to the fence leaves it drawn until you switch.
   - A barge fighter's body hangs in the air if the barge drives off while it
     lies there.
   - The frigate sets down on the port pit's pad, half its size; it may overlap
     the pit's edge. Its flight numbers are a first guess.
   - An upgrade T-89 bolts on mid-game is not in the ship's hull until the next
     load.
   - The interceptor circles under its ceiling while you are in orbit. After the
     fleet is beaten it hunts every flight out of town, which may get tiresome
     (`wanted()` in `atmo_fighter.gd`).
   - Quitting in open space saves nothing; the save keeps the last planet's.
   - The droid lasers (and the stage droid's) pass through walls and the floor.
8. **What a save forgets:** only a spot where you stood is kept (not mid-flight,
   not riding); a stolen ship, a sold stolen ship and where you parked the barge
   (or its wreck) are back home next session. Switching saves mid-flight lands
   you. Older builds still write `save.json`, which this build never reads after
   the one-time copy. *(2026-10-29 to 2026-11-01)*
9. **Packs walk straight at their goals:** steering is round known rocks only, so
   dune faces, the starcruiser wreck and anything not in WorldGround's boulders
   or columns are walked into. A camp moved by a rock can end at its pad's edge,
   where the tents' earth floors show. *(#96, 2026-10-28 and 2026-10-29)*
10. **The barge only stops for the world's data** (boxes, rocks, columns), not a
    parked ship or speeder, and floats level, never tilting with the dunes.
    *(#269, 2026-10-31)*
11. **The giant's clouds:** a space fight's flight doesn't check them, so a ship
    could dive in mid-fight and live (there's no fight there today); a crash in
    them is the normal crash, towed to the dock pad. *(the ringed giant,
    2026-11-03)*
12. **Station oddities:** Z only docks you on the dock pad; one hangar for both
    ship salesmen (a ship bought and never flown stands on the spare pad of
    whichever you visit); T-99's card offers the Remnant talk, which never
    happens at the station; the elevator's glass shaft is solid, so you step out
    from the gap round it. *(the station, 2026-11-04)*
13. **Flight oddities:** raiders don't follow you down (a fight you dive out of
    just vanishes); the pad's orbital fight still starts at the old edge with its
    "Contact!" toast; the interceptor only fights in the air and goes home if you
    land. The ALT read-out jumps at a switch (it is the true number for where
    you are). *(2026-10-27 to 2026-10-29)*
14. **Small ones:** speeders past the fourth park on top of the first spots;
    Skrugs's bench box is there in story too (only its menu is free roam);
    shelter from "no air" is a plan-view check, and a speeder counts as shelter;
    the wall pull-back is one ray from the eye, so a rail or door edge off to the
    side doesn't pull the gun back; the sword's first-person swings hit from
    where the blade is drawn. *(2026-10-30 to 2026-10-31)*
15. **Old notes, not rechecked:** ships are columns to the ship's collision
    (mesas, hoodoos); there are no ship-to-ship collisions in a fight; locals and
    troopers ignore each other's stray bolts; dead locals and troopers come back
    when the scene reloads. *(M10, M14, locals on foot, 2026-10-26)*

## 3. LAN

1. **Jobs, not the world, are shared.** Outposts, resupply and optional quests
   stay each game's own. If two players change a job in the same quarter second,
   one change is lost. A guest's own save keeps the host's jobs after they
   leave, and joining shows the host's jobs as New Job banners. Each player gets
   their own heist crew. *(LAN jobs, 2026-11-03)*
2. **A guest who hacks a console gets no wave**, and **killing the general as a
   guest pays the host**. The host's crew only wake aboard once the host's game
   sees the guest. *(2026-11-03 and 2026-11-04)*
3. **Ship fights between friends:** you hit where their ship is drawn in your
   game (up to a packet, 1/20 s, behind); a friend's ship in space is hit as a
   sphere; their cannon fire is a picture that can pass through a hill; their
   seekers show only unlocked; a seeker locked on the interceptor still hits a
   friend in its way; shooting the host down ends a space fight for everyone.
   *(LAN friendly fire, 2026-11-03)*
4. **Hijacking:** flying a hijacked ship to another planet isn't handled (the
   owner gets it back only by leaving and joining); another player's parked
   speeder isn't shown; one ship per player shows; the hop is a slide; a
   hijacked ship flies with your upgrades and name; an AI pilot thrown out
   leaves no body. *(hijacking, 2026-11-04)*
5. **Your droids' lasers and safety are your own;** others don't see them.
   *(2026-11-04 and 2026-11-25)*
6. **Nothing LAN has been played on two computers;** every check was a two-process
   loopback on one machine.

## 4. Looks or sounds wrong

1. **Desert packs:** members out of the sand collider's reach slide frozen in
   their last pose; the gesture poses were never watched moving and may be wrong;
   spears and knives hang at a fixed angle. *(#96, 2026-10-29; fix: #704)*
3. **Far from the origin** (the cruiser, 11.5 km out) the pistol's iron sights and
   the arms wobble about a millimetre; scoped in, the barrel casts no shadow, and
   the scope's last frames of aiming in can wobble once. *(the cruiser pass,
   2026-10-31; fix: #706)*
5. **Ships rest level** wherever they land, so a slope leaves one side hanging.
   *(M14, 2026-10-26; fix: #708)*
7. **Loading a save can make a coin sound.** *(#16, 2026-10-27; fix: #710)*
8. **Bounty targets have no marker:** the pointer leads to the outpost, not the
   person. *(#65, 2026-10-27; fix: #711)*
9. **The ring station isn't on the F11 map**, the cruiser's holo, the objective
   arrow or the waypoints. *(the station, 2026-11-03; fix: #712)*
10. **Crashes:** the break is jagged and open (no inside); a ShaderMaterial
    darkens less when burnt; the barge's wreck is its decks only and can lie
    where the rebuilt barge comes back. *(#404, 2026-11-24)*
11. **Pop-in to look at:** small props fade in at 120–220 m, people at 320 m,
    town lamps go out past 300 m at night, the cruiser's bay lights past 120 m;
    Low graphics shrinks these to 0.6. A cheap ball swaps for the real one at
    6 km (a small pop). The space scene's nine lights and your own light have no
    fade. *(2026-11-02 and 2026-11-05)*
12. **Station:** a floor two away is empty glass (only the near floors are
    drawn); the rooms are big, sparse, one wall finish, flat-coloured shapes, and
    the suites have no light of their own; the station uses the cruiser's metal
    and glass; seen only from its own planet's scene. *(2026-11-03 and
    2026-11-04)*
13. **First person:** the rifle reload shows little of the left hand; walking
    unarmed the hands stay out of view; the hilt is thicker than the closed
    fingers; aimed in, the top of the barrel reaches into the scope's front lens.
    *(#229, 2026-10-30 and 2026-10-31)*
14. **Bodies:** the ragdoll has no self-collision and the spine can over-twist; in
    first person the camera doesn't follow your body when you fall; droids still
    snap flat when destroyed; the assassin droid's pistol follows the hand, not
    the aim; NPC health bars and speech lines step at 60 Hz. *(#25, 2026-10-27;
    2026-10-29)*
15. **The beast:** its legs swing rather than plant; its shell is a shader on a
    chain of spheres; its eyes bloom nearly white; the puff is fading spheres and
    the fart is the old blob's. *(#220, #266, 2026-10-30 to 2026-11-01)*
16. **Places:** Skrugs's yard has no decor of its own; the droid post is small
    through the gate at 310 m; the camp fire is three glowing cones; people
    crouch for sitting and patrons stand in the booths; the cruiser's screens are
    shader pictures and its holo map isn't to scale; the barge's band and DJ are
    look-only bodies; the fog on the giant is a look, not a volume. *(2026-10-29
    to 2026-11-04)*
17. **Low graphics looks cooler and crisper** than full (it drops the warm haze and
    the sand's bounce light). *(2026-11-02)*
18. **Small ones:** the droid safety's wheel icon is small in its slot; the
    jetpack is big and bright yellow; grey rock reads tan in golden-hour light;
    the barricades may still be greybox crates (not rechecked). *(2026-10-26 to
    2026-11-25)*
19. **Sound:** one engine loop for every ship (the speeder borrows it, pitched
    up); a big dogfight may sound busy; the horn, chatter and klaxon are
    synthesized; no sound for landing gear, UI clicks or ambient town noise;
    nothing has had a listening pass. *(#16, M15, 2026-10-26 and 2026-10-27)*

## 5. Never played by hand

Checked by bots, headless runs and stills only; the numbers are first guesses.

- **Flight and fights:** the flight feel (turn rates, throttle, mouse stick,
  landing limit); the interceptor's difficulty, ranges and ground margin; the
  frigate has never been flown; balance in the dogfights. *(M10, M14, #76)*
- **On foot:** guard aim error, bursts, hide times, prices and standing changes;
  locals' health and damage; first-person sway, bob, landing dip, reload and the
  sword's swings; the slide, the camera tilt and the thud. *(M15, #65, #229)*
- **Not seen on screen:** a Remnant interceptor shot down in flight, and your own
  ship shot down or flown into the ground; borrowing a cruiser bay ship and a
  fight with locals aboard; the planets from the port at their new size and the
  chart's sun; the render smoothing (sight while sprinting, the first frame after
  leaving a vehicle, a downed body); the objective pointer in first person or
  from a ship. *(2026-10-29 to 2026-11-25)*
- **The NPC builder:** no AI chat with a player-made keeper, and the GitHub link
  was never opened in a browser. *(2026-11-08)*

## 6. Tests and tools

Players never see these.

- **Suites failing on `main`** (rerun one by one on 2026-11-26, headless, this
  Mac):
  - `test_town_decor`: the decor has 39 bodies, not one Props body (48 boxes,
    not 1,857), roof props don't collide, and stalls 18 and 19 both sell
    pottery.
  - `test_desert_terrain`: 48 level pads where it expects 32 (the climbable
    mountains' shelves and the race gates came after the test).
  - `test_m10_dogfight`: its trace is never written (errors before the fight).
  - `test_planets_trace` reads a trace that `scenes/planets_trace.gd` must write
    first, and that trace hangs (next bullet), so it fails.
  - Not rechecked: the guest half of `scripts/test_lan_world.sh` ("people here
    are not all copies").
  - Passing now, though older notes called them red: `test_inventory`,
    `test_dogfight`, `test_atmo_flight`, `test_globe_map`.
- **Traces under `-s`:** traces that touch WorldState fail to compile before the
  `NpcVoice` autoload exists, so `test_garrison_trace` has no trace to read, the
  cruiser trace builds no crew, and `planets_trace` hangs at the switch into
  open space. *(2026-10-29 to 2026-11-14)*
- **Traces that end badly:** the natives trace (and others now and then) aborts
  at teardown after writing its file; m13 (the jetpack trace) is disabled; the
  m11 body trace hangs on this Mac.
- **The descent trace:** both routes in one run flood "Too many instances using
  shader instance variables", so run `DESCENT_ROUTES=port_desert` then
  `grit_station`; no GUT test reads it.
- **Budgets near the line:** the combat and garrison traces sit at 40–49 ms
  against 50; `WORST_MS` in the planets trace depends on how busy the machine
  is; GPU timing on this Mac is noisy (compare medians).
- **Not run after recent changes:** the race suites (`test_speeder_race`,
  `test_race_beast`, `test_race_feel`, `test_pink_slips`, `test_race_crews`,
  `test_race_course`) and the planet and terrain suites; no GUT test for a real
  vehicle starting a crash. *(2026-11-24 and 2026-11-25)*
- **Odds and ends:** `DesertTerrain` (tests only) still scans its pads;
  `shoot_fpv.sh` runs turn the town hostile after a few minutes; the hijack and
  LAN jobs probes are not in the repo.

## 7. Not built yet

Stubs and fakes: things a player might expect that aren't there.

- **The ring station:** the top floor (cantina, barracks, bridge) and the outpost
  floor are empty (#314); no cantina, Oda, board or merchant on the giant; the
  drop hatch is sealed (#317); stalls have no keepers and sell nothing; four pads
  are empty; NPCs can't ride the elevator; the roof hatches need the jetpack; the
  glass middle means you can't drop over the railing; the locals hold it for
  good once taken (no retake or supply runs); the ring has no rocks (#312); home
  can't be seen from it; without the look layer there's no furniture.
- **The cruiser:** the Map page's row doesn't flash when it changes hands; the
  belt cruiser has no holders block, so it stays empty once taken (#317).
- **Combat and AI:** one alarm stage; nobody flees or surrenders; fights end only
  three ways; the search only knows contraband; one smuggling cache, once;
  guards don't flank or throw; the view cone doesn't turn with the head; no
  avoidance between NPCs.
- **Jobs and story:** bounty contracts off the home planet lead home; off home,
  the objective pointer only knows the station's drop and fence; no key to hide
  the pointer; one world seed for everyone (every port is the same town);
  the fixer, weapons, the outpost and the mission's crate aren't named on screen.
- **The beast and packs:** one beast, on one planet; no health bar; only you die
  to it; a blade hit with no owner counts as yours. Packs don't steal vehicles
  (#176) or fight each other or the Remnant; no sandstorms (#175); camps run on
  game hours while the sky follows the F11 slider.
- **Planets:** generated towns are plainer than the port (no pit bowl, stair
  tower, stage or fixer; a grid of lots) and their merchants don't trade; sea,
  lava and clouds are flat planes; planets are placed by hand and nothing stops
  two overlapping; bigger asteroid towns are untested; a square-desert planet
  would build its terrain whole on a handoff (only ball planets are targets
  today); a lava planet is still to come (#272).
- **The NPC builder:** the port only, 8 stalls; a try-out's wares don't change on
  the counter until merged; no voice sample or "write it for me".
- **Saves and menus:** only F11 > Game > Saves switches saves (no title screen);
  AI chat logs are shared between saves.
- **Flight:** no landing gear, contrails, re-entry glow or camera shake; no
  climb drag in open space; no floating origin (a few mm of float error ~57 km
  from the sun); no gamepad bindings; glow is off in `content/look/space.json`.
- **Small ones:** no air meter or breathing sound; the lasers run at 126 BPM, not
  the club's; the rave stalls' wares don't pulse; names are English only and the rude-word and franchise lists are
  short.
