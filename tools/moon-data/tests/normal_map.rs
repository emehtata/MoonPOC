//! Milestone 3 normal map (visual-quality-milestone-3.md, REQ-12 to REQ-15, REQ-19).
//!
//! (a) synthetic tilted plane, (b) 1000 real texels against an independent
//! recomputation, (c) Tycho west inner wall, (d) no NaN, (e) byte-identical runs,
//! plus the corrupted-level exit code (REQ-12) and the PNG and json fields (REQ-14, REQ-15).

mod common;

use std::f64::consts::PI;
use std::fs::{self, File};
use std::io::BufReader;
use std::path::Path;
use std::process::Command;

use common::{assets_dir, read_f32_le, scratch};
use moon_data::normal::{self, compute_normals, H, NORMAL_FILE, R_M, W};
use moon_data::sha256;

const LEVEL: &str = "lola_height_m_4096x2048.f32";

/// Decodes an 8-bit PNG into (width, height, colour type, raw bytes).
fn decode_png(path: &Path) -> (u32, u32, png::ColorType, png::BitDepth, Vec<u8>) {
    let decoder = png::Decoder::new(BufReader::new(File::open(path).expect("PNG file")));
    let mut reader = decoder.read_info().expect("PNG header");
    let mut buf = vec![0; reader.output_buffer_size().expect("PNG size")];
    let info = reader.next_frame(&mut buf).expect("PNG frame");
    let info_ct = reader.info().color_type;
    let info_bd = reader.info().bit_depth;
    buf.truncate(info.buffer_size());
    (info.width, info.height, info_ct, info_bd, buf)
}

/// Unit normal from one RGB8 texel (REQ-16 decode: n = rgb * 2 - 1, normalised).
fn decode_texel(rgb: &[u8], i: usize) -> [f64; 3] {
    let v = [0, 1, 2].map(|c| f64::from(rgb[3 * i + c]) / 255.0 * 2.0 - 1.0);
    let len = (v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).sqrt();
    v.map(|c| c / len)
}

fn angle_deg(a: [f64; 3], b: [f64; 3]) -> f64 {
    let d = (a[0] * b[0] + a[1] * b[1] + a[2] * b[2]).clamp(-1.0, 1.0);
    d.acos().to_degrees()
}

fn heights() -> Vec<f32> {
    read_f32_le(&assets_dir().join("elevation").join(LEVEL))
}

/// Copies moon_data.json into a scratch elevation dir. The json names the level by its
/// repository-relative path, so that path is rewritten to the scratch location (the
/// step looks up the level by the path it is given).
fn copy_metadata(elev: &Path) {
    let text = fs::read_to_string(assets_dir().join("elevation/moon_data.json")).unwrap();
    let text = text.replace("assets/elevation/", &format!("{}/", elev.display()));
    fs::write(elev.join("moon_data.json"), text).unwrap();
}

fn committed_png() -> std::path::PathBuf {
    assets_dir().join("textures").join(NORMAL_FILE)
}

/// Independent recomputation of REQ-13 for one texel (written separately from normal.rs).
fn reference_normal(h: &[f32], x: usize, y: usize) -> [f64; 3] {
    let r = R_M;
    let dy = PI * r / H as f64;
    let lat = (90.0 - 180.0 * (y as f64 + 0.5) / H as f64).to_radians();
    let dx = 2.0 * PI * r * lat.cos() / W as f64;
    let k = (dy / dx).ceil().max(1.0) as usize;
    let at = |xx: usize, yy: usize| f64::from(h[yy * W + xx]);
    let east = (at((x + k) % W, y) - at((x + W - k) % W, y)) / (2.0 * k as f64 * dx);
    let north = if y == 0 {
        (at(x, 0) - at(x, 1)) / dy
    } else if y == H - 1 {
        (at(x, H - 2) - at(x, H - 1)) / dy
    } else {
        (at(x, y - 1) - at(x, y + 1)) / (2.0 * dy)
    };
    let v = [-east, -north, 1.0];
    let len = (v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).sqrt();
    v.map(|c| c / len)
}

