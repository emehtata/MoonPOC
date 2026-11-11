//! Albedo texture from the ten LROC WAC GMM 100 m GeoTIFF tiles.
//!
//! The processing is the Milestone 1 processing, value for value: a box
//! average for the equirectangular tiles, and a box average to 1 km followed
//! by bilinear spherical polar stereographic sampling for the caps. No tonal
//! change is applied and the GeoTIFF scale/offset metadata is ignored. The
//! resampler itself is the Milestone 1 source file, compiled into this crate.

use std::f64::consts::PI;
use std::io::{Cursor, Read, Seek};

use tiff::decoder::{Decoder, DecodingResult, Limits};
use tiff::tags::Tag;

use crate::resample;
use crate::Failure;

/// Output size: longitude 0..360 E across columns, latitude 90..-90 down rows.
pub const W: usize = 4096;
pub const H: usize = 2048;
/// Radius of the sphere the LROC WAC mosaic is projected on, in metres.
pub const SPHERE_RADIUS_M: f64 = 1_737_400.0;
const PX_PER_DEG: f64 = W as f64 / 360.0;
/// Source pixel size in metres.
const RES_M: f64 = 100.0;
/// Pixel size of the box-averaged intermediate used for the polar caps.
const POLAR_STEP_M: f64 = 1000.0;
/// Latitude where the equirectangular tiles end and the polar caps begin.
const CAP_EDGE_LAT_DEG: f64 = 60.0;

/// Map extent of one source tile.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Extent {
    /// Equirectangular tile: (lat_top, lat_bottom, lon_west, lon_east) in degrees.
    Equirectangular(f64, f64, f64, f64),
    /// Polar stereographic cap from the pole down to 60 degrees latitude.
    Polar { south: bool },
}

/// The ten tiles, in processing order, with the extents documented in
/// `docs/DATA_SOURCES.md`.
pub const TILES: [(&str, Extent); 10] = [
    ("E300N0450", Extent::Equirectangular(60.0, 0.0, 0.0, 90.0)),
    ("E300N1350", Extent::Equirectangular(60.0, 0.0, 90.0, 180.0)),
    ("E300N2250", Extent::Equirectangular(60.0, 0.0, 180.0, 270.0)),
    ("E300N3150", Extent::Equirectangular(60.0, 0.0, 270.0, 360.0)),
    ("E300S0450", Extent::Equirectangular(0.0, -60.0, 0.0, 90.0)),
    ("E300S1350", Extent::Equirectangular(0.0, -60.0, 90.0, 180.0)),
    ("E300S2250", Extent::Equirectangular(0.0, -60.0, 180.0, 270.0)),
    ("E300S3150", Extent::Equirectangular(0.0, -60.0, 270.0, 360.0)),
    ("P900N0000", Extent::Polar { south: false }),
    ("P900S0000", Extent::Polar { south: true }),
];

/// Output rows filled from the polar caps (north, then south).
const NORTH_ROWS: std::ops::Range<usize> = 0..341;
const SOUTH_ROWS: std::ops::Range<usize> = 1707..2048;

pub fn tile_file_name(tile: &str) -> String {
    format!("WAC_GLOBAL_{tile}_100M.TIF")
}

/// Georeferencing tags of a GeoTIFF.
#[derive(Clone, Debug, PartialEq)]
pub struct GeoRef {
    pub width: usize,
    pub height: usize,
    /// ModelTiepointTag: raster (i, j, k) then model (x, y, z).
    pub tiepoint: Vec<f64>,
    /// ModelPixelScaleTag: (x, y, z) model units per pixel.
    pub pixel_scale: Vec<f64>,
}

fn tiff_error(file: &str, e: impl std::fmt::Display) -> Failure {
    Failure::Other(format!("{file}: {e}"))
}

fn open<R: Read + Seek>(file: &str, reader: R) -> Result<Decoder<R>, Failure> {
    Ok(Decoder::new(reader)
        .map_err(|e| tiff_error(file, e))?
        .with_limits(Limits::unlimited()))
}

fn f64_tag<R: Read + Seek>(
    file: &str,
    decoder: &mut Decoder<R>,
    tag: Tag,
    name: &str,
    min_len: usize,
) -> Result<Vec<f64>, Failure> {
    let values = decoder
        .find_tag(tag)
        .map_err(|e| tiff_error(file, e))?
        .map(|v| v.into_f64_vec())
        .transpose()
        .map_err(|e| tiff_error(file, e))?
        .unwrap_or_default();
    if values.len() < min_len {
        return Err(Failure::Invalid(format!("{file}: {name}: tag missing or too short")));
    }
    Ok(values)
}

/// Reads the size and the georeferencing tags without decoding the pixels.
pub fn read_georef<R: Read + Seek>(file: &str, reader: R) -> Result<GeoRef, Failure> {
    let mut decoder = open(file, reader)?;
    let (width, height) = decoder.dimensions().map_err(|e| tiff_error(file, e))?;
    let tiepoint = f64_tag(file, &mut decoder, Tag::ModelTiepointTag, "ModelTiepointTag", 6)?;
    let pixel_scale =
        f64_tag(file, &mut decoder, Tag::ModelPixelScaleTag, "ModelPixelScaleTag", 2)?;
    Ok(GeoRef { width: width as usize, height: height as usize, tiepoint, pixel_scale })
}

