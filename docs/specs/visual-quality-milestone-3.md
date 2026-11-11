# Milestone 3: Visual Quality

Status: Ready
Slug: visual-quality-milestone-3

## Goal

Make the Milestone 2 globe look like a real airless rocky body under the real Sun. This milestone covers the four areas the user chose: a lunar photometric material, crater shadows at every camera distance, camera controls that work at the surface, and a normal map made offline in Rust from the real LOLA heights. Every value below has a reason and a way to measure it. Checks that need a GPU and a display are run by the user.

## Scope

- Lunar surface shader `shaders/lunar_surface.gdshader`, which replaces the shared `StandardMaterial3D` on the 96 chunks.
- Settings for the DirectionalLight3D shadows, with a maximum shadow distance that follows the camera.
- Camera changes: a finer zoom step within 500 km of the surface, rotation and pan speeds that scale with altitude, and a new look-around mode.
- Normal map: a new `moon-data` step, a PNG asset, a `moon_data.json` entry, a runtime checksum check, and a section in `docs/DATA_SOURCES.md`.
- A user-run measurement script (`make visual-check`) for the checks that need a GPU, and automated checks for the rest.
- Documentation updates in `docs/ARCHITECTURE.md` and `docs/PERFORMANCE.md` for the new material.

## Non-goals

- No atmosphere, sky, fog, glow, ambient or environment light, and no Earthshine. M1 REQ-14 stays in force.
- No opposition surge, Hapke model or phase-dependent photometric parameters (see A1).
- No colour grading. No change to tonal values, exposure, tonemapping or light energy. The albedo texture is used unchanged.
- No vertical exaggeration, in the mesh or in the normal map.
- No LOD, streaming, new mesh resolution or terrain collision.
- No camera reset key, no camera animation, no keyboard camera movement, no change to the field of view or the clip planes.
- No change to how the Sun is computed or streamed (sun spec REQ-14 to REQ-26).
- No Python. No new Rust crates beyond the M2 list (`tiff`, `png`, `serde`/`serde_json`, `sha2`).

## Stack and constraints

- Godot 4.7.2-stable, GDScript, Forward+ on Vulkan. 1 unit = 1 km.
- Offline data stays in the Rust crate `tools/moon-data/`, using its pinned toolchain.
- Data is genuine LOLA and LROC only. The normal map comes only from `assets/elevation/lola_height_m_4096x2048.f32`.
- Fixed values from earlier work, all kept: reference radius 1737.4. Terrain radius range 1728.2 to 1747.732 (M2 REQ-30, `docs/VALIDATION.md`). Minimum camera distance 1748.232 from the Moon's centre (M1 REQ-18). Maximum distance from the pivot 20000. Zoom factor 0.95 per wheel notch. Default distance 6000. Camera near plane 0.01, far plane 100000, Godot's default vertical fov of 75°.
- Derived constant: default altitude A0 = 6000 − 1737.4 = 4262.6 km.
- Altitude means the camera's distance from the Moon node's global position, minus 1737.4. It never means the distance to the pivot or to the world origin.

## Requirements

### 1. Lunar material

