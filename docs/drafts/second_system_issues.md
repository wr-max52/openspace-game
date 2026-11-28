# Draft: The second system (epic + 6 sub-issues)

Labels on every one: `enhancement`, plus the size and areas listed.

---

## EPIC: The second system: a warp drive and a small red-desert system

Labels: `enhancement`, `size: XL`, `area: world`

> "We're going to have warp drives and the next solar system. To warp you need an upgrade from T89 that is 10k. Once ure in open space you can use warp its like hold a Key and then select destination (for now only the one)... It's a red desert planet... and one other planet or object. Smaller system... All of which need outposts" (the user)

# What and why
A second, smaller star system you reach by warp. Buy the warp drive from T-89, fly into open space, hold the warp key, pick the system and drop out there. The system has three places: a red desert planet full of folklore (its main port city with a dark station overhead, three mountain towns, and a giant worm), a water planet you cross by speeder, and an asteroid field with wrecks. Every place has outposts to take.

Right now there is one system: every planet is `near` the one sun (`types.json` `space.sun`, `PlanetGen.system_sun`), and open space draws all of them.

# Sub-issues (each one ships on its own, in this order)
1. **Warp drive:** T-89's 10k upgrade, hold to warp from open space, a second system in data.
2. **Red desert planet:** the planet, its mountain half with tunnels, and the tall port city.
3. **Dark ring station and the system's cruiser:** over the port city.
4. **Mountain towns:** three red-rock circle towns, each with its own look, outfits and cantina.
5. **Folklore and Dool'rey Kah:** the old storyteller, ghost and curse lore, and the worm.
6. **Water planet:** a rusty favela town on the sea, speeders as the only way round, outposts on pads.
7. **Asteroid field and wrecks:** rocks, derelict cruisers, outposts on the big rocks.

# Done looks like
* All seven sub-issues closed.
* **Round trip:** a save can buy the drive, warp out, visit all three places, warp home and load again in either system.

# What this leaves behind
A `system` field on planets and a warp route, so the third system is a set of planet files and one line.

---

## 1. Warp drive: T-89 sells it, hold to warp from open space

Labels: `enhancement`, `size: L`, `area: world`, `area: saves`

> "To warp you need an upgrade from T89 that is 10k. Once ure in open space you can use warp its like hold a Key and then select destination (for now only the one) it activates ur engines go crazy..." and "Press and hold animation starts u don't have to hold after that. The animation is just to give the game time to load the new system. Min 5s" (the user)

Part of the epic.

# What and why
The warp drive is how you leave the home system. It is a ship upgrade like Shields+, but it unlocks an action instead of multiplying a number. The warp sequence is a short loop that covers loading the next system.

Right now T-89's `upgrades` (`content/core/npcs/t89.json`) only multiply stats (`mult`), and there is one system.

# Done looks like
* **T-89 sells "Warp drive" for 10,000 cr** in "Upgrade your ships", once per ship, like the other upgrades. The price lives in `t89.json`.
* **Only in open space:** with the drive fitted, hold the warp key (default `J`, rebindable) for about 1 s and the destination picker opens. It lists the other system (one entry for now). On a planet or in its bubble the key does nothing, and a short line says why.
* **Pick it and let go:** the engines' glow ramps up, the starfield stretches and the FOV kicks. A cheap loop runs for at least 5 s, and for as long as the new system takes to load. You drop out in the new system's open space, pointed at its main planet.
* **Cheap, per the render rules (rule 13):** no new particles, trails or materials. Only the star sky, the FOV kick and the boosters' own glow, all already warm.
* **Warp home works the same way** from the new system's open space.
* **Systems are data:** each planet file gets `"system"` (default `"home"`). Each system has its own sun in `types.json` `space.systems`. Open space draws only the current system's planets, and the system chart shows only that system.
* **Saved:** `WorldState` holds the current system. A save made in the new system loads there.
* **Headless test:** a save with the drive, in open space, warps. It is in the new system after at least 5 s, and the old system's planets are not drawn. A save without the drive cannot open the picker.

