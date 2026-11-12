//! LDEM_64 tiles (spec `lunar-surface-procedural`, REQ-1): the source DNs cut
//! into 30 x 30 degree tiles of 1920 x 1920 int16 LE, written unchanged.
//! Tile `r{RR}_c{CC}`: row RR (0 = north) and column CC (0 = 0 deg E).

use std::fs::File;
use std::io::{BufReader, Read};
use std::path::{Path, PathBuf};

use crate::json::Json;
use crate::pds::{ByteOrder, DemInfo};
use crate::pipeline::{path_text, write_all};
use crate::sha256;
use crate::Failure;

pub const TILE: usize = 1920;
pub const TILE_DEG: usize = 30;
pub const TILE_DIR: &str = "ldem64";

/// The M2 REQ-8 grid, written tile-locally. It is not the global convention string, which the
/// metadata test expects exactly 5 times.
pub const TILE_GRID_CONVENTION: &str = "cell-centred as the elevation levels (M2 REQ-8), tile-local: column x centre at lon_west + 30*(x+0.5)/1920 deg E, row y centre at lat_north - 30*(y+0.5)/1920 deg, row 0 is the northernmost row of the tile";
const COLS: usize = 12;
const ROWS: usize = 6;

pub fn tile_file_name(row: usize, col: usize) -> String {
    format!("ldem64_r{row:02}_c{col:02}.i16")
}

/// Cuts the image into tiles band by band (one row of 12 tiles in memory at a
/// time), writes them under `dir` and returns the `ldem64_tiles` json array.
pub fn write_tiles(image_path: &Path, dem: &DemInfo, dir: &Path) -> Result<Json, Failure> {
    if dem.samples != COLS * TILE || dem.lines != ROWS * TILE {
        return Err(Failure::Invalid(format!(
            "LDEM_64: expected {} x {} samples, found {} x {}",
            COLS * TILE, ROWS * TILE, dem.samples, dem.lines
        )));
    }
    let io = |e: std::io::Error| Failure::Other(format!("{}: {e}", image_path.display()));
    let mut reader = BufReader::with_capacity(1 << 20, File::open(image_path).map_err(io)?);
    let mut row = vec![0u8; dem.samples * 2];
    let mut entries = Vec::new();
    for tr in 0..ROWS {
        let mut tiles = vec![Vec::with_capacity(TILE * TILE * 2); COLS];
        for _ in 0..TILE {
            reader.read_exact(&mut row).map_err(io)?;
            for (tc, tile) in tiles.iter_mut().enumerate() {
                for pair in row[tc * TILE * 2..(tc + 1) * TILE * 2].chunks_exact(2) {
                    let v = match dem.byte_order {
                        ByteOrder::Little => i16::from_le_bytes([pair[0], pair[1]]),
                        ByteOrder::Big => i16::from_be_bytes([pair[0], pair[1]]),
                    };
                    tile.extend_from_slice(&v.to_le_bytes());
                }
            }
        }
        let mut files: Vec<(PathBuf, Vec<u8>)> = Vec::new();
        for (tc, bytes) in tiles.into_iter().enumerate() {
            let path = dir.join(tile_file_name(tr, tc));
            let north = 90 - (tr * TILE_DEG) as i64;
            let west = (tc * TILE_DEG) as i64;
            entries.push(Json::Obj(vec![
                ("path", Json::str(path_text(&path))),
                ("lat_range_deg_north_south", Json::Arr(vec![Json::Num(north as f64), Json::Num((north - TILE_DEG as i64) as f64)])),
                ("lon_range_deg_west_east", Json::Arr(vec![Json::Num(west as f64), Json::Num((west + TILE_DEG as i64) as f64)])),
                ("width", Json::Int(TILE as u64)),
                ("height", Json::Int(TILE as u64)),
                ("data_type", Json::str("i16")),
                ("byte_order", Json::str("little-endian")),
                ("scale", Json::Num(dem.scaling_factor)),
                ("units", Json::str("m")),
                ("reference_radius_m", Json::Num(dem.offset_m)),
                ("grid_convention", Json::str(TILE_GRID_CONVENTION)),
                ("sha256", Json::str(sha256::hex_digest(&bytes))),
            ]));
            files.push((path, bytes));
        }
        write_all(&files)?;
    }
    Ok(Json::Arr(entries))
}