- **REQ-1**: All 96 chunks share one `ShaderMaterial` that uses `res://shaders/lunar_surface.gdshader`. The shader writes no `VERTEX` (displacement stays in the mesh, M2 REQ-15). It samples the albedo texture `assets/textures/lunar_albedo_4096x2048.png` with the same colour handling and filtering as the M1/M2 material: sRGB source colour, linear filtering with mipmaps, anisotropic.
- **REQ-2**: Reflectance law. For the Sun light, the diffuse light is `albedo · E · 2·cos i / (cos i + cos e)` when `cos i > 0`, and 0 otherwise. Here `i` is the angle between the shading normal (REQ-16) and the direction to the Sun, `e` is the angle between the shading normal and the direction to the camera, and `E` is the light energy and colour (unchanged, energy 1.0). This is the Lommel-Seeliger law with the factor 2, so at normal incidence and normal view it equals Lambert (see A1). When `cos e ≤ 0`, the light is 0. The divisor is never 0, because the law needs `cos i > 0`.
- **REQ-3**: The material has no specular reflection, no rim, no clearcoat, no emission and no ambient term. The shader declares `specular_disabled` (or writes `SPECULAR_LIGHT` as 0), sets metallic 0, and writes nothing to `EMISSION`, `RIM` or `CLEARCOAT`. Roughness is 1.0, or has no effect because the shader uses its own light function. This replaces M1 REQ-9 and M2 REQ-22's StandardMaterial3D wording.
- **REQ-4**: Measured response at zero phase angle (user-run). The Sun direction is set equal to the camera direction (the camera at distance 6000, yaw 0, pitch 0, Sun along +Z). The frame is rendered twice: once with the lunar material, and once with a test-only unshaded material that uses the same albedo texture and filtering. Both are converted from sRGB to linear. Over the Moon pixels, the per-pixel ratio (lunar / unshaded) is computed. The median ratio in the central region (angle from the sub-camera point at most 30°) and in the limb ring (70° to 80°) must both lie in [0.90, 1.10]. The limb median divided by the central median must lie in [0.90, 1.10]. Reason: REQ-2 gives exactly 1.0 at zero phase for every normal, so the ±0.10 tolerance covers only 8-bit quantisation and filtering. A Lambert or glossy material would give about cos 75° = 0.26 in the limb ring, so the check tells them apart.

### 2. Shadows

- **REQ-5**: The Sun (`DirectionalLight3D` "Sun") keeps `shadow_enabled = true`. It uses `directional_shadow_mode = SHADOW_PARALLEL_4_SPLITS` with splits 0.1, 0.2 and 0.5 (Godot defaults), `directional_shadow_blend_splits = true`, and `light_angular_distance = 0`. The project setting `rendering/lights_and_shadows/directional_shadow/size` is 4096 (Godot default). Shadow bias and normal bias keep Godot's defaults. The implementer reads the actual values from the node and lists them in `docs/PERFORMANCE.md`. Reasons:
  - Hard edges (angular distance 0): the real penumbra is `height · tan(0.53°)`, which is 28 m for a 3 km crater rim. That is below the smallest shadow texel at any allowed camera position (about 65 m, REQ-8), so soft shadows would only add cost.
  - Atlas size 4096: the GPU memory budget is not measured yet (`docs/PERFORMANCE.md`, pending user run), so the size is not raised.
  - Chunks keep the default `cast_shadow = on`. `SunDisc` keeps `cast_shadow = 0`.
- **REQ-6**: Each frame, `directional_shadow_max_distance` equals `S(D) = sqrt(D_c² − 1728.2²) + sqrt(1747.732² − 1728.2²)`. Here `D_c` is the camera's distance from the Moon's centre, and the second term is 260.6 km. If `D_c < 1728.2`, the first term is 0. Reason: no terrain point the camera can see is farther than the tangent distance to the lowest terrain sphere plus the distance from that tangent point to the highest terrain sphere. This makes shadows apply to all visible terrain at every allowed camera distance, without wasting resolution beyond it. Values: S = 524.5 at 1748.232, 6006.3 at 6000, and 20185.8 at 20000 (each ±0.5). Today the max distance is Godot's default of 100 km, so there are no Moon shadows at orbit distances. The value is set without any per-frame terrain work.
- **REQ-7**: Crater shadow check (user-run, Tycho):
  - Setup: camera pivot at the Moon's centre, Tycho (43.31° S, 348.64° E) at screen centre, distance 2037.4 (altitude 300 km), tilt 0. The Sun direction is fixed by the script: local azimuth 90° (from the east) and elevation 5° at Tycho's centre. In the Moon frame, sun = cos 5° · east + sin 5° · up, with up = (cos φ sin λ, sin φ, cos φ cos λ) and east = (cos λ, 0, −sin λ).
  - Measurement: render with shadows on and with shadows off. `F_render` is the fraction of screen pixels inside Tycho's projected 43 km radius where on / off < 0.1.
  - Reference: an independent CPU computation, `F_ref`. On a 1 km grid of surface points inside the same 43 km radius, with heights bilinear from the 2048 × 1024 level as the mesh does (M2 REQ-15), a point is in cast shadow if a ray toward the Sun passes below the terrain within 200 km.
  - Pass: `|F_render − F_ref| ≤ 0.10`, and `F_ref ≥ 0.05`. Both values are printed.
  - Reasons: 5° is a low Sun that gives a cast shadow about 3 km / tan 5° = 34 km long, against an 86 km crater. The 0.10 tolerance covers a shadow texel of about 0.9 km in the split that holds Tycho (frustum width at 670 km divided by 2048), plus the difference between the triangle mesh and the bilinear surface. 200 km is more than 2 × the 86 km diameter.
