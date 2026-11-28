# Repeatable performance traces

Issue #125 adds a repeatable route capture; it does not turn headless timing into a rendering benchmark or invent a target-hardware threshold.

## Capture the same routes

Run from the repository root. The trace scripts use the same physics-frame routes and warm up the scene before collecting samples.

Headless logic control (not a GPU measurement; leave frame pacing uncapped for wall-time samples):

~~~sh
DUNE_PERF_OUT=res://test_results/m14-headless.json godot --headless --path . -s res://scenes/m14_flight_trace.gd
DUNE_PERF_OUT=res://test_results/planets-headless.json godot --headless --path . -s res://scenes/planets_trace.gd
~~~

Rendered route capture with the full look enabled (do not add --headless or --fixed-fps):

~~~sh
DUNE_PERF_VISUALS=1 DUNE_PERF_OUT=res://test_results/m14-rendered.json godot --path . -s res://scenes/m14_flight_trace.gd
DUNE_PERF_VISUALS=1 DUNE_PERF_OUT=res://test_results/planets-rendered.json DUNE_PERF_SCREENSHOT=res://test_results/stationary-hero.png godot --path . -s res://scenes/planets_trace.gd
~~~

The JSON reports nearest-rank frame-time p50/p95/p99/max, Godot process and physics-process CPU time distributions, per-phase frame-time summaries, scene-ready wall time, and terrain metrics when the scene exposes them. Terrain metrics include far patches visible/culled, queued terrain jobs, far-build and worker-wait wall time, and main-thread mesh creation/submission time. Mesh submission timing is CPU-side work; it is not GPU completion time. GPU frame time is recorded as null because these in-engine samples do not provide it.

The planets trace captures the same stationary opening frame when DUNE_PERF_SCREENSHOT is set, with screenshot readback excluded from the timed samples. Save that image with the baseline and compare it after visual changes; the trace does not claim an automated perceptual image-diff.

## Coming down: the descent trace

`scenes/descent_trace.tscn` flies open space → a planet's bubble → 30 m over the
dunes → a 60 s low pass → climb out, rendered, and lists every frame over the
budget (33 ms, 50 ms for the switch) with what ran on it. Run it with a scratch
`HOME` so the real saves are never touched, and copy the real `save*.json`,
`settings/`, `llm_config.json`, `model_use.json`, `hull_fits.json`,
`shader_cache/` and `vulkan/` into it first (no save means the first-start
menu).

~~~sh
DESCENT_ROUTES=port_desert godot --rendering-driver vulkan --path . res://scenes/descent_trace.tscn
~~~

- **Warm (default):** every route's planet is built once first, a session that
  has been everywhere.
- **From the gas giant, home loading fresh (issue #714):**
  `DESCENT_WARM=ringed_giant DESCENT_OUT_M=6000`. Only the giant is warmed, and
  the ship starts 6 km outside home's bubble, so what the approach starts on
  workers (`SpaceTravel._prepare`) has time to run.
- `DESCENT_COLD=1` warms nothing (a fresh session).
- `DESCENT_PIECES=15` names every piece of a sliced step over 15 ms
  (`StagedBuild.piece_watch_ms`) and the kinds of node added on each slow frame.
- `DESCENT_KINDS=1` records every kind of material each route's scene drew (a
  material's shader-changing settings on a mesh's vertex format) to
  `user://warm_kinds.json`. Copy it to `content/look/warm_kinds.json` and
  `ShaderWarmup` compiles them one a frame from `prepare_m` out in open space.
  Record again after adding a planet or a new look. Recording walks the whole
  tree: those frames are slow, so don't read a recording run's numbers.

## Comparing results

- Keep the same route, machine, driver, Godot version, warm-up, display resolution, and run conditions before and after a change.
- Compare headless JSON only with headless JSON. Use rendered captures for CPU/render submission and visual review; GPU time still requires an external GPU profiler.
- Record the GPU model and driver alongside rendered JSON when sharing results; the trace records OS and Godot version but does not guess hardware identity.
- Collect baseline and post-change files on the target machine before setting thresholds. A single constrained-runner result is not an acceptance threshold.
- scripts/ci.sh remains unchanged. Its headless 50 ms assertion is not evidence of rendered CPU/GPU performance.

No baseline values are committed by this change because this environment did not run Godot or the target hardware.
