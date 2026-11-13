//! Rocks (spec REQ-14 to REQ-17, D3): shapes, placement, context and grounding.
//!
//! Choices made where the spec is open (recorded in the implementer report):
//! - Cumulative size law N(>=D) = rho0 x (D / 0.2 m)^-q per m2, q = 2 (the spec gives no slope).
//! - 4 geometric size bins per category; lattice cell of a bin = the larger of 2 x D_hi and the cell
//!   that holds about one candidate (so candidate counts stay small).
//! - Context factors are applied by thinning: candidates are drawn at 16 x the density and kept with
//!   probability factor / 16 (the largest product of the crater factor 4 and the slope factor 4).
//! - "Crater rim and ejecta within 1.5 R" is taken as 0.8 <= rho <= 1.5 (rho = r / rim radius).
//! - Slope is measured over a 2 m baseline.
//! - A rock whose footprint has a burial above 60 % of its height is dropped.

use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};

use crate::hash::{candidate, cells_in, hash, unit, FeatureId, R_KM, STREAM_ROCKS};

pub const CATEGORIES: usize = 3;
pub const MESHES: usize = 32;
pub const LODS: usize = 3;
/// Rock chunk: a cell of the 3D Moon-fixed lattice, side in km.
pub const CHUNK_KM: f64 = 0.064;
const OVERSAMPLE: f64 = 16.0;

type V = [f64; 3];

fn sub(a: V, b: V) -> V { [a[0] - b[0], a[1] - b[1], a[2] - b[2]] }
fn dot(a: V, b: V) -> f64 { a[0] * b[0] + a[1] * b[1] + a[2] * b[2] }
fn cross(a: V, b: V) -> V { [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]] }
fn norm(a: V) -> f64 { dot(a, a).sqrt() }
fn unitv(a: V) -> V { let n = norm(a); a.map(|c| c / n) }

#[derive(Clone, Debug)]
pub struct RockConfig {
    /// Category edges in metres: small, medium, large ranges (REQ-14 defaults).
    pub edges: [f64; 4],
    pub bins: usize,
    pub density_highland: f64,
    pub density_mare: f64,
    pub exponent: f64,
    pub density_scale: f64,
}

impl Default for RockConfig {
    /// A3: rocks >= 0.2 m per m2: 0.02 highland, 0.005 mare. The exponent is an assumption.
    fn default() -> Self {
        RockConfig { edges: [0.02, 0.2, 2.0, 20.0], bins: 4, density_highland: 0.02, density_mare: 0.005, exponent: 2.0, density_scale: 1.0 }
    }
}

impl RockConfig {
    pub fn edge_m(&self, cat: usize, b: usize) -> f64 {
        let (lo, hi) = (self.edges[cat], self.edges[cat + 1]);
        lo * (hi / lo).powf(b as f64 / self.bins as f64)
    }

    /// Rocks per m2 with diameter >= d at region weight m (REQ-13 mix of highland and mare).
    pub fn cumulative(&self, d: f64, m: f64) -> f64 {
        self.density_scale * ((1.0 - m) * self.density_highland + m * self.density_mare) * (d / 0.2).powf(-self.exponent)
    }

    fn bin_density(&self, cat: usize, b: usize, m: f64) -> f64 {
        self.cumulative(self.edge_m(cat, b), m) - self.cumulative(self.edge_m(cat, b + 1), m)
    }

    /// Lattice cell size of a bin in km.
    pub fn cell_km(&self, cat: usize, b: usize) -> f64 {
        let dens = self.bin_density(cat, b, 0.0).max(self.bin_density(cat, b, 1.0));
        (2.0 * self.edge_m(cat, b + 1)).max((1.0 / (OVERSAMPLE * dens)).sqrt()) / 1000.0
    }

    fn level(&self, cat: usize, b: usize) -> u64 {
        (cat * self.bins + b) as u64
    }
}

// ------------------------------------------------------------------ shapes

