//! REQ-24: 1000 pixels of the 4096 x 2048 level, chosen with seed 42, equal the
//! plain mean of the source samples that the REQ-7 index rule assigns to them.
//! The expected values are computed here from the raw LOLA file, independently
//! of the library's accumulator.

mod common;

use std::collections::{BTreeSet, HashMap};
use std::fs::File;
use std::io::{BufReader, Read};

use common::{assets_dir, dem_image, read_f32_le, DEM_LINES, DEM_SAMPLES, SCALE_M_PER_DN};

const OUT_W: usize = 4096;
const OUT_H: usize = 2048;

/// The REQ-7 rule: source index i of S goes to output index floor((2i+1)O/(2S)).
fn cell_of(i: usize, s: usize, o: usize) -> usize {
    (2 * i + 1) * o / (2 * s)
}

/// xorshift64* with a fixed seed, so the chosen pixels are the same on every run.
struct Seeded(u64);

impl Seeded {
    fn next(&mut self) -> u64 {
        self.0 ^= self.0 >> 12;
        self.0 ^= self.0 << 25;
        self.0 ^= self.0 >> 27;
        self.0.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }
}

#[test]
fn req24_1000_seeded_pixels_equal_the_plain_mean_of_their_source_samples() {
    let level = read_f32_le(&assets_dir().join("elevation/lola_height_m_4096x2048.f32"));
    assert_eq!(level.len(), OUT_W * OUT_H);

    let mut rng = Seeded(42);
    let mut chosen: BTreeSet<(usize, usize)> = BTreeSet::new();
    while chosen.len() < 1000 {
        let x = (rng.next() % OUT_W as u64) as usize;
        let y = (rng.next() % OUT_H as u64) as usize;
        chosen.insert((x, y));
    }
    let pixels: Vec<(usize, usize)> = chosen.into_iter().collect();

    // Source columns of each chosen pixel, and the pixels that take each output row.
    let mut cols_of_x: HashMap<usize, Vec<usize>> = HashMap::new();
    let mut pixels_of_y: HashMap<usize, Vec<usize>> = HashMap::new();
    for (p, &(x, y)) in pixels.iter().enumerate() {
        cols_of_x.entry(x).or_insert_with(|| {
            (0..DEM_SAMPLES).filter(|&i| cell_of(i, DEM_SAMPLES, OUT_W) == x).collect()
        });
        pixels_of_y.entry(y).or_default().push(p);
    }
    for cols in cols_of_x.values() {
        assert!(cols.len() == 5 || cols.len() == 6, "REQ-7: {} samples on one axis", cols.len());
    }

    // Stream the raw file once, row by row, and add each needed sample to its pixel.
    let mut sums = vec![0.0f64; pixels.len()];
    let mut counts = vec![0usize; pixels.len()];
    let mut reader = BufReader::new(File::open(dem_image()).expect("data/raw LDEM_64.IMG"));
    let mut row_bytes = vec![0u8; DEM_SAMPLES * 2];
    for j in 0..DEM_LINES {
        reader.read_exact(&mut row_bytes).expect("row");
        let y = cell_of(j, DEM_LINES, OUT_H);
        let Some(ps) = pixels_of_y.get(&y) else { continue };
        for &p in ps {
            let (x, _) = pixels[p];
            for &i in &cols_of_x[&x] {
                let dn = i16::from_le_bytes([row_bytes[2 * i], row_bytes[2 * i + 1]]);
                sums[p] += f64::from(dn);
                counts[p] += 1;
            }
        }
    }

    let mut worst = 0.0f64;
    let mut worst_at = (0, 0);
    for (p, &(x, y)) in pixels.iter().enumerate() {
        assert!(counts[p] >= 25 && counts[p] <= 36, "sample count {} at ({x},{y})", counts[p]);
        let expected = sums[p] * SCALE_M_PER_DN / counts[p] as f64;
        let got = f64::from(level[y * OUT_W + x]);
        let diff = (got - expected).abs();
        if diff > worst {
            worst = diff;
            worst_at = (x, y);
        }
    }
    println!("REQ-24: {} pixels, worst difference {:.6} m at {:?}", pixels.len(), worst, worst_at);
    assert!(worst <= 0.01, "REQ-24: worst difference {worst} m at {worst_at:?}");
}
