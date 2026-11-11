# Earth Milestone 1: Basic Earth

Status: Ready
Slug: earth-milestone-1-basic-earth

## Goal

Show Earth in the lunar sky as a real 3D sphere, at its true size and its true position relative to the Moon, turning about its tilted axis, lit by the same Sun as the Moon. This is Milestone 1 of `docs/earth-sky.md` section 13. Later Earth milestones (clouds, seasonal ice, atmosphere) build on this node tree and data path.

## Scope

- An `EarthRoot` node in the main scene with an `EarthSurface` child (a textured sphere) and an `EarthController` child.
- Earth's position, distance and orientation come from the existing Rust ephemeris and its streaming helper. The helper gets new output fields.
- The 12 monthly NASA Blue Marble Next Generation JPGs (lowest resolution), not committed, downloaded by `make earth-texture` and recorded in `docs/DATA_SOURCES.md`. This overrides `docs/earth-sky.md` sections 3 and 14 (single neutral texture, no monthly textures) for this spec only.
- The existing scene Sun light also lights Earth.
- Validation of the apparent size and of the shared Sun direction.

## Non-goals

- Procedural clouds (Earth Milestone 2).
- Permanent ice, seasonal snow and sea ice (Earth Milestone 3).
- Atmospheric rim and scattering (Earth Milestone 4).
- Full seasonal validation across the five test dates in `docs/earth-sky.md` section 10 (Earth Milestone 3).
- Night-side city lights.
- Earthshine on the Moon, the Moon's shadow on Earth, and Earth's shadow on the Moon (eclipses).
- Earth hiding the Sun disc during a lunar eclipse.
- Time acceleration, time reversal or a date picker. The clock stays the live UTC clock.
- Precession, nutation and polar motion of Earth's axis.
- A surface-level (standing) camera. Validation uses the existing orbit camera at its minimum distance.
- Any change to the Moon mesh, terrain, material, shaders or `tools/moon-data/`.

## Stack and constraints

- Godot 4.7.2-stable, GDScript, Forward+ on Vulkan. 1 unit = 1 km. Moon-fixed (IAU_MOON) frame mapped to Godot as in `docs/specs/sun-ephemeris-and-sun-disc.md`: (x, y, z) → (X, Y, Z) = (y, z, x). The Moon stays at the origin with identity transform.
- Earth data comes from the Rust crate `ephemeris/` and `moon-ephemeris --stream` only. GDScript does no ephemeris or rotation-model calculation. No new crate dependencies.
- The Sun direction for Earth is the same streamed Sun as the Moon's (`sun_dir_godot`). No second Sun calculation anywhere.
- Constants: Earth mean radius R_E = 6371.0 km. Axial tilt 23.44° (comes from the J2000 equatorial pole relative to the ecliptic; it is not set by hand). Sidereal rotation 86164.0905 s (23 h 56 min 4.09 s).
- Earth's rotation model: Earth's pole fixed along the ICRF/J2000 +z axis (fixed in inertial space), prime meridian angle = Earth Rotation Angle (IAU 2000), ERA = 2π · (0.7790572732640 + 1.00273781191135448 · (JD_UT1 − 2451545.0)), with UT1 = UTC. The Earth-fixed frame has +x toward (0° N, 0° E), +z toward the north pole.
- Forbidden: skybox, billboard, sprite or camera-attached Earth; scaling Earth or setting its angular size by hand; moving Earth by any rule other than the streamed ephemeris.

## Requirements

### Ephemeris output

- **REQ-1**: The one-shot CLI output (REQ-8 of the Sun spec) and every `--stream` line (REQ-23 of the Sun spec) contain, in addition to the nine existing fields, these fields. All nine existing fields keep their meaning and values.

  | Field | Meaning |
  |---|---|
  | `earth_pos_godot` | Array [X, Y, Z], vector from the Moon's centre to Earth's centre in km, Godot mapping of the Moon-fixed frame |
  | `earth_distance_km` | Length of that vector |
  | `earth_basis_godot` | Array of 9 numbers, the rotation matrix (row-major) that takes Earth-fixed vectors to Godot vectors |
  | `earth_sun_dir_godot` | Array [X, Y, Z], unit vector from Earth's centre to the Sun's centre, Godot mapping |
  | `earth_subsolar_lon_deg` | East longitude of the subsolar point on Earth, −180 < value ≤ 180 |
  | `earth_subsolar_lat_deg` | Latitude of the subsolar point on Earth, −90..90 |

