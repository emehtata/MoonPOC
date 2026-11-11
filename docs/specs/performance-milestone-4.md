# Performance report and terrain architecture (Milestone 4)

Status: Ready
Slug: performance-milestone-4

## Goal

The brief (`docs/init-moon-poc.md`, sections 8, 11 Milestone 4, 13 deliverables 8 and 9) asks for a measured performance report and a documented architecture for future chunked, LOD-based and streamed lunar terrain. Milestone 2 built a fixed 96-chunk cube-sphere from 64 ppd LOLA data (`docs/ARCHITECTURE.md`). This milestone measures that build repeatably, records its limits with real numbers, and designs the next step, without adding runtime features.

## Scope

- A repeatable measurement method and a measurement script.
- `docs/PERFORMANCE.md`: measured values, reproduce commands, dates, geometry limitations.
- `docs/ARCHITECTURE.md`: the chunk/LOD design and the regional data streaming path, replacing the current "Path to chunked terrain" section.

## Non-goals

- LOD, chunk splitting/merging, streaming, threaded mesh builds, or any other new runtime behaviour.
- An in-game FPS overlay or HUD (not asked for; a measurement script is enough).
- Performance optimisation of the existing build.
- Downloading or processing SLDEM2015 or polar grids.
- Milestone 3 work (material, shadows, camera-follows-terrain).

## Stack and constraints

- Godot 4.7.2 pinned by `make setup`, Forward+/Vulkan, GDScript. Rust tool `tools/moon-data/` for data.
- Statistics come only from what Godot provides: `Engine.get_frames_per_second()`, `Performance.get_monitor()` (e.g. `TIME_PROCESS`, `RENDER_TOTAL_DRAW_CALLS_IN_FRAME`, `RENDER_TOTAL_PRIMITIVES_IN_FRAME`, `RENDER_TOTAL_OBJECTS_IN_FRAME`, `RENDER_TEXTURE_MEM_USED`, `RENDER_VIDEO_MEM_USED`), `RenderingServer` frame timing, `Time.get_ticks_usec()`, and mesh array data. No new dependencies.
- Headless runs (`--headless`) use a dummy renderer: render statistics, FPS and GPU frame time are not meaningful there. Those numbers need a window run on the user's display and are **user-run**.
- Camera limits are fixed by `scripts/moon_camera.gd`: `MIN_DISTANCE = 1748.232`, `MAX_DISTANCE = 20000.0`, default `distance = 6000.0` (units = km, measured from the Moon centre).
- **No invented numbers.** Every number in `docs/PERFORMANCE.md` and every number added to `docs/ARCHITECTURE.md` must come from a measurement the implementer (or the user, for user-run items) made with the documented command. Numbers already in `docs/ARCHITECTURE.md` / `docs/VALIDATION.md` may be cited only if re-measured in this milestone or labelled with their original date and source. Constants that follow from the code (e.g. 96 chunks, 65 x 65 vertices, 64 ppd) are not measurements and may be stated.

## Requirements

### Measurement method

- **REQ-1** A measurement script exists outside the shipped scenes (under `tests/` or `tools/`), run with the pinned Godot via a `make` target named `perf`. It loads the existing main scene unchanged; it must not modify `scenes/`, `scripts/moon.gd`, `scripts/moon_camera.gd` or other runtime scripts' behaviour.
- **REQ-2** The script measures at exactly three camera positions, set through the existing camera's `distance`, yaw and pitch, with the Sun at the scene default:
  | Name | distance | yaw, pitch |
  |---|---|---|
  | `orbit_far` | 20000.0 (MAX_DISTANCE) | 0, 0 |
  | `orbit_default` | 6000.0 (default) | 0, 0 |
  | `surface` | 1748.232 (MIN_DISTANCE) | 0, 0 |
- **REQ-3** At each position the script waits 120 rendered frames (warm-up), then samples every frame for 10 seconds of wall-clock time, then moves to the next position.
- **REQ-4** Frame time is recorded per frame as the delta in milliseconds; FPS is reported as frames sampled divided by sampling seconds. For each position the script prints frame count, mean FPS, and frame time mean, median, 95th percentile and maximum in ms.
- **REQ-5** The script runs in two modes: windowed (default, user-run, needs a display) and headless (`--headless`). In headless mode it prints only the statistics listed as headless in REQ-7 and prints one line per render statistic saying it is not available headless, instead of printing a value.
- **REQ-6** The script prints the renderer in use (rendering method and driver, e.g. `forward_plus` / `vulkan`) and the GPU/adapter name (`RenderingServer.get_video_adapter_name()`), Godot version, and CPU core count, before any measurement.

