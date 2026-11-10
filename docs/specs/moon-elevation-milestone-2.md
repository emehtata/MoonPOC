# Milestone 2: Real Elevation

Status: Ready
Slug: moon-elevation-milestone-2

## Goal

Replace the plain sphere from Milestone 1 with a globe whose geometry is displaced by real NASA LOLA elevation. An offline Rust data pipeline reads the source DEM and the LROC imagery, checks their metadata, and writes aligned, Godot-friendly assets and a metadata file. The result is checked with measurements against known lunar landmarks. The geometry is split into chunks so a later milestone can add LOD and streaming.

## Scope

- Download and document one real elevation product (see "Elevation source").
- A Rust crate at `tools/moon-data/` (the offline pipeline) with Makefile targets. It reads the DEM and the LROC WAC tiles and writes the elevation levels, the albedo texture and a metadata file.
- Godot: a displaced cube-sphere globe, built once at startup from a heightmap level and split into chunk meshes.
- Measured validation against landmarks, plus visual checks marked as pending for the user.
- Documentation: `docs/DATA_SOURCES.md` (elevation section), `docs/ARCHITECTURE.md` (geometry and the path to chunked terrain).

## Non-goals

- No Python anywhere in the M2 pipeline: no `tools/prepare_moon_data.py`, no virtual environment, no requirements file, no GDAL or rasterio Python bindings. (User decision "NO PYTHON! RUST!", see Assumptions A1.)
- No 512 pixels-per-degree data in M2. SLDEM2015 at 512 ppd and regional high-resolution tiles are left for the chunk/LOD work (Milestones 3 and 4). See Assumption A3.
- No normal maps, no custom lunar shader and no material changes beyond what displacement needs (Milestone 3).
- No camera changes. The M1 camera may pass below the terrain at minimum distance (see Edge cases). No collision.
- No LOD switching, streaming or runtime chunk loading (Milestone 4). Only the chunk layout is in place.
- No vertical exaggeration. Heights are used at scale 1.0.
- No procedural, noise-based, interpolated-by-invention or substitute elevation.
- No gameplay, physics, vehicles, UI beyond M1 controls, no addons, no Road Rage Taxi code.

## Stack and constraints

- Godot 4.7.2-stable, GDScript, Forward+ on Vulkan, as in Milestone 1. 1 unit = 1 km.
- Offline pipeline: Rust, in a new crate `tools/moon-data/` with its own `Cargo.toml`, a committed `Cargo.lock`, and a `rust-toolchain.toml` that pins the same toolchain as `ephemeris/rust-toolchain.toml`. Binary name `moon-data`.
- Source data reading (see Assumption A2): pure Rust, no system GDAL.
  - LOLA LDEM `.IMG` is a raw binary raster with a PDS3 text label (`.LBL`). The crate parses the label itself and reads the raster with the standard library.
  - LROC WAC tiles are GeoTIFFs. The crate reads them with the `tiff` crate and reads the GeoTIFF tie-point and pixel-scale tags itself.
  - Allowed extra crates: `tiff`, `png` (writing the albedo), `serde`/`serde_json` (metadata), `sha2` (checksums). Each one is listed with its reason in `tools/moon-data/README.md`. Any other crate must be justified there.
- Raw data stays in `data/raw/` (not committed, never loaded by Godot). Generated assets go to `assets/elevation/` and `assets/textures/`.
- Godot never reads a GeoTIFF or a PDS `.IMG` file.

### Elevation source (mandatory)

| Item | Value |
|---|---|
| Product | LRO LOLA Gridded Data Record, global cylindrical DEM `LDEM_64` (PDS data set LRO-L-LOLA-4-GDR-V1.0) |
| Location | PDS Geosciences Node, `https://pds-geosciences.wustl.edu/lro/lro-l-lola-3-rdr-v1/lrolol_1xxx/data/lola_gdr/cylindrical/img/` (files `LDEM_64.IMG` and `LDEM_64.LBL`, letter case as served). The exact URLs used are recorded in `docs/DATA_SOURCES.md`. |
| Coverage | Global, 90° S to 90° N, 0° to 360° E |
| Resolution | 64 pixels per degree, 23040 × 11520 samples (about 474 m per pixel at the equator) |
| Projection | Simple cylindrical (equirectangular), planetocentric latitude, east-positive longitude 0..360, mean Earth/polar axis frame |
| Values | Signed 16-bit integers. Height in metres = DN × SCALING_FACTOR (0.5 expected) above the reference sphere of radius OFFSET (1 737 400 m expected). The pipeline reads these values from the label and does not hard-code them. |
| Vertical reference | Sphere of radius 1737.4 km centred at the Moon's centre of mass. Heights are relative to that sphere, not to a geoid. |
| NoData | The label is checked for a missing-constant keyword. If one is present, the pipeline handles it as in REQ-6. If none is present, `docs/DATA_SOURCES.md` says so. |
| License | PDS archive data from NASA. The terms are read on the PDS Geosciences Node at download time and quoted in `docs/DATA_SOURCES.md`, with the retrieval date. If the terms do not clearly allow redistribution of derived files, the generated elevation assets are not committed and the implementer reports BLOCKED. |
| Citation | Smith, D. E., et al., LRO LOLA RDR/GDR, as given in the product label or data set catalog, copied verbatim. |

