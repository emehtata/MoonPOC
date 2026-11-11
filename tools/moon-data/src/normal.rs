//! ENU normal map from the 4096 x 2048 LOLA height level
//! (spec: `docs/specs/visual-quality-milestone-3.md`, REQ-12 to REQ-15).

use std::f64::consts::PI;
use std::fs;
use std::path::Path;

use crate::json::Json;
use crate::pipeline::{self, path_text, Written};
use crate::sha256;
use crate::Failure;

pub const W: usize = 4096;
pub const H: usize = 2048;
pub const R_M: f64 = 1_737_400.0;
pub const NORMAL_FILE: &str = "lunar_normal_enu_4096x2048.png";
pub const METHOD: &str = "central difference, k rule";

/// Unit ENU normals, row-major, row 0 north (REQ-13). Fails on a NaN height.
pub fn compute_normals(h: &[f32], w: usize, rows: usize) -> Result<Vec<[f64; 3]>, Failure> {
    if let Some(i) = h.iter().position(|v| v.is_nan()) {
        return Err(Failure::Invalid(format!("height level: NaN at texel x={} y={}", i % w, i / w)));
    }
    let at = |x: usize, y: usize| f64::from(h[y * w + x]);
    let dy = PI * R_M / rows as f64;
    let mut out = Vec::with_capacity(w * rows);
    for y in 0..rows {
        let lat = (90.0 - 180.0 * (y as f64 + 0.5) / rows as f64).to_radians();
        let dx1 = 2.0 * PI * R_M * lat.cos() / w as f64;
        let k = ((dy / dx1).ceil() as usize).max(1);
        for x in 0..w {
            let g_e = (at((x + k) % w, y) - at((x + w - k) % w, y)) / (2.0 * k as f64 * dx1);
            let g_n = if y == 0 {
                (at(x, 0) - at(x, 1)) / dy
            } else if y == rows - 1 {
                (at(x, y - 1) - at(x, y)) / dy
            } else {
                (at(x, y - 1) - at(x, y + 1)) / (2.0 * dy)
            };
            let len = (g_e * g_e + g_n * g_n + 1.0).sqrt();
            out.push([-g_e / len, -g_n / len, 1.0 / len]);
        }
    }
    Ok(out)
}

/// REQ-15 encoding of one component.
pub fn encode_component(c: f64) -> u8 {
    ((c * 0.5 + 0.5) * 255.0).round().clamp(0.0, 255.0) as u8
}

pub fn encode_png(normals: &[[f64; 3]], w: usize, rows: usize) -> Result<Vec<u8>, Failure> {
    let rgb: Vec<u8> = normals.iter().flat_map(|n| n.map(encode_component)).collect();
    let png_error = |e: png::EncodingError| Failure::Other(format!("PNG encoding: {e}"));
    let mut out = Vec::new();
    let mut encoder = png::Encoder::new(&mut out, w as u32, rows as u32);
    encoder.set_color(png::ColorType::Rgb);
    encoder.set_depth(png::BitDepth::Eight);
    encoder.set_compression(png::Compression::High);
    let mut writer = encoder.write_header().map_err(png_error)?;
    writer.write_image_data(&rgb).map_err(png_error)?;
    writer.finish().map_err(png_error)?;
    Ok(out)
}

/// The `"sha256"` value of the json entry whose `"path"` is `path`.
fn json_sha_for(text: &str, path: &str) -> Option<String> {
    let start = text.find(&format!("\"path\": \"{path}\""))?;
    let rest = &text[start..];
    let at = rest.find("\"sha256\": \"")? + "\"sha256\": \"".len();
    Some(rest[at..].split('"').next()?.to_string())
}

/// Runs the step: checks the level against the json, writes the PNG and adds
/// the `normal_map` entry to `moon_data.json` (replacing an earlier one).
pub fn run(elevation_dir: &Path, textures_dir: &Path) -> Result<Vec<Written>, Failure> {
    let json_path = elevation_dir.join(pipeline::METADATA_FILE);
    let level_path = elevation_dir.join(pipeline::level_file_name(W, H));
    let level_text = path_text(&level_path);
    let text = fs::read_to_string(&json_path)
        .map_err(|e| Failure::Invalid(format!("{}: {e}", path_text(&json_path))))?;
    let expected_sha = json_sha_for(&text, &level_text).ok_or_else(|| {
        Failure::Invalid(format!("{}: no entry for {level_text}", path_text(&json_path)))
    })?;
    let bytes = fs::read(&level_path).map_err(|e| Failure::Invalid(format!("{level_text}: {e}")))?;
    let level_sha = sha256::hex_digest(&bytes);
    if bytes.len() != W * H * 4 || level_sha != expected_sha {
        return Err(Failure::Invalid(format!(
            "{level_text}: size or SHA-256 does not match {}",
            path_text(&json_path)
        )));
    }
    let heights: Vec<f32> =
        bytes.chunks_exact(4).map(|b| f32::from_le_bytes([b[0], b[1], b[2], b[3]])).collect();
    let png = encode_png(&compute_normals(&heights, W, H)?, W, H)?;

    let png_path = textures_dir.join(NORMAL_FILE);
    let entry = Json::Obj(vec![
        ("path", Json::str(path_text(&png_path))),
        ("width", Json::Int(W as u64)),
        ("height", Json::Int(H as u64)),
        ("encoding", Json::str("enu_rgb8")),
        (
            "frame",
            Json::str("local east-north-up at the texel centre; R,G,B = round((n*0.5+0.5)*255) for east, north, up"),
        ),
        (
            "source_level",
            Json::Obj(vec![("path", Json::str(&level_text)), ("sha256", Json::str(&level_sha))]),
        ),
        ("method", Json::str(METHOD)),
        ("sha256", Json::str(sha256::hex_digest(&png))),
    ]);
    // `normal_map` is always the last top-level key, so an older one is cut off here.
    let marker = ",\n  \"normal_map\": ";
    let body = match text.find(marker) {
        Some(i) => &text[..i],
        None => text.trim_end().strip_suffix('}').map(str::trim_end).ok_or_else(|| {
            Failure::Invalid(format!("{}: not a JSON object", path_text(&json_path)))
        })?,
    };
    let entry_text = entry.to_pretty_string();
    let metadata = format!("{body}{marker}{}\n}}\n", entry_text.trim_end().replace('\n', "\n  "));
    pipeline::write_all(&[(png_path, png), (json_path, metadata.into_bytes())])
}
