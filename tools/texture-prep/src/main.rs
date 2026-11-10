//! Builds the Milestone 1 lunar albedo texture from the LROC WAC GMM 100 m tiles.
//!
//! Usage:
//!   texture-prep <raw_dir> <output_png>
//!   texture-prep compare <a.png> <b.png>
//!
//! The processing is downsampling only (box average for the equirectangular
//! tiles, box average plus bilinear polar reprojection for the caps). No tonal
//! change is applied and the GeoTIFF scale/offset metadata is ignored.

mod resample;

use std::f64::consts::PI;
use std::fs::File;
use std::io::{BufReader, BufWriter};
use std::path::Path;
use std::process::ExitCode;

use tiff::decoder::{Decoder, DecodingResult, Limits};
use tiff::tags::Tag;

type Error = Box<dyn std::error::Error>;

/// Output size: longitude 0..360 E across columns, latitude 90..-90 down rows.
const W: usize = 4096;
const H: usize = 2048;
const RADIUS_M: f64 = 1_737_400.0;
const PX_PER_DEG: f64 = W as f64 / 360.0;
/// Source pixel size in metres.
const RES_M: f64 = 100.0;
/// Pixel size of the box-averaged intermediate used for the polar caps.
const POLAR_STEP_M: f64 = 1000.0;

/// Equirectangular tiles: (name, lat_top, lat_bottom, lon_west, lon_east).
const EQUI_TILES: [(&str, f64, f64, f64, f64); 8] = [
    ("E300N0450", 60.0, 0.0, 0.0, 90.0),
    ("E300N1350", 60.0, 0.0, 90.0, 180.0),
    ("E300N2250", 60.0, 0.0, 180.0, 270.0),
    ("E300N3150", 60.0, 0.0, 270.0, 360.0),
    ("E300S0450", 0.0, -60.0, 0.0, 90.0),
    ("E300S1350", 0.0, -60.0, 90.0, 180.0),
    ("E300S2250", 0.0, -60.0, 180.0, 270.0),
    ("E300S3150", 0.0, -60.0, 270.0, 360.0),
];

/// Output rows filled from the polar caps (north, then south).
const NORTH_ROWS: std::ops::Range<usize> = 0..341;
const SOUTH_ROWS: std::ops::Range<usize> = 1707..2048;

struct Tile {
    width: usize,
    height: usize,
    pixels: Vec<u8>,
    /// ModelTiepointTag values, empty when the tag is absent.
    tiepoint: Vec<f64>,
}

fn read_tile(raw_dir: &Path, name: &str) -> Result<Tile, Error> {
    let path = raw_dir.join(format!("WAC_GLOBAL_{name}_100M.TIF"));
    let file = File::open(&path).map_err(|e| format!("{}: {e}", path.display()))?;
    let mut decoder = Decoder::new(BufReader::new(file))?.with_limits(Limits::unlimited());
    let (width, height) = decoder.dimensions()?;
    let tiepoint = decoder
        .find_tag(Tag::ModelTiepointTag)?
        .map(|v| v.into_f64_vec())
        .transpose()?
        .unwrap_or_default();
    let pixels = match decoder.read_image()? {
        DecodingResult::U8(data) => data,
        _ => return Err(format!("{}: expected 8-bit samples", path.display()).into()),
    };
    let (width, height) = (width as usize, height as usize);
    if pixels.len() != width * height {
        return Err(format!("{}: expected a single 8-bit band", path.display()).into());
    }
    Ok(Tile { width, height, pixels, tiepoint })
}

/// Latitude of the top edge of output row `r`.
fn row_lat_edge(r: usize) -> f64 {
    90.0 - r as f64 * 180.0 / H as f64
}

/// Latitude of the centre of output row `r`.
fn row_lat_centre(r: usize) -> f64 {
    90.0 - (r as f64 + 0.5) * 180.0 / H as f64
}

fn paste(target: &mut [u8], piece: &[u8], piece_w: usize, col0: usize, row0: usize) {
    for (i, row) in piece.chunks_exact(piece_w).enumerate() {
        let start = (row0 + i) * W + col0;
        target[start..start + piece_w].copy_from_slice(row);
    }
}