- **REQ-2**: The values in REQ-1 are consistent: `earth_distance_km` = |`earth_pos_godot`| within 1e-6 km; `earth_basis_godot` is orthonormal with determinant +1 (each within 1e-9); `earth_sun_dir_godot` has length 1 ± 1e-9 and equals `earth_basis_godot` applied to (cos(lat)·cos(lon), cos(lat)·sin(lon), sin(lat)) of the Earth subsolar point within 1e-9.
- **REQ-3**: The Earth position uses the same geocentric Moon vector the crate already uses for the Moon-to-Sun vector (negated), rotated into the Moon-fixed frame by the same IAU lunar rotation. `earth_sun_dir_godot` is (Moon-to-Sun vector − Moon-to-Earth vector), normalised, from the same vectors.
- **REQ-4**: The angle between Earth's north pole (`earth_basis_godot` applied to (0, 0, 1)) and the ecliptic north pole (J2000 ecliptic, mapped into the Godot frame at the same time) is 23.44° ± 0.01°. The pole direction expressed in the ICRF frame is the same for any two input times (fixed in inertial space, within 1e-9).
- **REQ-5**: For two one-shot runs 86164 s apart (for example `2026-11-10T00:00:00Z` and `2026-11-10T23:56:04Z`), the Earth-fixed axes expressed in the ICRF frame agree within 0.01°. For two runs 21541 s apart (a quarter sidereal day), the prime meridian turns by 90° ± 0.01° eastward about the pole.
- **REQ-6**: Reference checks against JPL Horizons, recorded in `ephemeris/README.md` with the full query settings and the values. Common parameters for every query: `format=text`, `OBJ_DATA='NO'`, `MAKE_EPHEM='YES'`, `EPHEM_TYPE='OBSERVER'`, `CSV_FORMAT='NO'`, `ANG_FORMAT='DEG'`. The reference values below were retrieved on 2026-11-11 for 2026-11-10 00:00 UT.

  | Check | Query | Columns | Reference value | CLI comparison |
  |---|---|---|---|---|
  | Sub-Earth point on the Moon, `2026-11-10T00:00:00Z` | `COMMAND='301'`, `CENTER='500@399'`, `QUANTITIES='14'` | `ObsSub-LON`, `ObsSub-LAT` (frame MOON_ME, east-positive) | lon 3.450226°, lat 6.565800° | Sub-Earth point from `earth_pos_godot` (Moon-fixed lon/lat of that direction) within 0.5° great-circle angle |
  | Sun sub-point on the Moon, same time | `COMMAND='301'`, `CENTER='500@399'`, `QUANTITIES='15'` | `SunSub-LON`, `SunSub-LAT` | lon 175.405935°, lat −1.544939° | Same query as Sun spec REQ-13; `subsolar_lon_deg`/`subsolar_lat_deg` within 0.5° |
  | Earth distance from the Moon, same time | `COMMAND='399'`, `CENTER='500@301'`, `QUANTITIES='20'` | `delta` (au) | 0.00267226337481 au (≈ 399 770 km at 1 au = 149 597 870.7 km) | `earth_distance_km` within 0.2 % |
  | Earth apparent diameter from the Moon, same time | `COMMAND='399'`, `CENTER='500@301'`, `QUANTITIES='13'` | `Ang-diam` (arcsec) | 6582.073″ (≈ 1.828°) | Reference only. The CLI/scene value 2·asin(6371 / `earth_distance_km`) is checked against the geometry (REQ-19), not against Horizons. Known difference: it is about 0.11 % smaller than the Horizons value; this is expected and is not a failure |
  | Earth subsolar point, `2026-06-21T12:00:00Z` | `COMMAND='399'`, `CENTER='500@301'`, `QUANTITIES='15'` | `SunSub-LON`, `SunSub-LAT` (frame ITRF93, Earth body-fixed, east-positive, geodetic latitude) | lon 0.459544°, lat 23.578619° | `earth_subsolar_lon_deg`/`earth_subsolar_lat_deg` within 0.5° great-circle angle. Method: the Moon-to-Sun minus Moon-to-Earth vector, rotated into the Earth-fixed frame by the Milestone 1 model (ERA, pole fixed along ICRF +z), then converted to lon/lat. The CLI latitude is geocentric; at this latitude it is about 0.14° below the geodetic value, inside the tolerance |

  The sub-Earth query uses the geocentre as observer, because Horizons does not allow the Moon as both target and centre. The Moon-centred value is therefore not available. The geocentre's sub-observer point lies on the Moon-centre-to-Earth-centre line, so it is the same direction as `earth_pos_godot` apart from light-time and aberration (well under 0.01°).

  The Earth subsolar reference was retrieved for 2026-06-21 12:00 UT; Horizons reports it in ITRF93.

