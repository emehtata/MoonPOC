//! Lunar terrain GDExtension (spec `lunar-surface-procedural`). Phase 1: the
//! deterministic hash and feature lattice (`hash`), the LOLA height query with
//! checked tiles (`terrain`), and the Godot class that exposes them.

pub mod crater;
pub mod hash;
pub mod node;
pub mod relief;
pub mod rocks;
pub mod sha256;
pub mod terrain;

use std::path::Path;
use std::sync::Arc;

use godot::classes::{Image, Json};
use godot::prelude::*;

use crater::CraterConfig;
use terrain::{FileRef, Terrain};

struct LunarTerrainExtension;

#[gdextension]
unsafe impl ExtensionLibrary for LunarTerrainExtension {}

const METADATA: &str = "assets/elevation/moon_data.json";

/// Handle for GDScript. Call `load_data` once; the query methods are then safe from any thread.
#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct LunarTerrain {
    base: Base<RefCounted>,
    terrain: Option<Arc<Terrain>>,
    /// World seed (64-bit; GDScript int is the same bit pattern). Seed 0 is valid.
    #[var]
    seed: i64,
    /// Crater parameters (assumption A3 defaults); see `crater::CraterConfig`.
    #[var]
    #[init(val = 0.2)]
    k_d: f64,
    #[var]
    #[init(val = 0.04)]
    k_r: f64,
    #[var]
    #[init(val = 0.08)]
    k_i: f64,
    #[var]
    #[init(val = 2000.0)]
    c_highland: f64,
    #[var]
    #[init(val = 800.0)]
    c_mare: f64,
    #[var]
    #[init(val = 2.0)]
    b_highland: f64,
    #[var]
    #[init(val = 1.8)]
    b_mare: f64,
    #[var]
    #[init(val = 1.0)]
    density_scale: f64,
    /// Region weight forced to this value in [0, 1]; a negative value uses the albedo-derived weight.
    #[var]
    #[init(val = -1.0)]
    region_override: f64,
    /// REQ-11 step 2 (smoothing) on or off; the factor (1 - 0.8 a) is always applied.
    #[var]
    #[init(val = true)]
    smoothing: bool,
    /// Relief RMS per octave = k_s x wavelength (REQ-18).
    #[var]
    #[init(val = 0.01)]
    k_s: f64,
    /// Rock density (rocks >= 0.2 m per m2, A3), size exponent (assumption), density multiplier.
    #[var]
    #[init(val = 0.02)]
    rock_density_highland: f64,
    #[var]
    #[init(val = 0.005)]
    rock_density_mare: f64,
    #[var]
    #[init(val = 2.0)]
    rock_exponent: f64,
    #[var]
    #[init(val = 1.0)]
    rock_density_scale: f64,
    /// Category edges in metres: small, medium, large ranges (REQ-14).
    #[var]
    #[init(val = PackedFloat64Array::from([0.02, 0.2, 2.0, 20.0]))]
    rock_edges: PackedFloat64Array,
}

fn field(d: &VarDictionary, key: &str) -> Option<Variant> {
    d.get(key)
}

fn file_ref(d: &VarDictionary) -> Option<FileRef> {
    Some(FileRef {
        path: field(d, "path")?.try_to::<GString>().ok()?.to_string(),
        sha256: field(d, "sha256")?.try_to::<GString>().ok()?.to_string(),
    })
}

/// Reads the level and tile entries from moon_data.json (path text, `sha256`).
type Metadata = ([FileRef; 2], Vec<FileRef>, FileRef);