pub struct Shape {
    /// Unique vertices of LOD 0, centred on the bounding box, longest bounding-box axis = 1.
    pub verts: Vec<V>,
    /// Triangle soup (outward) per LOD.
    pub lods: [Vec<[V; 3]>; LODS],
    pub cut_faces: usize,
    /// Longest over shortest bounding-box axis.
    pub axis_ratio: f64,
    /// Planar cut faces' share of the hull surface area.
    pub cut_area: f64,
}

struct Gen<'a> {
    seed: u64,
    key: (u64, u64),
    k: &'a mut u64,
}

impl Gen<'_> {
    fn u(&mut self) -> f64 {
        *self.k += 1;
        unit(hash(self.seed, STREAM_ROCKS, (1 << 30) + self.key.0, self.key.1 as i64, 0, 0, *self.k))
    }
}

fn hull(points: &[V]) -> Vec<[V; 3]> {
    let n = points.len();
    let centre = points.iter().fold([0.0; 3], |a, p| [a[0] + p[0], a[1] + p[1], a[2] + p[2]]).map(|c| c / n as f64);
    let mut out = Vec::new();
    for i in 0..n {
        for j in i + 1..n {
            for k in j + 1..n {
                let nrm = cross(sub(points[j], points[i]), sub(points[k], points[i]));
                if norm(nrm) < 1e-12 {
                    continue;
                }
                let side = |l: usize| dot(nrm, sub(points[l], points[i]));
                let (pos, neg) = (0..n).fold((false, false), |(p, m), l| (p || side(l) > 1e-9, m || side(l) < -1e-9));
                if pos && neg {
                    continue;
                }
                let tri = if dot(nrm, sub(points[i], centre)) >= 0.0 { [points[i], points[j], points[k]] } else { [points[i], points[k], points[j]] };
                out.push(tri);
            }
        }
    }
    out
}

/// Clips a convex polygon to `v . n <= o`; returns the kept polygon and the points on the plane.
fn clip(poly: &[V], n: V, o: f64) -> (Vec<V>, Vec<V>) {
    let (mut kept, mut on) = (Vec::new(), Vec::new());
    for i in 0..poly.len() {
        let (a, b) = (poly[i], poly[(i + 1) % poly.len()]);
        let (da, db) = (dot(a, n) - o, dot(b, n) - o);
        if da <= 0.0 {
            kept.push(a);
        }
        if (da < 0.0 && db > 0.0) || (da > 0.0 && db < 0.0) {
            let t = da / (da - db);
            let x = [0, 1, 2].map(|c| a[c] + t * (b[c] - a[c]));
            kept.push(x);
            on.push(x);
        } else if da == 0.0 {
            on.push(a);
        }
    }
    (kept, on)
}

fn polygon_cap(points: &[V], n: V) -> Vec<V> {
    let mut u: Vec<V> = Vec::new();
    for p in points {
        if !u.iter().any(|q| norm(sub(*p, *q)) < 1e-9) {
            u.push(*p);
        }
    }
    if u.len() < 3 {
        return Vec::new();
    }
    let c = u.iter().fold([0.0; 3], |a, p| [a[0] + p[0], a[1] + p[1], a[2] + p[2]]).map(|v| v / u.len() as f64);
    let ex = unitv(sub(u[0], c));
    let ey = cross(n, ex);
    u.sort_by(|a, b| {
        let ang = |p: &V| dot(sub(*p, c), ey).atan2(dot(sub(*p, c), ex));
        ang(a).total_cmp(&ang(b))
    });
    u
}

fn triangulate(polys: &[(Vec<V>, bool)]) -> Vec<[V; 3]> {
    let mut tris = Vec::new();
    for (poly, _) in polys {
        let c = poly.iter().fold([0.0; 3], |a, p| [a[0] + p[0], a[1] + p[1], a[2] + p[2]]).map(|v| v / poly.len() as f64);
        for i in 1..poly.len() - 1 {
            let (a, b, d) = (poly[0], poly[i], poly[i + 1]);
            let nrm = cross(sub(b, a), sub(d, a));
            if norm(nrm) < 1e-14 {
                continue;
            }
            tris.push(if dot(nrm, c) >= 0.0 { [a, b, d] } else { [a, d, b] });
        }
    }
    tris
}

