//! Cube-face quadtree nodes (spec REQ-26 to REQ-30, docs/ARCHITECTURE.md "Quadtree per cube face").
//!
//! A node (face, depth, x, y) is a 65 x 65 vertex grid on the equal-angle face grid; node (x, y) at
//! depth d covers face-grid coordinates k = (x * 64 + i) / 2^d, with k = 0..256 across a face. The
//! 96 roots (depth 0) are the 6 x 4 x 4 chunks of `moon.gd`. Heights depend only on the direction, so
//! every vertex, including the one-vertex border used for normals, is computed from its own direction:
//! shared edges of same-depth nodes get identical vertices and normals.
//!
//! Choices made where the spec is open (recorded in the implementer report):
//! - Skirt depth is 0.25 x the vertex spacing of the node, straight down along the radial direction.
//! - Geometric error of a node is 0.5 x its vertex spacing (used by the controller for the screen error).
//! - Vertex positions are stored relative to the node centre on the reference sphere, as float32.

use crate::crater::{self, CraterConfig};
use crate::hash::R_KM;
use crate::terrain::{lat_lon, Terrain};

pub const QUADS: usize = 64;
pub const N: usize = QUADS + 1;
pub const SKIRT_VERTS: usize = 4 * N;
pub const VERTS: usize = N * N + SKIRT_VERTS;
const FACE_QUADS: f64 = 256.0;
pub const SKIRT_FRACTION: f64 = 0.25;

/// [normal, u axis, v axis] per face, u x v = normal (as `moon.gd`).
const FACES: [([f64; 3], [f64; 3], [f64; 3]); 6] = [
    ([1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]),
    ([-1.0, 0.0, 0.0], [0.0, 0.0, 1.0], [0.0, 1.0, 0.0]),
    ([0.0, 1.0, 0.0], [0.0, 0.0, 1.0], [1.0, 0.0, 0.0]),
    ([0.0, -1.0, 0.0], [1.0, 0.0, 0.0], [0.0, 0.0, 1.0]),
    ([0.0, 0.0, 1.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0]),
    ([0.0, 0.0, -1.0], [0.0, 1.0, 0.0], [1.0, 0.0, 0.0]),
];

fn warp(k: f64) -> f64 {
    if k == 0.0 {
        -1.0
    } else if k == FACE_QUADS {
        1.0
    } else {
        ((k - FACE_QUADS / 2.0) / (FACE_QUADS / 2.0) * std::f64::consts::FRAC_PI_4).tan()
    }
}

/// Unit direction of face-grid point (ku, kv); values outside 0..256 continue past the face edge.
pub fn face_dir(face: usize, ku: f64, kv: f64) -> [f64; 3] {
    let (n, u, v) = FACES[face];
    let (a, b) = (warp(ku), warp(kv));
    let p = [0, 1, 2].map(|c| n[c] + u[c] * a + v[c] * b);
    let l = (p[0] * p[0] + p[1] * p[1] + p[2] * p[2]).sqrt();
    p.map(|c| c / l)
}

fn k_of(node: u32, i: i64, depth: u32) -> f64 {
    (f64::from(node) * QUADS as f64 + i as f64) / f64::from(1u32 << depth)
}

fn sub(a: [f64; 3], b: [f64; 3]) -> [f64; 3] { [a[0] - b[0], a[1] - b[1], a[2] - b[2]] }
fn len(a: [f64; 3]) -> f64 { (a[0] * a[0] + a[1] * a[1] + a[2] * a[2]).sqrt() }

/// Centre on the reference sphere (km), bounding radius (km) and vertex spacing (km) from the grid
/// corners alone, without any height.
pub fn bounds(face: usize, depth: u32, x: u32, y: u32) -> ([f64; 3], f64, f64) {
    let at = |i: i64, j: i64| face_dir(face, k_of(x, i, depth), k_of(y, j, depth)).map(|c| c * R_KM);
    let centre = at(32, 32);
    let corners = [at(0, 0), at(64, 0), at(0, 64), at(64, 64)];
    let radius = corners.iter().map(|c| len(sub(*c, centre))).fold(0.0, f64::max);
    let spacing = len(sub(corners[1], corners[0])).max(len(sub(corners[2], corners[0]))) / QUADS as f64;
    // Terrain heights add up to the node's own size (capped at the 10 km LOLA range).
    (centre, radius + (radius * 0.5).min(10.0), spacing)
}