- **REQ-8**: Shadow acne check (user-run, Mare Imbrium). Setup: camera centred on 35° N, 340° E (the centre of the M2 REQ-28 Imbrium box), altitude 300 km, Sun at local elevation 30° from the east. Measurement: shadows on versus off. Pass: the fraction of pixels within 100 km of that point where on / off < 0.5 is at most 0.01. Reasons: mare slopes at this mesh scale are far below 30°, so real cast shadows there are about 0, and any dark pixels are acne. 0.01 allows a few pixels at small craters. In this view, the near split covers about 134 km (0.1 × S(2037.4) = 0.1 × 1339.6), which gives about 65 m per texel. That is the smallest texel cited in REQ-5.

### 3. Camera controls

The M1 grab conventions (REQ-16 directions, REQ-19 direction) and the clamps stay. Only the rates and the zoom variable change, plus one new mode. Reason: with M1 rates, one wheel notch near the surface moves 5% of about 1750 km = 87 km, which is about 8 times the 10.8 km altitude, and one pixel of drag sweeps 6.1 km of ground. You cannot approach or inspect the surface gradually.

| # | Control | M1 value | M3 value | At the surface (D_c = 1748.232, altitude 10.832) |
|---|---|---|---|---|
| C1 | Wheel notch | distance × 0.95 or / 0.95 | distance × f or / f, with f = 0.95 when altitude > 500 and f = sqrt(0.95) = 0.9747 when altitude ≤ 500 | f = 0.9747: 45.4 km per notch out from 1748.232; a notch in clamps to the minimum |
| C2 | Notches from 6000 to the minimum | 24 | 29 (20 at 0.95, then 9 at 0.9747, the last one clamped) | — |
| C3 | Notches from 6000 to the maximum | 24 (to 20000) | 24 (to 20000, unchanged) | — |
| C4 | Left-drag orbit rate | 0.2°/px | 0.2 · s °/px, with s = min(1, altitude / 4262.6) | 0.000508°/px = 15.5 m of ground per px |
| C5 | Middle-drag pan rate | distance × 0.0001 km/px | distance × 0.0001 · s km/px | 0.44 m/px |
| C6 | Right-drag look (new) | none | tilt and heading at 0.2°/px, tilt 0° to 85°, heading wraps at ±180° | same |
| C7 | Minimum distance | 1748.232 from the pivot | 1748.232 from the Moon's centre, whatever the pivot | 1748.232 |

- **REQ-9**: Zoom (C1, C7). One wheel notch sets the pivot distance to `distance · f^(±1)`, with exponent +1 for in and −1 for out, and `f = 0.95` if altitude > 500, otherwise `f = 0.95^0.5 = 0.974679`. Altitude is measured before the step (the camera's distance from the Moon's centre minus 1737.4). Reason (user decision): above 500 km the M1 step is kept. Within 500 km of the surface, each notch is half the M1 step in log terms, for finer approach. After the step, the distance is clamped so the camera's distance from the Moon's centre is at least 1748.232 and the distance from the pivot is at most 20000. If the pivot is not at the centre, the clamp still holds the camera at 1748.232 or more from the centre. This fixes the M1 clamp, which measured from the pivot. The orbit and pan rules (REQ-10) use altitude but do not depend on this zoom rule, so they are unchanged.
- **REQ-10**: Orbit and pan rates (C4, C5) are multiplied by `s = min(1, altitude / 4262.6)`. At and above the default distance 6000 (with the pivot at the centre), they equal the M1 values. Reason: at the surface, 0.000508°/px moves the ground by 15.5 m/px. That matches the ground size of one pixel seen straight down from 10.832 km with a 75° fov on a 1080 px viewport: 2 · 10.832 · tan 37.5° / 1080 = 15.4 m. So the ground follows the cursor about 1:1.
- **REQ-11**: Look mode (C6). Right-mouse drag changes `tilt_deg` and `heading_deg` at 0.2°/px each, using the grab rule: drag down increases tilt (the view rises toward the horizon), and drag right decreases heading.
  - Tilt rotates the camera about its own local X axis, away from the pivot direction. Heading rotates it about the axis from the camera toward the pivot.
  - Tilt is clamped to [0, 85]. Heading wraps to [−180, 180).
  - Look mode does not move the camera's position. It does not change zoom, orbit, pan or the clamps. With tilt 0 and heading 0 at startup, the view equals M1 REQ-21.
  - Reason for 85°: at the minimum altitude 10.832, the horizon lies acos(1737.4 / 1748.232) = 6.36° below horizontal, which is a tilt of 83.6°. So 85° can put the horizon at screen centre at every allowed altitude, without looking above the horizon into empty space for long.

