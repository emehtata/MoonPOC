//! LOLA height query (spec REQ-2): bilinear on the M2 levels at depths 0 and 1,
//! Catmull-Rom on the LDEM_64 tiles at depth 2 and deeper. A tile is used only
//! after its size and SHA-256 matched `moon_data.json`. Procedural layers
//! (REQ-8 and later) are not part of Phase 1, so `height_m` is the LOLA height.

use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use crate::sha256::hex_digest;

pub const TILE: usize = 1920;
pub const TILE_COLS: usize = 12;
pub const TILE_ROWS: usize = 6;
pub const LDEM_W: usize = TILE * TILE_COLS;
pub const LDEM_H: usize = TILE * TILE_ROWS;
/// Metres per DN.
pub const SCALE_M: f64 = 0.5;
/// Deepest quadtree depth (spec D4).
pub const ALBEDO_W: usize = 4096;
pub const ALBEDO_H: usize = 2048;
pub const MAX_DEPTH: u32 = 18;
/// Depth to which nodes in an invalid tile may still split (REQ-2).
pub const FALLBACK_DEPTH: u32 = 1;

/// A file named in `moon_data.json`: path relative to the project directory and SHA-256.
#[derive(Clone, Debug)]
pub struct FileRef {
    pub path: String,
    pub sha256: String,
}

pub struct Level {
    pub w: usize,
    pub h: usize,
    pub values: Vec<f32>,
}

enum Tile {
    Unloaded,
    /// The tile and the tick of its last use (REQ-29 LRU).
    Ok(Arc<Vec<i16>>, std::sync::atomic::AtomicU64),
    Bad,
}

pub struct Terrain {
    dir: PathBuf,
    /// Depth 0 (2048 x 1024) and depth 1 (4096 x 2048) levels.
    levels: [Level; 2],
    /// Tile files indexed row * 12 + col (row 0 = north, col 0 = 0 deg E).
    tile_refs: Vec<FileRef>,
    tiles: std::sync::RwLock<Vec<Tile>>,
    reported: Mutex<HashSet<usize>>,
    /// Use counter for the tile LRU, and the most tiles held in memory (7.4 MB each).
    clock: std::sync::atomic::AtomicU64,
    max_tiles: std::sync::atomic::AtomicUsize,
    /// Receives one line per tile that fails its check.
    on_error: Box<dyn Fn(String) + Send + Sync>,
    /// Albedo grey levels (4096 x 2048) and the 10th and 90th percentile used for the region weight.
    albedo: Vec<u8>,
    grey_lo: f64,
    grey_hi: f64,
}

/// Why `Terrain::new` failed, naming the file.
fn check_file(dir: &Path, r: &FileRef, size: usize) -> Result<Vec<u8>, String> {
    let path = dir.join(&r.path);
    let bytes = fs::read(&path).map_err(|e| format!("{}: {e}", r.path))?;
    if bytes.len() != size {
        return Err(format!("{}: {} bytes, expected {size}", r.path, bytes.len()));
    }
    if hex_digest(&bytes) != r.sha256 {
        return Err(format!("{}: SHA-256 does not match moon_data.json", r.path));
    }
    Ok(bytes)
}

impl Terrain {
    /// `levels` are the 2048 x 1024 and 4096 x 2048 files (depth 0 and 1); `tiles` has 72 entries.
    pub fn new(
        dir: &Path,
        levels: [FileRef; 2],
        tiles: Vec<FileRef>,
        albedo: Vec<u8>,
        on_error: Box<dyn Fn(String) + Send + Sync>,
    ) -> Result<Terrain, String> {
        if tiles.len() != TILE_COLS * TILE_ROWS {
            return Err(format!("moon_data.json lists {} ldem64 tiles, expected 72", tiles.len()));
        }
        let dims = [(2048usize, 1024usize), (4096, 2048)];
        let mut loaded = Vec::new();
        for (r, (w, h)) in levels.iter().zip(dims) {
            let bytes = check_file(dir, r, w * h * 4)?;
            let values = bytes.chunks_exact(4).map(|b| f32::from_le_bytes([b[0], b[1], b[2], b[3]])).collect();
            loaded.push(Level { w, h, values });
        }
        let [a, b]: [Level; 2] = loaded.try_into().map_err(|_| "levels".to_string())?;
        if albedo.len() != ALBEDO_W * ALBEDO_H {
            return Err(format!("albedo has {} samples, expected {}", albedo.len(), ALBEDO_W * ALBEDO_H));
        }
        let mut hist = [0usize; 256];
        albedo.iter().for_each(|&g| hist[g as usize] += 1);
        let pct = |q: usize| {
            let mut acc = 0;
            (0..256).find(|&v| { acc += hist[v]; acc * 100 >= albedo.len() * q }).unwrap_or(255) as f64
        };
        let (grey_lo, grey_hi) = (pct(10), pct(90));
        let n = tiles.len();
        Ok(Terrain {
            dir: dir.to_path_buf(),
            levels: [a, b],
            tile_refs: tiles,
            tiles: std::sync::RwLock::new((0..n).map(|_| Tile::Unloaded).collect()),
            reported: Mutex::new(HashSet::new()),
            clock: std::sync::atomic::AtomicU64::new(0),
            max_tiles: std::sync::atomic::AtomicUsize::new(24),
            on_error,
            albedo,
            grey_lo,
            grey_hi,
        })
    }

