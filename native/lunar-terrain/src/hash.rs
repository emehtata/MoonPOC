//! Deterministic hash and feature lattice (spec D2, REQ-3 foundation).
//! Pure 64-bit integer arithmetic: no floats in the hash, no global state.

/// Stream ids, one per feature category.
pub const STREAM_CRATERS: u64 = 1;
pub const STREAM_ROCKS: u64 = 2;
pub const STREAM_RELIEF: u64 = 3;
pub const STREAM_MATERIAL: u64 = 4;

/// Reference sphere radius in km (1 unit = 1 km).
pub const R_KM: f64 = 1737.4;

fn mix(mut z: u64) -> u64 {
    // splitmix64 finaliser
    z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
    z ^ (z >> 31)
}

/// `H(world_seed, stream_id, level, ix, iy, iz, n)`.
pub fn hash(seed: u64, stream: u64, level: u64, ix: i64, iy: i64, iz: i64, n: u64) -> u64 {
    let mut h = mix(seed ^ 0x9e37_79b9_7f4a_7c15);
    for v in [stream, level, ix as u64, iy as u64, iz as u64, n] {
        h = mix(h.wrapping_add(0x9e37_79b9_7f4a_7c15).wrapping_add(v));
    }
    h
}

/// Uniform in [0, 1) from the top 53 bits.
pub fn unit(h: u64) -> f64 {
    (h >> 11) as f64 / (1u64 << 53) as f64
}

/// Stable feature id: (stream, level, ix, iy, iz, n).
pub type FeatureId = (u64, u64, i64, i64, i64, u64);

/// Candidate point of feature `n` in lattice cell `(ix, iy, iz)` at cell size
/// `s` km. It exists only if the point lies within `s/2` of the reference
/// sphere; it is then projected onto the sphere. Axis jitter uses `n` slots
/// 0x100..0x102 of the same hash so it is independent of other uses of `n`.
pub fn candidate(seed: u64, id: FeatureId, s: f64) -> Option<[f64; 3]> {
    let (stream, level, ix, iy, iz, n) = id;
    let u = |axis: u64| unit(hash(seed, stream, level, ix, iy, iz, n.wrapping_mul(8).wrapping_add(axis)));
    let p = [(ix as f64 + u(0)) * s, (iy as f64 + u(1)) * s, (iz as f64 + u(2)) * s];
    let len = (p[0] * p[0] + p[1] * p[1] + p[2] * p[2]).sqrt();
    ((len - R_KM).abs() <= s * 0.5).then(|| p.map(|c| c * R_KM / len))
}

/// Lattice cell containing a Moon-fixed point (km) for cell size `s`.
pub fn cell_of(p: [f64; 3], s: f64) -> [i64; 3] {
    p.map(|c| (c / s).floor() as i64)
}

/// The 27 cells around `cell`, in a fixed order (x slowest), so a query never
/// depends on chunk order, threads or history.
pub fn neighbourhood(cell: [i64; 3]) -> impl Iterator<Item = [i64; 3]> {
    (-1..=1).flat_map(move |dx| {
        (-1..=1).flat_map(move |dy| (-1..=1).map(move |dz| [cell[0] + dx, cell[1] + dy, cell[2] + dz]))
    })
}

/// All candidates (id, point) with `n < count` within the 3x3x3 cells around `p`.
pub fn query(seed: u64, stream: u64, level: u64, s: f64, count: u64, p: [f64; 3]) -> Vec<(FeatureId, [f64; 3])> {
    let mut out = Vec::new();
    for [ix, iy, iz] in neighbourhood(cell_of(p, s)) {
        for n in 0..count {
            let id = (stream, level, ix, iy, iz, n);
            if let Some(pt) = candidate(seed, id, s) {
                out.push((id, pt));
            }
        }
    }
    out
}

