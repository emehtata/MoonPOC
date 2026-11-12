//! Procedural craters (spec REQ-8 to REQ-13). Pure functions of (seed, config, point):
//! no state, so results never depend on thread, order or history (REQ-3).
//!
//! Choices made where the spec is open (all recorded in the implementer report):
//! - 20 geometric size bins from 0.5 m to 400 m; a crater's diameter is log-uniform in its bin.
//! - Lattice cell size of bin j: s_j = 1.25 x D_hi(j) x (1 + k_i) = the largest ejecta radius
//!   (2.5 R with the azimuth swing), so a 3x3x3 read always sees every crater that touches a point.
//! - Expected craters per cell = density of the bin per km2 x s^2 (a cell column through the shell
//!   holds area/s^2 candidates), drawn as Poisson from the cell's own hash.
//! - The bowl is h = -d + (d + h_r) rho^p with p set so the profile integrates to 0 (REQ-10).
//! - A crater level is used only if its smallest diameter >= 2 x the vertex spacing (D4); the
//!   vertex spacing at depth n is taken as 10.7 km / 2^n (the larger end of the spec's range).

use crate::hash::{candidate, hash, unit, FeatureId, R_KM, STREAM_CRATERS};

pub const BINS: usize = 20;
pub const D_MIN_M: f64 = 0.5;
pub const D_MAX_M: f64 = 400.0;
pub const EJECTA_EXTENT: f64 = 2.5;
const ROOT_SPACING_KM: f64 = 10.7;
/// Hash slot for a cell's crater count (other slots are n * 8 + k).
const SLOT_COUNT: u64 = 1 << 62;

#[derive(Clone, Debug)]
pub struct CraterConfig {
    pub k_d: f64,
    pub k_r: f64,
    pub k_i: f64,
    /// Craters >= 1 m per km2, and the cumulative slope b, for highland and mare.
    pub c_highland: f64,
    pub c_mare: f64,
    pub b_highland: f64,
    pub b_mare: f64,
    /// Multiplies the crater density (scenario 4 uses 3).
    pub density_scale: f64,
    /// Fixed region weight m in [0, 1] instead of the albedo-derived one.
    pub region_override: Option<f64>,
    /// REQ-11 step 2 (smoothing) on or off; step 1 (the factor) is always applied.
    pub smoothing: bool,
    /// Relief RMS per octave = k_s x wavelength (REQ-18, assumption A3).
    pub k_s: f64,
}

impl Default for CraterConfig {
    /// Assumption A3 (provisional, not verified against the literature).
    fn default() -> Self {
        CraterConfig {
            k_d: 0.2,
            k_r: 0.04,
            k_i: 0.08,
            c_highland: 2000.0,
            c_mare: 800.0,
            b_highland: 2.0,
            b_mare: 1.8,
            density_scale: 1.0,
            region_override: None,
            smoothing: true,
            k_s: 0.01,
        }
    }
}

impl CraterConfig {
    /// Bowl exponent p of `h = -d + (d + h_r) rho^p` that makes the profile integrate to 0.
    /// `None` if the depth and rim heights cannot be balanced (needs d/2 > 0.6 h_r).
    pub fn bowl_exponent(&self) -> Option<f64> {
        let (d, hr) = (self.k_d, self.k_r);
        let den = d / 2.0 - 0.6 * hr;
        (den > 0.0).then(|| (d + hr) / den - 2.0).filter(|p| *p > 0.0)
    }

    /// Cumulative number per km2 with diameter >= `d_m`, for region weight `m` (REQ-13).
    pub fn cumulative(&self, d_m: f64, m: f64) -> f64 {
        self.density_scale
            * ((1.0 - m) * self.c_highland * d_m.powf(-self.b_highland) + m * self.c_mare * d_m.powf(-self.b_mare))
    }
}

/// Edge `j` (0..=BINS) of the diameter bins in metres.
pub fn edge_m(j: usize) -> f64 {
    D_MIN_M * (D_MAX_M / D_MIN_M).powf(j as f64 / BINS as f64)
}

/// Vertex spacing assumed at a quadtree depth, km.
pub fn spacing_km(depth: u32) -> f64 {
    ROOT_SPACING_KM / f64::from(1u32 << depth.min(30))
}

/// Largest ejecta radius of any crater in bin `j`, km (also the lattice cell size).
pub fn cell_km(j: usize, cfg: &CraterConfig) -> f64 {
    1.25 * edge_m(j + 1) / 1000.0 * (1.0 + cfg.k_i)
}