### 4. Normal mapping

- **REQ-12**: Generation. A new subcommand, `moon-data normal-map`, run by a new target `make normal-map`, reads only `assets/elevation/lola_height_m_4096x2048.f32` and `assets/elevation/moon_data.json`. It first checks that the file's size and SHA-256 match the json entry; if not, it exits 2 with one error line naming the file. `make moon-data` runs the same step last. Both paths write byte-identical output.
- **REQ-13**: Method, per texel (x, y) of the 4096 × 2048 grid (M2 REQ-8 convention), with h in metres and R = 1 737 400 m:
  - Grid spacing: `Δy = π R / 2048` (1332.6 m), and `Δx₁ = 2 π R cos φ_y / 4096`.
  - East step: `k = max(1, ceil(Δy / Δx₁))` columns.
  - East slope: `g_e = (h[x+k] − h[x−k]) / (2 k Δx₁)`, with the column index wrapping modulo 4096.
  - North slope: `g_n = (h[y−1] − h[y+1]) / (2 Δy)`, where row y−1 is north. On the first and last row, use the one-sided difference toward the interior, divided by Δy.
  - Normal: `n = normalize(−g_e, −g_n, 1)` in the local east-north-up (ENU) frame. Scale 1.0, no smoothing, no exaggeration.
  - Reason for k: near the poles Δx₁ becomes small (about 2 m in row 0), and differences over 2 m would amplify noise. The k rule keeps the east baseline at least Δy, which is the north baseline.
- **REQ-14**: Resolution 4096 × 2048, which is the finest committed height level and the same grid as the albedo, so texels align one to one. Reason: its 2.665 km cells are finer than the mesh's 7.538 km minimum quad side, so the map adds shading detail from 2.7 to 7.5 km that the mesh cannot show. Finer data (LDEM_64) would need a 23040 × 11520 texture, which is larger than the 16384 Godot texture limit.
- **REQ-15**: Storage. The output is `assets/textures/lunar_normal_enu_4096x2048.png`, 8-bit RGB, with `R = round((n_e·0.5 + 0.5)·255)` and G and B the same for n_n and n_u. It is imported as a lossless texture with mipmaps, without Godot's normal-map conversion (the shader decodes it). The 8-bit step is 2/255, about 0.45° near flat. GPU size is 4096·2048·4 bytes = 32 MiB, plus 1/3 for mipmaps = 42.7 MiB. Reason for lossless: no compression artefacts are added to measured data. `moon_data.json` gets a `normal_map` entry with path, width, height, encoding (`enu_rgb8`), frame, source level path and SHA-256, method (`central difference, k rule`), and the PNG's own SHA-256.
- **REQ-16**: Application. The shading normal used in REQ-2 is the decoded map normal: bilinearly filtered, `n = rgb·2 − 1`, then normalised. It is rotated from the ENU frame at the fragment's latitude and longitude into world space, using up = the radial direction from the Moon's centre, east = (cos λ, 0, −sin λ) and north = up × east, in the Moon's frame. The vertex normal is not added to it, because the map already includes the mesh-scale slope, and adding both would count the slope twice.
- **REQ-17**: At startup, Godot checks the normal map PNG's size and SHA-256 against `moon_data.json`. If the file is missing or does not match, Godot prints one ERROR line naming the file, and the shader uses the interpolated vertex normal instead. No other normal is made up.
- **REQ-18**: `docs/DATA_SOURCES.md` gets a section "Normal map (Milestone 3)" with:
  - the source level path and SHA-256
  - the REQ-13 formulas and the k rule
  - the encoding, the resolution, the commands (`make normal-map`, `make moon-data`) and the `moon-data` version
  - the output SHA-256 and byte size
  - the statement that no smoothing, scaling or invented data was used