# Could have
* The picker shows the travel time and a small picture of the system's star.
* A warp hum in `content/look/sound.json`.

# Built from
* `t89.json` `upgrades` plus `src/systems/flight/ship_upgrades.gd`: a new upgrade kind `unlock` (a flag on the ship) next to `mult`.
* `open_space.json` (still one place, rule 2), `PlanetGen.system_sun` and `system_port` (now per system), and `WorldState`.
* Render rung: **data only** (the sky, the FOV kick and the engine glow that already exist).

# What this leaves behind
`unlock` upgrades (a cloaking device or a tractor beam fits the same slot) and the `system` field, so a third system is planet files and a line in `space.systems`.

# Not in this issue
* Planets and ships drifting through the warp tunnel (the user chose the cheap loop).
* More than one destination.

---

## 2. Red desert planet: mountains, tunnels and the tall port city

Labels: `enhancement`, `size: L`, `area: world`, `area: visuals`

> "It's a red desert planet... The red desert planet has a lot of mountains with tunnels and it's smaller size homeworld maybe a bit smaller... Theres a main port city that is a lot of the tall buildings" (the user)

Part of the epic. Follows 1.

# What and why
The new system's main world. Half of it is dense red mountains with tunnels you can fly or ride through, and the other half is open red desert. The port city is a circle town built tall, in the dark red stone of the planet.

The `red_desert` type already exists in `types.json` (red sand, rock, sky and a native pack), but no planet uses it.