/// Is bin `j` sampled at this depth (D4: shortest wavelength >= 2 x spacing)? Depth < 2 has no craters (D1).
pub fn level_active(j: usize, depth: u32) -> bool {
    depth >= 2 && edge_m(j) / 1000.0 >= 2.0 * spacing_km(depth)
}

#[derive(Clone, Debug, PartialEq)]
pub struct Crater {
    pub id: FeatureId,
    /// Centre on the reference sphere, km, Moon-fixed.
    pub centre: [f64; 3],
    pub d_m: f64,
    /// 0 = fresh, 1 = oldest.
    pub age: f64,
    pub lobes: u32,
    pub phase: f64,
}

fn attr(seed: u64, id: FeatureId, k: u64) -> f64 {
    unit(hash(seed, id.0, id.1, id.2, id.3, id.4, id.5.wrapping_mul(8).wrapping_add(k)))
}

/// Number of craters in lattice cell `cell` of bin `j`: Poisson, with the mean set by the region
/// weight at the cell centre (`m_at` maps a Moon-fixed km point to m in [0, 1]).
pub fn cell_count(seed: u64, cfg: &CraterConfig, j: usize, cell: [i64; 3], m_at: &dyn Fn([f64; 3]) -> f64) -> u64 {
    let s = cell_km(j, cfg);
    let c = cell.map(|i| (i as f64 + 0.5) * s);
    let len = (c[0] * c[0] + c[1] * c[1] + c[2] * c[2]).sqrt();
    // Cells farther than one cell size from the sphere never hold a surviving candidate.
    if (len - R_KM).abs() > s * 1.5 {
        return 0;
    }
    let m = cfg.region_override.unwrap_or_else(|| m_at(c.map(|v| v * R_KM / len))).clamp(0.0, 1.0);
    let density = cfg.cumulative(edge_m(j), m) - cfg.cumulative(edge_m(j + 1), m);
    let lambda = density * s * s;
    let u = unit(hash(seed, STREAM_CRATERS, j as u64, cell[0], cell[1], cell[2], SLOT_COUNT));
    // Poisson by inversion.
    let (mut k, mut next) = (0u64, (-lambda).exp());
    let mut cdf = next;
    while u > cdf && k < 64 {
        k += 1;
        next *= lambda / k as f64;
        cdf += next;
    }
    k
}

/// The crater `n` of cell `cell` in bin `j`, if its candidate point survives the shell test.
pub fn make_crater(seed: u64, cfg: &CraterConfig, j: usize, cell: [i64; 3], n: u64) -> Option<Crater> {
    let id = (STREAM_CRATERS, j as u64, cell[0], cell[1], cell[2], n);
    let centre = candidate(seed, id, cell_km(j, cfg))?;
    let (lo, hi) = (edge_m(j), edge_m(j + 1));
    Some(Crater {
        id,
        centre,
        d_m: lo * (hi / lo).powf(attr(seed, id, 3)),
        age: attr(seed, id, 4),
        lobes: 6 + (attr(seed, id, 5) * 7.0) as u32, // 6 to 12
        phase: attr(seed, id, 6) * std::f64::consts::TAU,
    })
}

/// All craters of bin `j` in the 3x3x3 cells around `p`.
fn near(seed: u64, cfg: &CraterConfig, j: usize, p: [f64; 3], m_at: &dyn Fn([f64; 3]) -> f64, out: &mut Vec<Crater>) {
    let s = cell_km(j, cfg);
    for cell in crate::hash::neighbourhood(crate::hash::cell_of(p, s)) {
        for n in 0..cell_count(seed, cfg, j, cell, m_at) {
            out.extend(make_crater(seed, cfg, j, cell, n));
        }
    }
}

/// Local east/north axes at a point on the sphere.
fn frame(c: [f64; 3]) -> ([f64; 3], [f64; 3]) {
    let l = (c[0] * c[0] + c[1] * c[1] + c[2] * c[2]).sqrt();
    let u = c.map(|v| v / l);
    let (lat, lon) = (u[1].asin(), u[0].atan2(u[2]));
    ([lon.cos(), 0.0, -lon.sin()], [-lat.sin() * lon.sin(), lat.cos(), -lat.sin() * lon.cos()])
}

