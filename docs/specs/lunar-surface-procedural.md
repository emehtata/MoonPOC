# Procedural lunar surface

Status: Ready
Slug: lunar-surface-procedural

## Goal

The brief `docs/moon-geo.md` asks for a deterministic, multiscale lunar surface that still looks right from orbit down to about 10 cm above the ground. Today the Moon is a fixed 96-chunk cube-sphere. Its vertices are 7.5 to 10.7 km apart, and the camera cannot go below 10.8 km altitude (`docs/PERFORMANCE.md`, "Geometry limitations"). This spec keeps the real LOLA elevation wherever it exists. It adds procedural craters, rocks, fine relief and a regolith material below the LOLA resolution, and streams all of it through the cube-face quadtree already designed in `docs/ARCHITECTURE.md`. The work is split into seven phases, P1 to P7, and each phase can be built and tested on its own.

## Scope

- P1: foundation. Floating origin, coordinate and seed rules, a native terrain library, LOLA 64 ppd tiles, the height query, a first-person camera and a scenario loader.
- P2: geology. Procedural craters and how they interact, region classes, and preservation of the LOLA heights.
- P3: surface geometry. Rocks and boulders, small-scale relief, and the distribution rules.
- P4: materials and lighting. Regolith and rock materials, and shadows at close range.
- P5: LOD and streaming. A quadtree down to depth 18, geomorphing, skirts, asynchronous builds, a cache and cancellation.
- P6: optimisation. Measurements, budgets and quality levels.
- P7: validation and documentation. All 11 scenarios at all 6 camera distances, the benchmark and the deliverables.

## Non-goals

- Gameplay, vehicles, collision and physics.
- SLDEM2015 or any other 512 ppd regional data. The finest elevation used is LDEM_64. The regional-tile path in `docs/ARCHITECTURE.md` stays a future option.
- Changes to the live UTC Sun, the Sun disc, Earth, clouds, the albedo or normal-map files, or the Lommel-Seeliger law (M3 REQ-2).
- Procedural changes to any height on a scale that LOLA resolves (REQ-9).
- Ambient light, Earthshine, sky and fog. M1 REQ-14 stays in force.
- Hapke photometry, opposition surge and phase-dependent parameters (M3 A1).
- Craters larger than 400 m, which LOLA and the albedo already show. Secondary-crater rays.
- A GPU compute-shader path.

## Stack and constraints

- Godot 4.7.2, Forward+/Vulkan, GDScript for application logic. 1 unit = 1 km. The orientation follows M1 REQ-7.
- Rust for heavy computation. Offline work goes in `tools/moon-data/`. Runtime terrain generation goes in a new Rust GDExtension crate, `native/lunar-terrain/`, whose only new dependency is the `godot` crate (gdext). No Python. No other new crates beyond those M2 and M3 already allow.
- Elevation source: `data/raw/lola_ldem_64/LDEM_64.IMG`, 23040 x 11520 LSB int16, height = DN x 0.5 m above 1 737 400 m (from the label). A cell is 0.474 km at the equator. Note: the request said "about 1.8 km cells", but 64 ppd is 0.474 km per cell. `assets/elevation/` currently holds only the 4096 x 2048 and coarser levels.
- Earlier specs stay in force except where a REQ below says otherwise. The REQ-41 table lists every rule this spec replaces.

## Design decisions

| # | Decision | Reason |
|---|---|---|
| D1 | Procedural layers apply only below the LOLA scale. LOLA is interpolated with Catmull-Rom at quadtree depth 2 and deeper, which passes exactly through every post. Procedural craters are 0.5 m to 400 m across and mass-balanced: rim and ejecta volume equals bowl volume. Fine relief is zero-mean noise with wavelengths of 1 cm to 200 m | LOLA cannot resolve features under about 2 cells (0.95 km). Zero-mean layers leave the cell-scale heights unchanged (REQ-9). Catmull-Rom has no slope creases every 474 m, which bilinear would show at ground level |
| D2 | Determinism comes from a pure 64-bit integer hash `H(world_seed, stream_id, level, ix, iy, iz, n)`. Each feature category has its own `stream_id`: craters 1, rocks 2, relief 3, material 4. Features live in a 3D Moon-fixed lattice per size level, with cell size `s_k`. A cell holds features only where its candidate point lies within `s_k/2` of the reference sphere. The point is then projected onto the sphere. The stable feature ID is the tuple (stream, level, ix, iy, iz, n) | A 3D lattice has no cube-face edges or poles, so a feature never needs a face-to-face hand-off. A query reads only the 3x3x3 cells around a point, so the result does not depend on chunk order, threads or history |
| D3 | Rocks are made of 32 base meshes per category, generated from the seed: a convex hull of jittered points, cut by 2 to 4 random planes to give fractures, each with 3 mesh LODs. Large-class meshes differ: 128 jittered points on an ellipsoid with axis ratio longest/shortest 1.3 to 1.6, cut by exactly 2 planes, each removing at most 15 % of the axis it cuts along. Rocks are drawn with one `MultiMeshInstance3D` per chunk per base mesh. Each instance gets a random rotation and a non-uniform scale of 0.6 to 1.4 per axis (large class: 0.9 to 1.1 per axis) | One object per rock is forbidden by the brief. 32 meshes x random scale and rotation hides repetition. Instanced draw calls are bounded per chunk |
| D4 | Close-range geometry comes from the same quadtree, extended to depth 18 (vertex spacing 2.9 to 4.1 cm). A procedural layer is sampled at a node only if its shortest wavelength is at least 2 x that node's vertex spacing | Brief section 10 asks for maximum detail at 0 to 10 m. Depth 13 nodes are 59 to 83 m across, which matches the brief's 64 m chunk. The wavelength rule band-limits each LOD level and avoids aliasing |
| D5 | LOD: the quadtree roots are the existing 96 chunks, with a screen-space-error split and merge. Cracks are hidden by skirts (`docs/ARCHITECTURE.md`). Popping is removed by vertex-shader geomorphing toward the parent surface | This reuses the documented design. Geomorphing needs the shader to write `VERTEX`, which REQ-30 permits |
| D6 | A floating origin is used below 100 km altitude. The world root is shifted whenever the camera moves more than 1 km from the origin. Vertices are stored relative to their chunk's centre. Above 100 km the Moon stays at identity | Float32 at 1737 km has a step of 12 cm, which is useless for cm detail. A double-precision engine would replace the pinned Godot binary |
| D7 | The region class is a weight `m` in [0, 1] (1 = mare), taken from the brightness of the albedo texture. It scales crater density and rock density | A documented simplification. It uses real data and needs no new dataset |
| D9 | Fly mode renders with two cameras that share one transform every frame. The **near camera** (near 1e-6 km, far 20 km) has cull mask 3, so it draws the terrain layer (layer 2: quadtree terrain chunks, rocks and procedural craters) plus layer 1. Reason: with the terrain layer alone, the terrain renders black under the Sun in the near camera. Earth, the Sun disc and the clouds lie beyond its 20 km far plane, so it does not draw them. The **far camera** (near 0.05 km, far 440000 km, the orbit values) draws every layer: the Moon, Earth, the Sun disc and clouds, and the terrain too. The far camera renders to the main viewport. The near camera renders to a full-window `SubViewport` that shares the main `World3D` and has a transparent background. That SubViewport is drawn over the main viewport, so near pixels replace far pixels wherever the near camera drew something | Godot's light culler fails at a near-to-far ratio of about 4e11 (create_frustum_points errors), and errors were measured not to appear at 2.2e7 or less. Hiding any single node does not stop them. Each camera is culled separately with its own frustum: the near camera has a ratio of 2e7 and the far camera 8.8e6. 20 km covers the horizon at 1.7 m (about 2.4 km) with margin for flying up to about 100 m (horizon about 18.6 km). The overlay can never wrongly cover a far-layer object, because the only far-only objects (Earth, the Sun disc, clouds) are much further away than 20 km. Godot 4 has one active camera per viewport and no camera stacking, so a second viewport is the only built-in way. It needs no new dependency |
| D8 | Microscopic detail (Scale D) is done only in the shader: grain normals and roughness. Albedo variation is multiplicative, at most ±5 %, with a mean of 1.0 over every 1 m patch | The texture rule is unchanged on average, and the brief's "subtle colour variation" is met |

