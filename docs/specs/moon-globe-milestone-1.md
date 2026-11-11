# Milestone 1: Basic Lunar Globe

Status: Ready
Slug: moon-globe-milestone-1

## Goal

Create the standalone Moon POC Godot 4 project and show a textured, spherical Moon rendered with Forward+ on Vulkan. The user can orbit, zoom and rotate the camera around the Moon and change the Sun direction with a DirectionalLight3D. This milestone is the visual and control foundation that later milestones (real elevation, data pipeline, visual quality, performance) build on.

## Scope

- Godot 4 project at the repository root (`project.godot`), Forward+ renderer, Vulkan driver.
- One main scene that contains the Moon, a camera rig, the Sun and the environment.
- Moon as a sphere of the real mean radius, with a genuine LROC lunar albedo texture (see Stack and constraints).
- Orbit, zoom, rotate and pan camera controls, able to reach close-up surface distances.
- Adjustable sunlight through a DirectionalLight3D with runtime keyboard controls.
- `docs/DATA_SOURCES.md` documenting the texture dataset.

## Non-goals

- No real elevation data and no displacement. The M1 sphere is a plain, undisplaced sphere; this is a known gap, closed by Milestone 2.
- No general data pipeline in this milestone. The texture is prepared by the Rust crate `tools/texture-prep/`, with its exact command recorded in `docs/DATA_SOURCES.md`.
- No procedural, noise-based or otherwise synthetic texture or elevation, under any circumstances.
- No gameplay, vehicles, characters, physics, collision, NPCs, networking.
- No UI beyond the keyboard and mouse controls in this spec.
- No third-party addons or rendering frameworks.
- No dependency on any Road Rage Taxi code.
- No custom shader in M1 (`shaders/lunar_surface.gdshader` is a later milestone).
- No FPS or performance statistics in M1 (performance report is Milestone 4).

### Follow-up specs

- Milestone 2: Real elevation (DEM acquisition, data pipeline, displaced geometry, validation of major features).
- Milestone 3: Visual quality (lunar material, shadows, camera refinements, normal mapping if useful).
- Milestone 4: Performance and architecture (measurements, geometry limits, chunk/LOD architecture, streaming documentation).

## Stack and constraints

- Godot 4.x stable, GDScript for all scripts. Record the exact Godot version used in `docs/DATA_SOURCES.md` or the report. Godot is not yet installed in the repository, so the implementer must use an installed 4.x stable build or report BUILD_ISSUE.
- Renderer: Forward+. Rendering backend: Vulkan.
- No third-party rendering frameworks, no addons (`addons/` must not exist).
- Texture preparation is done by a Rust tool in `tools/texture-prep/` (a Cargo crate), using a pure-Rust or GDAL-based raster reader. No Python is used. The tool, its exact command and every dependency with its version must be listed in `docs/DATA_SOURCES.md`. The command must be repeatable: running it again on the same raw file gives the same processed texture.
- Keep the project independent of Road Rage Taxi.
- Folder layout follows section 9 of `docs/init-moon-poc.md` for M1:
  - `project.godot`
  - `scenes/main.tscn`, `scenes/moon.tscn`
  - `scripts/moon.gd`, `scripts/moon_camera.gd`, `scripts/sun_controller.gd`
  - `assets/textures/` (processed albedo texture)
  - `assets/elevation/` and `assets/materials/` may exist empty or with a `.gitkeep` file
  - `docs/DATA_SOURCES.md`
  - `shaders/`, `tools/`, `docs/ARCHITECTURE.md`, `docs/PERFORMANCE.md` are created in later milestones.
- Raw downloaded source data is stored in `data/raw/`, is never committed, and is never loaded directly by Godot (section 4 of the POC doc).

### Texture source (mandatory)