fn parse_metadata(text: &str) -> Result<Metadata, String> {
    let parsed = Json::parse_string(text);
    let root: VarDictionary = parsed.try_to().map_err(|_| format!("{METADATA} is not a JSON object"))?;
    let array = |key: &str| -> Result<Array<Variant>, String> {
        field(&root, key).and_then(|v| v.try_to().ok()).ok_or(format!("{METADATA} has no '{key}'"))
    };
    let mut levels: [Option<FileRef>; 2] = [None, None];
    for e in array("elevation_levels")?.iter_shared() {
        let Ok(d) = e.try_to::<VarDictionary>() else { continue };
        let w = field(&d, "width").and_then(|v| v.try_to::<f64>().ok()).unwrap_or(0.0) as i64;
        match w {
            2048 => levels[0] = file_ref(&d),
            4096 => levels[1] = file_ref(&d),
            _ => {}
        }
    }
    let [Some(l0), Some(l1)] = levels else { return Err(format!("{METADATA} lacks the 2048 or 4096 level")) };
    let mut tiles: Vec<Option<FileRef>> = vec![None; terrain::TILE_COLS * terrain::TILE_ROWS];
    for e in array("ldem64_tiles")?.iter_shared() {
        let d: VarDictionary = e.try_to().map_err(|_| "bad ldem64_tiles entry".to_string())?;
        // First element of each range array: the north latitude and the west longitude.
        let first = |k: &str| {
            field(&d, k)
                .and_then(|v| v.try_to::<Array<Variant>>().ok())
                .and_then(|a| a.get(0))
                .and_then(|v| v.try_to::<f64>().ok())
                .ok_or(format!("ldem64 tile has no {k}"))
        };
        let row = ((90.0 - first("lat_range_deg_north_south")?) / 30.0).round() as usize;
        let col = (first("lon_range_deg_west_east")? / 30.0).round() as usize;
        if row >= terrain::TILE_ROWS || col >= terrain::TILE_COLS {
            return Err("ldem64 tile outside the grid".into());
        }
        tiles[row * terrain::TILE_COLS + col] = file_ref(&d);
    }
    let tiles = tiles.into_iter().collect::<Option<Vec<_>>>().ok_or("ldem64_tiles is incomplete")?;
    let albedo = field(&root, "albedo").and_then(|v| v.try_to::<VarDictionary>().ok()).and_then(|d| file_ref(&d)).ok_or(format!("{METADATA} has no albedo entry"))?;
    Ok(([l0, l1], tiles, albedo))
}

/// Checks the albedo PNG (size and SHA-256 from moon_data.json) and returns its grey levels (R channel).
fn load_albedo(dir: &Path, r: &FileRef) -> Result<Vec<u8>, String> {
    let path = dir.join(&r.path);
    let bytes = std::fs::read(&path).map_err(|e| format!("{}: {e}", r.path))?;
    if sha256::hex_digest(&bytes) != r.sha256 {
        return Err(format!("{}: SHA-256 does not match moon_data.json", r.path));
    }
    let mut image = Image::load_from_file(&GString::from(path.to_string_lossy().as_ref())).ok_or(format!("{}: cannot decode", r.path))?;
    image.convert(godot::classes::image::Format::RGB8);
    let (w, h) = (image.get_width() as usize, image.get_height() as usize);
    if (w, h) != (terrain::ALBEDO_W, terrain::ALBEDO_H) {
        return Err(format!("{}: {w} x {h}, expected 4096 x 2048", r.path));
    }
    Ok(image.get_data().as_slice().chunks_exact(3).map(|p| p[0]).collect())
}

#[godot_api]
impl LunarTerrain {
    /// Loads moon_data.json and the two M2 levels under `project_dir`. Returns "" on success,
    /// otherwise a message naming the file. Tiles are checked when first used.
    #[func]
    fn load_data(&mut self, project_dir: GString) -> GString {
        let dir = project_dir.to_string();
        let result = std::fs::read_to_string(Path::new(&dir).join(METADATA))
            .map_err(|e| format!("{METADATA}: {e}"))
            .and_then(|text| parse_metadata(&text))
            .and_then(|(levels, tiles, albedo)| {
                let grey = load_albedo(Path::new(&dir), &albedo)?;
                Terrain::new(Path::new(&dir), levels, tiles, grey, Box::new(|m| godot_error!("{m}")))
            });
        match result {
            Ok(t) => {
                self.terrain = Some(Arc::new(t));
                GString::new()
            }
            Err(e) => e.as_str().into(),
        }
    }