## Requirements

### Phase 1: foundation

- **REQ-1** `make moon-data` also writes the LDEM_64 heights into `assets/elevation/ldem64/` as 72 tiles of 30° x 30° (1920 x 1920 int16 LE, the source DN unchanged). Each tile has an entry in `moon_data.json` under `ldem64_tiles` with: path, lat/lon range, width, height, data_type `i16`, scale 0.5, units m, grid convention (M2 REQ-8), and SHA-256. Two runs give byte-identical files.
- **REQ-2** The runtime library `native/lunar-terrain/` is built by `make native` and loaded as a GDExtension. Its height query, `height_m(lat, lon, depth)`, returns the LOLA interpolant: bilinear on the M2 levels at depths 0 and 1, and Catmull-Rom on the LDEM_64 tiles at depth 2 and deeper, plus the procedural layers (D1, D4). A tile is used only after its size and SHA-256 have been checked. If a tile fails the check, one ERROR line names it and the nodes inside it are not split below depth 1.
- **REQ-3** Determinism: with seed S, `height_m`, the crater list and the rock list for a region return bit-identical results across 2 runs, 1 or 4 worker threads, and 2 different query orders.
- **REQ-4** Floating origin as in D6. A rebase changes no rendered world position by more than 1e-6 km. Above 100 km altitude the Moon's global transform is identity.
- **REQ-5** First-person camera. Key `F` toggles between the existing orbit camera (unchanged) and a fly camera. Fly camera controls:
  - mouse look at 0.2°/px, pitch limited to ±89°;
  - WASD to move, Q/E to go down/up, at speed `v = clamp(2 x height above ground, 0.05 m/s, 2000 m/s)`;
  - the wheel multiplies v by 1.25 or 0.8 per notch.
  The camera stays at least 5 cm above the generated surface. It enters at the orbit camera's position and view.
- **REQ-6** Fly-mode cameras as in D9:
  - near camera: near 1e-6 km, far 20 km, cull mask 3 (terrain layer 2 plus layer 1). Reason: terrain alone renders black under the Sun in the near camera. Earth, the Sun disc and the clouds are beyond 20 km, so it does not draw them;
  - far camera: near 0.05 km, far 440000 km, draws all layers;
  - both cameras have the same global transform and the same vertical FOV in every rendered frame;
  - the near SubViewport is always the size of the window and is shown only in fly mode. In orbit mode it does not render;
  - the orbit camera, its near and far values and its view are unchanged. When F enters fly mode, the first fly frame shows the same position as the last orbit frame, and a view direction that differs from it by at most 1°. The difference comes from the fly camera's ±89° pitch cap (REQ-5); the user accepted it. When F leaves fly mode, the orbit camera shows the view it had when fly mode was entered.
  No camera in either mode has a far-to-near ratio above 2.2e7.
- **REQ-7** `make scenario N=<1..11> CAM=<orbit|high|ground|1m|10cm|rock>` loads the main scene with the seed, point and camera from the Scenario table. It sets the Sun as stated there (stopping the live Sun only as a test step, as M3 REQ-20 does), and stays open. `HEADLESS=1` prints the sampled heights and feature counts and exits 0.
  - **REQ-7a** Sun-angle override. `make scenario` takes an optional `SUN_EL=<degrees>`, from −90 to 90. The same script (`scripts/scenario.gd -- <N> <CAM> [<sun_el>]`) takes it as an optional third argument. When given, it replaces the scenario's Sun elevation; the azimuth stays the scenario's value. A value outside −90 to 90 prints one ERROR line and exits 2. Acceptance: `N=7 CAM=ground SUN_EL=5`, read the Sun headless: local elevation 5° ±0.01, azimuth 90° ±0.01. An optional fourth argument `<pt>` (`-- <N> <CAM> <sun_el> <pt>`) picks the scenario point by 1-based index; default 1.

### Phase 2: elevation and geology