/// SplitMix64, used only to pick the 1000 texels from seed 42.
fn splitmix64(state: &mut u64) -> u64 {
    *state = state.wrapping_add(0x9E37_79B9_7F4A_7C15);
    let mut z = *state;
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^ (z >> 31)
}

/// REQ-19 (a): a synthetic plane tilted 10 degrees toward the east gives the analytic
/// normal within 0.01 degrees, before encoding. Rows near the equator are used, where
/// the row's east spacing equals the reference spacing, so the plane is exact.
#[test]
fn req19a_synthetic_plane_tilted_10_deg_east_matches_analytic_normal() {
    let w = 256usize;
    let dx0 = 2.0 * PI * R_M / w as f64;
    let slope = (10.0_f64).to_radians().tan();
    // Height falls toward the east, so the normal leans east: n = (sin 10, 0, cos 10).
    let h: Vec<f32> = (0..H * w).map(|i| (-slope * (i % w) as f64 * dx0) as f32).collect();
    let normals = compute_normals(&h, w, H).expect("normals");
    let analytic = [(10.0_f64).to_radians().sin(), 0.0, (10.0_f64).to_radians().cos()];
    let mut worst: f64 = 0.0;
    for y in [H / 2 - 1, H / 2] {
        for x in 1..w - 1 {
            worst = worst.max(angle_deg(normals[y * w + x], analytic));
        }
    }
    assert!(worst < 0.01, "REQ-19a: worst angle {worst:.5} deg from the analytic normal");
}

/// REQ-19 (b): 1000 texels of the real 4096 level, chosen with seed 42, decode to within
/// 0.6 degrees of an independent recomputation from REQ-13.
#[test]
fn req19b_1000_real_texels_decode_to_the_reference_within_0_6_deg() {
    let h = heights();
    let (w, hgt, ct, bd, rgb) = decode_png(&committed_png());
    assert_eq!((w as usize, hgt as usize), (W, H));
    assert_eq!((ct, bd), (png::ColorType::Rgb, png::BitDepth::Eight));
    let mut state = 42u64;
    let mut worst: f64 = 0.0;
    for _ in 0..1000 {
        let x = (splitmix64(&mut state) % W as u64) as usize;
        let y = (splitmix64(&mut state) % H as u64) as usize;
        let got = decode_texel(&rgb, y * W + x);
        let want = reference_normal(&h, x, y);
        worst = worst.max(angle_deg(got, want));
    }
    assert!(worst <= 0.6, "REQ-19b: worst angle {worst:.4} deg against the reference");
}

/// REQ-19 (c): the texel nearest (43.24 S, 347.34 E) on Tycho's west inner wall faces east
/// and is tilted more than 5 degrees from up.
#[test]
fn req19c_tycho_west_wall_faces_east_and_is_steeper_than_5_deg() {
    let lat: f64 = -43.24;
    let lon: f64 = 347.34;
    let x = (lon / 360.0 * W as f64 - 0.5).round() as usize;
    let y = ((90.0 - lat) / 180.0 * H as f64 - 0.5).round() as usize;
    let (_, _, _, _, rgb) = decode_png(&committed_png());
    let n = decode_texel(&rgb, y * W + x);
    assert!(n[0] > 0.0, "REQ-19c: n_e = {:.4} at texel ({x}, {y}), expected > 0", n[0]);
    let tilt = angle_deg(n, [0.0, 0.0, 1.0]);
    assert!(tilt > 5.0, "REQ-19c: tilt {tilt:.3} deg at texel ({x}, {y}), expected > 5");
}

/// REQ-19 (d): no component of any computed normal is NaN (or infinite).
#[test]
fn req19d_no_component_is_nan() {
    let h = heights();
    let normals = compute_normals(&h, W, H).expect("normals");
    assert_eq!(normals.len(), W * H);
    assert!(normals.iter().all(|n| n.iter().all(|c| c.is_finite())), "REQ-19d: non-finite component");
}

