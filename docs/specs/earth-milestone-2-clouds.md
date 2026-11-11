# Earth Milestone 2: Procedural clouds

Status: Ready
Slug: earth-milestone-2-clouds

## Goal

Add two procedural cloud layers to the Earth from Earth Milestone 1, as asked by Milestone 2 of `docs/earth-sky.md` section 13. The clouds are made by shader noise sampled from directions on the sphere, so they have no seam and no polar pinching. Each layer drifts and changes shape on its own, and the same Sun that lights Earth lights them too. Everything Earth Milestone 1 requires stays as it is.

## Scope

- Lower cloud layer: large, soft, fairly dense systems.
- Upper cloud layer: smaller, thin, broken-up clouds that move at a different speed and in a different direction.
- 3D noise sampled from Earth-fixed direction vectors (no UV input).
- Cloud animation driven by the live UTC clock (the `utc` field of the latest applied streamed line).
- Coverage and density settings for each layer.
- Seam, polar, illumination and performance checks.

## Non-goals

- Atmospheric rim, scattering, better cloud lighting (Earth Milestone 4 of `docs/earth-sky.md`).
- Cloud shadows on the surface, clouds casting shadows on the Moon, and the Moon's shadow on clouds.
- Weather realism: real cloud data, a link to season or geography, storms that follow climate zones.
- Volumetric or ray-marched clouds.
- A quality setting for cloud complexity (number of octaves) and a runtime UI for the settings. Both are left to Milestone 4 optimisation.
- Time acceleration or a date picker. Without them, cloud drift is too slow to see during a session (see Assumptions).
- Any change to the Moon terrain, its material or shaders, the Sun controls, the ephemeris crate, the streamed fields, or the monthly texture handling (Earth M1 REQ-12 to REQ-17).

## Stack and constraints

- Godot 4.7.2-stable, GDScript, Forward+ on Vulkan, 1 unit = 1 km, as in Earth M1.
- All Earth M1 requirements (REQ-1 to REQ-25) still hold. Earth M1 REQ-7 ("no other Earth child nodes") is extended by REQ-1 below to allow the two cloud nodes. No other part of Earth M1 changes.
- The Sun direction for the clouds is the scene Sun light, which is driven by `sun_dir_godot` from the streamed line. GDScript and the shaders do no Sun or ephemeris calculation of their own (Earth M1 REQ-25, `docs/earth-sky.md` section 14).
- Cloud density is computed on the GPU in a shader. No cloud image file is used, and no texture is generated on the CPU, neither per frame nor at startup.
- The 12 monthly textures stay out of the repository (Earth M1 REQ-15).

## Requirements

### Layers