fn generate(seed: u64, cat: usize, idx: usize) -> Shape {
    let mut counter = 0u64;
    for _attempt in 0..200 {
        let mut g = Gen { seed, key: (cat as u64, idx as u64), k: &mut counter };
        // Large class (REQ-15): 64 points, ellipsoid ratio 1.3..1.6, exactly 2 cuts of at most 15% of the axis.
        let large = cat == 2;
        let axes = if large {
            let short = 1.0 / (1.3 + 0.3 * g.u());
            [1.0, short + (1.0 - short) * g.u(), short]
        } else {
            [1.0, 0.45 + 0.45 * g.u(), 0.3 + 0.4 * g.u()]
        };
        let points: Vec<V> = (0..if large { 128 } else { 18 })
            .map(|_| {
                let d = unitv([2.0 * g.u() - 1.0, 2.0 * g.u() - 1.0, 2.0 * g.u() - 1.0 + 1e-3]);
                let r = 0.7 + 0.3 * g.u();
                [d[0] * r * axes[0], d[1] * r * axes[1], d[2] * r * axes[2]]
            })
            .collect();
        let mut polys: Vec<(Vec<V>, bool)> = hull(&points).into_iter().map(|t| (t.to_vec(), false)).collect();
        let cuts = if large { 2 } else { 2 + (g.u() * 3.0) as usize }; // 2 to 4
        for _ in 0..cuts {
            let d = unitv([2.0 * g.u() - 1.0, 2.0 * g.u() - 1.0, 2.0 * g.u() - 1.0 + 1e-3]);
            let reach = polys.iter().flat_map(|(p, _)| p.iter()).map(|v| dot(*v, d)).fold(f64::MIN, f64::max);
            let low = polys.iter().flat_map(|(p, _)| p.iter()).map(|v| dot(*v, d)).fold(f64::MAX, f64::min);
            // Large: removes 5..15 % of the extent along the cut direction.
            let o = if large { reach - (reach - low) * (0.05 + 0.1 * g.u()) } else { reach * (0.55 + 0.3 * g.u()) };
            let mut next = Vec::new();
            let mut on = Vec::new();
            for (poly, cut) in &polys {
                let (kept, pts) = clip(poly, d, o);
                on.extend(pts);
                if kept.len() >= 3 {
                    next.push((kept, *cut));
                }
            }
            let cap = polygon_cap(&on, d);
            if cap.len() >= 3 {
                next.push((cap, true));
            }
            polys = next;
        }
        let cut_faces = polys.iter().filter(|(p, c)| *c && p.len() >= 3).count();
        let all: Vec<V> = polys.iter().flat_map(|(p, _)| p.iter().copied()).collect();
        let (mut lo, mut hi) = ([f64::MAX; 3], [f64::MIN; 3]);
        for v in &all {
            for c in 0..3 {
                lo[c] = lo[c].min(v[c]);
                hi[c] = hi[c].max(v[c]);
            }
        }
        let size = [0, 1, 2].map(|c| hi[c] - lo[c]);
        let (longest, shortest) = (size.iter().cloned().fold(f64::MIN, f64::max), size.iter().cloned().fold(f64::MAX, f64::min));
        if cut_faces < 2 || shortest <= 1e-6 || longest / shortest < 1.3 || (large && longest / shortest > 1.6) {
            continue;
        }
        let mid = [0, 1, 2].map(|c| 0.5 * (lo[c] + hi[c]));
        let norm_poly = |p: &V| [0, 1, 2].map(|c| (p[c] - mid[c]) / longest);
        let polys: Vec<(Vec<V>, bool)> = polys.into_iter().map(|(p, c)| (p.iter().map(norm_poly).collect(), c)).collect();
        let lod0 = triangulate(&polys);
        let area = |t: &[[V; 3]]| t.iter().map(|[a, b, c]| 0.5 * norm(cross(sub(*b, *a), sub(*c, *a)))).sum::<f64>();
        let cut_polys: Vec<_> = polys.iter().filter(|(_, c)| *c).cloned().collect();
        let cut_area = area(&triangulate(&cut_polys)) / area(&lod0);
        let mut verts: Vec<V> = Vec::new();
        for t in &lod0 {
            for v in t {
                if !verts.iter().any(|q| norm(sub(*q, *v)) < 1e-9) {
                    verts.push(*v);
                }
            }
        }
        let lod = |keep: usize| -> Vec<[V; 3]> {
            // Farthest-point subsample of the vertices, then their convex hull.
            let mut chosen = vec![verts.iter().copied().max_by(|a, b| norm(*a).total_cmp(&norm(*b))).unwrap_or([0.0; 3])];
            while chosen.len() < keep.min(verts.len()) {
                let next = verts.iter().copied().max_by(|a, b| {
                    let dmin = |p: &V| chosen.iter().map(|c| norm(sub(*p, *c))).fold(f64::MAX, f64::min);
                    dmin(a).total_cmp(&dmin(b))
                });
                chosen.extend(next);
            }
            let tris = hull(&chosen);
            if tris.is_empty() { lod0.clone() } else { tris }
        };
        let n = verts.len();
        let lods = [lod0.clone(), lod((n / 2).max(8)), lod((n / 4).max(6))];
        return Shape { verts, lods, cut_faces, axis_ratio: longest / shortest, cut_area };
    }
    // 200 attempts always succeed in practice; an elongated box keeps the invariants if not.
    let b = [[-0.5, -0.2, -0.1], [0.5, 0.2, 0.1]];
    let c = |x: usize, y: usize, z: usize| [b[x][0], b[y][1], b[z][2]];
    let verts: Vec<V> = (0..8).map(|i| c(i & 1, (i >> 1) & 1, (i >> 2) & 1)).collect();
    let tris = hull(&verts);
    Shape { verts, lods: [tris.clone(), tris.clone(), tris], cut_faces: 6, axis_ratio: 5.0, cut_area: 0.0 }
}