/// REQ-19 (e): two runs of the normal-map step give byte-identical PNGs.
#[test]
fn req19e_two_runs_give_byte_identical_pngs() {
    let mut pngs = Vec::new();
    for run in ["run_a", "run_b"] {
        let root = scratch(&format!("normal_{run}"));
        let elev = root.join("elevation");
        let tex = root.join("textures");
        fs::create_dir_all(&elev).unwrap();
        fs::create_dir_all(&tex).unwrap();
        fs::copy(assets_dir().join("elevation").join(LEVEL), elev.join(LEVEL)).unwrap();
        copy_metadata(&elev);
        normal::run(&elev, &tex).expect("normal-map run");
        pngs.push(fs::read(tex.join(NORMAL_FILE)).unwrap());
    }
    assert!(pngs[0] == pngs[1], "REQ-19e: the two PNGs differ");
}

/// REQ-12: a corrupted copy of the level makes `moon-data normal-map` exit 2 with one error line.
#[test]
fn req12_corrupted_level_exits_2_with_one_error_line() {
    let root = scratch("normal_corrupt");
    let elev = root.join("elevation");
    let tex = root.join("textures");
    fs::create_dir_all(&elev).unwrap();
    fs::create_dir_all(&tex).unwrap();
    let mut bytes = fs::read(assets_dir().join("elevation").join(LEVEL)).unwrap();
    bytes[1000] ^= 0x01;
    fs::write(elev.join(LEVEL), bytes).unwrap();
    copy_metadata(&elev);
    let out = Command::new(env!("CARGO_BIN_EXE_moon-data"))
        .arg("normal-map")
        .arg(&elev)
        .arg(&tex)
        .output()
        .expect("run moon-data");
    let stderr = String::from_utf8_lossy(&out.stderr);
    let errors: Vec<&str> = stderr.lines().filter(|l| l.starts_with("error")).collect();
    assert_eq!(out.status.code(), Some(2), "REQ-12: exit code; stderr: {stderr}");
    assert_eq!(errors.len(), 1, "REQ-12: one error line; stderr: {stderr}");
    assert!(errors[0].contains(LEVEL), "REQ-12: the error line names the level: {}", errors[0]);
    assert!(!tex.join(NORMAL_FILE).exists(), "REQ-12: no PNG is written on error");
}

/// REQ-14 and REQ-15: the committed PNG is 4096 x 2048 RGB8, and its json entry has
/// the required fields and the SHA-256 of the file.
#[test]
fn req14_req15_png_header_and_json_entry() {
    let png_path = committed_png();
    let (w, h, ct, bd, _) = decode_png(&png_path);
    assert_eq!((w, h), (4096, 2048), "REQ-14: size");
    assert_eq!(ct, png::ColorType::Rgb, "REQ-15: colour type");
    assert_eq!(bd, png::BitDepth::Eight, "REQ-15: bit depth");

    let json = fs::read_to_string(assets_dir().join("elevation/moon_data.json")).unwrap();
    let at = json.find("\"normal_map\"").expect("REQ-15: normal_map entry");
    let entry = &json[at..];
    for key in ["\"path\": \"", "\"width\": 4096", "\"height\": 2048", "\"encoding\": \"enu_rgb8\"",
        "\"frame\"", "\"source_level\"", "\"method\": \"central difference, k rule\"", "\"sha256\": \""] {
        assert!(entry.contains(key), "REQ-15: normal_map entry lacks {key}");
    }
    let level = fs::read(assets_dir().join("elevation").join(LEVEL)).unwrap();
    assert!(entry.contains(&sha256::hex_digest(&level)), "REQ-15: source level SHA-256");
    let png_bytes = fs::read(&png_path).unwrap();
    assert!(entry.contains(&sha256::hex_digest(&png_bytes)), "REQ-15: PNG SHA-256 matches the file");
}