    /// Loads tile `i` if needed. `None` if it failed its check (one error line, once).
    /// Tile `i` for a reader: read lock on the fast path, write lock only to load or evict.
    fn tile_arc(&self, i: usize) -> Option<Arc<Vec<i16>>> {
        {
            let r = self.tiles.read().unwrap();
            match &r[i] {
                Tile::Ok(a, stamp) => {
                    stamp.store(self.clock.fetch_add(1, std::sync::atomic::Ordering::Relaxed) + 1, std::sync::atomic::Ordering::Relaxed);
                    return Some(a.clone());
                }
                Tile::Bad => return None,
                Tile::Unloaded => {}
            }
        }
        let mut w = self.tiles.write().unwrap();
        self.tile(&mut w, i)
    }

    fn tile(&self, tiles: &mut Vec<Tile>, i: usize) -> Option<Arc<Vec<i16>>> {
        if let Tile::Unloaded = tiles[i] {
            let r = &self.tile_refs[i];
            tiles[i] = match check_file(&self.dir, r, TILE * TILE * 2) {
                Ok(b) => Tile::Ok(Arc::new(b.chunks_exact(2).map(|p| i16::from_le_bytes([p[0], p[1]])).collect()), std::sync::atomic::AtomicU64::new(0)),
                Err(msg) => {
                    if self.reported.lock().unwrap().insert(i) {
                        (self.on_error)(format!("LDEM_64 tile unusable, nodes inside stay at depth {FALLBACK_DEPTH} or shallower: {msg}"));
                    }
                    Tile::Bad
                }
            };
        }
        let now = self.clock.fetch_add(1, std::sync::atomic::Ordering::Relaxed) + 1;
        let tile = match &mut tiles[i] {
            Tile::Ok(a, stamp) => {
                stamp.store(now, std::sync::atomic::Ordering::Relaxed);
                Some(a.clone())
            }
            _ => None,
        };
        // Evict the least recently used tiles above the limit (never the one just used).
        let limit = self.max_tiles.load(std::sync::atomic::Ordering::Relaxed).max(4);
        while tiles.iter().filter(|t| matches!(t, Tile::Ok(..))).count() > limit {
            let oldest = tiles.iter().enumerate().filter_map(|(k, t)| match t { Tile::Ok(_, s) if k != i => Some((s.load(std::sync::atomic::Ordering::Relaxed), k)), _ => None }).min();
            match oldest {
                Some((_, k)) => tiles[k] = Tile::Unloaded,
                None => break,
            }
        }
        tile
    }

    /// Most LDEM_64 tiles kept in memory; the least recently used are evicted (REQ-29).
    pub fn set_max_tiles(&self, n: usize) {
        self.max_tiles.store(n, std::sync::atomic::Ordering::Relaxed);
    }

    /// Bytes of LDEM_64 tiles currently in memory.
    pub fn tile_bytes(&self) -> usize {
        self.tiles.read().unwrap().iter().filter(|t| matches!(t, Tile::Ok(..))).count() * TILE * TILE * 2
    }

    fn tile_index_at(lat: f64, lon: f64) -> usize {
        let x = ((lon.rem_euclid(360.0) / 360.0 * LDEM_W as f64) as usize).min(LDEM_W - 1);
        let y = (((90.0 - lat) / 180.0 * LDEM_H as f64).max(0.0) as usize).min(LDEM_H - 1);
        (y / TILE) * TILE_COLS + x / TILE
    }

