# Performance (Milestone 4)

Measured performance of the Milestone 2 terrain (96-chunk cube-sphere, `scripts/moon.gd`). Spec: `docs/specs/performance-milestone-4.md`. 1 unit = 1 km.

## Method

The script `tests/perf.gd` loads `scenes/main.tscn` unchanged and only sets the camera rig's `distance`, `yaw_deg` and `pitch_deg`. It writes nothing to the project.

| Command | Mode | What it prints |
|---|---|---|
| `make perf HEADLESS=1` | headless (dummy renderer) | machine, data file sizes, chunk/vertex/triangle counts, quad side range, mesh memory, nodes with per-frame processing, terrain build time over 5 runs; one "not available headless" line per render statistic |
| `make perf` | windowed (user-run, needs a display) | machine, the same counts, then for each of `orbit_far` (20000.0), `orbit_default` (6000.0), `surface` (1748.232), all at yaw 0, pitch 0: 120 warm-up frames, then 10 s of samples: frame count, mean FPS (frames / sampling seconds), frame time mean/median/p95/max in ms, mean draw calls, primitives, objects drawn, mean `TIME_PROCESS` in ms; after the last position, texture and video memory in MiB |

The windowed run takes 3 x (120 frames + 10 s) plus the terrain build. A run with a sample shorter than 10 s (window closed) must not be used here.

Godot statistics used, all confirmed to exist in Godot 4.7.2: `Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME`, `RENDER_TOTAL_PRIMITIVES_IN_FRAME`, `RENDER_TOTAL_OBJECTS_IN_FRAME`, `RENDER_TEXTURE_MEM_USED`, `RENDER_VIDEO_MEM_USED`, `TIME_PROCESS`, `RenderingServer.get_current_rendering_method()`, `get_current_rendering_driver_name()`, `get_video_adapter_name()`, `RenderingServer.mesh_get_surface()`. Frame time is the wall-clock delta between frames from `Time.get_ticks_usec()`.

## Machine

| Field | Headless run (implementer, 2026-11-11) | Windowed run (user-run) |
|---|---|---|
| CPU | Intel(R) Core(TM) i3-4130 CPU @ 3.40GHz, 4 cores | pending user run |
| Godot | 4.7.2-stable (official) | pending user run |
| Rendering method / driver | `forward_plus` / `vulkan` as configured; headless uses the dummy renderer, so these are not what draws | pending user run |
| Adapter | empty (no GPU in headless) | pending user run |

## Headless values (measured)

Command: `make perf HEADLESS=1`. Date: 2026-11-11. Machine: the headless column above.

| Statistic | Value |
|---|---|
| Chunk count (`MeshInstance3D` under Moon) | 96 |
| Vertex count (sum of vertex array lengths) | 405 600 |
| Index count | 2 359 296 |
| Triangle count (indices / 3) | 786 432 |
| Per chunk | 4225 vertices, 8192 triangles |
| Quad side on the 1737.4 km reference sphere (heights removed) | min 7.538 km, max 10.661 km |
| Terrain build time, 5 runs (`terrain build ms:` from `scripts/moon.gd`) | 964, 964, 965, 965, 971 ms: min 964, median 965, max 971 |
| Mesh memory estimate | 22 416 384 bytes (21.38 MiB) = 405 600 vertices x (12 position + 12 normal + 8 UV) bytes + 2 359 296 indices x 4 bytes |
| Mesh memory estimate per chunk | 233 504 bytes |
| Mesh surface buffers (`RenderingServer.mesh_get_surface`, sum of vertex, attribute and index data) | 16 075 392 bytes (15.33 MiB); per chunk 167 452 bytes |
| `lola_height_m_1024x512.f32` | 2 097 152 bytes |
| `lola_height_m_2048x1024.f32` | 8 388 608 bytes |
| `lola_height_m_4096x2048.f32` | 33 554 432 bytes |
| `moon_data.json` | 6 719 bytes |
| `lunar_albedo_4096x2048.png` | 7 865 389 bytes |

The counts match the code constants in `docs/ARCHITECTURE.md` (405 600 vertices, 786 432 triangles, 96 chunks). The estimate counts the arrays `moon.gd` passes to `add_surface_from_arrays` (float32 vectors, 32-bit indices). The surface buffers are the bytes Godot actually stores for the meshes, which are smaller: per chunk 167 452 = 24 576 indices x 2 bytes + 4225 vertices x 28 bytes, so Godot stores 16-bit indices and 28 bytes per vertex instead of 4 + 32. The GPU-side size is not measured here.

