//! Small-scale relief (spec REQ-18): zero-mean fractal noise, one octave per halving of the
//! wavelength from 200 m down to about 1 cm, RMS height of an octave of wavelength L = k_s x L.
//! Octave i is smooth-interpolated value noise on a 3D Moon-fixed lattice of cell L (stream 3), so
//! it has no cube-face seams. An octave is used at a depth only if L >= 2 x vertex spacing (D4).

use crate::crater::spacing_km;
use crate::hash::{hash, unit, STREAM_RELIEF};

pub const OCTAVES: usize = 15;
pub const LAMBDA_MAX_M: f64 = 200.0;
/// RMS of smoothstep-interpolated value noise per unit corner variance: sqrt((2*int(w^2) - 1 + 1)^3)
/// with int(w^2) = 0.3714 for w = 3t^2 - 2t^3, i.e. sqrt(0.7429^3).
const RMS_FACTOR: f64 = 0.640_4;

pub fn wavelength_m(i: usize) -> f64 {
    LAMBDA_MAX_M / f64::from(1u32 << i)
}

fn corner(seed: u64, i: usize, c: [i64; 3]) -> f64 {
    // Uniform on [-sqrt 3, sqrt 3]: zero mean, unit variance.
    3f64.sqrt() * (2.0 * unit(hash(seed, STREAM_RELIEF, i as u64, c[0], c[1], c[2], 0)) - 1.0)
}

/// Height of octave `i` in metres at a Moon-fixed point (km).
pub fn octave_m(seed: u64, i: usize, p: [f64; 3], k_s: f64) -> f64 {
    let lam_m = wavelength_m(i);
    let q = p.map(|v| v / (lam_m / 1000.0));
    let base = q.map(f64::floor);
    let f = [0, 1, 2].map(|k| {
        let t = q[k] - base[k];
        t * t * (3.0 - 2.0 * t)
    });
    let b = base.map(|v| v as i64);
    let mut sum = 0.0;
    for corner_id in 0..8usize {
        let (dx, dy, dz) = (corner_id & 1, (corner_id >> 1) & 1, (corner_id >> 2) & 1);
        let w = [dx, dy, dz].iter().zip(f).map(|(&d, t)| if d == 1 { t } else { 1.0 - t }).product::<f64>();
        sum += w * corner(seed, i, [b[0] + dx as i64, b[1] + dy as i64, b[2] + dz as i64]);
    }
    sum * k_s * lam_m / RMS_FACTOR
}

/// Sum of the octaves sampled at `depth` (none below depth 2, D1), metres.
pub fn offset_m(seed: u64, p: [f64; 3], depth: u32, k_s: f64) -> f64 {
    if depth < 2 {
        return 0.0;
    }
    let limit_km = 2.0 * spacing_km(depth);
    (0..OCTAVES).filter(|&i| wavelength_m(i) / 1000.0 >= limit_km).map(|i| octave_m(seed, i, p, k_s)).sum()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn octave_is_zero_mean_with_the_requested_rms() {
        let (mut sum, mut sq, n) = (0.0, 0.0, 20_000);
        for k in 0..n {
            let t = k as f64;
            let v = octave_m(7, 4, [t * 0.0173, t * 0.0291, 1737.0 + t * 0.0113], 0.01);
            sum += v;
            sq += v * v;
        }
        let (mean, rms) = (sum / n as f64, (sq / n as f64).sqrt());
        let want = 0.01 * wavelength_m(4);
        assert!(mean.abs() < 0.1 * want, "mean {mean}");
        assert!((rms / want - 1.0).abs() < 0.25, "rms {rms} want {want}");
    }
}