impl Crater {
    /// Distance from the centre in units of the local rim radius (rho) at a Moon-fixed point.
    pub fn rho_at(&self, cfg: &CraterConfig, p: [f64; 3]) -> f64 {
        // Cheap reject: far beyond the rim zone, so the caller's 0.8..1.5 test fails anyway.
        let near_km = 0.5 * self.d_m * (1.0 + cfg.k_i) * 1.6 / 1000.0;
        if (0..3).map(|k| (p[k] - self.centre[k]).powi(2)).sum::<f64>() > near_km * near_km {
            return f64::MAX;
        }
        let (east, north) = frame(self.centre);
        let d = [p[0] - self.centre[0], p[1] - self.centre[1], p[2] - self.centre[2]];
        let x = (d[0] * east[0] + d[1] * east[1] + d[2] * east[2]) * 1000.0;
        let y = (d[0] * north[0] + d[1] * north[1] + d[2] * north[2]) * 1000.0;
        x.hypot(y) / self.rim_radius_m(cfg, y.atan2(x))
    }

    /// Rim radius in metres at azimuth `theta`: R x (1 + k_i x cos(lobes x theta + phase)) (REQ-10).
    pub fn rim_radius_m(&self, cfg: &CraterConfig, theta: f64) -> f64 {
        0.5 * self.d_m * (1.0 + cfg.k_i * (f64::from(self.lobes) * theta + self.phase).cos())
    }

    /// Fresh profile (REQ-10) times (1 - 0.8 a) (REQ-11) at `rho` = r / rim radius; metres.
    pub fn profile(&self, cfg: &CraterConfig, rho: f64) -> f64 {
        let Some(p) = cfg.bowl_exponent() else { return 0.0 };
        let (d, hr) = (cfg.k_d * self.d_m, cfg.k_r * self.d_m);
        let f = 1.0 - 0.8 * self.age;
        f * if rho < 1.0 {
            -d + (d + hr) * rho.powf(p)
        } else if rho <= EJECTA_EXTENT {
            hr * rho.powi(-3)
        } else {
            0.0
        }
    }

    /// Unsmoothed height at tangent-plane offset (x, y) metres from the centre, and rho.
    fn raw(&self, cfg: &CraterConfig, x: f64, y: f64) -> (f64, f64) {
        let r = x.hypot(y);
        let rho = r / self.rim_radius_m(cfg, y.atan2(x));
        (self.profile(cfg, rho), rho)
    }

    /// Height in metres at a point (km, Moon-fixed) and whether it lies inside the rim.
    /// Applies the degradation smoothing of radius 0.2 a D (REQ-11) as a 24-tap disc average.
    pub fn height_at(&self, cfg: &CraterConfig, p: [f64; 3]) -> Option<(f64, bool)> {
        let reach_km = (0.5 * self.d_m * (1.0 + cfg.k_i) * EJECTA_EXTENT + 0.2 * self.age * self.d_m) / 1000.0;
        if (0..3).map(|k| (p[k] - self.centre[k]).powi(2)).sum::<f64>() > reach_km * reach_km {
            return None;
        }
        let (east, north) = frame(self.centre);
        let d = [p[0] - self.centre[0], p[1] - self.centre[1], p[2] - self.centre[2]];
        let x = (d[0] * east[0] + d[1] * east[1] + d[2] * east[2]) * 1000.0;
        let y = (d[0] * north[0] + d[1] * north[1] + d[2] * north[2]) * 1000.0;
        let s = 0.2 * self.age * self.d_m;
        let reach = 0.5 * self.d_m * (1.0 + cfg.k_i) * EJECTA_EXTENT + s;
        if x.hypot(y) > reach {
            return None;
        }
        let (h0, rho) = self.raw(cfg, x, y);
        if s <= 0.0 || !cfg.smoothing {
            return Some((h0, rho < 1.0));
        }
        let mut sum = 0.0;
        for ring in 0..3 {
            let rr = s * ((2 * ring + 1) as f64 / 6.0).sqrt();
            for k in 0..8 {
                let a = (k as f64 + 0.5 * ring as f64) * std::f64::consts::TAU / 8.0;
                sum += self.raw(cfg, x + rr * a.cos(), y + rr * a.sin()).0;
            }
        }
        Some((sum / 24.0, rho < 1.0))
    }
}