    #[func]
    fn is_ready(&self) -> bool {
        self.terrain.is_some()
    }

    fn config(&self) -> CraterConfig {
        CraterConfig {
            k_d: self.k_d,
            k_r: self.k_r,
            k_i: self.k_i,
            c_highland: self.c_highland,
            c_mare: self.c_mare,
            b_highland: self.b_highland,
            b_mare: self.b_mare,
            density_scale: self.density_scale,
            region_override: (self.region_override >= 0.0).then_some(self.region_override.min(1.0)),
            smoothing: self.smoothing,
            k_s: self.k_s,
        }
    }

    /// Height in metres above the 1 737 400 m sphere: LOLA plus the procedural craters (REQ-2); NaN before `load_data`.
    #[func]
    fn height_m(&self, lat_deg: f64, lon_deg: f64, depth: i64) -> f64 {
        let cfg = self.config();
        self.terrain.as_ref().map_or(f64::NAN, |t| t.height_m(self.seed as u64, &cfg, lat_deg, lon_deg, depth.max(0) as u32))
    }

    /// The LOLA interpolant alone (procedural layers off).
    #[func]
    fn height_lola_m(&self, lat_deg: f64, lon_deg: f64, depth: i64) -> f64 {
        self.terrain.as_ref().map_or(f64::NAN, |t| t.height_lola_m(lat_deg, lon_deg, depth.max(0) as u32))
    }

    /// The procedural offset alone, in metres.
    #[func]
    fn procedural_m(&self, lat_deg: f64, lon_deg: f64, depth: i64) -> f64 {
        let cfg = self.config();
        self.terrain.as_ref().map_or(f64::NAN, |t| t.offset_m(self.seed as u64, &cfg, lat_deg, lon_deg, depth.max(0) as u32))
    }

    /// Region weight m in [0, 1] (1 = mare) from the albedo (spec D7), or the override.
    #[func]
    fn region_weight(&self, lat_deg: f64, lon_deg: f64) -> f64 {
        if self.region_override >= 0.0 {
            return self.region_override.min(1.0);
        }
        self.terrain.as_ref().map_or(f64::NAN, |t| t.region_weight(terrain::surface_point(lat_deg, lon_deg)))
    }

    /// Craters whose centre lies in a cube of half-size `half_km` around a surface point, with diameter
    /// >= `min_d_m`, sorted by id. 12 values each: [bin, ix, iy, iz, n, x, y, z, D_m, age, lobes, phase]
    /// (x, y, z: km, Moon-fixed, on the sphere). Uses the seed and the crater parameters.
    #[func]
    fn crater_list(&self, lat_deg: f64, lon_deg: f64, half_km: f64, min_d_m: f64) -> PackedFloat64Array {
        let Some(t) = self.terrain.as_ref() else { return PackedFloat64Array::new() };
        let cfg = self.config();
        let list = crater::list(self.seed as u64, &cfg, terrain::surface_point(lat_deg, lon_deg), half_km, min_d_m, &|p| t.region_weight(p));
        list.iter()
            .flat_map(|c| {
                [c.id.1 as f64, c.id.2 as f64, c.id.3 as f64, c.id.4 as f64, c.id.5 as f64, c.centre[0], c.centre[1], c.centre[2],
                 c.d_m, c.age, f64::from(c.lobes), c.phase]
            })
            .collect()
    }

    /// Rim radius in metres of a crater at azimuth `theta` (radians, from east towards north).
    #[func]
    fn crater_rim_m(&self, d_m: f64, lobes: i64, phase: f64, theta: f64) -> f64 {
        crater_from(&[0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, d_m, 0.0, lobes as f64, phase]).rim_radius_m(&self.config(), theta)
    }