/// Box-averages one equirectangular tile into the output rows whose centre
/// latitude lies inside the tile. Returns the filled row range.
fn equi_into(
    target: &mut [u8],
    raw_dir: &Path,
    name: &str,
    (lat_t, lat_b, lon_w, lon_e): (f64, f64, f64, f64),
) -> Result<(usize, usize), Error> {
    let tile = read_tile(raw_dir, name)?;
    let hs = tile.height as f64;
    let inside = |r: &usize| {
        let lat = row_lat_centre(*r);
        lat_b <= lat && lat < lat_t
    };
    let r0 = (0..H).find(inside).ok_or("tile covers no output row")?;
    let r1 = (0..H).rfind(inside).ok_or("tile covers no output row")? + 1;
    let span = lat_t - lat_b;
    let y0 = ((lat_t - row_lat_edge(r0)) / span * hs).max(0.0);
    let y1 = ((lat_t - row_lat_edge(r1)) / span * hs).min(hs);
    let c0 = (lon_w * PX_PER_DEG).round() as usize;
    let c1 = (lon_e * PX_PER_DEG).round() as usize;
    let piece = resample::resize_box(
        &tile.pixels,
        tile.width,
        tile.height,
        c1 - c0,
        r1 - r0,
        [0.0, y0 as f32, tile.width as f32, y1 as f32],
    );
    paste(target, &piece, c1 - c0, c0, r0);
    Ok((r0, r1))
}

/// Reprojects one polar stereographic cap (latitude 60..90) into `rows`.
///
/// Output columns are longitude 0..360 E. Sampling is bilinear on a 1 km/pixel
/// box-averaged intermediate of the 100 m source tile.
fn polar_into(
    target: &mut [u8],
    raw_dir: &Path,
    name: &str,
    rows: std::ops::Range<usize>,
    south: bool,
) -> Result<(), Error> {
    let tile = read_tile(raw_dir, name)?;
    if tile.tiepoint.len() < 5 {
        return Err(format!("{name}: missing ModelTiepointTag").into());
    }
    // Projected coordinates of pixel (0, 0).
    let (x_origin, y_origin) = (tile.tiepoint[3], tile.tiepoint[4]);
    let ws = tile.width as f64;
    let k = POLAR_STEP_M / RES_M;
    let mid_w = (ws / k).round_ties_even() as usize;
    let mid = resample::resize_box(
        &tile.pixels,
        tile.width,
        tile.height,
        mid_w,
        mid_w,
        [0.0, 0.0, tile.width as f32, tile.height as f32],
    );
    // Exact intermediate pixel size in metres.
    let mid_step = ws * RES_M / mid_w as f64;
    drop(tile);

    let max_index = mid_w as i64 - 1;
    let clamp = |i: i64| i.clamp(0, max_index) as usize;
    let px = |x: usize, y: usize| f64::from(mid[y * mid_w + x]);
    let sign = if south { 1.0 } else { -1.0 };
    for r in rows {
        let phi = row_lat_centre(r) * (PI / 180.0);
        let rho = if south {
            2.0 * RADIUS_M * (PI / 4.0 + phi / 2.0).tan()
        } else {
            2.0 * RADIUS_M * (PI / 4.0 - phi / 2.0).tan()
        };
        for c in 0..W {
            let lam = ((c as f64 + 0.5) * 360.0 / W as f64) * (PI / 180.0);
            let x = rho * lam.sin();
            let y = sign * rho * lam.cos();
            let fx = (x - x_origin) / mid_step - 0.5;
            let fy = (y_origin - y) / mid_step - 0.5;
            let (ix, iy) = (fx.floor(), fy.floor());
            let (ax, ay) = (fx - ix, fy - iy);
            let (ix, iy) = (ix as i64, iy as i64);
            let (ix0, iy0) = (clamp(ix), clamp(iy));
            let (ix1, iy1) = (clamp(ix + 1), clamp(iy + 1));
            let v = (1.0 - ax) * (1.0 - ay) * px(ix0, iy0)
                + ax * (1.0 - ay) * px(ix1, iy0)
                + (1.0 - ax) * ay * px(ix0, iy1)
                + ax * ay * px(ix1, iy1);
            target[r * W + c] = v.round_ties_even() as u8;
        }
    }
    Ok(())
}