### Scene

- **REQ-7**: `scenes/main.tscn` contains a node `EarthRoot` (Node3D) that is a sibling of the Moon, not a child of the camera rig or the camera. `EarthRoot` has a child `EarthSurface` (MeshInstance3D with a sphere mesh) and a child `EarthController` (the script that applies streamed Earth data). No other Earth child nodes exist in this milestone.
- **REQ-8**: The rendered Earth sphere has radius 6371.0 ± 0.5 units (mesh radius times any scale of `EarthRoot` and `EarthSurface`), with at least 64 radial segments and 32 rings.
- **REQ-9**: For every applied streamed line, `EarthRoot`'s global position equals `earth_pos_godot` within 1 unit, and its global basis equals `earth_basis_godot` within 1e-6 per element. Before the first line arrives, `EarthRoot` is hidden. On helper failure (Sun spec REQ-25) Earth keeps its last applied position and orientation, or stays hidden if no line arrived. No extra error lines beyond the one REQ-25 already prints.
- **REQ-10**: Earth's position and orientation change only through REQ-9. Camera movement (orbit, zoom, pan) does not change `EarthRoot`'s global transform.
- **REQ-11**: The camera far clip plane is at least 440 000 units (max Earth distance about 406 700 + R_E + max camera distance 20 000, rounded up). The near plane stays at most 0.01 (Moon M1 REQ-20). Earth renders with the normal depth test, so the Moon hides Earth when the Moon is between the camera and Earth.

### Texture