    /// Height offset in metres at a surface point from the given craters (12 values each, as `crater_list`),
    /// combined oldest to youngest (REQ-12). Does not read LOLA or the seed.
    #[func]
    fn craters_offset_m(&self, craters: PackedFloat64Array, lat_deg: f64, lon_deg: f64) -> f64 {
        let cfg = self.config();
        let list: Vec<crater::Crater> = craters.as_slice().chunks_exact(12).map(crater_from).collect();
        crater::combine(&cfg, &list, terrain::surface_point(lat_deg, lon_deg))
    }

    /// Deepest quadtree depth allowed at this point: 18, or 1 inside a tile that failed its check.
    #[func]
    fn max_depth(&self, lat_deg: f64, lon_deg: f64) -> i64 {
        self.terrain.as_ref().map_or(1, |t| i64::from(t.max_depth(lat_deg, lon_deg)))
    }

    /// Lattice features of one stream and size level inside a cube of half-size `half_km`
    /// around a surface point: flat array of 7 values per feature, [ix, iy, iz, n, x, y, z]
    /// (x, y, z in km, Moon-fixed, on the sphere), sorted by id. Uses the world seed.
    #[func]
    fn feature_list(&self, stream: i64, level: i64, cell_km: f64, per_cell: i64, lat_deg: f64, lon_deg: f64, half_km: f64) -> PackedFloat64Array {
        let (lat, lon) = (lat_deg.to_radians(), lon_deg.to_radians());
        let c = [lat.cos() * lon.sin(), lat.sin(), lat.cos() * lon.cos()].map(|v| v * hash::R_KM);
        let list = hash::region(self.seed as u64, stream as u64, level as u64, cell_km, per_cell.max(0) as u64, c, half_km);
        list.iter()
            .flat_map(|(id, p)| [id.2 as f64, id.3 as f64, id.4 as f64, id.5 as f64, p[0], p[1], p[2]])
            .collect()
    }

    fn rock_config(&self) -> rocks::RockConfig {
        let mut c = rocks::RockConfig { density_highland: self.rock_density_highland, density_mare: self.rock_density_mare, exponent: self.rock_exponent, density_scale: self.rock_density_scale, ..Default::default() };
        if let Ok(e) = <[f64; 4]>::try_from(self.rock_edges.as_slice()) {
            c.edges = e;
        }
        c
    }

    /// Side of a rock chunk in km.
    #[func]
    fn rock_chunk_km(&self) -> f64 {
        rocks::CHUNK_KM
    }

    /// Rock chunks within `radius_km` of a surface point: 3 ints (lattice cell) per chunk.
    #[func]
    fn rock_chunks_near(&self, lat_deg: f64, lon_deg: f64, radius_km: f64) -> PackedInt64Array {
        Terrain::chunks_near(lat_deg, lon_deg, radius_km).iter().flatten().copied().collect()
    }

    /// Rocks of one category (0 small, 1 medium, 2 large) in a chunk, sorted by id. 22 values each:
    /// [level, ix, iy, iz, n, category, mesh, x, y, z, 9 basis values (3 columns), D_m, height_m, sink];
    /// x, y, z and the basis are Moon-fixed km (the basis includes size and the 0.6..1.4 scale).
    #[func]
    fn rock_chunk(&self, ix: i64, iy: i64, iz: i64, category: i64) -> PackedFloat64Array {
        let Some(t) = self.terrain.as_ref() else { return PackedFloat64Array::new() };
        let rocks = t.rock_chunk(self.seed as u64, &self.config(), &self.rock_config(), category.clamp(0, 2) as usize, [ix, iy, iz]);
        rock_values(&rocks)
    }