/// Procedural height offset in metres at a point (km, Moon-fixed) for a quadtree depth (REQ-12):
/// craters combine from the oldest to the youngest; inside its rim a younger crater replaces the
/// height older ones gave, outside it adds its ejecta.
pub fn offset_m(seed: u64, cfg: &CraterConfig, p: [f64; 3], depth: u32, m_at: &dyn Fn([f64; 3]) -> f64) -> f64 {
    let mut found = Vec::new();
    for j in (0..BINS).filter(|&j| level_active(j, depth)) {
        near(seed, cfg, j, p, m_at, &mut found);
    }
    combine(cfg, &found, p)
}

/// Is `p` on the rim or ejecta (0.8 <= rho <= 1.5) of a crater younger than age 0.3 (REQ-16)? Reads the
/// 3x3x3 cells around `p` in every bin.
pub fn on_young_rim(seed: u64, cfg: &CraterConfig, p: [f64; 3], m_at: &dyn Fn([f64; 3]) -> f64) -> bool {
    let mut found = Vec::new();
    for j in 0..BINS {
        near(seed, cfg, j, p, m_at, &mut found);
    }
    in_rim_zone(cfg, &found, p)
}

/// Same test on a prepared crater list.
pub fn in_rim_zone(cfg: &CraterConfig, craters: &[Crater], p: [f64; 3]) -> bool {
    craters.iter().any(|c| c.age < 0.3 && (0.8..=1.5).contains(&c.rho_at(cfg, p)))
}

/// Combines craters at a point, oldest first (REQ-12).
pub fn combine(cfg: &CraterConfig, craters: &[Crater], p: [f64; 3]) -> f64 {
    // Only the few craters that reach the point are sorted.
    let mut hits: Vec<(&Crater, f64, bool)> = craters.iter().filter_map(|c| c.height_at(cfg, p).map(|(v, inside)| (c, v, inside))).collect();
    hits.sort_by(|a, b| b.0.age.total_cmp(&a.0.age).then(a.0.id.cmp(&b.0.id)));
    let mut h = 0.0;
    for (_, v, inside) in hits {
        if inside {
            h = v;
        } else {
            h += v;
        }
    }
    h
}

/// Every crater whose centre lies in the cube of half-size `half` km around `centre`, from all bins
/// (or only bins with `min_d_m <= D`), sorted by id (REQ-3 crater list).
pub fn list(seed: u64, cfg: &CraterConfig, centre: [f64; 3], half: f64, min_d_m: f64, m_at: &dyn Fn([f64; 3]) -> f64) -> Vec<Crater> {
    let mut out = Vec::new();
    for j in (0..BINS).filter(|&j| edge_m(j + 1) >= min_d_m) {
        list_bin(seed, cfg, j, centre, half, min_d_m, m_at, &mut out);
    }
    out.sort_by_key(|c| c.id);
    out
}