- **REQ-12**: **Override of `docs/earth-sky.md` sections 3 and 14 (user decision, for this spec only):** the surface uses all 12 monthly NASA Blue Marble Next Generation images (January to December), in the lowest resolution NASA offers, as JPG, choosing the smallest file size. The 5400 × 2700 size and the "one neutral texture" and "no 12 monthly textures" wording of the document do not apply here. Each image is equirectangular, with mipmaps generated when the image is loaded at runtime (the texture directory is git-ignored, so no import settings are committed). Milestone 1 shows exactly one of the 12 at a time, selected by REQ-17; no other surface colour texture is used.
- **REQ-13**: Geographic alignment: in every monthly image the texel for longitude λ (east positive) and latitude φ is shown at the Earth-fixed direction (cos φ·cos λ, cos φ·sin λ, sin φ). The textures are not mirrored.
- **REQ-14**: A documented command (`make earth-texture`) downloads all 12 files from the NASA URLs recorded in `docs/DATA_SOURCES.md`, checks each SHA-256 against the recorded value, and writes them to a fixed directory. Running it again with all files present and valid makes no download and exits 0. On download or checksum failure it exits non-zero and leaves no partial file at any target path. `make run` does not download; if files are missing it prints the instruction to run `make earth-texture`.
- **REQ-15**: The 12 texture files are not committed (user decision). Their directory is listed in `.gitignore` and `git ls-files` shows none of them. They are downloaded at build time by REQ-14.
- **REQ-16**: `docs/DATA_SOURCES.md` has an "Earth surface textures (Earth Milestone 1)" section with, for the product and for each of the 12 files: product name, exact file name, NASA page URL and direct download URL, resolution and projection, month, file size, SHA-256; and once: the licence and usage terms with the date they were read, the required credit line, any processing (none, or exactly what was done), and the statement that this overrides the single-neutral-texture rule of `docs/earth-sky.md`. The values below come from the coordinator and are to be copied into that section. Licence and usage terms, recorded verbatim (there is no separate licence file, and neither page says "public domain"):

  - https://science.nasa.gov/earth/faq/, heading "May I reuse imagery that is on your site?": "Most materials published under science.nasa.gov/earth, including images, are freely available for re-publication or re-use, including commercial purposes, except for where copyright is indicated. In those cases, you must obtain the copyright holder’s permission; we usually provide the name (and link, when possible) to the person or organization that holds the copyright." and "We ask that NASA be given credit for its original materials."
  - https://science.nasa.gov/earth/earth-observatory/blue-marble-next-generation/, heading "Credits": "Anyone using or republishing Blue Marble: Next Generation please credit “NASA Earth Observatory.”"

  Required credit line (user-provided, use exactly):

  "Earth imagery: Blue Marble: Next Generation, NASA Earth Observatory, NASA Goddard Space Flight Center. Produced by Reto Stöckli. https://science.nasa.gov/earth/earth-observatory/blue-marble-next-generation/"

  Download URL for each file: `https://assets.science.nasa.gov/content/dam/science/esd/eo/images/bmng/bmng-base/<month>/<file>`, where `<month>` is the lowercase English month name (`january` ... `december`). Product: Blue Marble Next Generation base map, JPG, the lowest resolution NASA offers for each month. The 5400 × 2700 size is taken from the file name. The implementer must confirm it by decoding each file; if a file decodes to another size, report `SPEC_ISSUE`.

  | Month | File | Bytes | SHA-256 |
  |---|---|---|---|
  | Jan | world.200401.3x5400x2700.jpg | 1884678 | 99f5faad74efe985fbf1714c8be7296ca9999759a1215b65f99b7f1df278dde5 |
  | Feb | world.200402.3x5400x2700.jpg | 1865311 | 252444b224c7dc10289616fb5e3cd85c3738fca9ddbdc267775cd22a748bbfbe |
  | Mar | world.200403.3x5400x2700.jpg | 1830489 | 0d9967be048b5e2ba62195dd610042c9e0926b4eb9d1e9ae53dbf20eaadd9228 |
  | Apr | world.200404.3x5400x2700.jpg | 1774173 | 8db8d5e545b31cde0e4e5dfa46cb116bf485243a0200c2d6e4b04b4e6937f669 |
  | May | world.200405.3x5400x2700.jpg | 1735263 | d9a8dfc0a3e54775c3a4aeb547c729f710bb588d82d4602252d7cd7bf43a38ef |
  | Jun | world.200406.3x5400x2700.jpg | 1692239 | dc059529b8ed1cfcdd59747a7c3f259c93c1322bf88ca1ec8bab1dd71fcc57f5 |
  | Jul | world.200407.3x5400x2700.jpg | 1617810 | f55226d46d27e05511f2118dc6aa24f5dbf9b6b2cddc87cc6e0e7dd067c00b11 |
  | Aug | world.200408.3x5400x2700.jpg | 1616254 | 2048023ccc62250c677c0f4b03d4362f997b130eb0154a6cad00aa1b27c390b9 |
  | Sep | world.200409.3x5400x2700.jpg | 1709729 | ed72e87674861f72e2a6e5df52f0cc6bf3df1edd9b862664cf18ac423e2e9e0e |
  | Oct | world.200410.3x5400x2700.jpg | 1766694 | ccfd9b7a5e5ee601e1466556716bba50ea418f3a8e068ab0194ae0425815b1b0 |
  | Nov | world.200411.3x5400x2700.jpg | 1851209 | d63de0bb4274a7d9df08d2f69eeffc849d0f7aca157c4401f9bd2e41af63b178 |
  | Dec | world.200412.3x5400x2700.jpg | 1878742 | 3d38a8ecaceb1cdb51ced7f831e9ac18d261950049616feff6892efcae0dcc26 |

  `make earth-texture` (REQ-14) checks each download against these sizes and SHA-256 values.
- **REQ-17**: Month selection (user decision: hard switch). The Earth material shows exactly one monthly image at a time, with no blending: the image for the UTC month of the latest applied streamed line's `utc` field (January = file 1 ... December = file 12). When an applied line's UTC month differs from the shown month, the material switches to the new month's image on that same line, abruptly, with no cross-fade.

### Lighting

- **REQ-25**: Earth is lit by the existing scene Sun light (the DirectionalLight3D driven by `scripts/sun_controller.gd`). No other light affects Earth, and no Earth script or shader computes a Sun direction. Earth's material is lit (not unshaded), so the hemisphere facing away from the Sun receives no direct light.
- **REQ-18**: When the Sun light is disabled (before the first streamed line), Earth is hidden as well (REQ-9), so Earth never shows unlit while the Moon has no Sun.