/// The base mesh `idx` (0..32) of category `cat`, generated from the seed and cached.
pub fn shape(seed: u64, cat: usize, idx: usize) -> Arc<Shape> {
    static CACHE: OnceLock<Mutex<HashMap<(u64, usize, usize), Arc<Shape>>>> = OnceLock::new();
    let cache = CACHE.get_or_init(|| Mutex::new(HashMap::new()));
    if let Some(s) = cache.lock().unwrap().get(&(seed, cat, idx)) {
        return s.clone();
    }
    let s = Arc::new(generate(seed, cat, idx));
    cache.lock().unwrap().insert((seed, cat, idx), s.clone());
    s
}

// --------------------------------------------------------------- placement

#[derive(Clone, Debug)]
pub struct Rock {
    pub id: FeatureId,
    pub category: usize,
    pub mesh: usize,
    /// Mesh origin (bounding-box centre) on the grounded rock, km, Moon-fixed.
    pub pos: V,
    /// World-space columns of the instance transform (rotation x size in km x scale 0.6..1.4).
    pub basis: [V; 3],
    pub d_m: f64,
    pub height_m: f64,
    pub sink: f64,
}

fn attr(seed: u64, id: FeatureId, k: u64) -> f64 {
    unit(hash(seed, id.0, id.1 | (1 << 40), id.2, id.3, id.4, id.5.wrapping_mul(16).wrapping_add(k)))
}

/// Terrain heights for placement: LOLA at depth 18 plus a prepared list of craters and the relief.
pub struct Ground<'a> {
    pub height: &'a dyn Fn(V) -> f64,
    /// Is the point on the rim or ejecta (0.8 <= rho <= 1.5) of a crater younger than age 0.3?
    pub rim: &'a dyn Fn(V) -> bool,
    /// Terrain slope in degrees at a point, measured over a 2 m baseline (REQ-16).
    pub slope: &'a dyn Fn(V) -> f64,
}