- **REQ-1**: `EarthRoot` gains two children, `CloudLower` and `CloudUpper`. Each is a MeshInstance3D with a sphere mesh of at least 128 radial segments and 64 rings, the same as `EarthSurface`. Their radii (mesh radius times any scale) are 6373.0 ± 0.5 for `CloudLower` (2 km, a typical low-cloud altitude) and 6381.0 ± 0.5 for `CloudUpper` (10 km, a typical cirrus altitude). These are real altitudes, not exaggerated. Both nodes are hidden whenever `EarthRoot` is hidden (Earth M1 REQ-9, REQ-18).
- **REQ-2**: Lower layer shape. With default settings, the spatial correlation of lower-layer opacity at two points 500 km apart on the shell is at least 0.5 (synoptic weather systems are 1000 to 3000 km across). Edges are soft: along any great circle, opacity goes from 0.05·cap to 0.95·cap over at least 50 km at the median edge crossing. "cap" is the layer's opacity cap from REQ-4.
- **REQ-3**: Upper layer shape. With default settings, the correlation of upper-layer opacity at two points 500 km apart is at most 0.3 (cirrus bands are tens to a few hundred km wide). The upper layer has at least 3 times as many separate cloud patches (connected regions with opacity > 0.05) as the lower layer, counted on the same 2048 × 1024 equirectangular sampling of each layer.
- **REQ-4**: Opacity caps. With density = 1, no fragment of `CloudLower` has alpha above 0.85, and no fragment of `CloudUpper` has alpha above 0.40. The surface must still show through thick low cloud, and cirrus is thin, so neither layer is opaque. Where both layers overlap, the combined alpha is at most 1 − (1 − 0.85)·(1 − 0.40) = 0.91.
- **REQ-5**: Drift. Each layer turns relative to the Earth surface about Earth's axis (Earth-fixed +z), in the Earth-fixed frame, at a fixed angular rate:

  | Layer | Equatorial speed | Direction | Rate | Reason |
  |---|---|---|---|---|
  | Lower | 10 m/s | westward | −9.0e-5 °/s (10 m/s ÷ 6373 km) | trade-wind easterlies, typical low-level wind |
  | Upper | 30 m/s | eastward | +2.6938e-4 °/s (30 m/s ÷ 6381 km = 4.7015e-6 rad/s) | upper-level westerlies, typical jet-level wind |

  The drift angle is the rate times (t − t0), where t is the `utc` of the latest applied streamed line and t0 = 2000-01-01T12:00:00Z (J2000). This makes the angle depend only on the date, not on when the program started. The drift is in addition to Earth's own rotation, which the clouds inherit from `EarthRoot`.
- **REQ-6**: Shape change. Besides the drift, each layer's noise also moves along a time axis, so the pattern does not look like a static picture turning. Once the REQ-5 drift is removed, the mean absolute opacity difference between t and t + τ (sampled at 10 000 uniformly distributed directions) is at least 0.1·cap for τ = 6 h on the lower layer and for τ = 2 h on the upper layer. These timescales are typical for synoptic systems and for cirrus. Over 1 s the same difference is at most 0.001·cap, so the pattern changes continuously and does not jump.
- **REQ-7**: Both layers use the same clock, the `utc` of the latest applied streamed line. They keep their last state when the helper fails (Earth M1 REQ-9). No other time source is used (for example, wall clock or `Time` ticks).

### Noise

- **REQ-8**: Spherical noise. Cloud opacity is a function only of the unit Earth-fixed direction (rotated by the REQ-5 drift), the REQ-6 time and the REQ-11 settings. It is computed in the cloud shader from 3D noise (Perlin, simplex or value noise, fBm allowed, domain warping allowed). The cloud shaders do not read `UV` or `UV2` for opacity, and the cloud materials have no texture whose content sets cloud shape.
- **REQ-9**: Seam. For 1000 latitudes evenly spaced from −89.9° to 89.9°, the opacity at longitude 179.999° and at −179.999° differ by at most 0.01 in each layer. **User-run (needs a display):** in a frame with the camera at 3·R_E from Earth's centre, over the equator at longitude 180°, with Earth filling the view, no straight line or step is visible along the 180° meridian.
- **REQ-10**: Poles. The 500 km correlation from REQ-2 and REQ-3, measured over points with |latitude| ≥ 85°, is within ± 0.1 of the same value measured over points with |latitude| ≤ 5°, for each layer. Within 5° of a pole, opacity has no pinched or radial pattern: for directions at latitude 89.9°, opacity never differs by more than 0.01 between two longitudes less than 1° apart. **User-run (needs a display):** in a frame with the camera at 3·R_E above each pole, looking at it, the clouds show no star, swirl-to-a-point or streaks meeting at the pole.

### Coverage and density