    /// Rocks whose position lies in the cube of half-size `half_km` around a surface point (REQ-3 rock list);
    /// `category` -1 for all. Same 22 values each, sorted by id.
    #[func]
    fn rock_list(&self, lat_deg: f64, lon_deg: f64, half_km: f64, category: i64) -> PackedFloat64Array {
        let Some(t) = self.terrain.as_ref() else { return PackedFloat64Array::new() };
        let (ccfg, rcfg) = (self.config(), self.rock_config());
        let c = terrain::surface_point(lat_deg, lon_deg);
        let mut all = Vec::new();
        for chunk in Terrain::chunks_near(lat_deg, lon_deg, half_km * 1.75) {
            for cat in (0..3).filter(|&k| category < 0 || k as i64 == category) {
                all.extend(t.rock_chunk(self.seed as u64, &ccfg, &rcfg, cat, chunk));
            }
        }
        // Compare on the reference sphere: a rock sits at the terrain height, up to 9 km below it.
        all.retain(|r| {
            let l = (r.pos[0] * r.pos[0] + r.pos[1] * r.pos[1] + r.pos[2] * r.pos[2]).sqrt();
            (0..3).all(|k| (r.pos[k] * hash::R_KM / l - c[k]).abs() <= half_km)
        });
        all.sort_by_key(|r| r.id);
        rock_values(&all)
    }