### Statistics

- **REQ-7** The script records each statistic below, obtained as stated:
  | Statistic | How obtained | Mode |
  |---|---|---|
  | FPS, frame time | REQ-4 | windowed (user-run) |
  | Draw calls | `RENDER_TOTAL_DRAW_CALLS_IN_FRAME`, mean over the sample window per position | windowed (user-run) |
  | Primitives | `RENDER_TOTAL_PRIMITIVES_IN_FRAME`, mean per position | windowed (user-run) |
  | Objects drawn | `RENDER_TOTAL_OBJECTS_IN_FRAME`, mean per position | windowed (user-run) |
  | Texture memory | `RENDER_TEXTURE_MEM_USED` and `RENDER_VIDEO_MEM_USED` in MiB, after sampling | windowed (user-run) |
  | Vertex count | sum of vertex array lengths over all chunk meshes | headless and windowed |
  | Triangle count | sum of index count / 3 over all chunk meshes | headless and windowed |
  | Chunk count | number of chunk `MeshInstance3D` nodes | headless and windowed |
  | Terrain build time | the existing `terrain build ms:` line from `scripts/moon.gd`, over 5 runs (min, median, max) | headless |
  | CPU time of `_process` per frame | `TIME_PROCESS` mean per position | windowed (user-run) |
  | Generated data file sizes | byte size of each file under `assets/elevation/` and `assets/textures/lunar_albedo_4096x2048.png` | headless (file system) |
  | Mesh memory estimate | vertex count x bytes per vertex of the arrays actually used (position, normal, UV) + index bytes, stated with the formula | headless |
- **REQ-8** The script reports whether any script in the scene defines terrain work in `_process` or `_physics_process` by stating which nodes have per-frame processing enabled (`is_processing()`, `is_physics_processing()`), so the report can confirm "no per-frame CPU terrain work".

### Report

- **REQ-9** `docs/PERFORMANCE.md` exists and contains, for every statistic of REQ-7: the value(s), the exact command that reproduces it, the date measured, and the machine (from REQ-6).
- **REQ-10** Headless values in `docs/PERFORMANCE.md` are measured by the implementer. User-run values are listed in a table marked "user-run", with an empty value cell and the text `pending user run` until the user supplies them; the implementer must not fill them with estimates.
- **REQ-11** `docs/PERFORMANCE.md` has a section for each brief section 8 topic: mesh subdivision cost, vertex displacement cost, texture memory, draw calls, shader complexity, LOD requirements. Each section cites the measured value(s) it rests on, or states `pending user run`. Shader complexity is described from the material in use (one shared `StandardMaterial3D`, no custom shader, no vertex shader) plus the measured frame time.

### Geometry limitations

- **REQ-12** Geometry limitations are written in `docs/PERFORMANCE.md` (section "Geometry limitations"), not in `docs/ARCHITECTURE.md`. They cover at least: vertex spacing versus height-data cell size, which data level the mesh uses and what detail is lost, the fixed camera minimum distance versus terrain, total vertex/triangle count and memory, build time growth if the grid were refined (stated as the measured time per vertex times the vertex count of the refined grid, labelled as an extrapolation from a measurement), and the effect on the `surface` position (triangle size on screen is not required; on-ground spacing in km is).
- **REQ-13** Every number in the Geometry limitations section is either a measurement from this milestone with its command, a code constant, or arithmetic from those, with the inputs shown.

### Architecture design