- **REQ-19**: Normal map tests (`make moon-data-test`, automated):
  - (a) On a synthetic plane tilted 10° toward the east, the computed normal is within 0.01° of the analytic normal before encoding.
  - (b) On the real 4096 level, 1000 texels chosen with seed 42 decode to within 0.6° of an independent recomputation from REQ-13. The 0.6° covers the 0.45° quantisation.
  - (c) The texel nearest (43.24° S, 347.34° E), on Tycho's west inner wall, has n_e > 0 (it faces east, into the crater) and is tilted more than 5° from up. Reason: M2 REQ-20 already measures more than 2° at mesh scale, and the finer level shows a steeper wall.
  - (d) No component is NaN.
  - (e) Two runs give byte-identical PNGs.

### 5. Verification split and documentation

- **REQ-20**: `make visual-check` (windowed, user-run) loads `scenes/main.tscn` without changing project files. It stops the Sun node's per-frame updates, as a test-only step, so it can set fixed Sun directions. It runs REQ-4, REQ-7 and REQ-8, and prints each measured value with its threshold and PASS or FAIL. Headless, it prints one "not available headless" line per check.
- **REQ-21**: Verification table. The tester runs every "automated" row and reports every "user" row as `pending user check` (or `pending user run` for numbers). Neither kind is reported as passed without its result.

  | Check | REQ | Kind |
  |---|---|---|
  | Material type, shader path, no VERTEX/EMISSION/RIM/CLEARCOAT writes, specular disabled, metallic 0 | 1, 3 | automated (headless scene and shader-source inspection) |
  | Zero-phase limb response ratio | 4 | user (`make visual-check`) |
  | Shadow mode, splits, blend, angular distance, atlas size | 5 | automated |
  | `directional_shadow_max_distance` at D_c 1748.232, 6000, 20000 | 6 | automated (headless, set the camera and read the light) |
  | Tycho shadow fraction, Imbrium acne | 7, 8 | user (`make visual-check`) |
  | Zoom, rate, look and clamp values in the camera table | 9–11 | automated (synthetic input events, headless) |
  | Normal map generation, tests, json entry, DATA_SOURCES section | 12–15, 18, 19 | automated |
  | Runtime checksum check and fallback | 17 | automated |
  | Visual: crater relief looks like rock, not plastic; no glossy highlight; no seam at 0° E or face edges in the normal-mapped shading; no pole artefacts; shadows have no visible split seams while zooming from 20000 to 1748.232; surface look-around feels stable | 2, 5, 11, 16 | user (`pending user check`) |
  | Frame time with the new shader and shadows at the three `make perf` positions | — | user (`pending user run`) |

- **REQ-22**: `docs/ARCHITECTURE.md` and `docs/PERFORMANCE.md` replace the "one shared StandardMaterial3D" text with the REQ-1 shader. `docs/PERFORMANCE.md` adds:
  - the normal map file size, and its 42.7 MiB GPU estimate (marked as arithmetic)
  - the REQ-5 shadow settings, as read from the node
  - user-run frame times, marked `pending user run`

  `make perf` still runs unchanged.
- **REQ-23**: Replaced earlier rules. Everything else in the earlier specs stays in force, including the live Sun (sun spec REQ-15, REQ-16), the arrow-key adjustment (M1 REQ-13), and REQ-31-style 10 s runs without ERROR lines (which also cover this milestone).

  | Earlier | New |
  |---|---|
  | M1 REQ-9, M2 REQ-22 (StandardMaterial3D, roughness ≥ 0.9) | REQ-1 to REQ-3 |
  | M2 Non-goal "no normal maps, no custom shader" | REQ-1, REQ-12 to REQ-17 |
  | M1 REQ-16 rate 0.2°/px (directions kept) | REQ-10 |
  | M1 REQ-17 (zoom multiplies the distance) | REQ-9 |
  | M1 REQ-18 (clamp measured from the pivot when panned) | REQ-9 (from the centre; values 1748.232 and 20000 kept) |
  | M1 REQ-19 rate distance × 0.0001 (direction kept) | REQ-10 |