- **REQ-11**: Each layer has two exported settings on its material or script, each in 0..1: `coverage` and `density`. Defaults: lower coverage 0.55, density 1.0; upper coverage 0.25, density 1.0. These defaults give a combined cloud fraction of 1 − (0.45 · 0.75) = 0.66, close to the observed global mean of about 67 %. Values outside 0..1 are clamped.
- **REQ-12**: Coverage. Over 10 000 uniformly distributed directions at any time, the fraction with layer opacity > 0.05 equals the `coverage` setting within ± 0.05, for settings 0.1, 0.25, 0.5, 0.75 and 0.9. With coverage 0, no fragment has alpha > 0.0. With coverage 1, the fraction is at least 0.95.
- **REQ-13**: Density scales opacity. With density d, every sample's alpha equals d times its alpha at density 1, within 0.005. With d = 0, the layer is fully transparent.

### Illumination

- **REQ-14**: The cloud materials are lit, not unshaded. They are lit only by the existing scene Sun light, the same one as Earth (Earth M1 REQ-25). No cloud script or shader holds a Sun vector.
- **REQ-15**: Day and night. With the camera placed as in Earth M1 REQ-21, a cloud pixel at the subsolar point is at least 10 times brighter than a cloud pixel at the antisolar point. The cloud lit/unlit boundary is within 2° of Earth's surface terminator along the same line of sight, so the clouds are lit the same way as the surface.

### Performance

- **REQ-16**: Adding the clouds adds at most 2 draw calls (one per layer). The cloud nodes do no per-frame work except setting shader parameters (no `Image` or texture created or changed after startup). Measured by user run, `make perf` windowed, reading `RENDER_TOTAL_DRAW_CALLS_IN_FRAME`.
- **REQ-17**: Frame time budget. Measured by user run (needs a display) with `make perf` windowed, method as in `docs/PERFORMANCE.md` (120 warm-up frames, 10 s sample). Add a camera position `earth_close` at 3·R_E from Earth's centre, looking at it, so Earth fills most of the view: this is the worst case for overdraw from the clouds. Compare two runs, clouds visible and clouds hidden. The median frame time with clouds visible is at most 1.0 ms higher than with clouds hidden (1.0 ms is 6 % of a 16.7 ms frame at 60 FPS). At `orbit_default` the difference is at most 0.2 ms, because Earth is only about 1.8° wide there. Both values are recorded in `docs/PERFORMANCE.md` with machine, GPU and date. Until the user runs this, they are recorded as "pending user run" and REQ-17 is open.

### Validation and documentation

- **REQ-18**: The project runs 10 s with the helper and textures present, with no ERROR or SCRIPT ERROR lines (same check as Earth M1 REQ-23). Earth M1 REQ-19 to REQ-22 still pass with the clouds present. In the REQ-19 and REQ-22 frames the clouds show no z-fighting or flicker against the surface or each other.
- **REQ-19**: Documentation. `docs/ARCHITECTURE.md` (Earth section) describes the cloud nodes, the shader, the clock input and the settings. A "Known approximations" list, there or in `docs/PERFORMANCE.md` and linked, states at least the following:
  - Clouds are noise with no link to real weather or geography.
  - The drift is solid-body rotation, the same at every latitude.
  - The shells are thin and have no volume.
  - There are no cloud shadows.
  - The lighting is the standard lit shading, with no scattering.
  - At live speed the drift is too slow to see.
  - The altitudes are fixed at 2 km and 10 km.

### Test scope