### Validation

- **REQ-19**: Apparent diameter. With the camera at its minimum distance (1748.232 units, Moon M1 REQ-18) on the line from the Moon's centre toward Earth, pointed at Earth's centre, the angular diameter of Earth computed from the scene (2·asin(rendered radius / |camera − EarthRoot position|)) equals 2·asin(6371 / (`earth_distance_km` − 1748.232)) within 0.001°, and is between 1.79° and 2.06° for any date. In a rendered frame the measured Earth disc diameter in pixels equals the value predicted from that angle and the camera's vertical field of view and viewport height within ± 1 pixel.
- **REQ-20**: Shared Sun direction. For any applied line: the scene light's forward vector equals −`sun_dir_godot` within 0.001 per component (unchanged Sun spec rule), and the angle between `earth_sun_dir_godot` and `sun_dir_godot` is at most 0.2° (the true Earth–Moon parallax of the Sun is at most about 0.16°).
- **REQ-21**: Lit hemisphere. In a rendered frame with the camera placed at Earth's centre + 3·R_E along `earth_sun_dir_godot`, looking at Earth, Earth's centre pixel is lit (brighter than the night side in the frame taken from the opposite side). The surface point at the streamed Earth subsolar latitude and longitude lies within 1° of the direction toward the Sun from Earth's centre.
- **REQ-22**: Occlusion and far side. With the camera at distance 6000 on the line from the Moon's centre directly away from Earth (looking toward Earth through the Moon), no Earth pixels are visible. With the camera at 6000 toward Earth looking at Earth, Earth is visible.
- **REQ-23**: The project runs 10 s with the helper and the texture present with no ERROR or SCRIPT ERROR lines (same check as Sun spec REQ-21).

### Documentation

- **REQ-24**: `ephemeris/README.md` documents the new fields, the Earth rotation model and its constants, the fixed-pole approximation and its size (about 0.36° of precession since J2000 by 2026), and the REQ-6 checks. `docs/ARCHITECTURE.md` describes `EarthRoot`, its children, and the data path from helper to Earth.

## Acceptance criteria