fn write_rgb_png(path: &Path, grey: &[u8]) -> Result<(), Error> {
    let mut rgb = Vec::with_capacity(grey.len() * 3);
    for &v in grey {
        rgb.extend_from_slice(&[v, v, v]);
    }
    let file = File::create(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let mut encoder = png::Encoder::new(BufWriter::new(file), W as u32, H as u32);
    encoder.set_color(png::ColorType::Rgb);
    encoder.set_depth(png::BitDepth::Eight);
    encoder.set_compression(png::Compression::High);
    let mut writer = encoder.write_header()?;
    writer.write_image_data(&rgb)?;
    writer.finish()?;
    Ok(())
}

fn build(raw_dir: &Path, out_path: &Path) -> Result<(), Error> {
    let mut target = vec![0u8; W * H];
    for (name, lat_t, lat_b, lon_w, lon_e) in EQUI_TILES {
        let (r0, r1) = equi_into(&mut target, raw_dir, name, (lat_t, lat_b, lon_w, lon_e))?;
        eprintln!("{name}: rows {r0}..{}", r1 - 1);
    }
    polar_into(&mut target, raw_dir, "P900N0000", NORTH_ROWS, false)?;
    polar_into(&mut target, raw_dir, "P900S0000", SOUTH_ROWS, true)?;
    write_rgb_png(out_path, &target)
}

struct DecodedPng {
    width: u32,
    height: u32,
    color: png::ColorType,
    depth: png::BitDepth,
    data: Vec<u8>,
}

fn read_png(path: &Path) -> Result<DecodedPng, Error> {
    let file = File::open(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let mut reader = png::Decoder::new(BufReader::new(file)).read_info()?;
    let size = reader.output_buffer_size().ok_or("PNG too large")?;
    let mut data = vec![0u8; size];
    let info = reader.next_frame(&mut data)?;
    data.truncate(info.buffer_size());
    Ok(DecodedPng {
        width: info.width,
        height: info.height,
        color: info.color_type,
        depth: info.bit_depth,
        data,
    })
}

/// Decodes two PNG files and compares format and every sample. Returns true
/// when size, colour type, bit depth and all decoded values are equal.
fn compare(a_path: &Path, b_path: &Path) -> Result<bool, Error> {
    let a = read_png(a_path)?;
    let b = read_png(b_path)?;
    for (label, p) in [("a", &a), ("b", &b)] {
        println!("{label}: {}x{} {:?} {:?}-bit", p.width, p.height, p.color, p.depth);
    }
    let same_format =
        (a.width, a.height, a.color, a.depth) == (b.width, b.height, b.color, b.depth);
    if !same_format || a.data.len() != b.data.len() {
        println!("format differs");
        return Ok(false);
    }
    let channels = a.color.samples();
    let mut differing_pixels = 0u64;
    let mut max_difference = 0u8;
    for (pa, pb) in a.data.chunks_exact(channels).zip(b.data.chunks_exact(channels)) {
        if pa != pb {
            differing_pixels += 1;
            for (&va, &vb) in pa.iter().zip(pb) {
                max_difference = max_difference.max(va.abs_diff(vb));
            }
        }
    }
    println!("pixels compared: {}", a.data.len() / channels);
    println!("differing pixels: {differing_pixels}");
    println!("maximum difference: {max_difference}");
    Ok(differing_pixels == 0)
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let result = match args.as_slice() {
        [cmd, a, b] if cmd == "compare" => compare(Path::new(a), Path::new(b)),
        [raw_dir, out_png] => build(Path::new(raw_dir), Path::new(out_png)).map(|()| true),
        _ => {
            eprintln!("usage: texture-prep <raw_dir> <output_png>");
            eprintln!("       texture-prep compare <a.png> <b.png>");
            return ExitCode::from(2);
        }
    };
    match result {
        Ok(true) => ExitCode::SUCCESS,
        Ok(false) => ExitCode::FAILURE,
        Err(e) => {
            eprintln!("error: {e}");
            ExitCode::FAILURE
        }
    }
}