# Done looks like
* **A planet file** `content/core/planets/<id>.json` on the `red_desert` type, `"system"` set to the new system, a name from the name engine, and a radius about 80% of the home planet's (tunable).
* **The mountain half:** dense, tall crags (taller `desert_landforms.json` landforms) over one hemisphere, set by a mask in data. The other half is open dunes.
* **Tunnels:** six or more tunnels through the mountains, wide enough for a ship at low speed and a speeder at full speed. They are props with box colliders, not changes to the ground's height.
* **The port city:** `town_size` about 70 on a variation of `port_round`, with taller buildings (more stair-tower and tall-box variants), a landing bay, a cantina and merchants.
* **One material for the planet's towns:** a style line in dark red stone that matches the rock (`town_styles.json`). Every town on this planet starts from it.
* **Locals** in a red-desert look (new `characters.json` archetypes, kit pieces recoloured).
* **Outposts:** five Remnant outposts across both halves, as a Territory front (copy the moon's `landmarks` and `territory.json` front).
* **Headless test:** the planet boots, the town validates (V1 to V9), a speeder drives through one tunnel end to end, and the five outposts stand on level pads.

# Could have
* Dust haze that settles in the mountain valleys.

# Built from
* The `red_desert` type, `PlanetGen`, `TownGen` and the `port_round` layout, `desert_landforms.json`, `town_styles.json`, `characters.json`, and the moon's outpost landmarks.
* Render rung: **mix and recolour** (town and people) and **simple shapes** (tunnels).
* Render rules: boxes before models, draw by distance, never build what you outrun. Landforms are props, so a patch's rows cost the same as today.

# What this leaves behind
A hemisphere mask for landforms and a `tunnel` landform any desert planet can use.

---

## 3. Dark ring station and the system's cruiser, over the port city

Labels: `enhancement`, `size: M`, `area: world`, `area: visuals`

> "directly above it is a station like the grit station. New name, make some changes to it's metal so its darker metal and change the interior like room decor and colors etc but overall it's a copy same manufacturer same layout generally... it works the same (ownership, etc there is a cruiser in the system)" (the user; they chose the ring station over the gas giant as the one to copy)

Part of the epic. Follows 2.

# What and why
A sister ring station hangs straight over the desert port city: the same maker and floors, but in darker metal with new decor. A Remnant cruiser holds station near it, so the system has its own fight.

# Done looks like
* **A new station file** copying `orbital_station.json` (same floors, bay, elevator, tunnels and room owners), named by the name engine, hung as a `station` landmark over the port city.
* **Darker metal:** the hull and decks use a darker shade of the same metal (look data, not a new shader).
* **New interior:** different room decor, wall and floor colours, and stall dressing (`station_fill.gd` fill options in data).
* **Ownership works the same:** floor owners, the Remnant deck, the map page's owners, and capture through Territory.
* **A cruiser** copying `belt_cruiser.json`, holding near the station, with its own taken flag and reward.
* **Headless test:** the station loads over the port and you dock in the bay; taking its Remnant deck moves the owners on the map; killing the cruiser's general sets only this cruiser's flag.

# Built from
`orbital_station.json`, `station_hull.gd`, `station_fill.gd`, `belt_cruiser.json`, and the Territory fronts. Render rung: **data only** plus **recolour**.

# What this leaves behind
A station file that differs only in its look and fill, a template for any planet's station.

---

## 4. Mountain towns: three red-rock circle towns, each its own

Labels: `enhancement`, `size: L`, `area: world`, `area: cantina`

> "One half of the planet has dense mountains with towns and ports that are all different variations of the town we have layout changes a bit cantina size and type, the color pallets/material color of the town should change, the locals outfits are all different/ corresponding to the towns... some of them are like just a few ranches all near each other with a shared wall around all of them and it's on top of a mountain." (the user)

Part of the epic. Follows 2.

# What and why
Three small circle towns in the mountains, each a variation of the town we have. All of them share the planet's red stone, but each has its own palette, cantina and outfits. Right now a planet has one town; everything else is outposts and places.

# Done looks like
* **A new planet block, `settlements`:** a list of small towns at map points, each built by `TownGen` at a small size from a layout variation, with its own style line, cantina choice and look set for its locals.
* **The ranch ring:** three or four ranch houses on a mountain top inside one shared ring wall, with a small cantina.
* **The mining town:** by a tunnel mouth, in rust and soot tones, with a rough bar.
* **The shrine town:** a pilgrim stop in pale ochre and faded cloth. Its cantina is where the storyteller sits (issue 5).
* **Every town's people dress their own way:** each town has its own `characters.json` archetypes (kit pieces and colours on the one skeleton).
* **Cantinas differ in size and kind:** small, medium and large, with a `club` block in at most one.
* **Built by distance:** a town builds in stages when you come near and is not built when you only fly past (render rules: build over ticks, never build what you outrun).
* **Headless test:** each town validates (V1 to V9), its locals spawn in their own outfits, and the planet's frame time with all three towns stays within budget from the port.

# Could have
* A speeder road between two of the towns.

# Built from
`TownGen`, `town_layout.gd`, `cantina_dressing.gd`, `club_dressing.gd`, `town_styles.json`, `characters.json`, `Townsfolk`. The new part is the `settlements` block, built in the pattern of `domes` and `landmarks`. Render rung: **mix and recolour**.

# What this leaves behind
`settlements`: villages on the home planet, a native town or a frontier camp each become a few lines of data.

# Still open
* Do the settlements' locals fight back like the port's when shot? (Default: yes, they share the town brain.)

---

## 5. Folklore and Dool'rey Kah: the storyteller, the ghosts and the worm

Labels: `enhancement`, `size: M`, `area: llm-npcs`, `area: world`

> "one on the highlights is the deep folklore of the planet. It's like there's ghosts and curses and there's someone u can talk to who will tell you about the beast which is a giant worm in the desert. We'll need to render that." and "Make somethig else with simple shapes and rock renders its a worm so like it doesn't need to be that good just needs creepy teeth reuse the eyes and a long body an more balls than the current beast. It's name is 'Dool'rey Kah'" (the user)

Part of the epic. Follows 2 and 4.

# What and why
The planet's heart is its stories. An old storyteller in the shrine town's cantina tells of ghosts, curses and Dool'rey Kah, the giant worm of the open desert, and the worm is really out there.

# Done looks like
* **The storyteller:** an old local NPC (profile plus look) on a `TalkSpot` in the shrine town's cantina, with an AI card (`content/core/npcs/`) full of the planet's ghosts, curses and worm lore.
* **Locals mutter lore** as you pass (the beast block's `lore` lines and `locals_say`), different lines in each town.
* **Dool'rey Kah:** the planet's `beast` block with a new `worm` body made from simple shapes and the rock-shell look:
  * a long body of more segments than today's beast (about 2x), with no legs;
  * a round head with a ring of creepy teeth (cones) and today's glowing eyes, reused;
  * the same kill-on-touch, chase and `beast_slain_<planet>` flag.
* **It lives in the open-desert half,** not the mountains.
* **Headless test:** the worm spawns with its segment count and no legs, touching it kills, and asking the storyteller about the worm gets a reply that names Dool'rey Kah.

# Could have
* The worm dips under the sand and comes back up now and then.
* A curse that does something small (a flicker or a whisper at night).

# Built from
`planet_beast.gd` (a `kind: "worm"` body option next to the crawler), the `beast_shell` shader and eyes, `LookMeshKit` cones and balls, the NPC kit, and an AI card. Render rung: **simple shapes**, no new render.

# What this leaves behind
A second beast body: an eel on the water world or a sand serpent on any desert is a `kind` and colours.

---

## 6. Water planet: a rusty favela on the sea, crossed by speeder

Labels: `enhancement`, `size: L`, `area: world`, `area: visuals`

> "No moon a dif planet. Water planet? Reuse the godot water, speeders become the only way to get around, the town has a speeder pad out front. Buildings look more like the favela with rust. There's some outposts also on pads." (the user)

Part of the epic. Follows 1.

# What and why
An ocean world in the new system. The town floats on its deck, its buildings stacked like the station's favela and gone to rust. Speeders skim the sea between the town and the outposts on their pads.

Right now the `water` type is a town on a deck 160 m above a flat sea you can only fall into (`platform_world.gd`); nothing rides on the sea.

# Done looks like
* **A planet file** on the `water` type, in the new system, using the water surface material we already have (no new shader).
* **A round sea you can ride:** the sea is a smooth ball the speeder's hover model rides (`ground.height_above`). Walking or falling into it drowns you, with the type's fall text, and you wake at the landing bay.
* **The deck sits low on the water** with a speeder pad out front, and a rented or owned speeder waiting.
* **Favela buildings with rust:** a style line and building variants copying the station's favela fill, rusted.
* **Outposts on pads:** four or five Remnant outposts on floating pads (copy the skimmer decks from #846), reachable by speeder or ship, as a Territory front.
* **Headless test:** a speeder leaves the pad, crosses 1 km of sea to an outpost and back without sinking; a player on foot in the water drowns and respawns.

# Could have
* Waves that roll the speeder gently.

# Built from
The `water` type, `platform_world.gd`, `hover_model.gd`, `station_fill.gd` (the favela), the skimmer outposts, and `speeder_post.gd`. The new part is a sea ground that answers height checks. Render rung: **data** and **recolour**.

# What this leaves behind
A rideable sea any water or lava world can switch on.

---

## 7. Asteroid field and wrecks, with outposts on the big rocks

Labels: `enhancement`, `size: M`, `area: world`

> "and one other planet or object" (the user; they chose an asteroid field with wrecks)

Part of the epic. Follows 1.

# What and why
The system's third place: a drifting field of rocks with derelict cruisers wedged among them and Remnant outposts dug into the biggest rocks.

# Done looks like
* **A place with its own bubble:** a planet file on a new `field` type (no ground, open space's sky), so fights stay inside a bubble (rule 2) and the field is a place you fly to.
* **The field:** a few hundred rocks of mixed sizes from shared meshes, flown through with real collision on the big ones.
* **Two or three wrecked cruisers** among the rocks, entered on foot by jetpack (copy the belt wrecks, #848).
* **Four outposts** on the largest rocks, as a Territory front.
* **Headless test:** the field loads as its own place in the new system, a ship collides with a big rock, and each outpost can be taken.

# Built from
Belt wrecks (#848), skimmer outposts (#846), `LookMeshKit` balls, and Territory. Render rung: **data** and **simple shapes**.

# What this leaves behind
An asteroid-field place any system can drop in with one file.