- **REQ-8** Craters are placed per D2 at size levels with diameters from 0.5 m to 400 m. The cumulative number of craters per km² with diameter at least D follows `N(≥D) = c x D^-b`, with c and b set per region class (defaults in A3). Within one size level, the number of craters in a cell is Poisson-distributed.
- **REQ-9** DEM preservation. At depth 2 and deeper, the procedural height offset averaged over any 2 x 2 km block has |mean| ≤ 1 m. At every LDEM_64 post, the height with procedural layers turned off equals DN x 0.5 within 0.01 m. At depth 0, vertex positions equal the M2 positions (M2 REQ-25 still passes).
- **REQ-10** Crater profile. A crater has a bowl with depth/diameter ratio `k_d`, a raised rim of height `k_r x D` at radius D/2, and an ejecta blanket that falls off as `(r/R)^-3` out to 2.5 R. The rim radius varies with azimuth by ±`k_i` (smooth noise with 6 to 12 lobes). Each profile integrates to 0 over its support within 1 % of the bowl volume.
- **REQ-11** Degradation. Each crater draws an age `a` in [0, 1]. Step 1: rim height and bowl depth are multiplied by `(1 − 0.8a)`. Step 2, applied after step 1: the profile is smoothed with a radius of `0.2 x a x D`. The smoothing is a separate step and has its own acceptance row.
- **REQ-12** Interactions. Craters combine in age order: a younger crater replaces, inside its rim, the height that older craters gave there, and adds its ejecta on top. Small craters therefore appear inside large ones, and a young crater cuts through older rims.
- **REQ-13** Region weighting. Crater and rock densities are scaled by region weight m (D7): density = highland value x (1 − m) + mare value x m.

### Phase 3: surface geometry

- **REQ-14** Rock categories with configurable ranges (defaults): fine debris below 2 cm (shader only, REQ-24), small 2 to 20 cm, medium 20 cm to 2 m, large 2 to 20 m. Rocks are placed per D2 in their own stream.
- **REQ-15** Rock shapes as in D3. No rock is a scaled sphere: for each base mesh, the ratio of the longest to the shortest axis of its bounding box is at least 1.3, and the hull has at least 2 planar cut faces. Large class only (compact boulders; a faceted but compact silhouette is accepted, as in S3 and S7): the hull is built from 128 points, the cut faces together cover at most 25 % of the hull surface area, and after instance scale the shortest-to-longest extent ratio of every large rock is at least 0.5.
- **REQ-16** Context. Rock density per m² is multiplied by:
  - 4 on a crater rim and ejecta within 1.5 R, for craters with age a < 0.3;
  - 1 + 3 x slope/30° for slopes up to 30°;
  - the region factor (REQ-13), with the smooth-mare value 0.25 of the highland value.
- **REQ-17** Grounding. Each rock is sunk by 20 to 40 % of its height below the lowest terrain sample of its footprint. At 8 footprint perimeter points, the terrain is at or above the rock's lowest vertex (no gaps), and no rock is buried more than 60 % of its height.
- **REQ-18** Small-scale relief: zero-mean fractal noise over wavelengths of 1 cm to 200 m, applied as geometry under D4, with an RMS height for each octave of wavelength λ of `k_s x λ` (default in A3).
- **REQ-19** Instancing as in D3. The number of `MeshInstance3D` or `MultiMeshInstance3D` nodes for rocks is at most 32 x categories x resident chunks. No rock is its own node.
- **REQ-20** Rocks within 200 m cast shadows. Medium and large rocks cast shadows at any distance at which they are drawn.

### Phase 4: materials and lighting

- **REQ-21** Regolith and rocks use the M3 Lommel-Seeliger `light()` with no specular and no ambient (M3 REQ-2, REQ-3).
- **REQ-22** The base albedo is the existing texture. Detail albedo follows D8.
- **REQ-23** Rocks use the same light law. Their albedo is the local texture albedo x a factor in [1.0, 1.3] per rock, from the material stream. Rock material and regolith blend over the lowest 10 % of each rock's height.
- **REQ-24** Fine detail in the shader: a grain normal (wavelengths 1 mm to 2 cm) that fades to zero beyond 20 m from the camera. Its coordinates are reduced per chunk so they are precise to at least 0.1 mm everywhere. The shader samples no new texture larger than 1024² in total.
- **REQ-25** Shadows. Below 10 km altitude, the directional shadow max distance keeps M3 REQ-6's S(D). The split boundaries are set to 0.02 km, 0.2 km and 2 km, which gives about 1 cm texels in the first split. Above 10 km, M3 REQ-5 and REQ-6 are unchanged.

### Phase 5: LOD and streaming

- **REQ-26** Quadtree as in `docs/ARCHITECTURE.md`, with depth 0 to 18 and roots equal to the 96 chunks. A node splits when its screen error is more than 2 px (High), merges when it is below 1.4 px, and stops at depth 18.
- **REQ-27** Asynchronous builds. Height, normals, skirts and rock placement for a node run on worker threads in the native library. The main thread does only resource creation and `add_child`. Main-thread resource time (node creation, shader and position set-up, `add_child`, `queue_free` and other resource work; not selection or `_plan`) is ≤ 2 ms per frame. The same rule applies to the settle (camera held still at 1.7 m above the surface) and to the fly path: in each, at most 0.1 % of frames may exceed 2 ms, and no frame may exceed 30 ms. There is no stricter single-node 2 ms check. These checks run on the 2 minute run (`FLY_PATH_SECONDS=120`), not on the default 60 s `make test`. The old node stays visible until its replacement is ready.
- **REQ-28** No duplicate builds: a node already queued or resident is not queued again. A queued build whose node is no longer wanted is cancelled before it creates resources.
- **REQ-29** Cache. Every resident node and every LDEM_64 tile is held in an LRU cache with a node limit and a byte limit set per quality level (REQ-34). Eviction frees the node's GPU resources. Memory stays bounded during a 2 minute fly path.
- **REQ-30** Seams and popping. Skirts on every node. The vertex shader geomorphs each vertex between the parent-interpolated height and the node's own height. The morph weight w (1 = parent shape, 0 = own shape) depends on the parent's screen error, taken as 2 x the node's own screen error: w = 1 when the parent error is 2 px (the moment the parent splits, so the new node starts in the parent's shape and nothing pops), w falls linearly, and w = 0 when the parent error is 2.6 px or more. In node terms: w = clamp((2.6 - 2 x own_err) / 0.6, 0, 1). This replaces M3 REQ-1's "no `VERTEX`". Shared edges at the same depth match within the edge tolerance tol(d) = max(1e-6 km, 1e-4 x the node's vertex spacing at depth d). This is 1e-6 km at depths 11 to 18 (spacing below 10 m) and grows with node size above that, for example about 1e-3 km at depth 0 (spacing about 10 km); float32 node-relative vertices are far inside it at every depth.

