# Architecture

How the Moon's geometry is built in Milestone 2, and how it leads to chunked terrain with LOD. Spec: `docs/specs/moon-elevation-milestone-2.md`. 1 unit = 1 km.

## Data flow

```
data/raw/  (not committed, never read by Godot)
  lola_ldem_64/LDEM_64.IMG + .LBL      LOLA DEM, 64 pixels per degree
  lroc_wac_gmm_100m/*.TIF              LROC WAC mosaic tiles
        |
        |  make moon-data   (Rust crate tools/moon-data/)
        v
assets/elevation/lola_height_m_{4096x2048,2048x1024,1024x512}.f32
assets/elevation/moon_data.json
assets/textures/lunar_albedo_4096x2048.png
        |
        |  scripts/moon.gd, once in _ready()
        v
96 chunk meshes under the Moon node
```

Godot reads `moon_data.json`, checks the height file against it (size and SHA-256), and builds the mesh. If the metadata or the height file is missing or does not match, one ERROR line names the file and no terrain is built. There is no fallback sphere.

## Cube-sphere chunk layout

The Moon is a cube-sphere. Each of the six cube faces is a grid of 256 x 256 quads, split into 4 x 4 chunks of 64 x 64 quads. A chunk is one `MeshInstance3D` named `Chunk_<face>_<cx>_<cy>` with 65 x 65 vertices and its own `ArrayMesh`.

| Quantity | Value |
|---|---|
| Faces | 6 (+X, -X, +Y, -Y, +Z, -Z, in that order) |
| Chunks | 6 x 16 = 96 |
| Vertices per chunk | 65 x 65 = 4225 |
| Vertices in all chunks | 6 x 16 x 65 x 65 = 405 600 |
| Distinct surface points | 6 x 256 x 256 + 2 = 393 218 (chunk and face edges share points) |
| Triangles | 6 x 256 x 256 x 2 = 786 432 |

### Why a cube-sphere avoids polar distortion

A latitude/longitude sphere has rings of vertices that shrink to a point at each pole. Its triangles there become long thin slivers, and one pole vertex is shared by hundreds of them. Displacement and lighting on such triangles show pinching and spikes.

A cube-sphere has no special point. The poles lie in the middle of the +Y and -Y faces, where the grid is as regular as on the equator. Grid lines on a face are spaced by equal angles (`tan` of an evenly stepped angle, from -45 to +45 degrees), which keeps the cells close to the same size from the face centre to the cube corners. Measured on the undisplaced mesh: triangle edges are between 7.5 km and 17.4 km long (the long ones are quad diagonals), so the ratio of the longest to the shortest edge is 2.30. Quad sides are between 7.5 and 10.7 km.

### Vertices

For a face with outward normal `n` and axes `u`, `v` (with `u x v = n`), grid point `(i, j)` is the cube point `n + u tan(a_i) + v tan(a_j)`, `a_i = (i - 128) / 128 x 45 degrees`, normalised to a direction `d`. Then:

- latitude `asin(d.y)`, east longitude `atan2(d.x, d.z)` in 0..360 degrees. This is the Milestone 1 orientation: north pole on +Y, (0 N, 0 E) on +Z, (0 N, 90 E) on +X.
- height `h` in metres: bilinear sample of the 2048 x 1024 level between cell centres, wrapping in longitude between the last and first column, clamped in latitude to the first and last row centres.
- position `d x (1737.4 + h / 1000)`. No vertical exaggeration.
- UV: `u = longitude / 360`, `v = (90 - latitude) / 180`.

Points on chunk and face edges are created once and reused, so their positions are identical in every chunk. Normals are area-weighted sums of the displaced triangle normals over every triangle that touches a point, including triangles in neighbouring chunks and faces, so lighting has no seam.

The 0 E meridian runs along chunk edges (the middle of the +Z face and of the two pole faces). A vertex on it gets `u = 1` in chunks to its west and `u = 0` in chunks to its east. A pole vertex has no longitude; it gets the `u` of its chunk's centre. No triangle spans more than 0.25 in `u`.

### Height level used

The mesh samples the 2048 x 1024 level (about 5.3 km per cell at the equator). The vertex spacing is 7.5 to 10.7 km, so this level is the closest one that is still finer than the mesh. The 4096 x 2048 level would add detail the mesh cannot show; the 1024 x 512 level (10.7 km) would lose detail the mesh can show. The 4096 x 2048 level is used for the landmark measurements in `docs/VALIDATION.md` and is ready for finer chunk levels.