    /// Base mesh of a category: { "verts": PackedVector3Array, "normals": PackedVector3Array } as a triangle
    /// soup (clockwise from outside), unit size (longest bounding-box axis 1), `lod` 0..2. Also
    /// reports "cut_faces" and "axis_ratio" for the shape.
    #[func]
    fn rock_mesh(&self, category: i64, index: i64, lod: i64) -> VarDictionary {
        let s = rocks::shape(self.seed as u64, category.clamp(0, 2) as usize, index.clamp(0, 31) as usize);
        let mut verts = PackedVector3Array::new();
        let mut normals = PackedVector3Array::new();
        for t in &s.lods[lod.clamp(0, 2) as usize] {
            let n = {
                let (a, b) = ([t[1][0] - t[0][0], t[1][1] - t[0][1], t[1][2] - t[0][2]], [t[2][0] - t[0][0], t[2][1] - t[0][1], t[2][2] - t[0][2]]);
                let c = [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
                let l = (c[0] * c[0] + c[1] * c[1] + c[2] * c[2]).sqrt().max(1e-300);
                Vector3::new((c[0] / l) as f32, (c[1] / l) as f32, (c[2] / l) as f32)
            };
            // Godot front faces are clockwise: list each outward triangle as (0, 2, 1).
            for k in [0usize, 2, 1] {
                verts.push(Vector3::new(t[k][0] as f32, t[k][1] as f32, t[k][2] as f32));
                normals.push(n);
            }
        }
        let mut d = VarDictionary::new();
        d.set("verts", verts);
        d.set("normals", normals);
        d.set("cut_faces", s.cut_faces as i64);
        d.set("axis_ratio", s.axis_ratio);
        d
    }

    /// Terrain grid around a surface point (stand-in for the Phase 5 nodes): { "centre": Vector3 (km, f64 parts
    /// in "centre_xyz"), "verts", "normals", "uvs", "indices" }. Vertices are relative to the centre point.
    #[func]
    fn terrain_patch(&self, lat_deg: f64, lon_deg: f64, n: i64, extent_m: f64, depth: i64) -> VarDictionary {
        let mut d = VarDictionary::new();
        let Some(t) = self.terrain.as_ref() else { return d };
        let p = t.patch(self.seed as u64, &self.config(), lat_deg, lon_deg, n.max(2) as usize, extent_m, depth.max(0) as u32);
        let v3 = |a: &[f64; 3]| Vector3::new(a[0] as f32, a[1] as f32, a[2] as f32);
        d.set("centre_xyz", PackedFloat64Array::from(p.centre));
        d.set("verts", p.pos.iter().map(v3).collect::<PackedVector3Array>());
        d.set("normals", p.normals.iter().map(v3).collect::<PackedVector3Array>());
        d.set("uvs", p.uv.iter().map(|u| Vector2::new(u[0], u[1])).collect::<PackedVector2Array>());
        d.set("indices", p.indices.iter().copied().collect::<PackedInt32Array>());
        d
    }

    /// Centre at LOLA height (km, Moon-fixed), bounding radius and vertex spacing of a quadtree node, without building it.
    #[func]
    fn node_bounds(&self, face: i64, depth: i64, x: i64, y: i64) -> PackedFloat64Array {
        let (c, r, s) = node::bounds(face as usize, depth as u32, x as u32, y as u32);
        // The centre is lifted to the LOLA height of the node's depth so camera distances see the real ground.
        let h = self.terrain.as_ref().map_or(0.0, |t| {
            let (lat, lon) = terrain::lat_lon(c);
            t.height_lola_m(lat, lon, depth as u32) / 1000.0
        });
        let k = (hash::R_KM + h) / hash::R_KM;
        PackedFloat64Array::from([c[0] * k, c[1] * k, c[2] * k, r, s])
    }

    /// Index buffer shared by all quadtree nodes.
    #[func]
    fn node_indices(&self) -> PackedInt32Array {
        node::indices().into_iter().collect()
    }

    /// Builds quadtree node (face, depth, x, y) (REQ-26 to REQ-30): { "verts", "normals", "uvs" (Vector2),
    /// "morph" (PackedFloat32Array, 3 per vertex: parent-interpolated minus own position), "centre_xyz",
    /// "radius_km", "spacing_km" }. Vertices are relative to the node centre on the reference sphere, 4485 each
    /// (65 x 65 grid then 4 skirt rows). Safe to call from worker threads.
    #[func]
    fn build_node(&self, face: i64, depth: i64, x: i64, y: i64) -> VarDictionary {
        let mut d = VarDictionary::new();
        let Some(t) = self.terrain.as_ref() else { return d };
        let n = t.build_node(self.seed as u64, &self.config(), face as usize, depth as u32, x as u32, y as u32);
        let v3 = |a: &[f32; 3]| Vector3::new(a[0], a[1], a[2]);
        d.set("verts", n.verts.iter().map(v3).collect::<PackedVector3Array>());
        d.set("normals", n.normals.iter().map(v3).collect::<PackedVector3Array>());
        d.set("uvs", n.uvs.iter().map(|u| Vector2::new(u[0], u[1])).collect::<PackedVector2Array>());
        d.set("morph", n.morph.iter().flatten().copied().collect::<PackedFloat32Array>());
        d.set("centre_xyz", PackedFloat64Array::from(n.centre));
        d.set("radius_km", n.radius_km);
        d.set("spacing_km", n.spacing_km);
        d
    }

    /// Most LDEM_64 tiles kept in memory (REQ-29 LRU); the default is 24 (177 MB).
    #[func]
    fn set_max_tiles(&self, n: i64) {
        if let Some(t) = self.terrain.as_ref() {
            t.set_max_tiles(n.max(4) as usize);
        }
    }

    /// Bytes of LDEM_64 tiles in memory now.
    #[func]
    fn tile_bytes(&self) -> i64 {
        self.terrain.as_ref().map_or(0, |t| t.tile_bytes() as i64)
    }

    /// Hash as a signed 64-bit int (bit pattern of the u64 hash).
    #[func]
    fn hash64(seed: i64, stream: i64, level: i64, ix: i64, iy: i64, iz: i64, n: i64) -> i64 {
        hash::hash(seed as u64, stream as u64, level as u64, ix, iy, iz, n as u64) as i64
    }
}

fn crater_from(v: &[f64]) -> crater::Crater {
    crater::Crater {
        id: (hash::STREAM_CRATERS, v[0] as u64, v[1] as i64, v[2] as i64, v[3] as i64, v[4] as u64),
        centre: [v[5], v[6], v[7]],
        d_m: v[8],
        age: v[9],
        lobes: v[10] as u32,
        phase: v[11],
    }
}

fn rock_values(rocks: &[rocks::Rock]) -> PackedFloat64Array {
    rocks
        .iter()
        .flat_map(|r| {
            let mut v = vec![r.id.1 as f64, r.id.2 as f64, r.id.3 as f64, r.id.4 as f64, r.id.5 as f64, r.category as f64, r.mesh as f64];
            v.extend(r.pos);
            v.extend(r.basis.iter().flatten());
            v.extend([r.d_m, r.height_m, r.sink]);
            v
        })
        .collect()
}