fn tangent_frame(p: V) -> (V, V, V) {
    let up = unitv(p);
    let (lat, lon) = (up[1].asin(), up[0].atan2(up[2]));
    ([lon.cos(), 0.0, -lon.sin()], [-lat.sin() * lon.sin(), lat.cos(), -lat.sin() * lon.cos()], up)
}

fn offset_point(p: V, e: V, n: V, x_km: f64, y_km: f64) -> V {
    let q = [0, 1, 2].map(|c| p[c] + e[c] * x_km + n[c] * y_km);
    q.map(|c| c * R_KM / norm(q))
}

fn quat_basis(u: [f64; 3]) -> [V; 3] {
    // Shoemake uniform random rotation -> columns.
    let (s1, s2) = ((1.0 - u[0]).sqrt(), u[0].sqrt());
    let (a, b) = (std::f64::consts::TAU * u[1], std::f64::consts::TAU * u[2]);
    let (x, y, z, w) = (s1 * a.sin(), s1 * a.cos(), s2 * b.sin(), s2 * b.cos());
    [
        [1.0 - 2.0 * (y * y + z * z), 2.0 * (x * y + z * w), 2.0 * (x * z - y * w)],
        [2.0 * (x * y - z * w), 1.0 - 2.0 * (x * x + z * z), 2.0 * (y * z + x * w)],
        [2.0 * (x * z + y * w), 2.0 * (y * z - x * w), 1.0 - 2.0 * (x * x + y * y)],
    ]
}

/// All rocks of one category whose sphere position lies in lattice chunk `chunk` (side CHUNK_KM),
/// sorted by id. `m_at` is the region weight at a Moon-fixed point.
pub fn chunk_rocks(seed: u64, cfg: &RockConfig, cat: usize, chunk: [i64; 3], m_at: &dyn Fn(V) -> f64, ground: &Ground) -> Vec<Rock> {
    let c0 = chunk.map(|i| (i as f64 + 0.5) * CHUNK_KM);
    let len = norm(c0);
    if (len - R_KM).abs() > 0.0555 {
        return Vec::new();
    }
    let centre = c0.map(|c| c * R_KM / len);
    let mut out = Vec::new();
    for b in 0..cfg.bins {
        let s = cfg.cell_km(cat, b);
        let level = cfg.level(cat, b);
        for cell in cells_in(centre, 0.0875, s) {
            let cc = cell.map(|i| (i as f64 + 0.5) * s);
            let clen = norm(cc);
            if (clen - R_KM).abs() > s * 1.5 {
                continue;
            }
            let m = m_at(cc.map(|v| v * R_KM / clen)).clamp(0.0, 1.0);
            let lambda = OVERSAMPLE * cfg.bin_density(cat, b, m) * (s * 1000.0) * (s * 1000.0);
            let u = unit(hash(seed, STREAM_ROCKS, level, cell[0], cell[1], cell[2], 1 << 62));
            let (mut k, mut next) = (0u64, (-lambda).exp());
            let mut cdf = next;
            while u > cdf && k < 64 {
                k += 1;
                next *= lambda / k as f64;
                cdf += next;
            }
            for n in 0..k {
                let id = (STREAM_ROCKS, level, cell[0], cell[1], cell[2], n);
                let Some(p) = candidate(seed, id, s) else { continue };
                if cell_of_chunk(p) != chunk {
                    continue;
                }
                if let Some(r) = place(seed, cfg, cat, b, id, p, ground) {
                    out.push(r);
                }
            }
        }
    }
    out.sort_by_key(|r| r.id);
    out
}

fn cell_of_chunk(p: V) -> [i64; 3] {
    p.map(|c| (c / CHUNK_KM).floor() as i64)
}