### Build cost

The mesh is built once at startup on the CPU in GDScript (`scripts/moon.gd`, `_build_terrain`). There is no terrain code in `_process` or `_physics_process`. The build prints its time once. Measured on the development machine (4 cores, Godot 4.7.2, headless): `terrain build ms: 979` (five runs: 977 to 989 ms).

The material is one shared `ShaderMaterial` using `shaders/lunar_surface.gdshader` (Milestone 3, REQ-1 to REQ-3, REQ-16): Lommel-Seeliger diffuse light, no specular, no ambient, the albedo texture, and the ENU normal map `assets/textures/lunar_normal_enu_4096x2048.png` rotated into world space per fragment. `scripts/moon.gd` checks the normal map against `moon_data.json` at startup and falls back to vertex normals if it does not match. Displacement is in the vertices; the shader writes no `VERTEX`.

## Chunk, LOD and streaming design

A design for Milestones after 4. None of it is implemented; today's build is the fixed 96-chunk mesh above. Measured numbers here come from `make perf HEADLESS=1` (2026-11-11, `docs/PERFORMANCE.md`); the rest are code constants or arithmetic with the inputs shown.

### Quadtree per cube face

- The roots are exactly today's 96 chunks: 6 faces x 4 x 4, each 64 x 64 quads and 65 x 65 vertices, named `Chunk_<face>_<cx>_<cy>`.
- A chunk splits into 2 x 2 children. Every child keeps 64 x 64 quads and 65 x 65 vertices and covers a quarter of its parent's face-grid range, so the vertex spacing halves per depth. A node at depth `d` covers `1 / (4 x 2^d)` of a face side.
- The vertex rule stays the same: equal-angle grid on the face, height sampled bilinearly from one data source, edge points shared between chunks of the same depth.

### Depth to data source

Vertex spacing at depth 0 is the measured quad side range, 7.538 to 10.661 km on the reference sphere, halved per depth. Data cell size is at the equator, `2 x pi x 1737.4 km / width` (cells shrink in longitude toward the poles by cos(latitude)). A source supports a depth without oversampling when its cell is no larger than the shortest quad side at that depth.

| Depth | Chunks if uniform (96 x 4^d) | Vertex spacing (km) | Data source | Cell (km) |
|---|---|---|---|---|
| 0 | 96 | 7.538 to 10.661 | `lola_height_m_2048x1024` | 5.330 |
| 1 | 384 | 3.769 to 5.331 | `lola_height_m_4096x2048` | 2.665 |
| 2 | 1 536 | 1.885 to 2.665 | `LDEM_64` (23040 x 11520) | 0.474 |
| 3 | 6 144 | 0.942 to 1.333 | `LDEM_64` | 0.474 |
| 4 | 24 576 | 0.471 to 0.666 | regional tiles (SLDEM2015, 512 ppd; polar grids for the caps) | 0.059 |
| 5 | 98 304 | 0.236 to 0.333 | regional tiles | 0.059 |
| 6 | 393 216 | 0.118 to 0.167 | regional tiles | 0.059 |

Deepest depth each source supports without oversampling:

| Source | Cell (km) | Deepest depth | Reason |
|---|---|---|---|
| `lola_height_m_1024x512` | 10.661 | none | 10.661 > 7.538, the shortest quad at depth 0; usable only as a quick preview or a placeholder while a finer level loads |
| `lola_height_m_2048x1024` | 5.330 | 0 | 5.330 <= 7.538; at depth 1, 5.330 > 3.769 |
| `lola_height_m_4096x2048` | 2.665 | 1 | 2.665 <= 3.769; at depth 2, 2.665 > 1.885 |
| `LDEM_64` (64 ppd, finest global level) | 0.474 | 3 | 0.474 <= 0.942; at depth 4, 0.474 > 0.471 |
| Regional 512 ppd tiles | 0.059 | 6 | 0.059 <= 0.118; at depth 7, 0.0592 > 0.0589 |

`LDEM_64` is read by the tool, not by Godot today; serving depths 2 and 3 needs it cut into the same face-aligned tiles as the regional data (below).

### Split and merge