| REQ | Given | When | Then |
|---|---|---|---|
| REQ-1 | Built CLI | `moon-ephemeris 2026-11-10T00:00:00Z`; `--stream` for 3 s | Both outputs contain the nine old fields and the six new fields with the stated types; old fields equal the values before this change within 1e-12 |
| REQ-2 | Output of REQ-1 | Compute lengths, orthonormality, determinant, subsolar vector | All within the stated tolerances |
| REQ-3 | Library | Compare `earth_pos_godot` with −(geocentric Moon vector) rotated by the lunar rotation, from public functions | Equal within 1e-6 km |
| REQ-4 | Runs at `2026-03-20T00:00:00Z` and `2026-09-23T00:00:00Z` | Compute pole tilt to the ecliptic pole and pole in ICRF | Tilt 23.44° ± 0.01° both times; ICRF pole identical within 1e-9 |
| REQ-5 | Runs at `2026-11-10T00:00:00Z`, `+86164 s`, `+21541 s` | Compare Earth-fixed axes in ICRF | Same within 0.01° after one sidereal day; 90° ± 0.01° eastward after a quarter |
| REQ-6 | `ephemeris/README.md` | Compare recorded CLI and Horizons values | All five queries and values recorded; frame for `COMMAND='399'` read from its header; sub-Earth ≤ 0.5° of (3.450226°, 6.565800°); Sun sub-point ≤ 0.5° of (175.405935°, −1.544939°); distance ≤ 0.2 % of 0.00267226337481 au; Horizons 6582.073″ recorded as reference with the known ≈ 0.11 % difference from the 6371 km value; Earth subsolar ≤ 0.5° of (0.459544°, 23.578619°) |
| REQ-7 | Main scene | Inspect tree | `EarthRoot` with exactly `EarthSurface` and `EarthController`; not under CameraRig; no skybox, billboard, sprite or panorama sky for Earth |
| REQ-8 | `EarthSurface` | Read mesh radius, segments, rings and global scale | 6371.0 ± 0.5; ≥ 64 segments, ≥ 32 rings |
| REQ-9 | Running project; fake helper via `MOON_SUN_HELPER` printing one valid line then exiting | Read `EarthRoot` before and after the line, and after the helper stops | Hidden before; transform equals the line within tolerance after; unchanged after the helper stops |
| REQ-10 | Running project | Orbit, zoom 50 notches, pan 100 px | `EarthRoot` global transform unchanged (until the next streamed line) |
| REQ-11 | Camera | Read near and far | `near ≤ 0.01`, `far ≥ 440000` |
| REQ-12 | 12 texture files; running project | Count files; read format and size; read the loaded surface texture | 12 JPG files, one per month, the lowest NASA resolution; the loaded texture has mipmaps; the material holds only Blue Marble albedo textures; the spec states the override |
| REQ-13 | `EarthRoot` at identity | Find UV at Earth-fixed +x, +y (90° E), +z, in every month | +x shows 0° E (u = 0.5 for a −180..180 texture), +y shows 90° E, +z shows the north pole (v = 0) |
| REQ-14 | No texture files | `make earth-texture` twice; then with one corrupted file | First downloads 12 and verifies; second no download, exit 0; corrupted file makes it replace the file or fail with no partial file left |
| REQ-15 | Repo | `git check-ignore` on the directory; `git ls-files` | Directory ignored; no texture file tracked |
| REQ-16 | `docs/DATA_SOURCES.md` | Review | All listed items present for 12 files plus the licence, credit and override statement |
| REQ-17 | Fake helper (`MOON_SUN_HELPER`) streaming `2026-01-31T23:59:59Z` then `2026-02-01T00:00:00Z`; then one line for each month of 2026 | Read the surface texture after each line | January image after the first line, February image after the second; each month line shows that month's image; the material has one albedo texture and no blend parameter |
| REQ-25 | Main scene | List lights; inspect Earth material | Only the Sun light reaches Earth; material shading mode is not unshaded; no Sun vector in Earth scripts |
| REQ-18 | Start with no helper | Read Sun light and `EarthRoot` | Light disabled; Earth hidden |
| REQ-19 | Streamed line; camera placed as stated | Compute the angle from the scene; render one frame and measure the disc | Angle matches within 0.001° and lies in 1.79°–2.06°; pixel diameter matches prediction ± 1 px |
| REQ-20 | Streamed line | Compare light forward, `sun_dir_godot`, `earth_sun_dir_godot` | Forward = −`sun_dir_godot` ± 0.001; angle ≤ 0.2° |
| REQ-21 | Streamed line; camera on the Sun side and then the night side of Earth | Render and sample the Earth centre pixel | Day-side pixel brighter than night-side pixel; subsolar surface point within 1° of `earth_sun_dir_godot` |
| REQ-22 | Camera at −6000 and +6000 along the Earth direction | Render | No Earth pixels / Earth visible |
| REQ-23 | Helper built, texture present | Run 10 s capturing output | No ERROR or SCRIPT ERROR lines |
| REQ-24 | READMEs | Review | All listed items present |

## Edge cases and errors

- **Texture missing** (not downloaded, or only some of the 12): Godot prints one ERROR line naming the missing file and the command `make earth-texture`; Earth renders without a texture (plain material) so the rest of the scene still works. This fails REQ-23 by design.
- **Streamed line missing the new Earth fields or with a non-orthonormal basis** (tolerance 1e-6): treated as an invalid line under Sun spec REQ-25 (one ERROR line, keep last state).
- **Earth distance range**: about 356 400 to 406 700 km over a month; all limits above cover it. From the REQ-19 camera position (1748.232 units toward Earth) this gives an apparent diameter of 1.79° to 2.06° (2.0586° at 356 400 km).
- **Camera on the far side**: Earth is below the horizon and hidden by the Moon (REQ-22).
- **Depth precision** (near 0.01, far ≥ 440 000): Earth must show no z-fighting or flicker in the REQ-19 and REQ-22 frames.

## Assumptions