## Acceptance criteria

| REQ | Given | When | Then |
|---|---|---|---|
| REQ-1 | Main scene, headless | Inspect the chunk materials and the shader source | All 96 chunks share one ShaderMaterial with `lunar_surface.gdshader`. The albedo uniform is the M2 PNG with the sRGB hint and anisotropic mipmapped filtering. No `VERTEX` assignment |
| REQ-2 | Shader source | Review | The light function is the stated formula with factor 2, zero for `cos i ≤ 0` or `cos e ≤ 0` |
| REQ-3 | Shader source | Grep | `specular_disabled` (or SPECULAR_LIGHT = 0) and metallic 0; no EMISSION, RIM or CLEARCOAT writes |
| REQ-4 | Display, `make visual-check` | Zero-phase test | Central and limb medians in [0.90, 1.10]; limb / central in [0.90, 1.10]; values printed |
| REQ-5 | Main scene | Read the Sun and the project setting | 4 splits; 0.1/0.2/0.5; blend true; angular distance 0; atlas 4096; bias values listed in docs |
| REQ-6 | Pivot at centre; distance 1748.232, then 6000, then 20000 | Process one frame; read max distance | 524.5, 6006.3, 20185.8 (±0.5) |
| REQ-6 (pivot offset) | Pivot (500, 0, 0), distance 3000 | Read max distance | Equals S(D_c) with D_c measured from the Moon's centre (±0.5) |
| REQ-7 | Display | `make visual-check` Tycho | F_ref ≥ 0.05; \|F_render − F_ref\| ≤ 0.10; both printed |
| REQ-8 | Display | `make visual-check` Imbrium | Dark fraction ≤ 0.01 |
| REQ-9 | Pivot at centre, distance 6000 | One notch in | 5700 (±0.01) |
| REQ-9 | Pivot at centre, distance 6000 | 19 notches in, then 1 more | After 19: 6000 · 0.95^19 = 2264.12 (±0.01), altitude 526.72 > 500. After 20: 6000 · 0.95^20 = 2150.92 (±0.01) |
| REQ-9 | Distance 2150.92 (altitude 413.52) | 8 notches in, then 1 more | After 8: 2150.92 · 0.95^4 = 1751.94 (±0.01). After 9 (29 in total from 6000): exactly 1748.232 (±0.001), never below |
| REQ-9 | Pivot at centre, distance 2237.4 (altitude exactly 500) | One notch in | 2237.4 · 0.974679 = 2180.75 (±0.01), the half step |
| REQ-9 | Distance 1748.232 | One notch out | 1748.232 / 0.974679 = 1793.65 (±0.01) |
| REQ-9 | Distance 6000 | 23 notches out, then 1 more | After 23: 6000 / 0.95^23 = 19521.2 (±0.1). After 24: 20000 (±0.01) |
| REQ-9 | Pivot (500, 0, 0), wheel in 300 notches | Read camera | Distance from the Moon's centre ≥ 1748.232 |
| REQ-10 | Distance 6000 | Left drag 100 px right | Yaw −20° (±0.5), as in M1 |
| REQ-10 | Distance 1748.232 | Left drag 1000 px right | Yaw changes by 0.508° (±0.005) |
| REQ-10 | Distance 1748.232, pivot at centre | Middle drag 1000 px right | Pivot moves 0.444 km (±0.005) camera-left |
| REQ-11 | Startup | Read tilt and heading; compare the camera transform with M1 REQ-21 | 0, 0; same transform within 1e-4 |
| REQ-11 | Tilt 0 | Right drag 1000 px down; right drag 100 px right | Tilt 85 (clamped); heading −20; camera position unchanged within 1e-4 |
| REQ-12 | Committed 4096 level | `make normal-map`; `make moon-data` | Both exit 0 with byte-identical PNGs. A corrupted copy of the level gives exit 2 and one error line |
| REQ-13, REQ-19 | `make moon-data-test` | Run | Tests (a) to (e) pass |
| REQ-14, REQ-15 | Output PNG and json | Read the header and json | 4096 × 2048 RGB8; json entry fields present; SHA-256 matches |
| REQ-16 | Shader source | Review | Shading normal = decoded map normal in the ENU basis as stated; the vertex normal is not added |
| REQ-17 | PNG renamed | Run the project | One ERROR line naming the file; the project keeps running with vertex normals |
| REQ-18 | `docs/DATA_SOURCES.md` | Review; `sha256sum` | Section present; checksums match the files |
| REQ-20 | Headless | `make visual-check HEADLESS=1` | One "not available headless" line per check; exit 0 |
| REQ-21 | Tester report | Review | Every user row is listed as pending; every automated row has a result |
| REQ-22 | Docs | Review | Material text updated; normal map memory, shadow settings and pending rows present |
| REQ-23 | Earlier test suites | `make test`, `make moon-data-test`, `make ephemeris-test` | Pass, with replaced checks in their new form |

