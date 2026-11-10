# Sun Ephemeris, Sun Disc and Elevation Audit

Status: Ready
Slug: sun-ephemeris-and-sun-disc

## Goal

Milestone 1 lights the Moon from an arbitrary default direction (azimuth 45°, elevation 20°). This spec replaces that default with the real direction of the Sun as seen from the Moon at a given UTC time. A new Rust ephemeris crate computes the direction. The spec also draws the Sun as a visible disc with its real angular diameter, and it audits the M1 claim that the globe has no elevation data.

## Scope

- Elevation audit: confirm the M1 sphere is undisplaced, has radius 1737.4 km, and that `docs/DATA_SOURCES.md` states that no elevation data is used.
- Orientation audit: confirm the texture's east longitudes lie on the side of the sphere that the frame mapping in REQ-9 expects.
- New Rust crate `ephemeris/` (library + CLI): low-precision apparent Sun position, low-precision Moon position, IAU lunar rotation model, output of the Moon-to-Sun unit vector and distance in the Moon-fixed frame.
- Makefile targets that install a pinned Rust toolchain with rustup, build and test the crate, and generate the ephemeris file that Godot reads.
- Godot: the Sun light's startup direction comes from the generated file; a Sun disc is drawn in that direction with the correct angular diameter.

## Non-goals

- Real LOLA or SLDEM elevation, displacement, or terrain. This is Milestone 2.
- Changing the albedo texture, the M1 orbit, pan and zoom controls, or the camera clip planes.
- Changing the time while the game runs, or animating the Sun over time.
- Earth, Earthshine, stars, a sky, lens flare, glow or bloom around the Sun.
- High-precision ephemerides (JPL DE files, SPICE kernels), light-time correction beyond what the chosen formulas include, or topocentric corrections for a point on the lunar surface.
- A GDExtension. The integration is a generated file (see Stack and constraints).
- Python, anywhere in the project. The ephemeris and all offline data work are in Rust.

## Stack and constraints