## Requirements

### Data and documentation

- **REQ-1**: `docs/DATA_SOURCES.md` has an Elevation section that replaces the M1 "No elevation data is used yet" text. It lists every row of the "Elevation source" table with the values actually found in the label: product, exact URLs, retrieval date, sample/line counts, pixels per degree, projection, latitude/longitude extents, units, scaling factor, offset, vertical reference, NoData finding, license text, citation, and the SHA-256 of `LDEM_64.IMG` and `LDEM_64.LBL`.
- **REQ-2**: `docs/DATA_SOURCES.md` states the resolution decision: 64 ppd global LOLA is used instead of 512 ppd SLDEM2015, with the reasons in Assumption A3.

### Rust pipeline

- **REQ-3**: `make moon-data-test` runs `cargo test` in `tools/moon-data/` with the pinned toolchain and exits 0 when all tests pass.
- **REQ-4**: `make moon-data` builds the crate with `--locked` and runs `moon-data`, reading only from `data/raw/` and writing only to `assets/elevation/` and `assets/textures/`. It exits 0 on success.
- **REQ-5**: Metadata validation: before converting, the pipeline checks the DEM label for sample and line counts, sample type (16-bit signed, byte order), scaling factor, offset, units (metres), map projection (simple cylindrical), resolution and the four extents. It checks that the file size equals samples × lines × 2 bytes. For each LROC tile it checks the GeoTIFF tie point and pixel scale against the tile's expected extent (from `docs/DATA_SOURCES.md`). Any mismatch stops the run with exit code 2 and one error line naming the file and the field.
- **REQ-6**: NoData: samples equal to the label's missing constant (if any) are never treated as heights. When downsampling, they are left out of the average. An output cell with no valid input stays NoData and is written as the NaN value in the float output. The metadata file reports the NoData count per level. No value is filled in or invented.
- **REQ-7**: Elevation levels: the pipeline writes three equirectangular levels covering 0..360° E and 90° N..90° S: 4096 × 2048, 2048 × 1024 and 1024 × 512. Each output cell is the area average of the source samples whose centres fall inside that cell (box filter in the source grid), in metres above 1737.4 km, as little-endian 32-bit floats, row 0 = northernmost row, column 0 starting at 0° E. Files: `assets/elevation/lola_height_m_<W>x<H>.f32`.
- **REQ-8**: Grid convention: every elevation level and the albedo texture use the M1 convention from `docs/DATA_SOURCES.md`: column x centre at longitude 360·(x + 0.5)/W ° E, row y centre at latitude 90 − 180·(y + 0.5)/H °.
- **REQ-9**: Albedo: the pipeline regenerates `assets/textures/lunar_albedo_4096x2048.png` from the ten LROC WAC GMM 100 m tiles in `data/raw/lroc_wac_gmm_100m/`, on the REQ-8 grid, with the same processing as the M1 script documented in `docs/DATA_SOURCES.md` (box averaging for the equatorial tiles, spherical polar stereographic sampling of a 1 km intermediate for the caps, no tonal change, no scale/offset applied, 8-bit grey stored as RGB). The Python script is removed from `docs/DATA_SOURCES.md` and replaced by the `make moon-data` command.
- **REQ-10**: Port equivalence: the regenerated albedo matches the M1 PNG (SHA-256 `007f09f0...63fd`, as recorded in `docs/DATA_SOURCES.md`) pixel for pixel: every pixel has the same RGB values (maximum difference 0, zero differing pixels). The measured maximum difference and the count of differing pixels are recorded in `docs/DATA_SOURCES.md`.
- **REQ-11**: Metadata file `assets/elevation/moon_data.json` lists, for each elevation level and the albedo: file path, width, height, data type, byte order, units, grid convention (REQ-8), reference radius in metres, minimum, maximum and mean value (NaN excluded), NoData count, and SHA-256. It also records the source product names, source file SHA-256s, the `moon-data` crate version and the toolchain version.
- **REQ-12**: Repeatability: running `make moon-data` twice in a row on the same raw files gives byte-identical output files (same SHA-256 for every file in REQ-7, REQ-9 and REQ-11).
- **REQ-13**: Missing source files: if a raw file is missing, the pipeline exits with code 2 and one error line per missing file, and writes nothing (no partial outputs replace existing ones).