/// Checks a tile's tie point and pixel scale against its expected extent on
/// the sphere of radius `radius_m`. Positions may differ by up to one pixel,
/// because the tile sizes are whole pixels.
pub fn validate_georef(
    file: &str,
    geo: &GeoRef,
    extent: Extent,
    radius_m: f64,
) -> Result<(), Failure> {
    let bad = |field: &str, found: f64, want: f64| {
        Err(Failure::Invalid(format!("{file}: {field}: found {found}, need {want}")))
    };
    let (sx, sy) = (geo.pixel_scale[0], geo.pixel_scale[1]);
    if (sx - RES_M).abs() > 1e-6 {
        return bad("ModelPixelScaleTag x", sx, RES_M);
    }
    if (sy - RES_M).abs() > 1e-6 {
        return bad("ModelPixelScaleTag y", sy, RES_M);
    }
    if geo.tiepoint[0] != 0.0 || geo.tiepoint[1] != 0.0 {
        return bad("ModelTiepointTag raster point", geo.tiepoint[0].max(geo.tiepoint[1]), 0.0);
    }
    let (x0, y0) = (geo.tiepoint[3], geo.tiepoint[4]);
    let (width_m, height_m) = (geo.width as f64 * sx, geo.height as f64 * sy);
    let metres = |deg: f64| radius_m * deg * PI / 180.0;
    let (want_x0, want_y0, want_w, want_h) = match extent {
        Extent::Equirectangular(lat_t, lat_b, lon_w, lon_e) => {
            // Longitudes above 180 E may be written as negative x; both forms
            // describe the same tile, so x is compared modulo the circumference.
            let circumference = metres(360.0);
            let want = metres(lon_w);
            let nearest = want + ((x0 - want) / circumference).round() * circumference;
            (nearest, metres(lat_t), metres(lon_e - lon_w), metres(lat_t - lat_b))
        }
        Extent::Polar { .. } => {
            let half = 2.0 * radius_m * ((90.0 - CAP_EDGE_LAT_DEG) * PI / 360.0).tan();
            (-width_m / 2.0, height_m / 2.0, 2.0 * half, 2.0 * half)
        }
    };
    if (width_m - want_w).abs() > 2.0 * sx {
        return bad("width x ModelPixelScaleTag (extent in metres)", width_m, want_w);
    }
    if (height_m - want_h).abs() > 2.0 * sy {
        return bad("height x ModelPixelScaleTag (extent in metres)", height_m, want_h);
    }
    if (x0 - want_x0).abs() > sx {
        return bad("ModelTiepointTag x", x0, want_x0);
    }
    if (y0 - want_y0).abs() > sy {
        return bad("ModelTiepointTag y", y0, want_y0);
    }
    Ok(())
}