### Phase 6: optimisation

- **REQ-31** `make perf` adds the fly scenarios 1, 5 and 11 at CAM=ground and 1m. It reports: FPS, frame time (mean, median, p95, max), draw calls, primitives, video memory, process memory, node build time (mean and p95), nodes resident, and nodes queued.
- **REQ-32** Target (user-run): at Medium quality and 1920 x 1080, p95 frame time ≤ 33.3 ms and max ≤ 100 ms in those scenarios.
- **REQ-33** Every optimisation that removes visible detail cites a measured `make perf` difference in `docs/PERFORMANCE.md`.
- **REQ-34** Quality levels Low, Medium and High. They set the split threshold (4, 3 and 2 px), the rock draw distances, the cache limits and the maximum depth (16, 17 and 18). Medium is the default.

### Phase 7: validation and documentation

- **REQ-35** All 11 scenarios run at all 6 camera distances. Each shot is a user-run visual check against the inspection list in brief section 14, reported as `pending user check` until the user has checked it.
- **REQ-36** `make test` covers every automated row in the acceptance table.
- **REQ-37** `docs/ARCHITECTURE.md` describes the procedural algorithms, the configuration, the materials and shaders, the floating origin and the quadtree.
- **REQ-38** `docs/DATA_SOURCES.md` adds the LDEM_64 tiles (source, SHA-256, licence as already recorded for LDEM_64), states that no external rock or texture assets are used, and lists the References-to-check list.
- **REQ-39** A known-limitations section labels each feature implemented, partial, experimental or not implemented, and lists the remaining technical debt.
- **REQ-40** Earlier test suites still pass: `make test`, `make moon-data-test`, `make ephemeris-test`.
- **REQ-41** Replaced rules: M3 REQ-1 "no VERTEX" (by REQ-30), M3 REQ-5 split values below 10 km (by REQ-25), M1 REQ-20 and M3's near 0.01 in fly mode only (by REQ-6), M1 REQ-7's "Moon at identity" below 100 km (by REQ-4). Everything else stays.

## Scenario table

Seeds and points are fixed. "Pick" rules are deterministic searches on the generated data.

| N | Name | Seed | Point (lat, lon E) | Sun elev / az (local) | Pick |
|---|---|---|---|---|---|
| 1 | Flat plains | 1 | 0.674 N, 23.473 E (Apollo 11 site) | 10° / 90° | — |
| 2 | Dense small craters | 2 | 8.973 S, 15.500 E (Apollo 16 site) | 10° / 90° | — |
| 3 | Large impact crater | 3 | 43.31 S, 348.64 E (Tycho) | 5° / 90° | — |
| 4 | Overlapping craters | 4 | 8.973 S, 15.500 E, crater density x3 | 15° / 270° | — |
| 5 | Rocky terrain | 5 | 0.674 N, 23.473 E | 10° / 90° | rim of the largest crater with a < 0.3 within 1 km |
| 6 | Large boulders | 6 | 0.674 N, 23.473 E | 8° / 90° | largest rock within 500 m |
| 7 | Rim and interior | 7 | 0.674 N, 23.473 E | 15° / 90° | largest crater ≥ 100 m within 1 km, its rim |
| 8 | Steep terrain | 8 | 43.24 S, 347.34 E (Tycho west wall) | 20° / 90° | — |
| 9 | DEM-to-procedural | 9 | 26.13 N, 3.63 E (Hadley Rille) | 10° / 90° | — |
| 10 | Chunk boundaries | 10 | 0 N, 45 E (face edge) and 35.264 N, 45 E (cube corner) | 10° / 90° | — |
| 11 | Extreme close | 11 | 0.674 N, 23.473 E | 10° / 90° | — |

Camera distances: orbit = distance 6000. high = 50 km altitude. ground = 1.7 m. 1m = 1 m. 10cm = 0.1 m. rock = 0.3 m from the surface of the picked or nearest medium rock. All are above the generated surface and look toward the horizon at pitch −20°. "high" looks straight down.

## Screenshots

The screenshot agent takes and judges these images by the procedure in `.claude/skills/screenshot/SKILL.md`. It runs `scripts/scenario.gd -- <N> <CAM> [<sun_el> [<pt>]]` (REQ-7, REQ-7a) windowed, with the scenario's seed and point. The Sun azimuth is always the scenario's value. Cameras are as defined under the Scenario table, at Medium quality.

An entry passes only if:
- the agent's pass criteria hold in every listed image, and
- the same run logs 0 `create_frustum_points` and 0 ERROR lines.

The "User part" column lists what needs the user's own judgement. It stays `pending user check` and is not counted as passed. The numeric parts of the same REQs are checked by the automated rows in the acceptance table.

