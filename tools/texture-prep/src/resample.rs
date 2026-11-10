//! Two-pass box-filter (area average) resampling of 8-bit single-band images.
//!
//! The arithmetic is fixed-point with 22 fractional bits: a horizontal pass
//! rounded to 8 bits, then a vertical pass rounded to 8 bits. Coefficients are
//! computed in f64 from an f32 source box. This reproduces, value for value,
//! the resampler that produced the original Milestone 1 texture, so the order
//! of operations and the rounding steps here must not be changed.

const PRECISION_BITS: u32 = 32 - 8 - 2;
/// Half-width of the box filter, in output pixels.
const BOX_SUPPORT: f64 = 0.5;

struct Coeffs {
    /// Per output index: first source index and number of taps.
    bounds: Vec<(usize, usize)>,
    /// Fixed-point weights, `ksize` per output index.
    weights: Vec<i32>,
    ksize: usize,
}

fn box_filter(x: f64) -> f64 {
    if x > -0.5 && x <= 0.5 {
        1.0
    } else {
        0.0
    }
}

fn precompute_coeffs(in_size: usize, in0: f32, in1: f32, out_size: usize) -> Coeffs {
    let scale = f64::from(in1 - in0) / out_size as f64;
    let filterscale = scale.max(1.0);
    let support = BOX_SUPPORT * filterscale;
    let ksize = support.ceil() as usize * 2 + 1;
    let ss = 1.0 / filterscale;
    let mut bounds = Vec::with_capacity(out_size);
    let mut weights = vec![0i32; out_size * ksize];
    let mut taps = vec![0f64; ksize];
    for xx in 0..out_size {
        let center = f64::from(in0) + (xx as f64 + 0.5) * scale;
        let xmin = ((center - support + 0.5) as i64).max(0);
        let xmax = ((center + support + 0.5) as i64).min(in_size as i64);
        let count = (xmax - xmin).max(0) as usize;
        let mut ww = 0.0;
        for (x, tap) in taps.iter_mut().enumerate().take(count) {
            let w = box_filter(((x as i64 + xmin) as f64 - center + 0.5) * ss);
            *tap = w;
            ww += w;
        }
        let row = &mut weights[xx * ksize..(xx + 1) * ksize];
        for (x, &tap) in taps.iter().enumerate().take(count) {
            let k = if ww != 0.0 { tap / ww } else { tap };
            let fixed = k * f64::from(1u32 << PRECISION_BITS);
            row[x] = if k < 0.0 { (-0.5 + fixed) as i32 } else { (0.5 + fixed) as i32 };
        }
        bounds.push((xmin as usize, count));
    }
    Coeffs { bounds, weights, ksize }
}

fn clip8(v: i32) -> u8 {
    (v >> PRECISION_BITS).clamp(0, 255) as u8
}

/// Resamples the region `src_box` = [left, top, right, bottom] (source pixel
/// coordinates, fractional allowed) of a `src_w` x `src_h` image to
/// `out_w` x `out_h` with a box filter.
pub fn resize_box(
    src: &[u8],
    src_w: usize,
    src_h: usize,
    out_w: usize,
    out_h: usize,
    src_box: [f32; 4],
) -> Vec<u8> {
    assert_eq!(src.len(), src_w * src_h);
    let horiz = precompute_coeffs(src_w, src_box[0], src_box[2], out_w);
    let vert = precompute_coeffs(src_h, src_box[1], src_box[3], out_h);
    let half = 1i32 << (PRECISION_BITS - 1);

    // Horizontal pass over only the source rows the vertical pass uses.
    let row_first = vert.bounds[0].0;
    let (last_min, last_count) = vert.bounds[out_h - 1];
    let row_last = last_min + last_count;
    let temp_h = row_last - row_first;
    let mut temp = vec![0u8; out_w * temp_h];
    for (yy, out_row) in temp.chunks_exact_mut(out_w).enumerate() {
        let in_row = &src[(yy + row_first) * src_w..(yy + row_first + 1) * src_w];
        for (xx, out) in out_row.iter_mut().enumerate() {
            let (xmin, count) = horiz.bounds[xx];
            let k = &horiz.weights[xx * horiz.ksize..xx * horiz.ksize + count];
            let mut acc = half;
            for (&p, &w) in in_row[xmin..xmin + count].iter().zip(k) {
                acc += i32::from(p) * w;
            }
            *out = clip8(acc);
        }
    }

    // Vertical pass.
    let mut out = vec![0u8; out_w * out_h];
    let mut acc = vec![0i32; out_w];
    for (yy, out_row) in out.chunks_exact_mut(out_w).enumerate() {
        let (ymin, count) = vert.bounds[yy];
        let ymin = ymin - row_first;
        let k = &vert.weights[yy * vert.ksize..yy * vert.ksize + count];
        acc.fill(half);
        for (y, &w) in k.iter().enumerate() {
            let in_row = &temp[(y + ymin) * out_w..(y + ymin + 1) * out_w];
            for (a, &p) in acc.iter_mut().zip(in_row) {
                *a += i32::from(p) * w;
            }
        }
        for (o, &a) in out_row.iter_mut().zip(&acc) {
            *o = clip8(a);
        }
    }
    out
}
