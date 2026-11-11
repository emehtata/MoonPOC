//! Helpers shared by the moon-data integration tests.
//!
//! Tests read the real raw files in `data/raw/` and the generated files in
//! `assets/`. Scratch output goes under `CARGO_TARGET_TMPDIR` (inside
//! `tools/moon-data/target/`, which is git-ignored).

#![allow(dead_code)]

use std::fs::{self, File};
use std::io::BufReader;
use std::path::{Path, PathBuf};

use moon_data::albedo::{self, Extent};

/// Source DEM size from the LDEM_64 label (checked by the pipeline, not hard-coded there).
pub const DEM_SAMPLES: usize = 23040;
pub const DEM_LINES: usize = 11520;
pub const SCALE_M_PER_DN: f64 = 0.5;
pub const RADIUS_KM: f64 = 1737.4;

pub fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .canonicalize()
        .expect("repository root")
}

pub fn raw_dir() -> PathBuf {
    repo_root().join("data/raw")
}

pub fn assets_dir() -> PathBuf {
    repo_root().join("assets")
}

pub fn dem_image() -> PathBuf {
    raw_dir().join("lola_ldem_64/LDEM_64.IMG")
}

pub fn dem_label() -> PathBuf {
    raw_dir().join("lola_ldem_64/LDEM_64.LBL")
}

pub fn tile_dir() -> PathBuf {
    raw_dir().join("lroc_wac_gmm_100m")
}

/// A fresh, empty scratch directory for one test.
pub fn scratch(name: &str) -> PathBuf {
    let dir = Path::new(env!("CARGO_TARGET_TMPDIR")).join(name);
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).expect("create scratch dir");
    dir
}

/// Reads a little-endian float32 file.
pub fn read_f32_le(path: &Path) -> Vec<f32> {
    let bytes = fs::read(path).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
    assert_eq!(bytes.len() % 4, 0, "{} is not a whole number of float32 values", path.display());
    bytes.chunks_exact(4).map(|c| f32::from_le_bytes([c[0], c[1], c[2], c[3]])).collect()
}

/// Great-circle angle in degrees between two points given in degrees (haversine).
pub fn great_circle_deg(lat1: f64, lon1: f64, lat2: f64, lon2: f64) -> f64 {
    let (p1, p2) = (lat1.to_radians(), lat2.to_radians());
    let dphi = p2 - p1;
    let dlam = (lon2 - lon1).to_radians();
    let a = (dphi / 2.0).sin().powi(2) + p1.cos() * p2.cos() * (dlam / 2.0).sin().powi(2);
    2.0 * a.sqrt().min(1.0).asin().to_degrees()
}

/// Centre latitude (degrees) of row `y` on a grid of `h` rows (REQ-8).
pub fn row_centre_lat(y: usize, h: usize) -> f64 {
    90.0 - 180.0 * (y as f64 + 0.5) / h as f64
}

/// Centre longitude (degrees east) of column `x` on a grid of `w` columns (REQ-8).
pub fn col_centre_lon(x: usize, w: usize) -> f64 {
    360.0 * (x as f64 + 0.5) / w as f64
}

/// Regenerates the 4096 x 2048 grey albedo from the ten raw tiles with the
/// library functions the pipeline uses, one 8-bit value per pixel (row 0 = north).
pub fn regenerate_albedo_grey() -> Vec<u8> {
    let mut grey = vec![0u8; albedo::W * albedo::H];
    for (tile, extent) in albedo::TILES.iter() {
        let name = albedo::tile_file_name(tile);
        let path = tile_dir().join(&name);
        let geo = albedo::read_georef(&name, BufReader::new(File::open(&path).expect("tile")))
            .unwrap_or_else(|e| panic!("{name}: {:?}", e));
        albedo::validate_georef(&name, &geo, *extent, albedo::SPHERE_RADIUS_M)
            .unwrap_or_else(|e| panic!("{name}: {:?}", e));
        let reader = BufReader::new(File::open(&path).expect("tile"));
        albedo::add_tile(&mut grey, &name, reader, &geo, *extent, albedo::SPHERE_RADIUS_M)
            .unwrap_or_else(|e| panic!("{name}: {:?}", e));
    }
    grey
}

pub fn is_polar(extent: &Extent) -> bool {
    matches!(extent, Extent::Polar { .. })
}