### Nodes with per-frame processing

Printed by `make perf HEADLESS=1`, 2026-11-11:

| Node | `_process` | `_physics_process` | Script | Work per frame |
|---|---|---|---|---|
| `/root/Main/CameraRig` | yes | no | `scripts/moon_camera.gd` | sets the camera transform from distance, yaw, pitch |
| `/root/Main/Sun` | yes | no | `scripts/sun_controller.gd` | reads lines from the Sun helper's stdout |
| `/root/Main/SunDisc` | yes | no | `scripts/sun_disc.gd` | places and scales the Sun disc |

The Moon node and its 96 chunks do no per-frame processing. **There is no per-frame CPU terrain work.**

## User-run values

Command: `make perf` on the user's display. Date and machine: pending user run. Values stay empty until the user supplies them.

| Statistic (user-run) | `orbit_far` | `orbit_default` | `surface` |
|---|---|---|---|
| Frames sampled / sample seconds | pending user run | pending user run | pending user run |
| Mean FPS | pending user run | pending user run | pending user run |
| Frame time mean / median / p95 / max (ms) | pending user run | pending user run | pending user run |
| Draw calls (mean) | pending user run | pending user run | pending user run |
| Primitives (mean) | pending user run | pending user run | pending user run |
| Objects drawn (mean) | pending user run | pending user run | pending user run |
| CPU time of `_process` per frame (`TIME_PROCESS` mean, ms) | pending user run | pending user run | pending user run |

| Statistic (user-run, after sampling) | Value |
|---|---|
| Texture memory (`RENDER_TEXTURE_MEM_USED`, MiB) | pending user run |
| Video memory (`RENDER_VIDEO_MEM_USED`, MiB) | pending user run |

## Mesh subdivision cost

The mesh has 96 chunks of 64 x 64 quads: 405 600 vertices and 786 432 triangles (measured, headless). The whole mesh is built once at startup in 964 to 971 ms over 5 runs (median 965 ms). That is 965 ms / 405 600 vertices = 2.379 µs per vertex at the median. Primitives per frame at each camera position: pending user run.

## Vertex displacement cost

Displacement is done on the CPU during the startup build (bilinear sample of the 2048 x 1024 level per vertex), so it is part of the 965 ms median build time. It costs nothing per frame: no node does terrain work in `_process` or `_physics_process` (see the node list), and there is no vertex shader. The build time is not split into sampling and the rest; only the total is measured.

## Texture memory

Files on disk: the albedo PNG is 7 865 389 bytes; the three height levels are 2 097 152, 8 388 608 and 33 554 432 bytes. Godot reads only the 2048 x 1024 level and keeps it in a `PackedFloat32Array` in `scripts/moon.gd`. The GPU texture memory of the albedo and total video memory: pending user run (`RENDER_TEXTURE_MEM_USED`, `RENDER_VIDEO_MEM_USED`).

## Draw calls

96 chunk meshes, each with one surface and the same material (measured: 96 `MeshInstance3D` nodes). Draw calls and objects drawn per frame at each position: pending user run. How many chunks frustum culling removes at `surface` is also pending user run (objects drawn).

## Shader complexity

All 96 chunks use one shared `ShaderMaterial` with `shaders/lunar_surface.gdshader` (Milestone 3): a Lommel-Seeliger `light()` function, `specular_disabled` and `ambient_light_disabled`, two texture reads per fragment (albedo, anisotropic mipmapped; normal map, mipmapped) and an ENU-to-world rotation. The vertex stage only passes the position on; displacement is in the vertex positions. Frame time with this shader and the shadows below at the three `make perf` positions: pending user run.

### Normal map memory (Milestone 3)

- File: `assets/textures/lunar_normal_enu_4096x2048.png`, 10 108 231 bytes, imported lossless with mipmaps.
- GPU estimate (arithmetic, not measured): 4096 x 2048 x 4 bytes = 32 MiB, plus 1/3 for mipmaps = 42.7 MiB. Measured texture memory: pending user run.

### Shadow settings (Milestone 3, REQ-5, read from the Sun node headless)