/// Output of `build`: arrays for one mesh, `VERTS` entries each (grid, then 4 skirt rows).
pub struct NodeData {
    pub centre: [f64; 3],
    pub radius_km: f64,
    pub spacing_km: f64,
    pub verts: Vec<[f32; 3]>,
    pub normals: Vec<[f32; 3]>,
    pub uvs: Vec<[f32; 2]>,
    /// parent-interpolated position minus own position (km), for the vertex-shader geomorph.
    pub morph: Vec<[f32; 3]>,
}

/// Index buffer shared by every node: grid triangles (clockwise from outside) and skirt walls (both windings).
pub fn indices() -> Vec<i32> {
    let n = N as i32;
    let mut out = Vec::new();
    for j in 0..n - 1 {
        for i in 0..n - 1 {
            let (a, c) = (j * n + i, (j + 1) * n + i);
            out.extend([a, c, a + 1, a + 1, c, c + 1]);
        }
    }
    let base = (N * N) as i32;
    for e in 0..4i32 {
        for t in 0..n - 1 {
            let edge = |k: i32| match e {
                0 => k,
                1 => (n - 1) * n + k,
                2 => k * n,
                _ => k * n + n - 1,
            };
            let (t0, t1, s0, s1) = (edge(t), edge(t + 1), base + e * n + t, base + e * n + t + 1);
            out.extend([t0, t1, s1, t0, s1, s0, t0, s1, t1, t0, s0, s1]);
        }
    }
    out
}