| # | Name | Scenario, CAM, sun_el | Sun elev / az | Must show | Pass (screenshot agent) | User part | REQ |
|---|---|---|---|---|---|---|---|
| S1 | Rock field on a fresh rim | 5 ground; 5 1m | 10° / 90° | rocks of the small and medium classes on and around the picked rim | rocks are present; their outlines are irregular and angular with flat cut faces; none is round like a sphere | whether repetition is noticeable | 15 |
| S2 | Rim versus plains density (removed, Revision 20) | none | none | none | removed: at CAM high (50 km) rocks are smaller than a pixel, so the image cannot show density. S2 is checked by the automated REQ-16 density row only | none | 16 |
| S3 | Boulder contact and shadow | 6 rock; 6 ground | 8° / 90° | the picked largest rock where it meets the terrain | no gap or lit strip between the rock and the ground; a shadow falls on the side away from the Sun, joined to the base; the rock reads as a compact boulder: no flat blade, slab or shard, no dimension looks much shorter than the others; a faceted but compact silhouette is accepted; its shaded side faces away from the Sun | none | 17, 20 |
| S4 | Small-scale relief | 1 1m; 1 10cm | 10° / 90° | bare plains | the ground shows bumps and small craters with their own small cast shadows, not a flat plane; no regular repeating pattern is visible | none | 18 |
| S5 | Regolith up close | 11 10cm; 11 1m | 10° / 90° | regolith only | visible fine grain; no glossy highlight; grey colour with only small variation | whether it looks like lunar regolith rather than terrestrial sand, compared against Apollo photographs | 22, 24 |
| S6 | Grain fade with distance | 1 ground | 10° / 90° | regolith from the camera to the horizon | grain visible near the camera, gone by about 20 m, with no visible ring or step where it fades | none | 24 |
| S7 | Rock versus regolith material | 6 ground_sun (Sun-side view: camera south-east of the rock, looking north-west; the S3 view, CAM ground, is for the shadow) | 8° / 90° | the picked rock and the soil around it | the lit rock face is as bright as or brighter than the lit soil next to it; no gap or hard lit seam where the base meets the soil; the silhouette edge against the soil is not judged; the rock reads as a compact boulder (no flat blade or slab, no dimension much shorter than the others; a faceted but compact silhouette is accepted), with its shaded side and shadow away from the Sun | none | 23 |
| S8 | Lit surface at three Sun elevations | 7 ground 5; 7 ground 15; 7 ground 45 | 5°, 15°, 45° / 90° | the rim and interior of the picked crater, in the same framing | shadows are longest at 5° and shorter at each higher elevation; shadowed areas are black in all three images (no ambient fill); rocks and relief remain visible at 45° | none | 21, 25 |
| S9 | Close shadow detail | 11 1m | 10° / 90° | small rocks within 2 m | each small rock has a sharp shadow with its own outline, not a blob or square | none | 25 |
| P5-a | Ground LOD, plains | `-- 1 ground`, 40 s convergence | scenario's value | horizon and terrain | no cracks at node borders, no skirt seams, no popping, no coarse M2 mesh showing through | the look, if the image cannot settle it (error count is automated) | 26–30 |
| P5-b | Ground LOD, crater | `-- 5 ground`, 40 s convergence | scenario's value | horizon, terrain and crater shadow | as P5-a; the crater shadow is black with no ambient fill | as P5-a | 26–30 |
| P5-c | Cube face boundary | `-- 10 ground <sun_el> 1`, 40 s convergence | scenario's value | terrain across the face boundary | continuous terrain, no edge line at the face boundary | as P5-a | 30 |
| P5-d | Cube corner | `-- 10 ground 15 2`, about 90 s convergence | 15° / scenario's az | lit terrain at the cube corner | frame is not black; no edge line. At 10° this point is in terrain shadow by design (LOLA horizon 12.8° to the east), so a black frame there is expected | as P5-a | 30 |
| P5-e | Orbit root chunks | `-- 1 orbit`, 20 s convergence | scenario's value | root chunks as before | no chunk seams | none | 26–30 |
| P5-f | High LOD | `-- 5 high`, 40 s convergence | scenario's value | terrain from CAM high | smooth terrain, no chunk seams | none | 26–30 |

No entry needs a real GPU frame rate; frame-rate checks are REQ-31 and REQ-32 (user-run).

Not judged from a screenshot, so left to the automated rows:

| REQ | What a screenshot cannot show |
|---|---|
| 15 | the exact axis ratio of at least 1.3 |
| 16 | the exact density ratio of at least 2 |
| 17 | the burial percentage, and contact on the side away from the camera |
| 18 | the RMS per octave |
| 19 | the node and instance counts |
| 21 | the exact light law (checked by shader inspection) |
| 22 | the mean of the albedo factor over 1 m² |
| 25 | the split distances |

## Acceptance criteria