| Setting | Value |
|---|---|
| `shadow_enabled` | true |
| `directional_shadow_mode` | 2 (`SHADOW_PARALLEL_4_SPLITS`) |
| `directional_shadow_split_1` / `_2` / `_3` | 0.1 / 0.2 / 0.5 |
| `directional_shadow_blend_splits` | true |
| `light_angular_distance` | 0.0 |
| `shadow_bias` | 0.1 (Godot default) |
| `shadow_normal_bias` | 2.0 (Godot default) |
| `rendering/lights_and_shadows/directional_shadow/size` | 4096 |
| `directional_shadow_max_distance` | set each frame by `scripts/moon_camera.gd` to S(D_c) (REQ-6) |

Shadow cost in frame time: pending user run.

## LOD requirements

Today there is no LOD: every frame the GPU gets all 786 432 triangles that survive culling, at a quad side of 7.538 to 10.661 km whatever the camera distance. The build is 965 ms (median) for one level on one thread. A quadtree LOD (design in `docs/ARCHITECTURE.md`, "Chunk, LOD and streaming design") is needed before finer data can be shown, because a finer uniform grid grows the build time and mesh memory with the vertex count (see Geometry limitations). Whether the current grid already limits the frame rate: pending user run.

## Geometry limitations

All numbers below come from `make perf HEADLESS=1` (2026-11-11), from code constants, or from arithmetic with the inputs shown. Data cell sizes are at the equator: cell = 2 x pi x 1737.4 km / width (1737.4 km is the reference radius in `moon_data.json`); in longitude the cells shrink toward the poles by cos(latitude).

- **Vertex spacing versus height cell size.** Quad sides are 7.538 to 10.661 km (measured). The level used, 2048 x 1024, has cells of 2 x pi x 1737.4 / 2048 = 5.330 km. The mesh samples the data at 1.4 to 2.0 cells per quad side (7.538 / 5.330 = 1.41, 10.661 / 5.330 = 2.00), so it is the coarsest of the three levels that is still finer than every quad. The 1024 x 512 level (10.661 km cells) would be coarser than the shortest quads.
- **Data level used and detail lost.** The mesh uses 2048 x 1024 (`HEIGHT_LEVEL_WIDTH`, `HEIGHT_LEVEL_HEIGHT` in `scripts/moon.gd`). The source, LDEM_64 at 64 pixels per degree (23 040 x 11 520), has cells of 2 x pi x 1737.4 / 23040 = 0.474 km. The 2048 level holds 23040 / 2048 = 11.25 source cells per cell in each direction, and the mesh shows at best one height per 7.538 km. Features smaller than about two quads (2 x 7.538 = 15.1 km) cannot be shown as relief; craters a few km across are seen only in the albedo texture.
- **Fixed camera minimum versus terrain.** `MIN_DISTANCE = 1748.232` from the Moon centre (`scripts/moon_camera.gd`): the highest terrain radius 1747.732 km plus 0.5 km, so it holds everywhere. Above the reference sphere that is 1748.232 - 1737.4 = 10.832 km. Over lower terrain the camera stays further away; it cannot follow the ground.
- **Total size and memory.** 405 600 vertices, 786 432 triangles; mesh arrays 22 416 384 bytes (21.38 MiB, formula in the headless table), stored surface buffers 16 075 392 bytes (15.33 MiB).
- **Build time if the grid were refined.** Extrapolation from the measurement, assuming time grows linearly with vertex count: 965 ms / 405 600 = 2.379 µs per vertex (median). Splitting every chunk once (depth 1 everywhere, 384 chunks x 4225 = 1 622 400 vertices): 2.379 µs x 1 622 400 = 3 860 ms. A uniform grid at depth 3, the deepest depth LDEM_64 supports (6144 chunks x 4225 = 25 958 400 vertices): 2.379 µs x 25 958 400 = 61 760 ms. Mesh arrays grow by the same factors: 4 x 21.38 = 85.5 MiB and 64 x 21.38 = 1368 MiB. These are extrapolations, not measurements.
- **Effect at the `surface` position.** At 1748.232 the camera is 10.832 km above the reference sphere, while the on-ground vertex spacing is 7.538 to 10.661 km: the spacing is about as large as the camera height, so the nearby ground is a few large flat triangles. Frame time and primitives at `surface`: pending user run.
