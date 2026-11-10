//! Box-filter downsampling of the DEM to the equirectangular output levels.
//!
//! A source sample belongs to the output cell that contains its centre. With
//! source size `S` and output size `O` along one axis, source index `i`
//! (centre at `i + 0.5`) goes to output index `floor((2 i + 1) O / (2 S))`,
//! computed in integers. A centre that falls exactly on a cell boundary
//! therefore belongs to the cell that starts there (the eastern or southern
//! one). Each output value is the plain mean of its valid samples.

/// One output level in metres. NoData cells hold NaN.
#[derive(Clone, Debug)]
pub struct Level {
    pub width: usize,
    pub height: usize,
    pub values: Vec<f32>,
    pub nodata_count: u64,
}

impl Level {
    /// Little-endian 32-bit floats, row 0 first.
    pub fn to_le_bytes(&self) -> Vec<u8> {
        let mut bytes = Vec::with_capacity(self.values.len() * 4);
        for v in &self.values {
            bytes.extend_from_slice(&v.to_le_bytes());
        }
        bytes
    }

    /// Minimum, maximum and mean over the cells that are not NaN. The mean is
    /// the f64 sum in row order divided by the count. `None` if all are NaN.
    pub fn stats(&self) -> Option<(f32, f32, f64)> {
        let mut min = f32::INFINITY;
        let mut max = f32::NEG_INFINITY;
        let mut sum = 0.0f64;
        let mut n = 0u64;
        for &v in self.values.iter().filter(|v| !v.is_nan()) {
            min = min.min(v);
            max = max.max(v);
            sum += f64::from(v);
            n += 1;
        }
        (n > 0).then(|| (min, max, sum / n as f64))
    }
}

/// Output index of source index `i` (see the module comment).
pub fn target_index(i: usize, src_size: usize, out_size: usize) -> usize {
    (2 * i + 1) * out_size / (2 * src_size)
}

/// Accumulates source rows into one output level.
pub struct BoxAccumulator {
    src_w: usize,
    src_h: usize,
    out_w: usize,
    out_h: usize,
    missing: Option<i16>,
    column_target: Vec<u32>,
    sums: Vec<i64>,
    counts: Vec<u32>,
}

impl BoxAccumulator {
    pub fn new(
        src_w: usize,
        src_h: usize,
        out_w: usize,
        out_h: usize,
        missing: Option<i16>,
    ) -> BoxAccumulator {
        BoxAccumulator {
            src_w,
            src_h,
            out_w,
            out_h,
            missing,
            column_target: (0..src_w).map(|x| target_index(x, src_w, out_w) as u32).collect(),
            sums: vec![0; out_w * out_h],
            counts: vec![0; out_w * out_h],
        }
    }

    /// Adds source row `y` (0 = northernmost), given as digital numbers.
    pub fn add_row(&mut self, y: usize, row: &[i16]) {
        assert_eq!(row.len(), self.src_w);
        let base = target_index(y, self.src_h, self.out_h) * self.out_w;
        for (&dn, &tx) in row.iter().zip(&self.column_target) {
            if Some(dn) == self.missing {
                continue;
            }
            let cell = base + tx as usize;
            self.sums[cell] += i64::from(dn);
            self.counts[cell] += 1;
        }
    }

    /// Mean digital number per cell times `scaling_factor` (metres per DN).
    /// A cell with no valid sample becomes NaN.
    pub fn finish(self, scaling_factor: f64) -> Level {
        let mut nodata_count = 0u64;
        let values = self
            .sums
            .iter()
            .zip(&self.counts)
            .map(|(&sum, &n)| {
                if n == 0 {
                    nodata_count += 1;
                    f32::NAN
                } else {
                    (sum as f64 * scaling_factor / f64::from(n)) as f32
                }
            })
            .collect();
        Level { width: self.out_w, height: self.out_h, values, nodata_count }
    }
}

/// Downsamples a whole raster held in memory (row 0 first).
pub fn downsample(
    src: &[i16],
    src_w: usize,
    src_h: usize,
    out_w: usize,
    out_h: usize,
    scaling_factor: f64,
    missing: Option<i16>,
) -> Level {
    assert_eq!(src.len(), src_w * src_h);
    let mut acc = BoxAccumulator::new(src_w, src_h, out_w, out_h, missing);
    for (y, row) in src.chunks_exact(src_w).enumerate() {
        acc.add_row(y, row);
    }
    acc.finish(scaling_factor)
}