| REQ | Given | When | Then | Kind |
|---|---|---|---|---|
| 1 | raw LDEM_64 | `make moon-data` twice | 72 tiles; the json entries match; identical SHA-256; 1000 random posts (seed 42) equal the source DN | automated |
| 2 | tile with 1 byte changed | run the project | one ERROR naming it; no node in it deeper than 1 | automated |
| 2 | seed 1, 0.674 N 23.473 E, procedural off | `height_m` at the nearest post | equals DN x 0.5 within 0.01 m | automated |
| 3 | seed 1, a 200 x 200 m box at scenario 1 | crater and rock lists and 10 000 heights; 1 vs 4 threads; two orders; two runs | bit-identical | automated |
| 4 | fly camera at scenario 1 ground | move 5 km | at least 1 rebase; rendered positions of 3 fixed rocks change ≤ 1e-6 km across it | automated |
| 4 | orbit camera at 6000 | read the Moon's transform | identity | automated |
| 5 | fly mode at 1.7 m | Q held 10 s | height ≥ 0.05 m all the time | automated |
| 5 | fly mode | wheel up 1 notch | v x 1.25 | automated |
| 6 | fly at 0.1 m | read both cameras | near camera 1e-6 / 20 km, cull mask 3; far camera 0.05 / 440000 km; same global transform and FOV | automated |
| 6 | orbit at 6000, press F, then F again | compare transforms | first fly frame equals the last orbit frame's position (within 1e-6 km) and direction (within 1°, the pitch cap); after the second F the orbit camera equals its state before the first F; the near SubViewport does not render in orbit mode | automated |
| 6 | scenario 1 at CAM ground, 10cm and rock | look at the screen | the local surface (ground, rocks, small craters) is drawn up to the camera, with no cut-away area near it | user (`pending user check`) |
| 6 | scenario 1 at CAM ground, Sun and Earth above the horizon in view | look at the screen | Earth and the Sun disc are visible and terrain hides them only where it is in front | user (`pending user check`) |
| 6 (D9 check) | scenario 1 at CAM ground, windowed, Sun and Earth above the horizon in view, shared Environment with its sky | implementer runs it before finishing REQ-6 | (1) the near SubViewport's background is transparent: the sky, Earth and the Sun disc from the far camera show through wherever no terrain is drawn; (2) near terrain has the same colour as far-camera terrain across the 20 km boundary, and no halo or bright or dark fringe appears at terrain edges against the sky. If either fails, the implementer reports `SPEC_ISSUE` | implementer, windowed run |
| 6 | scenarios 1 and 11 at CAM orbit, ground, 1m, 10cm and rock, each a 25 s windowed run | count `create_frustum_points` and other light-culler errors in the log | 0 | automated |
| 7 | each N, `HEADLESS=1` | run | exit 0; prints the seed, point and counts | automated |
| 8 | seed 2, 10 x 10 km at scenario 2 | count craters per size bin | log-log slope of N(≥D) within ±0.15 of −b | automated |
| 9 | seed 1, a 10 x 10 km box at scenario 1 | average of the offset over 25 blocks of 2 x 2 km | every |mean| ≤ 1 m | automated |
| 10 | one crater, D 100 m, a = 0 | radial profile | depth k_d x D ±2 %; rim k_r x D ±5 %; integral ≤ 1 % | automated |
| 11 | the same crater with a = 1 | profile after step 1, before smoothing | rim and depth = 0.2 x fresh ±5 % | automated |
| 11 | the same crater with a = 1 | smoothed vs unsmoothed (step 1) profile | integral equal within 1 % of the fresh bowl volume; smoothed rim ≤ unsmoothed rim; smoothed |depth| ≤ unsmoothed |depth|; both > 0 | automated |
| 12 | 2 craters, the younger one centred on the older one's rim | height at that rim point | equals the younger crater's own profile value there, ±1 % | automated |
| 13 | m = 0 vs m = 1 at the same seed | crater count | ratio = highland/mare ±10 % | automated |
| 15 | 32 base meshes x 4 categories | measure | every axis ratio ≥ 1.3; ≥ 2 cut faces | automated |
| 16 | scenario 5 pick | rock density on the rim vs the plains 2 km away | ratio ≥ 2 | automated |
| 17 | all rocks within 200 m in scenarios 5 and 6 | check 8 perimeter points | no gap; burial ≤ 60 % | automated |
| 18 | scenario 1, detrended | RMS per octave | k_s x λ ±25 % | automated |
| 19 | scenario 5 ground | count rock nodes | ≤ 32 x 3 x resident chunks; 0 single-rock nodes | automated |
| 20 | scenario 6 rock | inspect `cast_shadow` | on | automated |
| 21–23 | shader source | inspect | Lommel-Seeliger; no specular, ambient or emission; the D8 amplitude bound | automated |
| 22 | scenario 1 at 10cm | mean of the detail factor over 1 m², CPU replica | 1.000 ±0.01 | automated |
| 25 | fly at 1.7 m | read the light | splits give 0.02, 0.2 and 2 km | automated |
| 26–28 | scenario 10 headless, Medium quality, fly camera, 60 s total. Path: start at point 1 (0 N, 45 E) at 1.7 m above the generated surface, heading north (azimuth 0°), pitch −20°. Fly north at 20 m/s. At the first frame after load where nodes queued ≥ 1, hop (teleport in one frame) to point 2 (35.264 N, 45 E) at 1.7 m, same heading and pitch, and keep flying north at 20 m/s until 60 s. The builds still queued for point 1 at the hop are no longer wanted | log | the log shows nodes queued ≥ 1 in the frame of the hop; no node queued twice; ≥ 1 cancellation. Cancellation is required only on this path, not in every flight (a steady straight flight may give 0) | automated |
| 27 | the 2 minute run only (`FLY_PATH_SECONDS=120`, the REQ-29 2 min fly path), both the settle at 1.7 m and the fly path; not part of the default 60 s `make test` | per-frame main-thread resource time log | for the settle and for the fly path, each: ≤ 0.1 % of frames above 2 ms; no frame above 30 ms | automated |
| 29 | 2 min fly path | memory log | resident bytes ≤ the quality limit all the time | automated |
| 30 | scenario 10, both points, depth 18 next to depth 17 | edge and skirt check | same-depth edges within tol(d) = max(1e-6 km, 1e-4 x vertex spacing): 1e-6 km at depths 17, 18 and 15, and the same check repeated at depths 12, 8 and 4 with tol(d) from that node's spacing; skirt covers the gap; morph weight is 1 at parent error 2 px, 0.5 at 2.3 px, 0 at 2.6 px | automated |
| 30 | scenario 10 | fly through at 20 m/s | no visible cracks or popping | user (`pending user check`) |
| 31–32 | user display | `make perf` | values printed; p95 ≤ 33.3 ms, max ≤ 100 ms at Medium | user (`pending user run`) |
| 35 | each N x CAM | `make scenario` | brief section 14 list checked against Apollo/LROC photos | user (`pending user check`) |
| 36–40 | repo | review; run the suites | docs present; suites pass | automated |

## Edge cases and errors

- A pole (|lat| > 89.9): the 3D lattice and the query have no special case. Scenario 10's corner point and a check at 89.95 S must give no NaN.
- The 0/360° seam: tile lookup and Catmull-Rom wrap in longitude.
- The native library is missing: one ERROR line; the project falls back to the M2 96-chunk mesh with no procedural detail; fly mode is disabled.
- NaN in a tile: the tool exits 2 and names the post. Nothing is filled in.
- Seed 0 is valid. Seeds are 64-bit.
- The camera is inside a rock: the fly floor rule uses terrain only, so this is allowed. No error is raised and nothing else is required for this case.
- The window is resized in fly mode: the near SubViewport follows the new size in the same frame or the next one.

## Assumptions

Several choices below were decided by the spec writer on the coordinator's instruction while the user was away. The coordinator relayed that the user had permitted this; that permission has not been confirmed by the user directly. The user should confirm the items marked **(confirm)**.