impl Terrain {
    /// Builds node (face, depth, x, y). Heights are `height_m` of the node's depth (LOLA plus craters
    /// and relief by the D4 band rule), evaluated per vertex direction.
    pub fn build_node(&self, seed: u64, cfg: &CraterConfig, face: usize, depth: u32, x: u32, y: u32) -> NodeData {
        let (centre, radius_km, spacing_km) = bounds(face, depth, x, y);
        let m_at = |p: [f64; 3]| self.region_weight(p);
        // Position (km, absolute) of grid vertex (i, j) of node (nx, ny) at `d`, with height of depth `d`.
        let sampler = |d: u32, nx: u32, ny: u32| {
            let (c, r, _) = bounds(face, d, nx, ny);
            let (lat, lon) = lat_lon(c);
            let usable = self.max_depth(lat, lon) >= d;
            let craters = if usable { crater::list_reaching(seed, cfg, c, r * 1.1, d, &m_at) } else { Vec::new() };
            move |dir: [f64; 3]| -> [f64; 3] {
                let (la, lo) = lat_lon(dir);
                let q = dir.map(|v| v * R_KM);
                let off = if usable { crater::combine(cfg, &craters, q) + crate::relief::offset_m(seed, q, d, cfg.k_s) } else { 0.0 };
                let h = (self.height_lola_m(la, lo, d) + off) / 1000.0;
                dir.map(|v| v * (R_KM + h))
            }
        };
        let own = sampler(depth, x, y);
        // Extended (N + 2)^2 grid so every normal is a central difference across node borders.
        let m = N + 2;
        let mut pos = vec![[0.0f64; 3]; m * m];
        let mut dirs = vec![[0.0f64; 3]; N * N];
        for jj in 0..m {
            for ii in 0..m {
                let (i, j) = (ii as i64 - 1, jj as i64 - 1);
                let d = face_dir(face, k_of(x, i, depth), k_of(y, j, depth));
                pos[jj * m + ii] = own(d);
                if (0..N as i64).contains(&i) && (0..N as i64).contains(&j) {
                    dirs[j as usize * N + i as usize] = d;
                }
            }
        }
        let p = |i: i64, j: i64| pos[(j + 1) as usize * m + (i + 1) as usize];
        // Parent grid (depth - 1), for the geomorph target.
        let parent: Option<Vec<[f64; 3]>> = (depth > 0).then(|| {
            let (px, py) = (x >> 1, y >> 1);
            let par = sampler(depth - 1, px, py);
            (0..N * N)
                .map(|k| par(face_dir(face, k_of(px, (k % N) as i64, depth - 1), k_of(py, (k / N) as i64, depth - 1))))
                .collect()
        });
        let (ox, oy) = ((x & 1) as usize * QUADS, (y & 1) as usize * QUADS);
        let (lat_c, lon_c) = lat_lon(centre);
        let mut verts = Vec::with_capacity(VERTS);
        let mut normals = Vec::with_capacity(VERTS);
        let mut uvs = Vec::with_capacity(VERTS);
        let mut morph = Vec::with_capacity(VERTS);
        let _ = lat_c;
        for j in 0..N {
            for i in 0..N {
                let me = p(i as i64, j as i64);
                verts.push(sub(me, centre).map(|v| v as f32));
                let du = sub(p(i as i64 + 1, j as i64), p(i as i64 - 1, j as i64));
                let dv = sub(p(i as i64, j as i64 + 1), p(i as i64, j as i64 - 1));
                let c = [du[1] * dv[2] - du[2] * dv[1], du[2] * dv[0] - du[0] * dv[2], du[0] * dv[1] - du[1] * dv[0]];
                let l = len(c).max(1e-300);
                normals.push(c.map(|v| (v / l) as f32));
                let d = dirs[j * N + i];
                let (la, lo) = lat_lon(d);
                let cos_lat = (d[0] * d[0] + d[2] * d[2]).sqrt();
                let dlon = (lo - lon_c + 540.0).rem_euclid(360.0) - 180.0;
                let u = if cos_lat < 1e-9 { lon_c / 360.0 } else { (lon_c + dlon) / 360.0 };
                uvs.push([u as f32, ((90.0 - la) / 180.0) as f32]);
                morph.push(match &parent {
                    None => [0.0; 3],
                    Some(g) => {
                        // Parent vertex coordinates of this child vertex: (ox + i) / 2, (oy + j) / 2.
                        let (a, b) = (ox + i, oy + j);
                        let at = |u: usize, v: usize| g[v * N + u];
                        let target = match (a % 2, b % 2) {
                            (0, 0) => at(a / 2, b / 2),
                            (1, 0) => mid(at(a / 2, b / 2), at(a / 2 + 1, b / 2)),
                            (0, 1) => mid(at(a / 2, b / 2), at(a / 2, b / 2 + 1)),
                            _ => mid(at(a / 2 + 1, b / 2), at(a / 2, b / 2 + 1)),
                        };
                        sub(target, me).map(|v| v as f32)
                    }
                });
            }
        }
        // Skirts: each edge vertex copied and lowered along the radial direction.
        let skirt = SKIRT_FRACTION * spacing_km;
        for e in 0..4usize {
            for t in 0..N {
                let k = match e {
                    0 => t,
                    1 => (N - 1) * N + t,
                    2 => t * N,
                    _ => t * N + N - 1,
                };
                let up = dirs[k];
                let v = verts[k];
                verts.push([v[0] - (up[0] * skirt) as f32, v[1] - (up[1] * skirt) as f32, v[2] - (up[2] * skirt) as f32]);
                normals.push(normals[k]);
                uvs.push(uvs[k]);
                morph.push(morph[k]);
            }
        }
        NodeData { centre, radius_km, spacing_km, verts, normals, uvs, morph }
    }
}

fn mid(a: [f64; 3], b: [f64; 3]) -> [f64; 3] {
    [0, 1, 2].map(|c| 0.5 * (a[c] + b[c]))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn neighbouring_nodes_share_edge_directions() {
        for face in 0..6 {
            for depth in [0u32, 5, 18] {
                let max = 4u32 << depth;
                let x = (max / 3).min(max - 2);
                for dy in 0..3u32 {
                    let y = (max / 5 + dy).min(max - 1);
                    let (a, b) = (face_dir(face, k_of(x, 64, depth), k_of(y, 17, depth)), face_dir(face, k_of(x + 1, 0, depth), k_of(y, 17, depth)));
                    assert_eq!(a, b);
                }
            }
        }
    }

    #[test]
    fn indices_cover_grid_and_skirts_within_bounds() {
        let idx = indices();
        assert_eq!(idx.len(), 64 * 64 * 6 + 4 * 64 * 12);
        assert!(idx.iter().all(|&i| (i as usize) < VERTS));
    }

    #[test]
    fn root_bounds_have_the_documented_spacing() {
        let (_, _, s) = bounds(4, 0, 1, 1);
        assert!((7.0..11.0).contains(&s), "spacing {s}");
    }
}