- **REQ-14** `docs/ARCHITECTURE.md` section "Path to chunked terrain" is replaced by a section "Chunk, LOD and streaming design" that describes, as a design with no code: a per-face quadtree whose roots are exactly today's 96 chunks (6 faces x 4 x 4, 64 x 64 quads, 65 x 65 vertices each), children splitting 2 x 2 and keeping 64 x 64 quads. The heading `## Path to chunked terrain` is renamed to `## Chunk, LOD and streaming design`. The existing Milestone 2 check in `tests/run_tests.gd` that looks for the old heading is updated by the tester to look for the new heading.
- **REQ-15** The design maps each quadtree depth to a data source, using the existing levels: `lola_height_m_1024x512`, `2048x1024`, `4096x2048`, then 64 ppd `LDEM_64` (23040 x 11520) as the finest global level, then regional higher-resolution tiles. For each depth it states the vertex spacing (from the measured edge range at depth 0, halved per depth) and the data cell size, and names the deepest depth each source supports without oversampling.
- **REQ-16** The design states the split/merge criterion (screen-space error from vertex spacing and camera distance), the per-frame budget concept, off-main-thread mesh building, and the crack handling at level boundaries (skirts or edge stitching; choose one and say why).
- **REQ-17** The design describes the streaming path for high-resolution regional data: tile layout aligned to the cube-face quadtree, the tool that produces tiles (`tools/moon-data/`), how tiles are listed in `moon_data.json` (field names and per-tile checksum, consistent with today's level entries), how a tile is loaded and evicted (cache size expressed as a rule, not a measured number unless measured), and the polar gap of SLDEM2015 (60 S to 60 N coverage) with LOLA polar grids for the caps.
- **REQ-18** The design states the memory and draw-call implications using the REQ-7 per-chunk measurements (per-chunk vertex bytes, one draw call per visible chunk if measured so), not new estimates.

### No runtime change

- **REQ-19** No LOD, streaming, chunk split/merge, or threaded build code is added. `git diff` of this milestone touches only: `docs/PERFORMANCE.md`, `docs/ARCHITECTURE.md`, the measurement script and its `make perf` target, and, if needed, `tests/` files that check the script. Existing tests (`make test`, `make moon-data-test`, `make ephemeris-test`) still pass.

## Acceptance criteria

| REQ | Given | When | Then |
|---|---|---|---|
| 1 | repo after implementation | `make perf` runs, then `git diff --stat scenes/ scripts/` | perf runs; diff for `scenes/` and `scripts/` is empty |
| 2 | `make perf` windowed | output inspected | three blocks named `orbit_far`, `orbit_default`, `surface` with distance 20000.0, 6000.0, 1748.232 |
| 3 | windowed run | per-position output | warm-up 120 frames reported; sample duration between 10.0 and 10.5 s |
| 4 | windowed run | per-position output | frame count, mean FPS, mean/median/p95/max ms all printed as numbers |
| 5 | `make perf` with `--headless` (e.g. `make perf HEADLESS=1`) | output inspected | vertex count, triangle count, chunk count, build times, file sizes printed; each render stat line says not available headless; exit code 0 |
| 6 | any run | first lines | renderer method, driver, adapter name, Godot version, core count printed |
| 7 | headless run | vertex/triangle/chunk counts | numbers printed match the code constants in `docs/ARCHITECTURE.md` (405 600 vertices, 786 432 triangles, 96 chunks) or the difference is explained in PERFORMANCE.md |
| 8 | any run | output | list of nodes with process/physics_process enabled; PERFORMANCE.md states whether any does terrain work |
| 9 | `docs/PERFORMANCE.md` | read | each REQ-7 statistic has value or `pending user run`, command, date, machine |
| 10 | `docs/PERFORMANCE.md` before user run | read | user-run table cells say `pending user run`, no numbers |
| 11 | `docs/PERFORMANCE.md` | read | six section 8 topic headings present, each citing a measured value or `pending user run` |
| 12–13 | `docs/PERFORMANCE.md` "Geometry limitations" | each number checked | traceable to a command output, code constant, or shown arithmetic |
| 14–18 | `docs/ARCHITECTURE.md` | read | "Chunk, LOD and streaming design" present; old "Path to chunked terrain" gone; roots = 96 chunks; depth table with source and spacing; split criterion; crack choice with reason; tile listing fields; polar caps |
| 19 | finished milestone | `git diff --stat`; `make test`, `make moon-data-test`, `make ephemeris-test` | only allowed files changed; all pass |

## Edge cases and errors

- Height data or `moon_data.json` missing: the scene prints its existing ERROR and builds no terrain; the perf script prints that terrain is absent, prints counts as 0, and exits non-zero.
- No display available in windowed mode: Godot fails to open a window; the script must not be reported as having produced user-run values.
- Fewer than 10 s possible (e.g. window closed): the script prints the actual sample duration and frame count; a run shorter than 10 s is not used in the report.
- Build-time variance: the 5 runs are reported as min/median/max, not a single value.

## Assumptions

- A standalone measurement script plus `make perf` satisfies "basic FPS and rendering statistics for testing"; no in-game overlay.
- Camera yaw 0, pitch 0 looks at (0 N, 0 E) per the Milestone 1 orientation; one view direction per distance is enough for this milestone.
- 10 s sample after 120 warm-up frames is enough for stable means.
- Geometry limitations go in `docs/PERFORMANCE.md`; the design goes in `docs/ARCHITECTURE.md` (deliverable 9).
- Milestone 3 remains open and is not part of this spec. The camera minimum stays at 1748.232 for this milestone.

## Open questions

None.

## Revision history

- 2026-11-11: initial spec.
- 2026-11-11 (Revision 2): Milestone 3 stays open and is out of scope (no longer called skipped). REQ-14 now names the heading rename and says the tester updates the old-heading check in `tests/run_tests.gd`.