- **REQ-20**: Headless cloud tests are small and limited in scope. Each test samples only the points it needs, using the fixed number in the table below. All headless cloud tests together finish in under 10 s of wall-clock time. Any check that needs more samples or a windowed run is a user-run display check (marked "user-run" in the acceptance criteria), not a headless test. Headless tests cover only the rows below. The tolerances are the same as in the requirements they check.

  | Headless test | Checks | Samples |
  |---|---|---|
  | Layer heights | REQ-1 radii, segments, rings, hidden with no helper | 0 (read node properties) |
  | Opacity caps and overlap | REQ-4 | 200 directions per layer at coverage 1, density 1 |
  | Drift rates | REQ-5 | 0 (read the drift angle at 2 streamed times) |
  | Coverage settings | REQ-12 at coverage 0, 0.25, 0.5, 1 | 1000 directions per setting per layer (8000 in total). 1000 samples give a standard error of about 0.016 on the fraction, inside ± 0.05 |
  | Clamping | REQ-11 defaults and clamping of −0.5 and 1.5 | 0 (read settings) |
  | Alpha limits (density) | REQ-13 at density 0, 0.5, 1 | 100 directions per density per layer |
  | Seam | REQ-9 | 1 pair: latitude 0°, longitudes 179.999° and −179.999°, per layer |
  | Pole | REQ-10 longitude part | 1 pair: latitude 89.9°, longitudes 0° and 0.9°, per layer |

  REQ-2, REQ-3, REQ-6, the REQ-9 1000-latitude sweep, the REQ-10 correlation comparison, and the REQ-12 10 000-direction count at the other coverage values (0.1, 0.75, 0.9) are user-run display checks.

## Acceptance criteria

| REQ | Given | When | Then |
|---|---|---|---|
| REQ-1 | Main scene | Inspect the tree, mesh radii, segments, rings, scale; start with no helper | `CloudLower` 6373.0 ± 0.5, `CloudUpper` 6381.0 ± 0.5, both ≥ 128/64, children of `EarthRoot`; both hidden with no helper |
| REQ-2 | **User-run display check, not headless (REQ-20).** Default settings, fake helper line `2026-11-10T00:00:00Z` | Sample lower opacity on a 2048 × 1024 equirectangular grid; compute correlation at 500 km and edge widths | Correlation ≥ 0.5; median edge width ≥ 50 km |
| REQ-3 | **User-run display check, not headless (REQ-20).** Same as REQ-2 | Same for the upper layer; count patches with opacity > 0.05 in both | Correlation ≤ 0.3; upper patches ≥ 3 × lower patches |
| REQ-4 | density 1, coverage 1 | Sample the maximum alpha per layer and of the overlap | ≤ 0.85, ≤ 0.40, ≤ 0.91 |
| REQ-5 | Fake helper lines at `2026-11-10T00:00:00Z` and +3600 s | Read each layer's drift angle about Earth-fixed +z | Lower changes by −0.324° ± 0.001°, upper by +0.9698° ± 0.001° (2.6938e-4 °/s × 3600 s = 0.96977°); angle at t equals rate · (t − J2000) |
| REQ-6 | **User-run display check, not headless (REQ-20).** Lines at t, t + 1 s, t + 2 h, t + 6 h | Sample 10 000 directions, drift removed | Lower at 6 h and upper at 2 h: mean abs difference ≥ 0.1·cap; at 1 s: ≤ 0.001·cap |
| REQ-7 | Helper streams then stops | Read cloud state before and after the stop; grep the cloud scripts | Unchanged after stop; no wall-clock time source |
| REQ-8 | Cloud shader sources and materials | Review | Opacity from direction, time and settings only; no `UV`/`UV2` use for opacity; no cloud-shape texture |
| REQ-9 | Any time | Headless: 1 pair at latitude 0°, ±179.999°, per layer. User-run: the 1000-latitude sweep and the frame at lon 180° | Difference ≤ 0.01; user sees no seam |
| REQ-10 | Any time | Headless: 1 pair at latitude 89.9°, longitudes 0° and 0.9°, per layer. User-run: compare the 500 km correlation at the poles and at the equator, and the polar frames | ≤ 0.01 across the pair; correlation within ± 0.1; user sees no polar pattern |
| REQ-11 | Materials | Read defaults; set −0.5 and 1.5 | Defaults 0.55/1.0 and 0.25/1.0; clamped to 0 and 1 |
| REQ-12 | Headless: coverage ∈ {0, 0.25, 0.5, 1}, 1000 directions each per layer. User-run: coverage ∈ {0.1, 0.75, 0.9} with 10 000 directions | Sample | Fractions within ± 0.05; 0 gives no alpha; 1 gives ≥ 0.95 |
| REQ-13 | density ∈ {0, 0.5, 1} | Sample the same directions | alpha(d) = d · alpha(1) ± 0.005 |
| REQ-14 | Scene and shaders | Inspect | Lit materials; only the Sun light; no Sun vector |
| REQ-15 | Camera as in Earth M1 REQ-21 | Render day and night sides | Day cloud ≥ 10 × night cloud; cloud terminator within 2° of the surface terminator |
| REQ-16 | `make perf` windowed (user-run) | Clouds visible vs hidden | Draw calls differ by ≤ 2; no texture is created after startup |
| REQ-17 | `make perf` windowed (user-run), positions `earth_close` and `orbit_default` | Clouds visible vs hidden | Median frame time difference ≤ 1.0 ms and ≤ 0.2 ms; recorded in `docs/PERFORMANCE.md` |
| REQ-18 | Helper and textures present | Run 10 s; rerun Earth M1 REQ-19 to REQ-22 | No ERROR lines; M1 checks pass; no z-fighting |
| REQ-19 | Docs | Review | All listed items present |
| REQ-20 | Headless cloud test suite | Run it and time it; count the samples in each test | Total < 10 s; each test uses at most its sample count from the REQ-20 table; no test covers a user-run row |