- **Criterion: screen-space error.** For a node with largest vertex spacing `s` (km) at distance `D` (km) from the camera, the projected error in pixels is `e = s / D x H / (2 tan(fov / 2))`, with `H` the viewport height in pixels and `fov` the camera's vertical field of view. Split when `e` exceeds a threshold (in pixels) and a finer source exists for the child depth; merge four children when their parent's `e` falls below the threshold times a factor under 1, so a node does not split and merge on alternate frames.
- **Per-frame budget.** Each frame the main thread applies at most a fixed number of splits/merges and a fixed time slice, taken in order of largest error first. Work beyond the budget waits for the next frame; the old node stays visible until its replacement is ready. The budget numbers are set from user-run frame times, which are pending (`docs/PERFORMANCE.md`).
- **Off-main-thread builds.** Height sampling, normals and array building for a node run on worker threads (`WorkerThreadPool`). Only the `ArrayMesh` creation and `add_child` happen on the main thread. Today the whole build is on the main thread and takes 964 to 971 ms for 96 chunks (measured), which is the cost this removes from the frame.

### Cracks at level boundaries: skirts

Where a chunk meets a neighbour one depth coarser, every second edge vertex of the fine chunk has no partner, and the gap shows as a crack. The design uses **skirts**: each chunk gets a strip of 4 x 65 = 260 extra vertices along its edges, copied from the edge vertices and moved inward toward the Moon centre, with the edge normals.

Reason: a skirt depends only on the chunk itself, so a chunk can be built on a worker thread without knowing its neighbours' depths, and it does not need rebuilding when a neighbour splits or merges. Edge stitching needs every neighbour's depth at build time and a rebuild of the neighbours on every change, which conflicts with the per-frame budget. The cost is 260 / 4225 = 6.2% more vertices per chunk and a small seam in shading at depth changes, which the shared-normal rule already keeps small within one depth.

### Streaming regional data

- **Tile layout.** A tile is the height grid for one quadtree node at depth 3, sampled on that node's equal-angle face grid at the resolution of depth 6 (64 x 8 = 512 quads, so 513 x 513 heights), little-endian float32 metres above the reference sphere, as the global levels are. One tile is 513 x 513 x 4 = 1 052 676 bytes. A chunk at depth 3 to 6 reads its heights from the one tile of its depth-3 ancestor. `LDEM_64` is cut the same way at the resolution of depth 3 (65 x 65 heights) for depths 2 and 3.
- **Tool.** `tools/moon-data/` (`make moon-data`) produces the tiles, the same way it produces the global levels now, from `data/raw/`, with checksums written into `moon_data.json`.
- **Listing in `moon_data.json`.** A new array `elevation_tiles`. Each entry has the same fields as an `elevation_levels` entry: `path`, `width`, `height`, `data_type`, `byte_order`, `units`, `quantity`, `grid_convention` (here the face grid), `reference_radius_m`, `min`, `max`, `mean`, `nodata_value`, `nodata_count`, `sha256` (per tile); plus `face`, `depth`, `x`, `y` (the quadtree node) and `sources` (the source products used). Godot checks the size and SHA-256 of a tile before it uses it, as it does for the 2048 x 1024 level today; a tile that fails is not used and its node is not split.
- **Load and evict.** A tile is loaded on a worker thread when a node at depth 2 or deeper is chosen for splitting into the tile's range, and kept in an LRU cache. Cache rule: keep every tile used by a currently visible node and by the nodes queued for building; beyond those, keep the most recently used tiles up to the same count again (twice the tiles in use); evict the least recently used above that. No cache size in bytes is given until one is measured.
- **Polar caps.** SLDEM2015 covers 60 S to 60 N only. North of 60 N and south of 60 S the tool uses the LOLA polar grids. A tile that crosses 60 degrees takes each height from SLDEM2015 where the point is within 60 S to 60 N and from the polar grid elsewhere, and lists both in `sources`. The tiles keep the same face grid everywhere, so Godot does not know which source a tile came from.

### Memory and draw calls

Per chunk, measured: 4225 vertices, 8192 triangles, 233 504 bytes of mesh arrays (positions, normals and UVs as float32, 32-bit indices) and 167 452 bytes stored in Godot's surface buffers (`RenderingServer.mesh_get_surface`). With skirts the vertex count per chunk becomes 4225 + 260 = 4485. Mesh memory therefore grows with the number of resident chunks, `N x 167 452` bytes for `N` chunks without skirts, not with the depth; the quadtree keeps `N` bounded by the split criterion instead of by 96 x 4^d. Draw calls per visible chunk: pending user run (`make perf`, draw calls versus objects drawn), so the design does not yet state a draw-call total.

## Earth (Earth Milestone 1)

Spec: `docs/specs/earth-milestone-1-basic-earth.md`.