    /// Deepest depth a node at this point may reach: 18, or 1 inside an unusable tile.
    pub fn max_depth(&self, lat: f64, lon: f64) -> u32 {
        let i = Self::tile_index_at(lat, lon);
        if self.tile_arc(i).is_some() { MAX_DEPTH } else { FALLBACK_DEPTH }
    }

    /// Region weight m in [0, 1] (1 = mare) at a Moon-fixed point (km), from the albedo brightness
    /// (spec D7): 1 at or below the 10th percentile grey level, 0 at or above the 90th, linear between.
    pub fn region_weight(&self, p: [f64; 3]) -> f64 {
        let r = (p[0] * p[0] + p[1] * p[1] + p[2] * p[2]).sqrt();
        let lat = (p[1] / r).asin().to_degrees();
        let lon = p[0].atan2(p[2]).to_degrees().rem_euclid(360.0);
        let x = ((lon / 360.0 * ALBEDO_W as f64) as usize).min(ALBEDO_W - 1);
        let y = (((90.0 - lat) / 180.0 * ALBEDO_H as f64).max(0.0) as usize).min(ALBEDO_H - 1);
        let g = f64::from(self.albedo[y * ALBEDO_W + x]);
        ((self.grey_hi - g) / (self.grey_hi - self.grey_lo).max(1.0)).clamp(0.0, 1.0)
    }

    /// Procedural height offset in metres (craters, REQ-8 to REQ-13) at a quadtree depth.
    pub fn offset_m(&self, seed: u64, cfg: &crate::crater::CraterConfig, lat: f64, lon: f64, depth: u32) -> f64 {
        if depth >= 2 && self.max_depth(lat, lon) < depth {
            return 0.0; // inside an unusable tile nothing is built below depth 1
        }
        let p = surface_point(lat, lon);
        crate::crater::offset_m(seed, cfg, p, depth, &|q| self.region_weight(q)) + crate::relief::offset_m(seed, p, depth, cfg.k_s)
    }

    /// LOLA height plus the procedural offset (REQ-2).
    pub fn height_m(&self, seed: u64, cfg: &crate::crater::CraterConfig, lat: f64, lon: f64, depth: u32) -> f64 {
        self.height_lola_m(lat, lon, depth) + self.offset_m(seed, cfg, lat, lon, depth)
    }

    /// Height in metres above the 1 737 400 m sphere, procedural layers off. Latitude and east longitude in degrees.
    pub fn height_lola_m(&self, lat: f64, lon: f64, depth: u32) -> f64 {
        if depth >= 2 {
            if let Some(h) = self.catmull_rom(lat, lon) {
                return h;
            }
        }
        let level = &self.levels[(depth.min(1)) as usize];
        bilinear(&level.values, level.w, level.h, lat, lon)
    }