- Product: LROC WAC Global Morphologic Mosaic (GMM), 100 m/pixel global mosaic (about 303 pixels per degree), from the LROC image downloads (https://lroc.im-ldi.com/images/downloads or https://data.lroc.im-ldi.com/).
- Projection: equirectangular (equidistant cylindrical, longitude/latitude). If the source is delivered in another projection, reprojection must be documented and must not stretch the surface.
- Processed texture for M1: equirectangular, 4096 x 2048 pixels (about 11.4 pixels per degree), 8-bit RGB PNG, stored as `assets/textures/lunar_albedo_4096x2048.png`. Downsampling is the only permitted processing (no color grading, no contrast stretching that alters the surface look beyond the single documented step, no reprojection beyond what is documented).
- License: must be read from the download page or the product's readme at download time and copied verbatim into `docs/DATA_SOURCES.md`. Record the retrieval date and SHA-256 of the raw and processed files. If the stated license or usage terms do not clearly allow redistribution inside the repository, do not commit the texture; report BLOCKED with the license text.
- Credit: the LROC/ASU/NASA credit line from the product page is copied into the docs.

## Requirements

- **REQ-1**: The repository root contains `project.godot` that declares a Godot 4.x project named "Moon POC".
- **REQ-2**: `project.godot` sets the renderer to Forward+ (`rendering/renderer/rendering_method` = `"forward_plus"`) and the rendering driver to Vulkan (`rendering/rendering_device/driver` = `"vulkan"`).
- **REQ-3**: At runtime, the engine reports the renderer and driver actually in use: `RenderingServer.get_current_rendering_method()` returns `"forward_plus"` and `RenderingServer.get_current_rendering_driver_name()` returns `"vulkan"`.
- **REQ-4**: `scenes/main.tscn` is the project's main scene and contains the Moon, the camera rig, the Sun and a WorldEnvironment.
- **REQ-5**: The Moon is a sphere with radius 1737.4 units, where 1 unit = 1 km, and the sphere has no displacement (surface is at a constant radius).
- **REQ-6**: The Moon's surface shows the processed LROC albedo texture from `assets/textures/lunar_albedo_4096x2048.png`, mapped with equirectangular UVs (u = longitude, v = latitude), with no reprojection or stretching of the image at render time.
- **REQ-7**: Orientation: the lunar north pole points to the Moon node's local +Y axis, and the selenographic point (0° N, 0° E) lies on the local +Z axis.
- **REQ-8**: The longitude seam at ±180° is not visible to a human observer on the target display, at the default view and at a view centred on longitude ±180°. This is a visual check made by a person looking at the render; there is no numeric or automated seam threshold. No tonal correction beyond downsampling is applied to hide the seam: the known brightness step at 180° E in the source mosaic stays in the texture.
- **REQ-9**: The Moon uses a StandardMaterial3D (or equivalent) with metallic 0.0 and roughness at least 0.9, so it has no glossy highlight.
- **REQ-10**: The Sun is a DirectionalLight3D named "Sun" with shadows enabled, controlled by `scripts/sun_controller.gd`.
- **REQ-11**: The Sun direction is defined by azimuth (degrees, 0–360) and elevation (degrees, −90 to 90). The unit vector from the Moon toward the Sun is d = (cos(el)·sin(az), sin(el), cos(el)·cos(az)), in the Moon's frame (Moon at identity transform). The DirectionalLight3D's forward vector (its −Z axis) equals −d.
- **REQ-12**: Default Sun state is azimuth 45° and elevation 20°.
- **REQ-13**: Keyboard controls change the Sun at runtime: Left and Right arrows change azimuth by −5° and +5°; Up and Down arrows change elevation by +5° and −5°. Elevation is clamped to −90..90; azimuth wraps modulo 360.
- **REQ-14**: The environment has no sky, no ambient light, no fog and no glow: background mode is a solid black color, ambient light source is disabled, fog is disabled, glow is disabled.
- **REQ-15**: The camera (`scripts/moon_camera.gd`) orbits a pivot point, an exported Vector3 that defaults to the Moon's center. The orbit does not assume the pivot is the origin.
- **REQ-16**: Left mouse button drag is a screen-space trackball orbit, at 0.2° per pixel. The Moon behaves like a ball held in the hand: the camera's orbit around the pivot is rotated about axes taken from the camera's current screen, never from the Moon's own axes.
  - Horizontal drag of dx px rotates the Moon (relative to the camera) by 0.2 · dx° about the camera's screen up axis, through the pivot, in the direction that moves the surface under the cursor horizontally with the cursor (drag right → surface moves right). Equivalently, the camera orbits the pivot toward its own left.
  - Vertical drag of dy px rotates the Moon by 0.2 · dy° about the camera's screen right axis, through the pivot, so the surface under the cursor moves vertically with the cursor (drag down → surface moves down). Equivalently, the camera orbits toward its own up.
  - The axes are re-read from the camera at each drag event, so the result does not depend on where the Moon's poles are on screen. There is no pitch clamp: the camera can orbit over a pole without stopping or flipping, and the Moon's north can end up anywhere on screen, including upside down. The camera's distance from the pivot does not change.
- **REQ-17**: Mouse wheel zooms: each wheel notch multiplies the camera distance from the pivot by 0.95 (zoom in) or 1/0.95 (zoom out).
- **REQ-18**: The camera cannot pass the Moon's surface at any terrain point. Camera distance from the Moon's center is clamped to a minimum of maximum terrain radius + 0.5 km margin = 1747.732 + 0.5 = 1748.232 units (maximum terrain radius from `docs/VALIDATION.md`, REQ-30), and a maximum of 20000 units. Margin reason: 0.5 km keeps the camera and its near plane clear of the highest peak while still allowing close-up views.
- **REQ-19**: Middle mouse button drag pans the pivot in the camera's view plane, at a rate of distance × 0.0001 units per pixel of drag. Pan follows the same grab rule as REQ-16: the pivot moves opposite to the drag, so the content under the cursor moves in the same screen direction as the cursor.
- **REQ-20**: The camera near clip plane is at most 0.05 units (50 m) and the far clip plane is at least 50000 units, so surface close-ups do not clip.
- **REQ-21**: The default camera state, at startup, is at distance 6000 units from the pivot, looking at the pivot, with yaw 0° and pitch 0°, placing the camera on the local +Z side of the Moon so that the near side (sub-Earth hemisphere) is visible.
- **REQ-22**: `docs/DATA_SOURCES.md` documents the texture: product name, URL, retrieval date, original resolution and pixels per degree, projection, full license text or link, credit line, exact processing command(s), tool name and version used, and SHA-256 of the raw and processed files.
- **REQ-23**: The project contains no `addons/` directory and no reference to "Road Rage" or any Road Rage Taxi path or asset.
- **REQ-24**: The project launches with the main scene and runs for at least 10 seconds without ERROR or SCRIPT ERROR messages in the Godot output. This is an automated check run by the tester.
- **REQ-25**: `docs/DATA_SOURCES.md` documents the source mosaic's brightness step at 180° E: its location (column 2048 of the 4096-wide texture), its size (about 8 grey levels on average), and the statement that it was not corrected.
- **REQ-26** (revision): The texture produced by `tools/texture-prep/` decodes to pixel-identical data with the current `assets/textures/lunar_albedo_4096x2048.png`: 4096 × 2048, 8-bit RGB, every pixel's RGB values equal. The PNG file bytes may differ because of the encoder; if the file's SHA-256 changes, `docs/DATA_SOURCES.md` records the new SHA-256 and the reason (different PNG encoder, same decoded pixels).

## Acceptance criteria

| REQ | Given | When | Then |
|---|---|---|---|
| REQ-1 | Repository root | Read `project.godot` | Contains `config/name="Moon POC"` and `config_version=5` (Godot 4 format) |
| REQ-2 | `project.godot` | Search for renderer keys | `rendering_method="forward_plus"` and `driver="vulkan"` are present |
| REQ-3 | Project run in a window on a system with a Vulkan driver | Print both `RenderingServer` getters on startup | Outputs `forward_plus` and `vulkan` |
| REQ-4 | Project run | Inspect scene tree | Nodes Moon, CameraRig (with Camera3D), Sun (DirectionalLight3D), WorldEnvironment exist under main |
| REQ-5 | Moon sphere mesh | Sample mesh vertices and compute their distance from the Moon center | All distances equal 1737.4 ± 0.1 units |
| REQ-6 | Texture file and Moon material | Inspect material | Albedo texture resource is `assets/textures/lunar_albedo_4096x2048.png`; file is 4096×2048 |
| REQ-7 | Moon at identity transform | Compute the world direction of the point at 90° N and of (0° N, 0° E) | North pole maps to +Y; (0° N, 0° E) maps to +Z |
| REQ-8 (visual check) | Project running on the target display, (a) default view and (b) camera view centred on longitude ±180° | A person looks at the render | The seam is not visible to the observer in either view; the result is recorded in the report as a visual check, not as an automated test. The texture file has had no tonal correction beyond downsampling |
| REQ-9 | Moon material | Read properties | `metallic == 0.0`, `roughness >= 0.9` |
| REQ-10 | Main scene | Read Sun node | `DirectionalLight3D`, `shadow_enabled == true` |
| REQ-11 | Sun azimuth 90°, elevation 30° | Read light global forward vector | Equals −(0.866, 0.5, 0.0) to within 0.001 |
| REQ-12 | Fresh start | Read sun_controller values | Azimuth 45, elevation 20 |
| REQ-13 | Sun at azimuth 45, elevation 20 | Press Right arrow once, Up arrow once | Azimuth 50, elevation 25 |
| REQ-13 (wrap/clamp) | Sun at azimuth 358, elevation 88 | Press Right arrow once, Up arrow three times | Azimuth 3, elevation 90 (clamped) |
| REQ-14 | Main scene | Read Environment | Background mode color black, ambient source disabled, fog off, glow off |
| REQ-15 | Pivot set to (0, 0, 0) and then to (10, 0, 0) through the export | Rotate with a drag | Camera orbit center follows the pivot; the camera stays at its distance from the pivot |
| REQ-16 | Camera at default state | Drag left mouse 100 px right | The camera's offset from the pivot has rotated 20° (±0.5°) about the camera's screen up axis, toward camera-left; distance unchanged (±0.01) |
| REQ-16 (grab direction) | Camera at default state (near side visible, (0° N, 0° E) at screen centre) | Drag left mouse 100 px right, then from default drag 100 px down | After the right drag, (0° N, 0° E) is right of screen centre at the same screen height. After the down drag, it is below screen centre at the same screen x. Left and up drags give the mirrored results |
| REQ-16 (no pole stop) | Camera at default state | Drag left mouse 1000 px down in steps of 10 px | The camera's offset rotates 200° (±1°) in total about the screen right axis, passing over the north pole without stopping; no step changes the view direction by more than 2.5°; no NaN |
| REQ-16 (pole independence) | Camera at default state, then left drag 450 px down, so the camera is above the north pole looking straight at it (pole at screen centre) | Drag left mouse 100 px right | The point at screen centre before the drag (the north pole) moves right of screen centre at the same screen height; the camera's offset rotated 20° (±0.5°) about the camera's current screen up axis, which is perpendicular to the Moon's Y axis. The view does not spin about the pole as a fixed-axis yaw would |
| REQ-17 | Distance 6000 | One wheel notch in | Distance is 5700 (±0.5); one notch out from 5700 gives 6000 (±0.5) |
| REQ-18 | Distance 6000 | Wheel in 100 notches | Distance equals 1748.232 (±0.01, minimum), never below it, so the camera is above the surface at every terrain point; wheel out 50 notches gives 20000 |
| REQ-19 | Distance 6000, pivot at center | Middle drag 100 px right | Pivot moves 60 units in the camera-left direction (±0.5), so the Moon moves right on screen with the cursor; a 100 px middle drag down moves the pivot 60 units in the camera-up direction, so the Moon moves down on screen |
| REQ-20 | Read camera | Inspect properties | `near <= 0.05` and `far >= 50000` |
| REQ-21 | Fresh start | Read camera transform | Distance 6000 from pivot, camera on +Z side, looking at pivot |
| REQ-22 | `docs/DATA_SOURCES.md` | Review | All listed fields present; SHA-256 values match the files in `data/raw/` and `assets/textures/` |
| REQ-23 | Full repository | `find` for `addons/`; grep for "Road Rage" (case-insensitive) | No `addons/` directory; zero matches |
| REQ-24 (automated) | Main scene | Tester runs the project automatically for 10 s and captures the Godot output | No ERROR or SCRIPT ERROR lines in the output |
| REQ-25 | `docs/DATA_SOURCES.md` | Review | States the brightness step at 180° E, column 2048 of the 4096-wide texture, about 8 grey levels on average, and that it was not corrected |
| REQ-26 | Current texture and raw source in `data/raw/` | Run the documented `tools/texture-prep/` command twice; decode both outputs and the current texture | All three are 4096×2048 8-bit RGB with identical RGB values at every pixel; if the PNG SHA-256 differs from the old value, `docs/DATA_SOURCES.md` lists the new SHA-256 and the reason; all crate dependencies are listed with versions |

## Edge cases and errors

- **Texture download impossible** (no network, authentication required, license unclear, or source unreadable): do not substitute a procedural or other dataset. Document the blocker in `docs/DATA_SOURCES.md` (what was attempted, the error or license text, date) and report BLOCKED with the reason. Do not commit a placeholder texture.
- **Texture file missing at runtime**: the project must not fall back to a generated texture. The Moon renders with a plain material and an error is printed to the output; this counts as a failure of REQ-6.
- **Source in a non-equirectangular projection**: reprojection must be documented with the command and CRS; a stretched result is a failure of REQ-6.
- **Orbit over a pole**: there is no pitch clamp (REQ-16). Passing over a pole gives a continuous view with no sudden flip, jump or NaN.
- **Zoom beyond limits**: wheel input is ignored past the clamp; no error is printed.
- **Sun elevation at ±90°**: direction stays valid (no NaN); azimuth is still applied.
- **Window without Vulkan support**: the project must print the engine's renderer and driver names so the failure is visible; REQ-3 fails if the renderer falls back to another method.
- **Sun direction exactly parallel to the camera view**: no requirement; the Moon remains rendered.

## Assumptions

- 1 Godot unit = 1 km, so the Moon radius is 1737.4 units and camera distances are in km.
- Milestone 1 sphere is a standard Godot SphereMesh with enough segments (at least 256 radial, 128 rings) to show the texture detail; this is a choice of the implementer within that minimum.
- Texture resolution 4096×2048 is chosen as a reasonable M1 size; higher resolutions are a Milestone 3 concern.
- Keyboard keys for the Sun use arrow keys because they do not conflict with mouse controls.
- Mouse controls are the standard desktop scheme (left drag orbit, wheel zoom, middle drag pan).
- No custom shader in M1; StandardMaterial3D is sufficient for the M1 requirements.
- Camera pivot defaults to the Moon's center, with pan allowed to move it.
- Lunar selenographic orientation: north up in the standard Earth-side view, with Mare Imbrium toward the upper-left and Mare Crisium toward the right of the near-side disc at the default camera view. The tester can use this as a visual check that the texture is oriented correctly.

## Open questions

None. The license, resolution and blocker behavior are specified; the final license text must be read at download time (see Stack and constraints).

## Revision history

- 2026-11-10: Initial spec for Milestone 1 (basic lunar globe), based on `docs/init-moon-poc.md` sections 1–3, 5–7, 9, 11, 12.
- 2026-11-10: REQ-8 seam acceptance changed to a human visual check (default view and view centred on ±180°), no numeric/automated threshold, no tonal correction beyond downsampling; added REQ-25 requiring DATA_SOURCES.md to document the uncorrected 180° E brightness step (column 2048, about 8 grey levels); REQ-24 clarified as an automated tester check for ERROR/SCRIPT ERROR over 10 s. License wording unchanged.
- 2026-11-10: User reported reversed mouse control. REQ-16 now uses a grab convention (surface under the cursor moves with the cursor; pitch positive = camera toward +Y, drag down raises pitch); REQ-16 clamp criterion changed from −89° to +89° and a grab-direction acceptance criterion added; REQ-19 middle-drag pan follows the same grab rule (100 px right moves pivot camera-left). Zoom and Sun controls unchanged.
- 2026-11-10: User instruction "use rust, no python anywhere". Texture preparation is now a Rust Cargo crate `tools/texture-prep/` (pure-Rust or GDAL-based reader) instead of GDAL CLI or Python; dependencies with versions listed in `docs/DATA_SOURCES.md`; command stays repeatable and documented. Added REQ-26: decoded output pixel-identical to the current texture; a changed PNG SHA-256 is recorded with its reason. No other requirement or number changed.
- 2026-11-10: Non-goals line about `tools/prepare_moon_data.py` replaced with a reference to the Rust crate `tools/texture-prep/` (command recorded in `docs/DATA_SOURCES.md`), removing the leftover Python reference. No requirement changed.
- 2026-11-11: User request "limit the zoom in to moon's surface and make it slower". REQ-17 wheel factor 0.9 → 0.95 (one notch in from 6000 gives 5700); REQ-18 minimum distance 1737.9 → 1748.232 (maximum terrain radius 1747.732 from VALIDATION.md REQ-30 + 0.5 km margin), camera cannot pass the surface at any terrain point; REQ-18 acceptance uses 100 notches in. Maximum 20000, orbit and pan unchanged.
- 2026-11-11: User decision: left-drag orbit is a screen-space trackball. REQ-16 rewritten: horizontal drag rotates the Moon about the camera's screen up axis, vertical drag about the screen right axis, 0.2°/px, grab direction kept, independent of the poles' screen position. The ±89° pitch clamp is removed because a trackball has no pitch angle and no gimbal flip; the camera may cross the poles. REQ-16 acceptance rows rewritten and two added (no pole stop, pole independence); the "Pitch at poles" edge case replaced. REQ-21 default (yaw 0, pitch 0) remains the start orientation. Right-drag look and middle-drag pan unchanged.
- 2026-11-11: User decision. REQ-20 near clip limit 0.01 → 0.05 units (fixes a Godot light-culling error from the depth range ratio); acceptance row updated. Far ≥ 50000 unchanged. Nothing else changed.
