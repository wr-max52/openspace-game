# Render rules

The rules for anything that is drawn or ticked, so the game stays fast while it
grows. Read this before dressing a place, adding props or people, or writing
per-frame code. They apply as much as "What can not change" in the
[write-issue skill](../.claude/skills/write-issue/SKILL.md): a PR that breaks one
says why in its body.

Lifted from four places, which keep the detail and the history:
[`docs/station/STATION_FILL.md`](station/STATION_FILL.md) (the station's eleven
rules and the crowd's five), DECISIONS "Draw distance" (2026-11-02),
[`docs/ART_DIRECTION.md`](ART_DIRECTION.md) (the budget) and
[`docs/performance-traces.md`](performance-traces.md) (how to measure).

**The budget:** 60 fps at 1440p on an Apple Silicon laptop, about 11 ms of GPU
a frame, with headroom left for the local LLM.

## Drawing

1. **Batch.** Props go through the building kit (`TownBuildings.part` and
   `solid_part`, `src/systems/world/town_buildings.gd`); a place ends as one
   mesh per material, and anything repeated is a MultiMesh. A new node per prop
   is a review comment.
2. **Share materials.** A new material is a new draw call. Colours come from
   short lists in `content/look/`, never random per piece. Glows are cached
   (`StationFill._glow`; `LookMaterials.glow` makes a new one each call).
3. **Boxes before models.** A prop is a few boxes (a shack is about ten, about
   120 triangles). A model is for what the player looks at up close.
4. **No new shaders in a dressing.** A shader compiles on first use, 60 to
   70 ms on the Mac. Reuse one from `src/systems/look/shaders/` through
   `LookMaterials`. A new surface is a new finish in a shader already
   compiled (the station's rooms: `cruiser_metal` 14 to 32, `StationFill._t`).
5. **Never read a mesh back** from the renderer (`append_from`,
   `surface_get_arrays`, `PrimitiveMesh.get_mesh_arrays`): about 8 ms a mesh
   waiting on the GPU. Build triangles from your own numbers
   (`StationFill._flat`, `LookMeshKit.ring_segment` with a transform).
6. **Draw by distance, from data.** `DrawDistance` gives every mesh under 6 m
   and every light a range from the `draw_distance` block of
   `content/look/world.json` (outdoor, interior, person, orbit). Register a new
   system's root with the town once; do not set ranges by hand. There is no
   occlusion culling, so an interior shows only the floor you are on and the
   ones next to it.
7. **One shadow caster, the sun.** Lamps are glowing materials, or lights with
   `shadow_enabled = false` and a fade distance.

## Building and ticking

8. **Build over ticks** under a ms budget: `StagedBuild`
   (`src/systems/flow/staged_build.gd`) or a `begin` / `step` queue like
   `StationFill`, a couple of ms a physics tick, so a big place loads over
   frames instead of in one hitch.
9. **Few colliders.** Only what you would walk into gets a box, all in one body
   per place. Colliders and people are built before the `use_look` branch; the
   branch only dresses them ("What can not change" 5). The station fill does
   not do this yet (#543).
10. **Tick by distance.** People sleep past the draw distance and think less
    often further out (puppets, not NPCs, until a fight); at most a set number
    of bodies are posed a frame, nearest first. Per-tick code allocates nothing
    and scans no tree: find things once and keep the list.

## Speed

Smooth frames beat finished detail: ground or props that come in late or
coarse while you go fast are fine, a long frame is not. Lifted from the speeder
lag fix (2026-11-25) and issue #574.

11. **Never build what you outrun.** Anything built by position (the 1 m
    ground, a patch, a ring of props) is started only while the player is slow
    enough for it to finish; faster, a half-built one is dropped, and what is
    already there stays until you slow down. The speeds are data:
    `prefetch_speed` (ships) and `speeder_prefetch_speed` (speeders) in
    `content/core/flow/launch_pads.json`.
12. **Per-sample code is the hottest loop there is.** The ground's height
    (`PlanetSphere.elevation`) runs twice for every point of every ground
    patch: hundreds of thousands of times a rebuild, a few hundred every
    physics tick while you move. Whatever it checks (level pads, sinks,
    landmarks) is binned by map cell (`PlanetSphere._flat_grid`), never a scan
    of every one. 51 pads scanned per sample were ~14 ms a tick and ~280 ms
    frames on a boosting speeder. A new kind of pad, rock or dip in it is a
    performance change: time a patch's rows in a probe before and after.
13. **Speed feel is cheap or nothing.** Effects that only sell speed (dust
    streaks, trails, particles) are not added; the camera's FOV kick and the
    boosters' own glow do that job. A new material compiles on first use
    (rule 4), so it would hitch on the first boost.

## Data and proof

14. **Look numbers in `content/look/`, gameplay numbers in `content/core/`.**
    A literal colour or distance in a script is a review comment.
15. **Measure.** Draw calls and primitives from a probe, before and after, in
    the PR. Frame time only as a median over several runs; GPU ms on this Mac
    is noisy, and headless timing is not a render measurement
    ([`performance-traces.md`](performance-traces.md)).