fn place(seed: u64, cfg: &RockConfig, cat: usize, b: usize, id: FeatureId, p: V, g: &Ground) -> Option<Rock> {
    // Thinning for the context factors (REQ-16).
    let t = attr(seed, id, 0) * OVERSAMPLE;
    let crater_factor = if (g.rim)(p) { 4.0 } else { 1.0 };
    if t >= crater_factor * 4.0 {
        return None;
    }
    let (e, n, _up) = tangent_frame(p);
    let slope_deg = (g.slope)(p).min(30.0);
    if t >= crater_factor * (1.0 + 3.0 * slope_deg / 30.0) {
        return None;
    }
    // Shape, size, rotation, scale.
    let mesh = ((attr(seed, id, 1) * MESHES as f64) as usize).min(MESHES - 1);
    let sh = shape(seed, cat, mesh);
    let (lo, hi) = (cfg.edge_m(cat, b), cfg.edge_m(cat, b + 1));
    let d_m = lo * (hi / lo).powf(attr(seed, id, 2));
    let rot = quat_basis([attr(seed, id, 3), attr(seed, id, 4), attr(seed, id, 5)]);
    let (smin, sspan) = if cat == 2 { (0.9, 0.2) } else { (0.6, 0.8) };
    let sc = [smin + sspan * attr(seed, id, 6), smin + sspan * attr(seed, id, 7), smin + sspan * attr(seed, id, 8)];
    let sink = 0.2 + 0.2 * attr(seed, id, 9);
    // Local-frame (east, north, up) vertices in metres.
    let local: Vec<V> = sh
        .verts
        .iter()
        .map(|v| {
            let s = [v[0] * sc[0] * d_m, v[1] * sc[1] * d_m, v[2] * sc[2] * d_m];
            [0, 1, 2].map(|r| rot[0][r] * s[0] + rot[1][r] * s[1] + rot[2][r] * s[2])
        })
        .collect();
    let (zmin, zmax) = local.iter().fold((f64::MAX, f64::MIN), |(a, b), v| (a.min(v[2]), b.max(v[2])));
    let height = zmax - zmin;
    if height < 1e-6 {
        return None;
    }
    // 8 footprint perimeter points: the vertex farthest along each of 8 horizontal directions.
    let mut samples = vec![(g.height)(p)];
    for k in 0..8 {
        let a = k as f64 * std::f64::consts::FRAC_PI_4;
        let far = local.iter().max_by(|u, v| (u[0] * a.cos() + u[1] * a.sin()).total_cmp(&(v[0] * a.cos() + v[1] * a.sin())))?;
        samples.push((g.height)(offset_point(p, e, n, far[0] / 1000.0, far[1] / 1000.0)));
    }
    let (low, high) = samples.iter().fold((f64::MAX, f64::MIN), |(a, b), &h| (a.min(h), b.max(h)));
    let lowest_vertex = low - sink * height;
    if (high - lowest_vertex) / height > 0.6 {
        return None;
    }
    let origin_h = lowest_vertex - zmin; // origin height above the reference sphere, m
    let up = unitv(p);
    let pos = up.map(|c| c * (R_KM + origin_h / 1000.0));
    let to_world = |l: V| [0, 1, 2].map(|c| e[c] * l[0] + n[c] * l[1] + up[c] * l[2]);
    let basis = [0, 1, 2].map(|col| {
        // Column col of (rot x diag(size scale)) in the local frame, then to Moon-fixed.
        let s = d_m / 1000.0 * sc[col];
        to_world([rot[col][0] * s, rot[col][1] * s, rot[col][2] * s])
    });
    Some(Rock { id, category: cat, mesh, pos, basis, d_m, height_m: height, sink })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_base_mesh_is_elongated_with_cut_faces() {
        for cat in 0..CATEGORIES {
            for idx in 0..MESHES {
                let s = shape(3, cat, idx);
                assert!(s.axis_ratio >= 1.3, "cat {cat} mesh {idx}: ratio {}", s.axis_ratio);
                assert!(s.cut_faces >= 2, "cat {cat} mesh {idx}: cuts {}", s.cut_faces);
                assert!(s.lods.iter().all(|l| l.len() >= 4));
            }
        }
    }

    #[test]
    fn large_rocks_are_blocky_with_small_cut_faces() {
        let (mut lo, mut hi, mut amax) = (f64::MAX, f64::MIN, 0.0f64);
        for idx in 0..MESHES {
            let s = shape(3, 2, idx);
            lo = lo.min(s.axis_ratio);
            hi = hi.max(s.axis_ratio);
            amax = amax.max(s.cut_area);
            assert!(s.cut_area <= 0.25, "mesh {idx}: cut area {}", s.cut_area);
            assert_eq!(s.cut_faces, 2, "mesh {idx}: exactly 2 cuts");
            assert!(s.axis_ratio >= 1.3 - 1e-9 && s.axis_ratio <= 1.6 + 1e-9, "mesh {idx}: ratio {}", s.axis_ratio);
            assert!(1.0 / (s.axis_ratio * 1.1 / 0.9) >= 0.5 - 1e-9, "mesh {idx}: scaled ratio");
        }
        println!("LARGE ratio {lo:.3}..{hi:.3} at scale limit {:.3}..{:.3} cut area max {amax:.3}", 0.9 / (hi * 1.1), 1.0 / (lo * 1.1 / 0.9));
    }

    #[test]
    fn rocks_are_grounded_with_no_gap_and_bounded_burial() {
        let height = |p: V| (p[0] * 200.0) + 0.3 * (p[0] * 4000.0).sin() + 0.2 * (p[1] * 3000.0).cos();
        let rim = |_: V| false;
        let slope = |p: V| ((0.2f64 + 0.0 * p[0]).atan()).to_degrees();
        let ground = Ground { height: &height, rim: &rim, slope: &slope };
        let cfg = RockConfig::default();
        let chunk = [0, 0, (R_KM / CHUNK_KM) as i64];
        let mut checked = 0;
        for cat in 0..CATEGORIES {
            for r in chunk_rocks(1, &cfg, cat, chunk, &|_| 0.5, &ground) {
                let sh = shape(1, cat, r.mesh);
                let (e, n, up) = tangent_frame(r.pos);
                let local: Vec<V> = sh.verts.iter().map(|v| {
                    let w = [0, 1, 2].map(|k| r.basis[0][k] * v[0] + r.basis[1][k] * v[1] + r.basis[2][k] * v[2]);
                    [dot(w, e) * 1000.0, dot(w, n) * 1000.0, dot(w, up) * 1000.0]
                }).collect();
                let zmin = local.iter().map(|v| v[2]).fold(f64::MAX, f64::min);
                let origin_h = (norm(r.pos) - R_KM) * 1000.0;
                let lowest = origin_h + zmin;
                let mut top = f64::MIN;
                for k in 0..8 {
                    let a = k as f64 * std::f64::consts::FRAC_PI_4;
                    let far = local.iter().max_by(|u, v| (u[0] * a.cos() + u[1] * a.sin()).total_cmp(&(v[0] * a.cos() + v[1] * a.sin()))).unwrap();
                    let q = offset_point(r.pos, e, n, far[0] / 1000.0, far[1] / 1000.0);
                    let t = height(q);
                    assert!(t >= lowest - 1e-6, "gap: terrain {t} below rock bottom {lowest}");
                    top = top.max(t);
                }
                assert!((top - lowest) / r.height_m <= 0.6 + 1e-6, "burial {}", (top - lowest) / r.height_m);
                checked += 1;
            }
        }
        assert!(checked > 100, "only {checked} rocks");
    }

    #[test]
    fn shapes_are_deterministic_and_differ() {
        let (a, b) = (shape(5, 0, 1), shape(5, 0, 2));
        assert_eq!(a.verts, generate(5, 0, 1).verts);
        assert_ne!(a.verts, b.verts);
    }
}