- **A1 (confirm)** Camera: a separate fly mode (key F). Reason: it leaves the orbit camera and its tests unchanged, and walking at eye height could not reach 10 cm.
- **A2 (confirm)** Runtime compute in a Rust GDExtension (gdext). Reason: the project rule "Rust for heavy computation", and GDScript already costs 2.379 µs per vertex for LOLA sampling alone. Risk: if gdext does not support Godot 4.7, the implementer reports `BUILD_ISSUE`.
- **A3 (confirm)** Provisional defaults, **not verified against the literature** (see References to check). All are configurable:

  | Parameter | Default |
  |---|---|
  | k_d | 0.2 |
  | k_r | 0.04 |
  | k_i | 0.08 |
  | b | 2.0 highland, 1.8 mare |
  | c (craters ≥ 1 m per km²) | 2000 highland, 800 mare |
  | rocks ≥ 0.2 m per m² | 0.02 highland, 0.005 mare |
  | k_s | 0.01 |
  | rock albedo factor | 1.0 to 1.3 |

  The values come from memory of commonly cited figures, not from a checked source.
- **A4 (confirm)** Frame-time target: 30 fps p95 at Medium. Reason: the GPU is unknown and the CPU is a 4-core i3.
- A5 The LDEM_64 tiles stay int16 as in the source: exact, about 531 MB on disk, and loaded lazily.
- A6 The region class comes from albedo brightness (D7). This is a simplification: mare and highland boundaries are only approximate.
- A7 The mass balance ignores bulking and compaction, and the ejecta fall-off is one fixed power law. Secondary craters are covered only by the population law, with no rays.
- A9 (orchestrator decision, 2026-11-12) The degradation factor is applied before the smoothing, and each step is checked on its own. The suggested "smoothed within 10 % of unsmoothed" check was not used. A disc smoothing of radius 0.2 D halves a 100 m crater's rim (the implementer measured 0.40 m against 0.8 m), so no small percentage tolerance can hold. The smoothing row checks what a smoothing must always do: it keeps the volume (so REQ-10's mass balance still holds), and it lowers the rim and the depth without removing either.
- A10 (coordinator-relayed user decision, 2026-11-12, replaces the earlier 0.02 km near plane) Close-range views are kept: the fly near plane is 1e-6 km. The light-culler errors are avoided with two cameras (D9, REQ-6), each with a far-to-near ratio of at most 2.2e7. Evidence, as reported by the coordinator and not seen by the spec writer: near 1 mm with far 440000 km (ratio about 4e11) gives create_frustum_points errors, hiding any single node does not stop them, and a ratio of 2.2e7 gave none.
  Assumptions in D9: the near camera's 20 km far plane is enough because the far camera draws the terrain beyond it too; terrain beyond 20 km is drawn with the far camera's depth precision only. The fly camera may go higher than 100 m; there the near layer simply ends at 20 km and the far camera draws the rest.
- A8 The scenario coordinates for Apollo 11, Apollo 16 and Hadley Rille are given from memory to 3 decimals. The tester uses them as fixed inputs. Whether they are geographically exact needs checking.

## References to check (no web access during writing)

- Pike 1977 (crater depth/diameter); Melosh 1989, *Impact Cratering*.
- Neukum, Ivanov and Hartmann 2001 (production function); Shoemaker 1965 and Gault 1970 (equilibrium density).
- Soderblom 1970 and Fassett and Thomson 2014 (crater degradation by diffusion).
- Shoemaker and Morris 1968 (Surveyor rock size distributions); Cintala and McBride 1995; Golombek and Rapp 1997; Bandfield et al. 2011 (Diviner rock abundance).
- Heiken, Vaniman and French 1991, *Lunar Sourcebook* (regolith); McEwen 1991 (photometry).
- Apollo Lunar Surface Journal imagery, LROC NAC images, USGS geologic maps.
- Licences: LDEM_64 as already recorded in `docs/DATA_SOURCES.md`. No other external data is added.

## Open questions

None. Decisions A1 to A4 were made in place of questions; see Assumptions. Q2 (D9 combination method) was resolved as option (a): D9 stays as written and the implementer verifies it in a windowed run (REQ-6 acceptance row "D9 check").

Remaining user checks (not open questions; they do not block Ready):
- Crater dark stripe on the far wall: accepted as relief for now; user to confirm.
- S9 near-rock look: pending user check in a live window.

## Revision history