### Godot geometry

- **REQ-14**: The Moon's geometry is a cube-sphere: six cube faces, each split into 4 × 4 chunks of 64 × 64 quads (96 chunk `MeshInstance3D` nodes, each with 65 × 65 vertices). This replaces the M1 SphereMesh.
- **REQ-15**: Displacement: each vertex lies on the direction of its undisplaced cube-sphere point at lat φ, lon λ, at radius 1737.4 + h(φ, λ)/1000 units, where h is the bilinear sample of the 2048 × 1024 level in metres, with longitude wrapping between the last and the first column and latitude clamped at the first and last row centres. The mesh uses scale 1.0 (no exaggeration).
- **REQ-16**: The mesh is built once at startup on the CPU in GDScript from the `.f32` file and `moon_data.json`. There is no per-frame terrain computation. The build time is measured and printed once (`terrain build ms: <n>`).
- **REQ-17**: Orientation is unchanged from M1 REQ-7 and the sun spec REQ-4: north pole on local +Y, (0° N, 0° E) on local +Z, (0° N, 90° E) on local +X.
- **REQ-18**: Texture mapping: each vertex has UV u = λ/360, v = (90 − φ)/180 for the albedo. No triangle has vertex u values that differ by more than 0.5 (triangles that cross 0° E use u values beyond 1 or below 0 on the wrapped side, or duplicated seam vertices, so the texture does not smear across the seam).
- **REQ-19**: Watertight seams: vertices that lie on a shared chunk or face edge have identical positions (within 1e-4 units) in every chunk that contains them, and identical normals (within 1e-3 per component).
- **REQ-20**: Normals: vertex normals are computed from the displaced geometry, using neighbours across chunk and face edges, so that lighting follows the real terrain.
- **REQ-21**: Polar handling: over the whole mesh, the ratio of the longest triangle edge to the shortest triangle edge (in the undisplaced cube-sphere) is at most 3. No vertex position or normal is NaN.
- **REQ-22**: The Moon material keeps M1 REQ-9 (metallic 0.0, roughness ≥ 0.9) and the M1 albedo texture path. No height-map texture or vertex-displacement shader is used: the displacement is in the mesh vertices.
- **REQ-23**: If `moon_data.json` or the `.f32` file is missing or does not match the metadata (size or SHA-256), the project prints one ERROR line naming the file and builds no displaced terrain. It does not fall back to a flat sphere or a generated surface.

### Validation (measured)

A Godot headless test and Rust tests measure the following. Landmark coordinates are from the IAU Gazetteer of Planetary Nomenclature; the values are recorded in `docs/VALIDATION.md` with the method and the measured numbers.