/// All candidates with `n < count` inside the cube of half-size `half` km around `centre`
/// (a point on the sphere), sorted by id so the list never depends on visit order.
/// Cells are visited along the two non-dominant axes; on the dominant axis only the
/// few cells next to the sphere can hold a candidate.
pub fn region(seed: u64, stream: u64, level: u64, s: f64, count: u64, centre: [f64; 3], half: f64) -> Vec<(FeatureId, [f64; 3])> {
    let a = (0..3).max_by(|&i, &j| centre[i].abs().total_cmp(&centre[j].abs())).unwrap_or(0);
    let (b, c) = ((a + 1) % 3, (a + 2) % 3);
    let cell = |v: f64| (v / s).floor() as i64;
    let mut out = Vec::new();
    for ib in cell(centre[b] - half - s)..=cell(centre[b] + half + s) {
        for ic in cell(centre[c] - half - s)..=cell(centre[c] + half + s) {
            let (vb, vc) = ((ib as f64 + 0.5) * s, (ic as f64 + 0.5) * s);
            let va = (R_KM * R_KM - vb * vb - vc * vc).max(0.0).sqrt() * centre[a].signum();
            let ia0 = cell(va);
            for ia in ia0 - 2..=ia0 + 2 {
                let mut idx = [0i64; 3];
                (idx[a], idx[b], idx[c]) = (ia, ib, ic);
                for n in 0..count {
                    let id = (stream, level, idx[0], idx[1], idx[2], n);
                    if let Some(p) = candidate(seed, id, s) {
                        if (0..3).all(|k| (p[k] - centre[k]).abs() <= half) {
                            out.push((id, p));
                        }
                    }
                }
            }
        }
    }
    out.sort_by_key(|(id, _)| *id);
    out
}

/// Lattice cells of size `s` that can hold a surface candidate inside the cube of half-size `half`
/// around a surface point `centre` (see `region`).
pub fn cells_in(centre: [f64; 3], half: f64, s: f64) -> Vec<[i64; 3]> {
    let a = (0..3).max_by(|&i, &j| centre[i].abs().total_cmp(&centre[j].abs())).unwrap_or(0);
    let (b, c) = ((a + 1) % 3, (a + 2) % 3);
    let cell = |v: f64| (v / s).floor() as i64;
    let mut out = Vec::new();
    for ib in cell(centre[b] - half - s)..=cell(centre[b] + half + s) {
        for ic in cell(centre[c] - half - s)..=cell(centre[c] + half + s) {
            let (vb, vc) = ((ib as f64 + 0.5) * s, (ic as f64 + 0.5) * s);
            let va = (R_KM * R_KM - vb * vb - vc * vc).max(0.0).sqrt() * centre[a].signum();
            for ia in cell(va) - 2..=cell(va) + 2 {
                let mut idx = [0i64; 3];
                (idx[a], idx[b], idx[c]) = (ia, ib, ic);
                out.push(idx);
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hash_is_stable_and_stream_separated() {
        assert_eq!(hash(1, 1, 0, 2, 3, 4, 5), hash(1, 1, 0, 2, 3, 4, 5));
        assert_ne!(hash(1, 1, 0, 2, 3, 4, 5), hash(1, 2, 0, 2, 3, 4, 5));
        assert_ne!(hash(0, 1, 0, 0, 0, 0, 0), hash(1, 1, 0, 0, 0, 0, 0));
        // Pinned value: the hash must never change between releases.
        assert_eq!(hash(0, 1, 0, 0, 0, 0, 0), 1242192138459492916);
    }

    #[test]
    fn region_matches_brute_force() {
        let c = [0.6 * R_KM, 0.0, 0.8 * R_KM];
        let (s, half) = (0.05, 0.2);
        let fast = region(3, STREAM_ROCKS, 1, s, 2, c, half);
        let mut brute = Vec::new();
        let rng = |v: f64| ((v - 0.5) / s) as i64..=((v + 0.5) / s) as i64;
        for ix in rng(c[0]) { for iy in -8..=8 { for iz in rng(c[2]) {
            for n in 0..2 {
                let id = (STREAM_ROCKS, 1, ix, iy, iz, n);
                if let Some(p) = candidate(3, id, s) {
                    if (0..3).all(|k| (p[k] - c[k]).abs() <= half) { brute.push((id, p)); }
                }
            }
        } } }
        brute.sort_by_key(|(id, _)| *id);
        assert!(!brute.is_empty());
        assert_eq!(fast, brute);
    }

    #[test]
    fn query_is_order_independent_and_on_sphere() {
        let p = [R_KM, 0.0, 0.0];
        let a = query(7, STREAM_CRATERS, 3, 0.5, 4, p);
        assert!(!a.is_empty());
        assert_eq!(a, query(7, STREAM_CRATERS, 3, 0.5, 4, p));
        for (_, q) in a {
            let r = (q[0] * q[0] + q[1] * q[1] + q[2] * q[2]).sqrt();
            assert!((r - R_KM).abs() < 1e-9);
        }
    }
}