- 2026-11-11: initial spec, phases P1 to P7. Open choices decided on the coordinator's instruction (A1 to A4, marked confirm).
- 2026-11-12: Revision 2, from implementer report. REQ-11 is now two ordered steps (factor, then smoothing). The REQ-11 acceptance row checks the factor before smoothing, and a new row checks the smoothing (volume kept, rim and depth reduced but not removed). Added A9.
- 2026-11-12: Revision 3, user decision relayed by the coordinator. REQ-6 fly near maximum 0.01 → 0.02 km, and the fly far plane is fixed at 440000 km. Added an acceptance row at 100 m, A10 and open question Q1 (ratio limit). Status set to Draft until Q1 is answered.
- 2026-11-12: Revision 4, Q1 resolved as (c) by user choice (relayed). Fly near plane fixed at 0.02 km, far 440000 km. REQ-6 clamp removed; the 0.1 m row now expects 0.02 km; the camera-inside-a-rock edge case was updated; A10 states the 20 m clipping and the views it affects. Q1 removed. Status Ready.
- 2026-11-12: Revision 5, user decision relayed by the coordinator. Fly mode keeps near 1e-6 km and uses two cameras (new D9): near camera 1e-6 / 20 km for the terrain layer in an overlaid transparent SubViewport, far camera 0.05 / 440000 km for all layers. REQ-6 rewritten, REQ-6 acceptance rows replaced (camera values, F switch, close views, Earth and Sun visible, 0 light-culler errors in 25 s runs). A10 rewritten; inside-a-rock edge case updated; resize edge case added. Q2 (combination method unconfirmed in Godot 4.7) added. Status Draft.
- 2026-11-12: Revision 6, Q2 resolved as option (a) by coordinator decision. D9 kept as written; added the REQ-6 "D9 check" acceptance row (transparent SubViewport with sky, no colour mismatch or edge halo, `SPEC_ISSUE` if either fails). Q2 removed. Status Ready.
- 2026-11-12: Revision 7, user decision relayed by the coordinator. D9 and REQ-6: the near camera's cull mask is 3 (terrain layer 2 plus layer 1), because terrain alone renders black under the Sun. REQ-6 and its acceptance row allow the first fly frame's direction to differ from the orbit view by up to 1° (the ±89° pitch cap). The far camera, the 20 km far plane and the 1e-6 km near plane are unchanged. Status Ready.
- 2026-11-12: Revision 8, spec-writer rule (Screenshots section). Added screenshots S1 to S9 for Phase 3 (REQ-15 to 18, 20) and Phase 4 (REQ-21 to 25), all user-only, plus a list of the parts that are not judged from a screenshot. No requirement changed. Status Ready.
- 2026-11-12: Revision 9, from coordinator. Screenshots S1 to S9 are now judged by the screenshot agent, with agent pass criteria and a separate user part (S1 repetition, S5 regolith realism). Added REQ-7a (optional Sun elevation in `make scenario` and `scripts/scenario.gd`) so S8 can be built. No other number changed. Status Ready.
- 2026-11-12: Revision 10, user decisions relayed by the coordinator. REQ-30 geomorph: pop-free direction, w = 1 (parent shape) at parent error 2 px down to w = 0 (own shape) at 2.6 px, parent error = 2 x own error. REQ-30 shared-edge tolerance is per depth: tol(d) = max(1e-6 km, 1e-4 x vertex spacing), so 1e-6 km at depths 11 to 18. REQ-30 acceptance row updated. No other requirement changed. Status Ready.
- 2026-11-12: Revision 11, from tester `SPEC_ISSUE`. The REQ-26 to 28 acceptance row now defines the scenario 10 fly path: point 1 at 1.7 m, north at 20 m/s, a one-frame hop to point 2 at the first frame with nodes queued ≥ 1, then north at 20 m/s to 60 s. Cancellation is required only on this path. No requirement changed. Status Ready.
- 2026-11-12: Revision 12, user decision relayed by the coordinator. REQ-29 and its acceptance row: the memory fly path is shortened from 10 minutes to 2 minutes. The 60 s fly path row is unchanged. No other requirement changed. Status Ready.
- 2026-11-12: Revision 13, user decision relayed by the coordinator. REQ-27 allows rare spikes: main-thread resource time ≤ 2 ms per frame, with at most 0.1 % of fly-path frames above 2 ms and none above 30 ms. Scope is resource time only, not selection or `_plan`. New REQ-27 acceptance row on the REQ-29 2 min fly path; the resource-time check moved out of the REQ-26 to 28 row. No other requirement changed. Status Ready.
- 2026-11-12: Revision 14, user decisions relayed by the coordinator. (1) REQ-27: the settle (camera still at 1.7 m) uses the same rule as the fly path, at most 0.1 % of frames above 2 ms and none above 30 ms; the strict single-node 2 ms check is removed. (2) The REQ-27 checks run on the 2 minute run (`FLY_PATH_SECONDS=120`), not on the default 60 s `make test`; the acceptance row says so. No other requirement changed. Status Ready.
- 2026-11-12: Revision 15, from coordinator. Added Phase 5 screenshots P5-a to P5-f as used by the screenshot agent. REQ-7a documents the optional fourth argument `<pt>` (1-based point index). Point 2 of scenario 10 is judged at Sun 15°; at 10° it is in terrain shadow by design (LOLA horizon 12.8° east). No other requirement changed. Status Ready.
- 2026-11-12: Revision 16, user decision relayed by the coordinator. Large rocks must look like rounded boulders; small and medium stay angular. Reading chosen: (c) more hull points (64 on a 1.3 to 1.6 ellipsoid), with exactly 2 shallow cuts (≤ 15 % of the axis, ≤ 25 % of surface) and large-class instance scale 0.9 to 1.1, so shortest/longest extent ≥ 0.5. Why: it reuses the existing hull-and-cut generator with only parameter changes; (a) adds a new rounding step and (b) adds noise that fights the convex hull. D3, REQ-15, S3 and S7 shape wording updated; S1 unchanged. Status Ready.
- 2026-11-13: Revision 17, user decision relayed by the coordinator. Large-class hull raised from 64 to 128 jittered points so large rocks read as curved boulders, not faceted polyhedra. D3 and REQ-15 updated. Ellipsoid ratio 1.3 to 1.6, exactly 2 cuts (≤ 15 % of the axis), cut faces ≤ 25 % of hull area, instance scale 0.9 to 1.1 and extent ratio ≥ 0.5 unchanged. S3 and S7 do not name the point count and are unchanged. Status Ready.
- 2026-11-13: Revision 18, user decision relayed by the coordinator. Current large-rock look accepted. S3 and S7 pass criteria changed from curved silhouette / rounded boulder to compact boulder: no flat blade or slab, no dimension much shorter than the others, faceted but compact silhouette accepted, shadow and shaded side away from the Sun. Lit/dark, error and contact criteria unchanged. REQ-15 and D3 (128-point hull and its limits) unchanged. Status Ready.
- 2026-11-13: Revision 19, user decision relayed by the coordinator. S7 contact criterion applies to the base contact only: no gap or hard lit seam where the base meets the soil; the silhouette edge against the soil is not judged. S7 camera named as the Sun-side view: scenario 6 with CAM ground_sun (south-east of the rock, looking north-west); the S3 view (CAM ground) is for the shadow. Brightness criterion and all other rows unchanged. Status Ready.
- 2026-11-13: Revision 20, user decision relayed by the coordinator. S2 screenshot removed (rocks are sub-pixel at CAM high, 50 km); the automated REQ-16 density row is the S2 check. REQ-15 large-class wording changed from "rounded boulders" to "compact boulders", aligned with S3 and S7; no number changed (128 points, ratio 1.3 to 1.6, exactly 2 cuts ≤ 15 % of the axis, cut faces ≤ 25 % of area, extent ratio ≥ 0.5). Two user checks recorded under Open questions: crater far-wall dark stripe (accepted as relief for now) and S9 near-rock look (pending, live window). Status Ready.