- Earth's distance is the real streamed Moon–Earth distance, not a fixed 384 400 km. 384 400 km is the mean; the true value varies by about ±6 %. Earth's position follows the ephemeris, so libration and the observer's position on the Moon follow from the geometry. (User decision.)
- One DirectionalLight lights both bodies. This is "the same Sun": a directional light ignores the 0.16° parallax, which REQ-20 bounds.
- This spec extends the Sun spec's REQ-8 and REQ-23 field list. Their "exactly nine fields" wording must be revised in `docs/specs/sun-ephemeris-and-sun-disc.md` to allow the REQ-1 fields. The orchestrator should send that change to the spec writer, or confirm that this spec overrides it.
- UT1 = UTC (error below 1 s, about 0.004° of rotation). Fixed pole: precession since J2000 (about 0.36° by 2026) is ignored, as `docs/earth-sky.md` asks for an axis fixed in inertial space. The REQ-6 tolerance of 0.5° covers it.
- The validation camera is the existing orbit camera at its minimum distance, standing in for "the Moon's surface camera position". No surface camera is added.
- The textures are used as downloaded, with no colour correction.
- URLs, sizes, checksums, the credit line and the licence quotes in REQ-16 come from the coordinator and the user.
- User decisions applied: real streamed Earth distance (REQ-9, REQ-19); 12 monthly lowest-resolution JPGs, not committed, downloaded by `make earth-texture`.

## Open questions

None.

## Revision history

- 2026-11-11: Revision 9, tester SPEC_ISSUEs with user decisions. REQ-19 apparent-diameter range raised to 1.79°–2.06° (acceptance row and Earth-distance edge case updated; formula unchanged). REQ-12: mipmaps generated at runtime when each month's image loads, import-settings wording removed (acceptance row updated). Duplicate REQ-17: the lighting requirement and its acceptance row renumbered to REQ-25. Nothing else changed.
- 2026-11-11: Revision 8, verified Earth subsolar Horizons query recorded in REQ-6 (COMMAND='399', CENTER='500@301', Q15, ITRF93, geodetic; lon 0.459544°, lat 23.578619°, tolerance 0.5°) with a one-line method in the Milestone 1 model; "pending verification" and the frame-not-confirmed note removed; acceptance row updated; open question closed; Status Ready.
- 2026-11-11: Revision 7, user decision. Mean radius 6371 km used for the apparent-size check; equatorial-radius reasoning removed; Horizons 6582.073″ kept as reference with the ≈ 0.11 % known difference stated as not a failure. Earth subsolar row marked pending verification with no reference value; reopened as Open question 1; Status back to Draft.
- 2026-11-11: Revision 6, coordinator-verified Horizons queries. REQ-6 rewritten as a table naming exact queries, columns and reference values (sub-Earth Q14, Sun sub-point Q15, distance Q20, angular diameter Q13); "or equivalent" dropped; geocentre-observer note added; the `COMMAND='399'` frame marked not confirmed, to be read from the header by the implementer. New angular-diameter check added. REQ-6 acceptance row updated. Open question closed; Status Ready.
- 2026-11-11: Revision 5, licence wording recorded verbatim in REQ-16 (NASA Earth FAQ and BMNG Credits, with URLs and headings; no licence file, no "public domain" statement); "not yet checked" removed; licence open question closed. REQ-6 sub-Earth Horizons quantity is now Open question 1. Status stays Draft.
- 2026-11-11: Revision 4, user-provided credit line recorded verbatim in REQ-16; Open question 1 narrowed to licence and usage terms. Nothing else changed.
- 2026-11-11: Revision 3, coordinator data. REQ-16: base URL, month folder rule and the 12-file table (file, bytes, SHA-256) recorded; 5400 × 2700 is from file names and must be confirmed by decoding. Open question 1 narrowed to the licence only. No other requirement changed.
- 2026-11-11: Revision 2, user decision "hard switch by month". REQ-17: one image at a time for the UTC month of the latest applied line, abrupt switch at month boundaries, no blending; acceptance row made concrete (Jan 31 / Feb 1 boundary, all 12 months). Monthly-switching open question removed. Nothing else changed.
- 2026-11-11: Revision 1, user decisions. Real distance confirmed. Textures changed to 12 monthly lowest-resolution JPGs, override of earth-sky.md sections 3 and 14 stated (REQ-12, Scope); REQ-13 to REQ-16 and acceptance rows rewritten for 12 files, not committed, `make earth-texture`; new REQ-17 (month selection, blocked on Open question 1). Open questions replaced: monthly switching design, NASA URLs/licence still unconfirmed. Sun spec revised to agree on fifteen fields.
- 2026-11-11: Initial spec (Draft). EarthRoot with EarthSurface and EarthController; Earth position, orientation and Earth Sun direction from new ephemeris fields; Blue Marble texture by `make earth-texture`; apparent-size and shared-Sun validation. Licence, month and distance choice left open.