    /// Rocks of one category in lattice chunk `chunk` (REQ-14 to REQ-17), grounded on the depth-18 terrain.
    pub fn rock_chunk(&self, seed: u64, ccfg: &crate::crater::CraterConfig, rcfg: &crate::rocks::RockConfig, cat: usize, chunk: [i64; 3]) -> Vec<crate::rocks::Rock> {
        let c0 = chunk.map(|i| (i as f64 + 0.5) * crate::rocks::CHUNK_KM);
        let len = (c0[0] * c0[0] + c0[1] * c0[1] + c0[2] * c0[2]).sqrt();
        if (len - crate::hash::R_KM).abs() > 0.0555 {
            return Vec::new();
        }
        let centre = c0.map(|c| c * crate::hash::R_KM / len);
        let m_at = |p: [f64; 3]| self.region_weight(p);
        let point_height = |p: [f64; 3]| {
            let (lat, lon) = lat_lon(p);
            self.height_lola_m(lat, lon, MAX_DEPTH)
        };
        let relief = |p: [f64; 3]| crate::relief::offset_m(seed, p, MAX_DEPTH, ccfg.k_s);
        if cat == crate::rocks::CATEGORIES - 1 {
            // Large rocks are sparse: query craters at each point instead of listing them for the chunk.
            let height = |p: [f64; 3]| point_height(p) + crate::crater::offset_m(seed, ccfg, p, MAX_DEPTH, &m_at) + relief(p);
            let rim = |p: [f64; 3]| crate::crater::on_young_rim(seed, ccfg, p, &m_at);
            let slope = |p: [f64; 3]| {
                let (e, n, _) = frame_at(p);
                let d = 0.001;
                let dx = (height(offset_pt(p, e, n, d, 0.0)) - height(offset_pt(p, e, n, -d, 0.0))) / 2.0;
                let dy = (height(offset_pt(p, e, n, 0.0, d)) - height(offset_pt(p, e, n, 0.0, -d))) / 2.0;
                dx.hypot(dy).atan().to_degrees()
            };
            return crate::rocks::chunk_rocks(seed, rcfg, cat, chunk, &m_at, &crate::rocks::Ground { height: &height, rim: &rim, slope: &slope });
        }
        // The chunk, the largest footprint and slope baseline of the category, plus each bin's own reach.
        let margin = 0.0555 + 0.002 + rcfg.edges[cat + 1] * 1.4 / 1000.0;
        let craters = crate::crater::list_reaching(seed, ccfg, centre, margin, MAX_DEPTH, &m_at);
        let height = |p: [f64; 3]| point_height(p) + crate::crater::combine(ccfg, &craters, p) + relief(p);
        let rim = |p: [f64; 3]| crate::crater::in_rim_zone(ccfg, &craters, p);
        // Slope from a 2 m height grid around the chunk, constant inside each grid cell.
        let (e, n, _) = frame_at(centre);
        const GRID: usize = 61;
        let at = |i: usize, j: usize| height(offset_pt(centre, e, n, (i as f64 - 30.0) * 0.002, (j as f64 - 30.0) * 0.002));
        let grid: Vec<f64> = (0..GRID * GRID).map(|k| at(k % GRID, k / GRID)).collect();
        let slope = |p: [f64; 3]| {
            let d = [p[0] - centre[0], p[1] - centre[1], p[2] - centre[2]];
            let (x, y) = ((d[0] * e[0] + d[1] * e[1] + d[2] * e[2]) * 500.0 + 30.0, (d[0] * n[0] + d[1] * n[1] + d[2] * n[2]) * 500.0 + 30.0);
            let (i, j) = ((x.floor() as i64).clamp(0, GRID as i64 - 2) as usize, (y.floor() as i64).clamp(0, GRID as i64 - 2) as usize);
            let h = |a: usize, b: usize| grid[b * GRID + a];
            let dx = (h(i + 1, j) + h(i + 1, j + 1) - h(i, j) - h(i, j + 1)) / (2.0 * 2.0);
            let dy = (h(i, j + 1) + h(i + 1, j + 1) - h(i, j) - h(i + 1, j)) / (2.0 * 2.0);
            dx.hypot(dy).atan().to_degrees()
        };
        crate::rocks::chunk_rocks(seed, rcfg, cat, chunk, &m_at, &crate::rocks::Ground { height: &height, rim: &rim, slope: &slope })
    }

    /// Lattice chunks (side CHUNK_KM) within `radius_km` of a surface point that touch the sphere.
    pub fn chunks_near(lat: f64, lon: f64, radius_km: f64) -> Vec<[i64; 3]> {
        let p = surface_point(lat, lon);
        let k = crate::rocks::CHUNK_KM;
        let r = ((radius_km + 0.06) / k).ceil() as i64;
        let c = p.map(|v| (v / k).floor() as i64);
        let mut out = Vec::new();
        for ix in c[0] - r..=c[0] + r {
            for iy in c[1] - r..=c[1] + r {
                for iz in c[2] - r..=c[2] + r {
                    let m = [ix, iy, iz].map(|i| (i as f64 + 0.5) * k);
                    let len = (m[0] * m[0] + m[1] * m[1] + m[2] * m[2]).sqrt();
                    let d = ((m[0] - p[0]).powi(2) + (m[1] - p[1]).powi(2) + (m[2] - p[2]).powi(2)).sqrt();
                    if (len - crate::hash::R_KM).abs() <= 0.0555 && d <= radius_km + 0.06 {
                        out.push([ix, iy, iz]);
                    }
                }
            }
        }
        out
    }