/// Craters of one bin with the centre in the cube of half-size `half` around `centre`.
#[allow(clippy::too_many_arguments)]
pub fn list_bin(seed: u64, cfg: &CraterConfig, j: usize, centre: [f64; 3], half: f64, min_d_m: f64, m_at: &dyn Fn([f64; 3]) -> f64, out: &mut Vec<Crater>) {
    {
        let s = cell_km(j, cfg);
        let a = (0..3).max_by(|&i, &k| centre[i].abs().total_cmp(&centre[k].abs())).unwrap_or(0);
        let (b, c) = ((a + 1) % 3, (a + 2) % 3);
        let cell = |v: f64| (v / s).floor() as i64;
        for ib in cell(centre[b] - half - s)..=cell(centre[b] + half + s) {
            for ic in cell(centre[c] - half - s)..=cell(centre[c] + half + s) {
                let (vb, vc) = ((ib as f64 + 0.5) * s, (ic as f64 + 0.5) * s);
                let va = (R_KM * R_KM - vb * vb - vc * vc).max(0.0).sqrt() * centre[a].signum();
                for ia in cell(va) - 2..=cell(va) + 2 {
                    let mut idx = [0i64; 3];
                    (idx[a], idx[b], idx[c]) = (ia, ib, ic);
                    for n in 0..cell_count(seed, cfg, j, idx, m_at) {
                        if let Some(cr) = make_crater(seed, cfg, j, idx, n) {
                            if (0..3).all(|k| (cr.centre[k] - centre[k]).abs() <= half) && cr.d_m >= min_d_m {
                                out.push(cr);
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Craters of the bins sampled at `depth` that can touch any point within `half` km of `centre`, for rock
/// placement; each bin adds its own reach to the search cube.
pub fn list_reaching(seed: u64, cfg: &CraterConfig, centre: [f64; 3], half: f64, depth: u32, m_at: &dyn Fn([f64; 3]) -> f64) -> Vec<Crater> {
    let mut out = Vec::new();
    for j in (0..BINS).filter(|&j| level_active(j, depth)) {
        list_bin(seed, cfg, j, centre, half + cell_km(j, cfg), 0.0, m_at, &mut out);
    }
    out.sort_by_key(|c| c.id);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fresh(d: f64, age: f64) -> Crater {
        Crater { id: (1, 0, 0, 0, 0, 0), centre: [0.0, 0.0, R_KM], d_m: d, age, lobes: 8, phase: 0.0 }
    }

    #[test]
    fn profile_balances_and_hits_depth_and_rim() {
        let cfg = CraterConfig::default();
        let c = fresh(100.0, 0.0);
        let (mut vol, mut bowl, n) = (0.0, 0.0, 200_000);
        let top = EJECTA_EXTENT;
        for i in 0..n {
            let rho = (i as f64 + 0.5) / n as f64 * top;
            let h = c.profile(&cfg, rho);
            vol += h * rho;
            if h < 0.0 {
                bowl += -h * rho;
            }
        }
        assert!((vol / bowl).abs() < 0.01, "balance {}", vol / bowl);
        assert!((c.profile(&cfg, 0.0) + 20.0).abs() < 1e-9);
        assert!((c.profile(&cfg, 1.0) - 4.0).abs() < 1e-9);
        assert!((fresh(100.0, 1.0).profile(&cfg, 0.0) + 4.0).abs() < 1e-9);
    }

    #[test]
    fn smoothing_keeps_volume_and_lowers_but_keeps_rim_and_depth() {
        let mut cfg = CraterConfig::default();
        for age in [0.5, 1.0] {
            let c = fresh(100.0, age);
            let (mut vol, mut bowl_fresh) = (0.0, 0.0);
            let (mut rim_s, mut dep_s, mut rim_u, mut dep_u) = (f64::MIN, f64::MAX, f64::MIN, f64::MAX);
            let (east, north) = frame(c.centre);
            for i in -130..=130 {
                for j in -130..=130 {
                    let (x, y) = (f64::from(i), f64::from(j));
                    let p = [0, 1, 2].map(|k| c.centre[k] + (east[k] * x + north[k] * y) / 1000.0);
                    cfg.smoothing = true;
                    let hs = c.height_at(&cfg, p).map_or(0.0, |v| v.0);
                    cfg.smoothing = false;
                    let hu = c.height_at(&cfg, p).map_or(0.0, |v| v.0);
                    vol += hs;
                    bowl_fresh += (-fresh(100.0, 0.0).profile(&cfg, x.hypot(y) / c.rim_radius_m(&cfg, y.atan2(x)))).max(0.0);
                    rim_s = rim_s.max(hs);
                    dep_s = dep_s.min(hs);
                    rim_u = rim_u.max(hu);
                    dep_u = dep_u.min(hu);
                }
            }
            assert!(vol.abs() < 0.01 * bowl_fresh, "age {age}: volume {vol} vs bowl {bowl_fresh}");
            assert!(rim_s > 0.0 && rim_s <= rim_u + 1e-9, "age {age}: rim {rim_s} vs {rim_u}");
            assert!(dep_s < 0.0 && dep_s >= dep_u - 1e-9, "age {age}: depth {dep_s} vs {dep_u}");
        }
    }

    #[test]
    fn younger_crater_on_the_rim_replaces_the_older_one() {
        let cfg = CraterConfig::default();
        let old = fresh(100.0, 0.9);
        let mut young = fresh(60.0, 0.0);
        young.id = (1, 0, 1, 0, 0, 0);
        let (east, _) = frame(old.centre);
        let rim = old.rim_radius_m(&cfg, 0.0) / 1000.0;
        young.centre = [east[0] * rim, east[1] * rim, R_KM + east[2] * rim];
        let (v, inside) = young.height_at(&cfg, young.centre).unwrap();
        assert!(inside && (v + 12.0).abs() < 1e-6);
    }

    #[test]
    fn offset_is_deterministic_and_finite() {
        let cfg = CraterConfig::default();
        let p = [0.0, 0.0, R_KM];
        let a = offset_m(1, &cfg, p, 18, &|_| 0.5);
        assert_eq!(a, offset_m(1, &cfg, p, 18, &|_| 0.5));
        assert!(a.is_finite());
    }
}