```
moon-ephemeris --stream            one JSON line per second, 15 fields (Earth fields: earth_pos_godot,
        |                          earth_distance_km, earth_basis_godot, earth_sun_dir_godot,
        |                          earth_subsolar_lon_deg, earth_subsolar_lat_deg)
        v
scripts/sun_controller.gd          parses and validates the line (Earth fields included; an invalid line is the
        |                          one REQ-25 error), applies the Sun, emits signal line_applied(data)
        v
EarthRoot/EarthController          scripts/earth_controller.gd: sets EarthRoot's global transform from
                                   earth_pos_godot and earth_basis_godot, shows it, and picks the monthly image
```

Node tree in `scenes/main.tscn`, sibling of the Moon (not under the camera rig):

- `EarthRoot` (Node3D), hidden until the first line. Its local frame is the Earth-fixed frame (+x at 0° N 0° E, +z north).
- `EarthSurface` (MeshInstance3D), child of `EarthRoot`: SphereMesh radius 6371 km, 128 segments, 64 rings, lit
  StandardMaterial3D, no shadow casting. A fixed rotation in the scene maps the sphere mesh (pole +Y, u = 0 at +Z)
  to the Earth-fixed frame, so u = 0.5 is 0° E and v = 0 is the north pole.
- `EarthController` (Node): `scripts/earth_controller.gd`.

The existing `Sun` DirectionalLight3D lights Earth; Earth scripts compute no Sun direction. The camera far plane is 440 000.
The monthly image is chosen from the UTC month of each applied line (hard switch, no blending). Images are read at
runtime from `assets/earth/bmng/` (downloaded by `make earth-texture`, not committed), decoded with
`Image.load_from_file`, with mipmaps generated at load. If a file is missing, one ERROR line names it and the
command, and Earth renders with a plain material.

### Earth clouds (Earth Milestone 2)

Spec: `docs/specs/earth-milestone-2-clouds.md`.

`EarthRoot` has two more children, `CloudLower` (radius 6373 km, 2 km up) and `CloudUpper` (radius 6381 km, 10 km up).
Each is a 128 x 64 sphere mesh (same fixed rotation as `EarthSurface`) with a `ShaderMaterial` of
`shaders/cloud.gdshader` as `material_override`, no shadow casting, and the script `scripts/cloud_layer.gd`.
Both shells are lit by the scene `Sun`; no cloud script or shader holds a Sun vector.

- Shader: opacity is 4-octave 3D value-noise fBm sampled at the Earth-fixed direction (mesh direction mapped to the
  Earth-fixed frame, then rotated about +z by the drift angle). `UV` is not read and no texture is used, so there is no seam
  and no polar pinching. The noise value is turned into an approximately uniform rank by a logistic function
  (`spread`), a soft threshold at `1 - coverage` (`softness` wide) gives the shape, and alpha = `cap` x `density` x shape
  (`cap` 0.85 lower, 0.40 upper). Coverage 0 gives alpha 0.
- Clock: `EarthController` passes the `utc` of each applied line to `CloudLower.apply_utc` and `CloudUpper.apply_utc`. In
  doubles, the script computes t = utc - J2000, the drift angle `drift_deg_per_s` x t reduced to 0..360 deg, and the time
  axis w = t / `shape_period_s` split into an integer cell and a fraction. Only these reduced numbers reach the GPU, so
  float32 keeps sub-second resolution. The shader cross-fades (cos/sin weights) two independent noise fields, cell and
  cell + 1, so the pattern changes shape continuously. No wall-clock time is used; after helper failure the last values stay.
- Settings (exported on `cloud_layer.gd`, clamped to 0..1): `coverage` and `density`; lower 0.55 / 1.0, upper 0.25 / 1.0.
  Drift rates: lower -9.0e-5 deg/s (10 m/s west), upper +2.6938e-4 deg/s (30 m/s east). Shape periods: lower 6 h, upper 2 h.
  Noise frequency (cells per radius): lower 4, upper 12 (material parameters).

Known approximations:

- Clouds are noise with no link to real weather or geography.
- The drift is solid-body rotation, the same at every latitude.
- The shells are thin and have no volume.
- There are no cloud shadows.
- The lighting is the standard lit shading, with no scattering.
- At live speed the drift is too slow to see (about 0.32 deg/h lower, 0.97 deg/h upper).
- The altitudes are fixed at 2 km and 10 km.
- The rank mapping of the noise is a logistic fit, so the cloud fraction matches `coverage` to about 0.03, not exactly.