    /// A square grid of terrain around a surface point for the near-camera ground (a stand-in for the
    /// quadtree nodes of Phase 5): `n` x `n` vertices over `extent_m`, heights from `height_m(.., depth)`.
    /// Positions are relative to the point on the reference sphere (km), so they stay precise.
    pub fn patch(&self, seed: u64, cfg: &crate::crater::CraterConfig, lat: f64, lon: f64, n: usize, extent_m: f64, depth: u32) -> Patch {
        let c = surface_point(lat, lon);
        let (e, nn, up) = frame_at(c);
        let step = extent_m / 1000.0 / (n - 1) as f64;
        let half = extent_m / 2000.0;
        let m_at = |q: [f64; 3]| self.region_weight(q);
        let usable = self.max_depth(lat, lon) >= depth;
        let craters = if usable { crate::crater::list_reaching(seed, cfg, c, half * 1.5, depth, &m_at) } else { Vec::new() };
        let mut pos = Vec::with_capacity(n * n);
        let mut uv = Vec::with_capacity(n * n);
        for j in 0..n {
            for i in 0..n {
                let q = offset_pt(c, e, nn, -half + i as f64 * step, -half + j as f64 * step);
                let (la, lo) = lat_lon(q);
                let off = if usable { crate::crater::combine(cfg, &craters, q) + crate::relief::offset_m(seed, q, depth, cfg.k_s) } else { 0.0 };
                let h = (self.height_lola_m(la, lo, depth) + off) / 1000.0;
                let r = crate::hash::R_KM + h;
                let u = q.map(|v| v / crate::hash::R_KM * r);
                pos.push([u[0] - c[0], u[1] - c[1], u[2] - c[2]]);
                let dlon = (lo - lon + 540.0).rem_euclid(360.0) - 180.0;
                uv.push([((lon + dlon) / 360.0) as f32, ((90.0 - la) / 180.0) as f32]);
            }
        }
        let at = |i: usize, j: usize| pos[j * n + i];
        let mut normals = Vec::with_capacity(n * n);
        for j in 0..n {
            for i in 0..n {
                let (i0, i1, j0, j1) = (i.saturating_sub(1), (i + 1).min(n - 1), j.saturating_sub(1), (j + 1).min(n - 1));
                let t1 = [0, 1, 2].map(|k| at(i1, j)[k] - at(i0, j)[k]);
                let t2 = [0, 1, 2].map(|k| at(i, j1)[k] - at(i, j0)[k]);
                let nr = [t1[1] * t2[2] - t1[2] * t2[1], t1[2] * t2[0] - t1[0] * t2[2], t1[0] * t2[1] - t1[1] * t2[0]];
                let l = (nr[0] * nr[0] + nr[1] * nr[1] + nr[2] * nr[2]).sqrt().max(1e-300);
                normals.push(nr.map(|v| v / l));
            }
        }
        let mut indices = Vec::with_capacity((n - 1) * (n - 1) * 6);
        for j in 0..n - 1 {
            for i in 0..n - 1 {
                let (a, b, cc, d) = ((j * n + i) as i32, (j * n + i + 1) as i32, ((j + 1) * n + i) as i32, ((j + 1) * n + i + 1) as i32);
                indices.extend([a, cc, b, b, cc, d]);
            }
        }
        let _ = up;
        Patch { centre: c, pos, normals, uv, indices }
    }

    fn catmull_rom(&self, lat: f64, lon: f64) -> Option<f64> {
        let fx = lon.rem_euclid(360.0) / 360.0 * LDEM_W as f64 - 0.5;
        let fy = ((90.0 - lat) / 180.0 * LDEM_H as f64 - 0.5).clamp(0.0, (LDEM_H - 1) as f64);
        let (x0, y0) = (fx.floor(), fy.floor());
        let mut dn = [[0.0f64; 4]; 4];
        let mut cache: Option<(usize, Arc<Vec<i16>>)> = None;
        for (j, row) in dn.iter_mut().enumerate() {
            let y = (y0 as i64 + j as i64 - 1).clamp(0, LDEM_H as i64 - 1) as usize;
            for (i, v) in row.iter_mut().enumerate() {
                let x = (x0 as i64 + i as i64 - 1).rem_euclid(LDEM_W as i64) as usize;
                let idx = (y / TILE) * TILE_COLS + x / TILE;
                if cache.as_ref().map(|c| c.0) != Some(idx) {
                    cache = Some((idx, self.tile_arc(idx)?));
                }
                *v = f64::from(cache.as_ref()?.1[(y % TILE) * TILE + x % TILE]);
            }
        }
        let (tx, ty) = (fx - x0, fy - y0);
        let col: Vec<f64> = dn.iter().map(|r| cubic(r, tx)).collect();
        Some(cubic(&col, ty) * SCALE_M)
    }
}