- Godot 4.7.2-stable (pinned in the Makefile), GDScript, Forward+ on Vulkan, as in Milestone 1.
- Rust, stable channel, pinned to one exact version (assumed 1.90.0) in `ephemeris/rust-toolchain.toml`. The toolchain is not installed on the machine; the Makefile installs it.
- Crate layout: `ephemeris/Cargo.toml`, a library target and a binary target named `moon-ephemeris`. No crates other than the Rust standard library are required; if the implementer adds a dependency, it must be justified in the crate's README and pinned in `Cargo.lock`, which is committed.
- **Integration choice: generated file.** `make ephemeris` runs the CLI and writes `assets/ephemeris/sun_moon_fixed.json`. Godot reads this file at startup with `FileAccess` and `JSON`. This needs no native code in Godot and no process launch from Godot. The file is committed so that the project runs without Rust installed.
- Methods (documented in the crate's README with chapter or section references):
  - Time: input in UTC; Terrestrial Time TT = UTC + 69.2 s (fixed ΔT, see Assumptions). Julian Date from the calendar date by Meeus, *Astronomical Algorithms*, 2nd ed., chapter 7.
  - Sun: apparent geocentric position by Meeus chapter 25 ("low accuracy", including nutation in longitude and aberration), or the equivalent Astronomical Almanac low-precision formula (section C). Distance in AU, 1 AU = 149 597 870.7 km.
  - Moon: geocentric position by Meeus chapter 47 (the full or truncated ELP-2000/82 series), or the Astronomical Almanac low-precision Moon formula (section D).
  - Moon-to-Sun vector: geocentric Sun vector minus geocentric Moon vector, in the ICRF/J2000 equatorial frame. Positions of date must be precessed to J2000 (Meeus chapter 21) before this step, or the method must already give J2000 coordinates.
  - Rotation to the Moon-fixed frame: IAU WGCCRE lunar rotation model (Archinal et al. 2011, "Report of the IAU Working Group on Cartographic Coordinates and Rotational Elements: 2009", Table 2), pole α0, δ0 and prime meridian W, with all periodic terms E1 to E13. The resulting frame is the IAU mean-Earth/polar-axis approximation: +x toward (0° N, 0° E), +z toward the north pole, +y toward (0° N, 90° E).
- Sun radius: R_sun = 695 700 km (IAU 2015 Resolution B3 nominal solar radius).
- Godot frame mapping (follows M1 REQ-7 and REQ-11): a Moon-fixed vector (x, y, z) maps to Godot local (X, Y, Z) = (y, z, x). This is a cyclic permutation, so handedness is preserved. With it, M1 azimuth equals selenographic east longitude of the subsolar point, and M1 elevation equals its latitude.

## Requirements

### Elevation and orientation audit

- **REQ-1**: The Moon mesh has no displacement: every vertex of the rendered Moon mesh is at distance 1737.4 ± 0.1 units from the Moon's centre, and no displacement, height map or vertex-offset shader is assigned to the Moon.
- **REQ-2**: The Moon radius used by the scene is 1737.4 units (1 unit = 1 km).
- **REQ-3**: `docs/DATA_SOURCES.md` states that no elevation data is used yet, that `assets/elevation/` holds no elevation file, and that real elevation (LOLA or SLDEM) is planned for Milestone 2. `assets/elevation/` contains no file other than `.gitkeep`.
- **REQ-4**: Texture orientation matches the frame mapping. With the Moon at identity transform, the surface point at (0° N, 90° E) lies on local +X, the point at (0° N, 0° E) on local +Z, and the north pole on local +Y. The texture is not mirrored: the texel for 90° E (column 1024 of the 4096-wide texture) is shown on the +X side.

### Rust toolchain and crate

- **REQ-5**: `make rust-setup` installs rustup (if missing) and the exact toolchain named in `ephemeris/rust-toolchain.toml`, without changing the system's default toolchain beyond what rustup needs. Running it a second time makes no changes and exits 0.
- **REQ-6**: `make ephemeris-test` runs `cargo test` in `ephemeris/` with the pinned toolchain and exits 0 when all tests pass. The tests include the reference checks in REQ-11 and REQ-12.
- **REQ-7**: The CLI `moon-ephemeris` accepts one UTC time as an ISO 8601 argument of the form `YYYY-MM-DDTHH:MM:SSZ`. With no argument it uses `2026-11-10T00:00:00Z`.
- **REQ-8**: The CLI prints one JSON object to standard output and exits 0. Fields:

  | Field | Meaning |
  |---|---|
  | `utc` | Input time, ISO 8601 with `Z` |
  | `jd_tt` | Julian Date in TT |
  | `frame` | The string `"IAU_MOON"` (mean-Earth/polar-axis approximation, axes as in Stack and constraints) |
  | `sun_dir_moon_fixed` | Array [x, y, z], unit vector from the Moon's centre to the Sun's centre in the Moon-fixed frame |
  | `sun_dir_godot` | Array [X, Y, Z] = [y, z, x] of the above |
  | `subsolar_lon_deg` | East longitude of the subsolar point, 0 ≤ value < 360 |
  | `subsolar_lat_deg` | Latitude of the subsolar point, −90..90 |
  | `sun_distance_km` | Distance from the Moon's centre to the Sun's centre |
  | `sun_angular_diameter_deg` | 2·asin(R_sun / sun_distance_km), in degrees |

- **REQ-9**: The two direction arrays are unit vectors (length 1 ± 1e-9), and `subsolar_lon_deg`, `subsolar_lat_deg` and `sun_dir_moon_fixed` describe the same direction (x = cos(lat)·cos(lon), y = cos(lat)·sin(lon), z = sin(lat), each within 1e-9).
- **REQ-10**: The library exposes, as public functions, the apparent geocentric Sun right ascension and declination of date for a given TT Julian Date, and the Moon-fixed Sun direction for a given UTC time, so that tests can check intermediate results.

### Cross-checks against published values

- **REQ-11**: Sun position check against Meeus, *Astronomical Algorithms* 2nd ed., Example 25.a (1992 October 13, 0h TD, JDE 2448908.5): the apparent right ascension is 198.38083° (13h 13m 31.4s) and the apparent declination is −7.78507° (−7° 47′ 06″). The library's values must match both to within 0.01°.
- **REQ-12**: Selenographic Sun position check against Meeus Example 53.a (1992 April 12, 0h TD): the selenographic longitude of the Sun l0 = 67.89° and latitude b0 = 1.46°. The CLI run for `1992-04-12T00:00:00Z` must give `subsolar_lon_deg` within 0.5° of 67.89 and `subsolar_lat_deg` within 0.5° of 1.46. The tolerance covers the difference between Meeus's Cassini-law frame and the IAU model (a few hundredths of a degree), the 59 s difference between UTC and TD on that date, and the truncated series.
- **REQ-13**: The crate's README records, for the default date `2026-11-10T00:00:00Z`, the CLI output and a JPL Horizons value for the same time (target 301 Moon, quantity 15 "Sun sub-longitude & sub-latitude", output columns `SunSub-LON` and `SunSub-LAT`, as reported by Horizons in its MOON_ME body-fixed frame), with the Horizons query settings. The Horizons MOON_ME value is compared with the CLI result, which is in the IAU_MOON frame; the two frames differ by well under 0.5°, which the tolerance covers. The CLI subsolar point must lie within 0.5° (great-circle angle) of the Horizons value.

### Godot integration

- **REQ-14**: `make ephemeris` builds the CLI with the pinned toolchain and writes its output to `assets/ephemeris/sun_moon_fixed.json`. The time is taken from the Makefile variable `EPHEMERIS_UTC`, default `2026-11-10T00:00:00Z` (`make ephemeris EPHEMERIS_UTC=...` overrides it). The generated file is committed with the default date.
- **REQ-15**: At startup, `scripts/sun_controller.gd` reads `assets/ephemeris/sun_moon_fixed.json` and sets azimuth = `subsolar_lon_deg` and elevation = `subsolar_lat_deg`. The light direction then follows M1 REQ-11 unchanged, so the light's forward vector equals −`sun_dir_godot` (within 0.001 per component). This replaces M1 REQ-12's default of 45°/20°.
- **REQ-16**: The arrow keys keep their M1 REQ-13 behaviour, starting from the ephemeris values. The Sun disc (REQ-17) always points in the current light direction.
- **REQ-17**: The main scene contains a node named `SunDisc` that draws the Sun as a filled, unshaded, circular disc that always faces the camera, in direction d (the current Moon-to-Sun unit vector in the Moon's frame) as seen from the camera. Its centre is at camera position + d · D, with D = 40 000 units. The disc does not cast shadows and is not lit by the Sun light.
- **REQ-18**: Disc size: radius r = D · R_sun / sun_distance_km, where sun_distance_km comes from the ephemeris file. This is a uniform scale factor k = D / sun_distance_km (about 2.67 × 10⁻⁴ for 1 AU) applied to both the Sun's distance and radius, so the angular diameter seen from the camera, 2·atan(r / D), equals the true angular diameter 2·asin(R_sun / sun_distance_km) to within 0.001°. For the default date the true value is about 0.53°.
- **REQ-19**: The disc is drawn behind the Moon: when the Moon lies between the camera and the disc direction, the Moon hides the disc (normal depth test). The disc's farthest point (D + r ≤ 40 200 units; REQ-18 gives r ≈ 188.3 units at 1 AU, about 189.5 at the closest Sun distance of the year, so D + r ≈ 40 188 to 40 190) is inside the camera far plane (at least 50 000 units, M1 REQ-20).
- **REQ-20**: The disc colour is white or near-white (each RGB channel ≥ 0.9 in linear space) on the black background.
- **REQ-21**: With the generated file present, the project runs for at least 10 seconds without ERROR or SCRIPT ERROR lines (same automated check as M1 REQ-24).

### Documentation

- **REQ-22**: `ephemeris/README.md` documents: the methods and references listed in Stack and constraints, the ΔT value, the frame definitions and the Godot mapping, the CLI usage, the reference checks (REQ-11 to REQ-13) and their tolerances, and the pinned Rust version.

## Acceptance criteria

| REQ | Given | When | Then |
|---|---|---|---|
| REQ-1 | Main scene loaded | Read all vertices of the Moon mesh; inspect the Moon's material and shader | Every distance is 1737.4 ± 0.1; no height map, displacement or custom vertex shader |
| REQ-2 | Moon node | Read the mesh radius | 1737.4 |
| REQ-3 | `docs/DATA_SOURCES.md`, `assets/elevation/` | Read the Elevation section; list the folder | States no elevation data is used and Milestone 2 adds LOLA or SLDEM; folder holds only `.gitkeep` |
| REQ-4 | Moon at identity transform | Compute the mesh position and UV for the surface point facing +X | Point is at (1737.4, 0, 0) ± 0.1 and its u = 0.25 ± 0.001 (90° E); +Z point has u = 0 or 1; +Y point has v = 0 |
| REQ-5 | Machine without Rust | `make rust-setup`, then again | First run installs the pinned version (`rustc --version` in `ephemeris/` shows it); second run exits 0 with no download |
| REQ-6 | Toolchain installed | `make ephemeris-test` | Exit code 0; test output lists the REQ-11 and REQ-12 tests as passed |
| REQ-7 | Built CLI | Run with no argument | `utc` field is `2026-11-10T00:00:00Z` |
| REQ-8 | Built CLI | Run `moon-ephemeris 2026-11-10T00:00:00Z` | Output parses as JSON and contains all nine fields with the stated types |
| REQ-9 | Output of REQ-8 | Compute vector lengths and the lon/lat-to-vector formula | Lengths 1 ± 1e-9; formula matches within 1e-9; `sun_dir_godot` = [y, z, x] |
| REQ-10 | Library | Call the public functions from a test | Functions exist and return values used by REQ-11 |
| REQ-11 | JDE 2448908.5 | Compute apparent RA and Dec | RA = 198.38083° ± 0.01°, Dec = −7.78507° ± 0.01° |
| REQ-12 | Input `1992-04-12T00:00:00Z` | Run the CLI | `subsolar_lon_deg` = 67.89 ± 0.5, `subsolar_lat_deg` = 1.46 ± 0.5 |
| REQ-13 | `ephemeris/README.md` | Compare recorded CLI and Horizons subsolar points for 2026-11-10 00:00 UTC | Both values and the query settings are recorded; great-circle separation ≤ 0.5° |
| REQ-14 | Toolchain installed | `make ephemeris`; then `make ephemeris EPHEMERIS_UTC=1992-04-12T00:00:00Z` | File written with `utc` = default; second run writes the 1992 time. The committed file has the default date |
| REQ-15 | Default ephemeris file | Start the project; read sun_controller azimuth, elevation and the light's forward vector | Azimuth = `subsolar_lon_deg`, elevation = `subsolar_lat_deg` (± 0.001°); forward = −`sun_dir_godot` ± 0.001 |
| REQ-16 | Started project | Press Right arrow once | Azimuth = `subsolar_lon_deg` + 5 (mod 360); SunDisc direction from the camera equals the new d within 0.001 |
| REQ-17 | Camera at default state and then at distance 1737.9 after zooming | Read SunDisc global position and orientation | Position = camera position + 40000·d (± 1 unit); disc normal points to the camera; disc material unshaded; shadow casting off |
| REQ-18 | Default ephemeris file (sun_distance_km ≈ 1.48 × 10⁸) | Compute 2·atan(r / 40000) from the disc's world-space radius | Equals `sun_angular_diameter_deg` ± 0.001° (about 0.53°) |
| REQ-19 | Camera placed so the Moon's centre is between the camera and the Sun direction (for example camera at −6000·d from the centre) | Render a frame | No disc pixels are visible; with the camera at +6000·d looking along d, the disc is visible |
| REQ-20 | SunDisc material | Read albedo/emission colour | Each channel ≥ 0.9 |
| REQ-21 (automated) | Committed ephemeris file | Run the project for 10 s capturing output | No ERROR or SCRIPT ERROR lines |
| REQ-22 | `ephemeris/README.md` | Review | All listed items present |

## Edge cases and errors

- **Invalid CLI time** (wrong format, month 13, missing `Z`): the CLI prints a one-line error to standard error, prints nothing to standard output, and exits with code 2.
- **Supported range**: the CLI accepts years 1900 to 2100. Outside that range it reports an error and exits 2, because the low-precision formulas and fixed ΔT are not valid there.
- **Ephemeris file missing or unreadable in Godot**: the game prints one ERROR line naming the file, falls back to M1 defaults (azimuth 45°, elevation 20°) and to 1 AU for the disc size. This counts as a failure of REQ-15 and REQ-21, never as a silent success.
- **Ephemeris file with missing fields or a non-unit vector** (length outside 1 ± 1e-6): treated as unreadable (previous case).
- **Subsolar latitude near ±90°**: impossible in practice (|b0| stays below about 1.6°), but the light code from M1 already handles it without NaN.
- **Sun direction parallel to the view direction**: the disc is drawn at the screen centre; no special case needed.
- **rustup install without network**: `make rust-setup` exits non-zero with the curl or rustup error; the committed JSON file keeps the game runnable.

## Assumptions

- Elevation: Milestone 1 adds no elevation data and the Moon stays a plain sphere. The elevation part of this spec is an audit only (REQ-1 to REQ-3). LOLA or SLDEM elevation is Milestone 2.
- Sun direction is computed by a new Rust ephemeris using low-precision analytic formulas (Meeus or Astronomical Almanac) and the IAU 2009 lunar rotation model. The default time is 2026-11-10 00:00 UTC, and the sphere orientation follows M1 REQ-7.
- The Moon's own position is included (Moon-to-Sun rather than Earth-to-Sun vector). Leaving it out would cause an error of up to about 0.15°.
- ΔT is fixed at 69.2 s (close to the observed value for 2020 to 2026). Over 1900 to 2100 the resulting error in the Moon's rotation stays far below 0.01°, which the tolerances absorb.
- The IAU model is taken as the Moon-fixed frame. The difference from the LOLA/LROC "mean Earth" frame used by the texture is below about 0.01° in the tolerance sense of this spec, so the texture and the Sun direction can be compared directly.
- Sun disc: the real distance (about 1.5 × 10⁸ km) cannot be rendered, so the disc is placed at 40 000 units from the camera with the scale factor k = 40 000 / sun_distance_km. This keeps the angular size exact. Placing it relative to the camera rather than the Moon removes parallax, which matches reality because the real Sun's parallax over 20 000 km is below 0.01°.
- The Sun's light direction logic is unchanged apart from the startup values. The arrow keys from M1 stay so the user can still try other lighting; they move the disc as well.
- Integration through a committed, Makefile-generated JSON file is the simplest option that works. A GDExtension is not justified for one vector computed once per time choice.
- The Rust version is pinned to 1.90.0 (a stable release). The implementer may pin a newer stable release if 1.90.0 is unavailable, and must record it in `rust-toolchain.toml` and the README.
- The reference values from Meeus Examples 25.a and 53.a are taken from the 2nd edition (1998). The tester checks them against the book if available. If a printed value differs from the value in this spec, the book wins and the spec gets a revision.
- Python is not used anywhere. The ephemeris and all offline data work are in Rust.
- The texture, the M1 orbit controls, zoom and pan stay unchanged.

## Open questions

None.

## Revision history

- 2026-11-10: Initial spec. Covers the elevation and orientation audit, the Rust Sun ephemeris in the Moon-fixed frame with Meeus and Horizons cross-checks, the Makefile-generated JSON integration, and a Sun disc with its true angular diameter at a scaled distance.
- 2026-11-10: Revision 1, from tester SPEC_ISSUE reports. REQ-19: far-edge bound corrected from D + r ≤ 40 011 to ≤ 40 200 units to match REQ-18 (r ≈ 188.3 at 1 AU); the disc stays inside the 50 000-unit far plane. REQ-13: Horizons query changed to quantity 15 "Sun sub-longitude & sub-latitude" (SunSub-LON, SunSub-LAT); the wrong quantity 14 and the "or an equivalent" phrase removed. Meeus reference values (REQ-11, REQ-12) unchanged and still unverified against the book.
- 2026-11-10: Revision 2, from tester SPEC_ISSUE. REQ-13: Horizons frame label corrected from "IAU_MOON" to MOON_ME (the Horizons body-fixed frame, as recorded in the README), compared with the IAU_MOON-based CLI result within 0.5°. No numbers, quantity, target, tolerance or Meeus values changed.
- 2026-11-10: Revision 3, user instruction "use rust, no python anywhere". Non-goals and Assumptions: Python wording removed; the ephemeris and all offline data work are in Rust. No requirement, number or Meeus value changed.