## Edge cases and errors

- **Sun below the local horizon** (`cos i ≤ 0`): the light is 0. There is no ambient light, so the surface is black, which is correct for an airless body.
- **Fragment at a pole**: the ENU basis is undefined when cos φ < 1e-6. There the shader uses the interpolated vertex normal, and no NaN or black pixel appears. This is a visual check.
- **Longitude seam**: the normal map wraps in x (REQ-13). Texture sampling at u = 0 and u = 1 uses the M2 UVs. Seam visibility is a visual check.
- **Pivot panned far from the Moon**: altitude can exceed 4262.6, so s = 1. The minimum clamp still holds from the centre.
- **Camera exactly at 1748.232**: one notch in changes nothing. The wheel never moves the camera below the minimum.
- **No Sun yet (helper not started)**: shadows and the light are off, as in sun spec REQ-15. The max shadow distance is still set and is harmless.
- **NaN in the height level**: the level has `nodata_count` 0 today. If a NaN is met, `moon-data normal-map` exits 2 naming the texel. Nothing is filled in.

## Assumptions

- **A1 – Reflectance law**: pure Lommel-Seeliger (McEwen's lunar-Lambert with L = 1). Reasons: it is the single-scattering law for a dark, particulate, airless surface. It reproduces the well-known observation that the full Moon is about as bright at the limb as at the centre (no limb darkening), which a Lambert or glossy sphere does not. It needs no fitted parameter. A phase-dependent L(α) or the Hapke model would add fitted constants that this POC cannot validate, so they are non-goals.
- **A2 – Albedo handling**: the PNG is treated as sRGB, the same as M1/M2, so the on-screen tone of the albedo does not change.
- **A3 – Pan rate at the surface** (0.44 m/px) is slow by design: at the surface, orbiting (C4, 15.5 m/px) is the way to travel, and panning is for fine adjustment. The user can judge it from the table.
- **A4 – Viewport height 1080 px** is used only to explain the C4 reason. The rates do not depend on the window size.
- **A5 – User-run checks** need a GPU and a display, as `make perf` does. The headless dummy renderer cannot render pixels.

## Open questions

None.

## Revision history

- 2026-11-11: Initial spec for Milestone 3 (visual quality). Covers all four areas per the user's decision: Lommel-Seeliger shader, PSSM shadows with a camera-tracking max distance, altitude-based camera control with look mode, and an offline Rust ENU normal map from the 4096 × 2048 LOLA level.
- 2026-11-11: Revision 2, from implementer report. REQ-9 acceptance row "116 notches in": bound corrected from "1748.232 < D ≤ 1748.30" to D = 1737.4 + 4262.6 · 0.95^116 = 1748.507 (±0.002), which is what REQ-9's formula gives. Nothing else changed.
- 2026-11-11: Revision 3, user decisions. REQ-9 zoom rule replaced: distance · f^(±1), with f = 0.95 above 500 km altitude and sqrt(0.95) = 0.974679 at or below it. The altitude-based step (117 notches) is dropped. Camera table rows C1 to C3, the Scope line and the REQ-9 acceptance rows were updated (29 notches from 6000 to the minimum, 24 to the maximum). Minimum, maximum, the orbit and pan rules (REQ-10, independent of zoom), look mode and the normal map are unchanged.