/// Output of `Terrain::patch`.
pub struct Patch {
    pub centre: [f64; 3],
    pub pos: Vec<[f64; 3]>,
    pub normals: Vec<[f64; 3]>,
    pub uv: Vec<[f32; 2]>,
    pub indices: Vec<i32>,
}

/// Latitude and east longitude (degrees) of a Moon-fixed point.
pub fn lat_lon(p: [f64; 3]) -> (f64, f64) {
    let r = (p[0] * p[0] + p[1] * p[1] + p[2] * p[2]).sqrt();
    ((p[1] / r).asin().to_degrees(), p[0].atan2(p[2]).to_degrees().rem_euclid(360.0))
}

fn frame_at(c: [f64; 3]) -> ([f64; 3], [f64; 3], [f64; 3]) {
    let r = (c[0] * c[0] + c[1] * c[1] + c[2] * c[2]).sqrt();
    let u = c.map(|v| v / r);
    let (la, lo) = (u[1].asin(), u[0].atan2(u[2]));
    ([lo.cos(), 0.0, -lo.sin()], [-la.sin() * lo.sin(), la.cos(), -la.sin() * lo.cos()], u)
}

fn offset_pt(p: [f64; 3], e: [f64; 3], n: [f64; 3], x: f64, y: f64) -> [f64; 3] {
    let q = [0, 1, 2].map(|k| p[k] + e[k] * x + n[k] * y);
    let l = (q[0] * q[0] + q[1] * q[1] + q[2] * q[2]).sqrt();
    q.map(|v| v * crate::hash::R_KM / l)
}

/// Moon-fixed point (km) on the reference sphere at a latitude and east longitude in degrees.
pub fn surface_point(lat: f64, lon: f64) -> [f64; 3] {
    let (la, lo) = (lat.to_radians(), lon.to_radians());
    [la.cos() * lo.sin(), la.sin(), la.cos() * lo.cos()].map(|v| v * crate::hash::R_KM)
}

/// Catmull-Rom through p[1] (t = 0) and p[2] (t = 1).
pub fn cubic(p: &[f64], t: f64) -> f64 {
    0.5 * (2.0 * p[1]
        + (p[2] - p[0]) * t
        + (2.0 * p[0] - 5.0 * p[1] + 4.0 * p[2] - p[3]) * t * t
        + (3.0 * p[1] - p[0] - 3.0 * p[2] + p[3]) * t * t * t)
}

/// Bilinear between cell centres, wrapping in longitude, clamped in latitude (as `moon.gd`).
pub fn bilinear(v: &[f32], w: usize, h: usize, lat: f64, lon: f64) -> f64 {
    let fx = lon.rem_euclid(360.0) / 360.0 * w as f64 - 0.5;
    let xf = fx.floor();
    let ax = fx - xf;
    let x0 = (xf as i64).rem_euclid(w as i64) as usize;
    let x1 = (x0 + 1) % w;
    let fy = ((90.0 - lat) / 180.0 * h as f64 - 0.5).clamp(0.0, (h - 1) as f64);
    let y0 = fy.floor() as usize;
    let y1 = (y0 + 1).min(h - 1);
    let ay = fy - y0 as f64;
    let at = |x: usize, y: usize| f64::from(v[y * w + x]);
    let top = at(x0, y0) + (at(x1, y0) - at(x0, y0)) * ax;
    let bottom = at(x0, y1) + (at(x1, y1) - at(x0, y1)) * ax;
    top + (bottom - top) * ay
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn catmull_rom_passes_through_posts() {
        let p = [3.0, 7.0, -2.0, 11.0];
        assert_eq!(cubic(&p, 0.0), 7.0);
        assert_eq!(cubic(&p, 1.0), -2.0);
    }

    #[test]
    fn bilinear_hits_cell_centres_and_wraps() {
        let v: Vec<f32> = (0..8).map(|i| i as f32).collect(); // 4 x 2
        // centre of cell (1, 0): lon = 360 * 1.5 / 4, lat = 90 - 180 * 0.5 / 2
        assert_eq!(bilinear(&v, 4, 2, 45.0, 135.0), 1.0);
        // between the last and first column the value stays between them
        let seam = bilinear(&v, 4, 2, 45.0, 0.0);
        assert!(seam > 0.0 && seam < 3.0);
    }
}