fn read_pixels<R: Read + Seek>(file: &str, reader: R, geo: &GeoRef) -> Result<Vec<u8>, Failure> {
    let mut decoder = open(file, reader)?;
    let pixels = match decoder.read_image().map_err(|e| tiff_error(file, e))? {
        DecodingResult::U8(data) => data,
        _ => return Err(Failure::Invalid(format!("{file}: BitsPerSample: need 8-bit samples"))),
    };
    if pixels.len() != geo.width * geo.height {
        return Err(Failure::Invalid(format!("{file}: SamplesPerPixel: need a single band")));
    }
    Ok(pixels)
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
/// latitude lies inside the tile.
fn equi_into(
    target: &mut [u8],
    pixels: &[u8],
    geo: &GeoRef,
    (lat_t, lat_b, lon_w, lon_e): (f64, f64, f64, f64),
) {
    let hs = geo.height as f64;
    let inside = |r: &usize| {
        let lat = row_lat_centre(*r);
        lat_b <= lat && lat < lat_t
    };
    let r0 = (0..H).find(inside).expect("tile covers output rows");
    let r1 = (0..H).rfind(inside).expect("tile covers output rows") + 1;
    let span = lat_t - lat_b;
    let y0 = ((lat_t - row_lat_edge(r0)) / span * hs).max(0.0);
    let y1 = ((lat_t - row_lat_edge(r1)) / span * hs).min(hs);
    let c0 = (lon_w * PX_PER_DEG).round() as usize;
    let c1 = (lon_e * PX_PER_DEG).round() as usize;
    let piece = resample::resize_box(
        pixels,
        geo.width,
        geo.height,
        c1 - c0,
        r1 - r0,
        [0.0, y0 as f32, geo.width as f32, y1 as f32],
    );
    paste(target, &piece, c1 - c0, c0, r0);
}

/// Reprojects one polar stereographic cap (latitude 60..90) into `rows`.
/// Sampling is bilinear on a 1 km/pixel box-averaged intermediate.
fn polar_into(
    target: &mut [u8],
    pixels: Vec<u8>,
    geo: &GeoRef,
    rows: std::ops::Range<usize>,
    south: bool,
    radius_m: f64,
) {
    // Projected coordinates of pixel (0, 0).
    let (x_origin, y_origin) = (geo.tiepoint[3], geo.tiepoint[4]);
    let ws = geo.width as f64;
    let k = POLAR_STEP_M / RES_M;
    let mid_w = (ws / k).round_ties_even() as usize;
    let mid = resample::resize_box(
        &pixels,
        geo.width,
        geo.height,
        mid_w,
        mid_w,
        [0.0, 0.0, geo.width as f32, geo.height as f32],
    );
    // Exact intermediate pixel size in metres.
    let mid_step = ws * RES_M / mid_w as f64;
    drop(pixels);

    let max_index = mid_w as i64 - 1;
    let clamp = |i: i64| i.clamp(0, max_index) as usize;
    let px = |x: usize, y: usize| f64::from(mid[y * mid_w + x]);
    let sign = if south { 1.0 } else { -1.0 };
    for r in rows {
        let phi = row_lat_centre(r) * (PI / 180.0);
        let rho = if south {
            2.0 * radius_m * (PI / 4.0 + phi / 2.0).tan()
        } else {
            2.0 * radius_m * (PI / 4.0 - phi / 2.0).tan()
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
}

/// Decodes one tile (already validated) and writes its part of the
/// `W` x `H` grey output.
pub fn add_tile<R: Read + Seek>(
    target: &mut [u8],
    file: &str,
    reader: R,
    geo: &GeoRef,
    extent: Extent,
    radius_m: f64,
) -> Result<(), Failure> {
    let pixels = read_pixels(file, reader, geo)?;
    match extent {
        Extent::Equirectangular(lat_t, lat_b, lon_w, lon_e) => {
            equi_into(target, &pixels, geo, (lat_t, lat_b, lon_w, lon_e));
        }
        Extent::Polar { south } => {
            let rows = if south { SOUTH_ROWS } else { NORTH_ROWS };
            polar_into(target, pixels, geo, rows, south, radius_m);
        }
    }
    Ok(())
}

/// Encodes 8-bit grey as an 8-bit RGB PNG (R = G = B).
pub fn encode_rgb_png(grey: &[u8]) -> Result<Vec<u8>, Failure> {
    let mut rgb = Vec::with_capacity(grey.len() * 3);
    for &v in grey {
        rgb.extend_from_slice(&[v, v, v]);
    }
    let png_error = |e: png::EncodingError| Failure::Other(format!("PNG encoding: {e}"));
    let mut out = Vec::new();
    let mut encoder = png::Encoder::new(&mut out, W as u32, H as u32);
    encoder.set_color(png::ColorType::Rgb);
    encoder.set_depth(png::BitDepth::Eight);
    encoder.set_compression(png::Compression::High);
    let mut writer = encoder.write_header().map_err(png_error)?;
    writer.write_image_data(&rgb).map_err(png_error)?;
    writer.finish().map_err(png_error)?;
    Ok(out)
}

/// Decoded PNG samples with their format.
pub struct DecodedPng {
    pub width: u32,
    pub height: u32,
    pub channels: usize,
    pub bit_depth: u8,
    pub data: Vec<u8>,
}

pub fn decode_png(file: &str, bytes: &[u8]) -> Result<DecodedPng, Failure> {
    let png_error = |e: png::DecodingError| Failure::Other(format!("{file}: {e}"));
    let mut reader = png::Decoder::new(Cursor::new(bytes)).read_info().map_err(png_error)?;
    let size = reader
        .output_buffer_size()
        .ok_or_else(|| Failure::Other(format!("{file}: PNG too large")))?;
    let mut data = vec![0u8; size];
    let info = reader.next_frame(&mut data).map_err(png_error)?;
    data.truncate(info.buffer_size());
    Ok(DecodedPng {
        width: info.width,
        height: info.height,
        channels: info.color_type.samples(),
        bit_depth: info.bit_depth as u8,
        data,
    })
}

/// Result of comparing two decoded PNG files pixel by pixel.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PngDifference {
    pub pixels: u64,
    pub differing_pixels: u64,
    pub max_difference: u8,
}

/// Compares every sample of two PNG files. `None` when size, channel count
/// or bit depth differ.
pub fn compare_png(a: &DecodedPng, b: &DecodedPng) -> Option<PngDifference> {
    let format = |p: &DecodedPng| (p.width, p.height, p.channels, p.bit_depth, p.data.len());
    if format(a) != format(b) {
        return None;
    }
    let mut diff = PngDifference {
        pixels: (a.data.len() / a.channels) as u64,
        differing_pixels: 0,
        max_difference: 0,
    };
    for (pa, pb) in a.data.chunks_exact(a.channels).zip(b.data.chunks_exact(b.channels)) {
        if pa != pb {
            diff.differing_pixels += 1;
            for (&va, &vb) in pa.iter().zip(pb) {
                diff.max_difference = diff.max_difference.max(va.abs_diff(vb));
            }
        }
    }
    Some(diff)
}