- **REQ-24**: Source fidelity: for 1000 pixels of the 4096 × 2048 level chosen with a fixed seed, the value equals the mean of the corresponding 5.625 × 5.625 source block computed independently in the test, within 0.01 m.
- **REQ-25**: Mesh fidelity: for every vertex, |vertex radius − (1737.4 + h/1000)| ≤ 0.001 units, with h from REQ-15 computed independently in the test.
- **REQ-26**: Global extremes on the 4096 × 2048 level: the maximum lies within 3° great-circle of 5.4° N, 201.4° E (the highest point, near Engel'gardt) and is at least 9000 m; the minimum lies within 3° of 70.4° S, 187.5° E (inside Antoniadi crater) and is at most −8000 m.
- **REQ-27**: Craters: on the 4096 × 2048 level, measured as (mean height of the ring between 0.9 R and 1.1 R from the centre) minus (minimum height within 0.3 R of the centre), with the Gazetteer centre and radius R:

  | Crater | Centre | Diameter | Depth at least |
  |---|---|---|---|
  | Tycho | 43.31° S, 348.64° E | 86 km | 3000 m |
  | Copernicus | 9.62° N, 339.92° E | 96 km | 2500 m |
  | Theophilus | 11.45° S, 26.28° E | 99 km | 2500 m |

  The lowest cell within 0.3 R lies within 0.5 R of the Gazetteer centre.
- **REQ-28**: Maria versus highlands: the mean height of Mare Imbrium (box 25° N–45° N, 330° E–350° E) is at least 1500 m lower than the mean height of the far-side highland box 0°–20° N, 180° E–200° E.
- **REQ-29**: Albedo/elevation alignment: `moon_data.json` shows the same grid convention and extents for the albedo and every elevation level. In addition, the Copernicus centre found in REQ-27 and the centre of its bright ejecta ring in the albedo (the albedo-weighted centroid of pixels within 1.5 R that are brighter than the albedo mean of the 1.5 R to 3 R annulus) are within 0.5° of each other.
- **REQ-30**: Shape: the mean vertex radius over all vertices is 1737.4 ± 2 units, and every vertex radius lies between 1737.4 − 9.2 and 1737.4 + 10.8 units.
- **REQ-31**: The project runs for at least 10 seconds without ERROR or SCRIPT ERROR lines (same automated check as M1 REQ-24).

### Visual checks (pending for the user)

- **REQ-32**: The following are visual checks made by the user and are reported as "pending user check", not as passed, by the tester: (a) Tycho, Copernicus and the Imbrium basin are recognisable as relief under low Sun (Sun elevation lowered with the arrow keys); (b) no seam is visible at 0° E or at the cube-face edges; (c) no pinching or spikes near the poles; (d) the albedo features sit on the matching relief.

### Architecture documentation

- **REQ-33**: `docs/ARCHITECTURE.md` documents: the cube-sphere chunk layout and why it avoids polar distortion; the vertex count (6 × 16 × 65 × 65 = 405 600); the height level used and why; the measured build time from REQ-16; and the transition path to chunked terrain: per-chunk LOD levels from the existing heightmap levels, chunk loading by camera distance, and regional 512 ppd SLDEM2015 tiles for the ±60° band (LOLA for the poles) produced by the same Rust pipeline.

### Changes to earlier specs

- **REQ-34**: These earlier requirements are replaced. Everything else in `moon-globe-milestone-1.md` and `sun-ephemeris-and-sun-disc.md` stays in force.

  | Earlier requirement | New rule |
  |---|---|
  | M1 REQ-5 (undisplaced sphere, all vertices at 1737.4 ± 0.1) | REQ-14, REQ-15, REQ-30 |
  | M1 Non-goal "no real elevation" and "no pipeline" | This spec |
  | M1 Assumption "standard SphereMesh" | REQ-14 |
  | Sun spec REQ-1 (no displacement) and REQ-2 (radius read from a sphere mesh) | REQ-15 and REQ-30; the reference radius stays 1737.4 |
  | Sun spec REQ-3 (no elevation data documented, `assets/elevation/` only `.gitkeep`) | REQ-1, REQ-7, REQ-11 |
  | Sun spec REQ-4 (UV check on a sphere point) | Same check on the cube-sphere vertex nearest each axis direction, using REQ-18 UVs, tolerance u ± 0.002 |
  | M1 Stack note "Python with rasterio/Pillow for texture preparation" and the Python script in `docs/DATA_SOURCES.md` | REQ-9, REQ-10 |

- **REQ-35**: Makefile targets: `moon-data` and `moon-data-test` exist, depend on `require-rust`, appear in `make help`, and use the toolchain pinned in `tools/moon-data/rust-toolchain.toml`. No Python target is added.

## Acceptance criteria

| REQ | Given | When | Then |
|---|---|---|---|
| REQ-1 | `docs/DATA_SOURCES.md`, raw files | Review; run `sha256sum` on the raw files | All fields present; values match the label; checksums match |
| REQ-2 | `docs/DATA_SOURCES.md` | Review | 64 ppd versus 512 ppd decision and reasons stated |
| REQ-3 | Toolchain installed | `make moon-data-test` | Exit 0 |
| REQ-4 | Raw files present | `make moon-data`; list files changed | Exit 0; only files under `assets/elevation/` and `assets/textures/` changed |
| REQ-5 | Copy of `LDEM_64.LBL` with `LINES` changed to 11519, in a scratch raw dir | Run the binary on it | Exit 2; error line names `LDEM_64` and `LINES`; no output written |
| REQ-6 | Synthetic test raster in a Rust unit test: 4 × 4 cells with one missing-constant cell, downsampled to 2 × 2 | Run the downsampler | The block with the missing cell is the mean of its 3 valid cells; an all-missing block gives NaN |
| REQ-7 | Generated files | Check sizes | 4096·2048·4, 2048·1024·4, 1024·512·4 bytes |
| REQ-8 | `moon_data.json` | Read grid fields | Convention string and extents match REQ-8 for all levels and the albedo |
| REQ-9, REQ-10 | Regenerated PNG and the M1 PNG kept in a scratch copy | Compare per pixel | Every pixel identical (max difference 0, zero differing pixels); numbers recorded in docs |
| REQ-11 | `moon_data.json` | Parse; recompute SHA-256 and min/max/mean from files | All fields present; values match |
| REQ-12 | Raw files | Run `make moon-data` twice; compare SHA-256 | Identical |
| REQ-13 | Raw dir without `WAC_GLOBAL_P900S0000_100M.TIF` | Run the binary | Exit 2; one error line naming the file; existing outputs unchanged |
| REQ-14 | Main scene loaded | Count chunk meshes and vertices | 96 chunks, each 65 × 65 vertices |
| REQ-15, REQ-25 | Main scene loaded | Recompute h per vertex in the test | Within 0.001 units |
| REQ-16 | Project run | Read output | One `terrain build ms:` line; no terrain code in `_process` or `_physics_process` |
| REQ-17 | Moon at identity | Find vertices nearest +Y, +Z, +X directions | Their lat/lon are 90° N; (0° N, 0° E); (0° N, 90° E), within 1° |
| REQ-18 | All triangles | Compare vertex u values | No triangle with a u difference above 0.5 |
| REQ-19 | All chunk edges | Match vertices by lat/lon key | Position within 1e-4, normal within 1e-3 |
| REQ-20 | Vertex on the Tycho west inner wall (43.31° S, 347.9° E) | Compare normal with radial direction | Normal deviates from the radial direction by more than 2° |
| REQ-21 | All triangles | Compute the edge-length ratio on the undisplaced mesh | ≤ 3; no NaN |
| REQ-22 | Moon chunks | Inspect materials | metallic 0.0, roughness ≥ 0.9, albedo path unchanged, no shader with `VERTEX` writes, no height texture |
| REQ-23 | `.f32` file renamed | Run project | One ERROR line naming the file; no Moon mesh is built |
| REQ-24 | 4096 level, raw DEM | Test with seed 42 | All 1000 within 0.01 m |
| REQ-26 | 4096 level | Find min and max | Locations and values as stated |
| REQ-27 | 4096 level | Measure the three craters | Depths and centre offsets as stated |
| REQ-28 | 4096 level | Compute box means | Imbrium at least 1500 m lower |
| REQ-29 | Metadata and albedo | Compute as stated | Grids equal; centres within 0.5° |
| REQ-30 | All vertices | Compute radii | Mean 1737.4 ± 2; all in [1728.2, 1748.2] |
| REQ-31 (automated) | Generated assets | Run project 10 s | No ERROR or SCRIPT ERROR |
| REQ-32 | Running project | Tester reports | Each of (a) to (d) listed as "pending user check" |
| REQ-33 | `docs/ARCHITECTURE.md` | Review | All listed items present |
| REQ-34 | Earlier specs' tests | Rerun the remaining M1 and sun-spec checks | All still pass; replaced checks run in their new form |
| REQ-35 | Makefile | `make help` | Both targets listed; no Python target |

## Edge cases and errors

- **DEM download fails, needs authentication, or the license is unclear**: no other dataset is substituted. The blocker is written in `docs/DATA_SOURCES.md` (what was tried, the error or license text, date) and the implementer reports BLOCKED.
- **Label values differ from the expected ones** (for example scaling factor not 0.5): the pipeline uses the label value; the spec's "expected" numbers are not hard-coded. REQ-5 fails only if the label is internally inconsistent with the file.
- **Polar rows**: the first and last rows of each level are kept as computed; the mesh clamps latitude to row centres (REQ-15), so there is no sampling outside the grid at the pole.
- **Longitude 0°/360°**: bilinear sampling wraps; the seam has no gap or step from sampling.
- **Camera below terrain**: M1 REQ-18 keeps the minimum camera distance at 1737.9 units, which is below highland terrain (up to about +10.8 km). The camera can pass through the surface. This is known and accepted for M2; camera changes are Milestone 3.
- **Shadow quality**: the DirectionalLight3D shadow settings from M1 may not show crater shadows well at orbital distance; this is not an M2 failure (Milestone 3).
- **Large raw file**: `LDEM_64.IMG` is about 530 MB. The pipeline may read it in strips; peak memory is recorded in the crate README.

## Assumptions

- **A1 – No Python (user decision "NO PYTHON! RUST!")**: the M2 pipeline is written in Rust. The brief's `tools/prepare_moon_data.py`, its virtual environment, requirements file, and GDAL/rasterio preference do not apply. Because the brief also requires the pipeline to read the imagery and keep it aligned with elevation, the M1 albedo script (Python + Pillow) is ported to the Rust pipeline openly (REQ-9, REQ-10) and removed from `docs/DATA_SOURCES.md`. This is how "no Python" is applied to the whole project for data preparation. The port must reproduce the M1 texture pixel for pixel (REQ-10, user decision "exact match"), so the M1 result is unchanged. If the user wants the M1 script kept as historical documentation, that only changes the documentation, not the design.
- **A2 – Rust way to read the source data: pure Rust, no GDAL.** I could not run shell commands in this session, so I could not try installing anything. What I found by searching the file system: no `libgdal*` in `/usr/lib/x86_64-linux-gnu/`, no `/usr/include/gdal/gdal.h`, no `gdal-config`. The existing Makefile builds Rust for the static `x86_64-unknown-linux-musl` target, which the `gdal` crate (bindings to the C library) does not fit well. The two formats are simple enough to read without GDAL: the LDEM `.IMG` is a raw 16-bit grid with a text label, and the LROC tiles are GeoTIFFs that the `tiff` crate reads (the M1 Python script also read them without GDAL, from the TIFF tags). The polar stereographic formulas are already documented in `docs/DATA_SOURCES.md`. If the `tiff` crate cannot decode the LROC tiles (for example an unsupported compression), the implementer reports BUILD_ISSUE naming the problem, and does not switch to GDAL or Python without a spec change.
- **A3 – DEM choice: global LOLA LDEM_64 (64 ppd), not 512 ppd and not regional.** The M2 mesh has vertex spacing of about 7.6 to 10.7 km, so data finer than about 5 km per pixel cannot show on it. SLDEM2015 at 512 ppd covers only ±60° latitude (poles missing, so it fails the polar check by itself), and the global grid would be about 184 320 × 92 160 samples, tens of GB. LDEM_64 is global (poles included), about 530 MB, from the PDS archive. The 512 ppd data is the regional path for the chunk/LOD milestones (REQ-33). This choice is visible in REQ-2.
- **A4 – Mesh build**: CPU build in GDScript once at startup from the 2048 × 1024 level (about 5.3 km per pixel, close to the vertex spacing), not an offline mesh file. The heightmap is the stored asset that later chunk LOD will also use; a stored mesh would need rebuilding for every LOD. Build time is measured (REQ-16), no limit is set for M2.
- **A5 – Subdivisions**: cube-sphere, 6 faces × 4 × 4 chunks × 64 × 64 quads, 405 600 vertices. A cube-sphere avoids the pole convergence of a latitude/longitude sphere; the chunks are the unit for later LOD.
- **A6 – Elevation file format**: raw little-endian float32 `.f32` with a JSON sidecar, read with `FileAccess`. It keeps real metre values with no quantisation, and Godot does not try to import it.
- **A7 – Landmark values** (centres, diameters, highest and lowest points) are taken from the IAU Gazetteer and the LOLA literature. The thresholds are set below the expected values so that averaging to 4096 × 2048 does not cause false failures. If the Gazetteer differs from a value here, the Gazetteer wins and the spec gets a revision.
- **A8 – Rust toolchain**: the same pinned version as `ephemeris/`; the existing `make rust-setup` installs it.

## Open questions

None.

## Revision history

- 2026-11-10: Initial spec for Milestone 2 (real elevation), from `docs/init-moon-poc.md` sections 3, 4, 5, 8, 10, 11 and the user's "NO PYTHON! RUST!" decision: Rust pipeline in `tools/moon-data/`, global LOLA LDEM_64, cube-sphere chunked mesh, measured landmark validation, replacements of earlier requirements listed in REQ-34.
- 2026-11-10: Revision 1, user decision "exact match". REQ-10 now requires the Rust albedo to match the M1 PNG pixel for pixel; the "at most 1 grey level / 0.1 % of pixels" tolerance is removed from REQ-10, its acceptance criterion and Assumption A1. Nothing else changed.