## Edge cases and errors

- **No streamed line yet**: the clouds are hidden with Earth (REQ-1).
- **Helper failure**: the clouds keep their last drift and time (REQ-7).
- **Textures missing** (Earth M1 edge case): the clouds still render over the plain Earth material.
- **Settings out of range**: clamped to 0..1 (REQ-11).
- **Float precision**: (t − J2000) is about 8.4e8 s in 2026. If it is passed to the GPU as one 32-bit float, its resolution is about 64 s, which would make the motion jump. The REQ-6 1-second continuity check must hold, so the time value must reach the shader without losing precision. How this is done is up to the implementer.
- **Depth**: the 2 km gap at about 400 000 km with near 0.01 must not z-fight (REQ-18).

## Assumptions

- Real wind speeds and the live clock mean the drift is about 0.32° per hour for the lower layer and about 0.97° per hour for the upper layer. From the Moon this is about 1 to 2 pixels per hour, so it cannot be seen in a session. This follows from "use the same live UTC clock" and "no time acceleration", and it is checked numerically (REQ-5, REQ-6) and not by eye.
- Opacity and correlation checks may sample the shader's opacity function in a test viewport or render target. How the tester samples it is not set here.
- The 1.0 ms and 0.2 ms budgets are chosen here, not taken from any earlier measurement. There are no measured windowed frame times yet (`docs/PERFORMANCE.md` lists them as pending user run).
- Cloud altitudes, wind speeds, timescales, opacity caps and the default coverages are typical climatological values, chosen for plausibility. They are not fitted to data.
- The `earth_close` perf position is an addition to the `make perf` script, not a change to the Moon perf positions.

## Open questions

None.

## Revision history

- 2026-11-11: Revision 3, coordinator fix. REQ-5: the upper drift rate is now written exactly as 2.6938e-4 °/s, replacing the rounded 2.69e-4. The REQ-5 acceptance row now expects +0.9698° ± 0.001° over 3600 s, replacing +0.968°, so the exact value 0.96977° is inside the tolerance. Nothing else changed.
- 2026-11-11: Revision 2, user request: small headless tests. Added REQ-20, with a sample count for each headless test and a total time under 10 s. REQ-2, REQ-3 and REQ-6 acceptance rows marked as user-run display checks. REQ-9, REQ-10 and REQ-12 rows split into headless and user-run parts. REQ-20 acceptance row added. All other requirements and numbers unchanged.
- 2026-11-11: Initial spec. Two procedural cloud shells (2 km and 10 km), direction-based 3D noise, drift and shape change from the streamed UTC, coverage and density settings, seam, polar, illumination and performance checks, approximations documented.
