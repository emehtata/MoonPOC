//! REQ-4, REQ-7, REQ-12: a full run of the binary on the real raw files.
//!
//! The binary runs twice, into the same output directories, and every output
//! file must have the same SHA-256 both times. The elevation levels and the
//! albedo are also compared with the files in `assets/`. The run takes about a
//! minute per pass (`make moon-data` takes about 52 seconds).

mod common;

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use common::{assets_dir, raw_dir, scratch};
use moon_data::sha256;

const LEVEL_FILES: [&str; 3] = [
    "lola_height_m_4096x2048.f32",
    "lola_height_m_2048x1024.f32",
    "lola_height_m_1024x512.f32",
];

/// Name, size in bytes, SHA-256 of every regular file under `dir`.
fn listing(dir: &Path) -> Vec<(String, u64, String)> {
    let mut out = Vec::new();
    for entry in fs::read_dir(dir).expect("directory") {
        let entry = entry.unwrap();
        let path = entry.path();
        if path.is_file() {
            let bytes = fs::read(&path).unwrap();
            out.push((
                entry.file_name().to_string_lossy().into_owned(),
                bytes.len() as u64,
                sha256::hex_digest(&bytes),
            ));
        }
    }
    out.sort();
    out
}

fn run_pipeline(elev: &Path, tex: &Path) {
    let out = Command::new(env!("CARGO_BIN_EXE_moon-data"))
        .arg(raw_dir())
        .arg(elev)
        .arg(tex)
        .output()
        .expect("run moon-data");
    assert!(
        out.status.success(),
        "REQ-4: moon-data exits {:?}: {}",
        out.status.code(),
        String::from_utf8_lossy(&out.stderr)
    );
}

fn raw_listing() -> Vec<(String, u64)> {
    let mut out = Vec::new();
    for sub in ["lola_ldem_64", "lroc_wac_gmm_100m"] {
        for entry in fs::read_dir(raw_dir().join(sub)).unwrap() {
            let entry = entry.unwrap();
            let len = entry.metadata().unwrap().len();
            out.push((format!("{sub}/{}", entry.file_name().to_string_lossy()), len));
        }
    }
    out.sort();
    out
}

#[test]
fn req4_req12_two_runs_give_byte_identical_outputs_and_match_the_assets() {
    let root = scratch("repeatability");
    let elev: PathBuf = root.join("elevation");
    let tex: PathBuf = root.join("textures");
    let raw_before = raw_listing();

    run_pipeline(&elev, &tex);
    let first_elev = listing(&elev);
    let first_tex = listing(&tex);
    assert_eq!(first_elev.len(), 4, "REQ-7/REQ-11: three levels and moon_data.json: {first_elev:?}");
    // REQ-9 (albedo) and M3 REQ-12 (the normal map PNG, written by the same run).
    let tex_names: Vec<&str> = first_tex.iter().map(|(n, _, _)| n.as_str()).collect();
    assert_eq!(tex_names, ["lunar_albedo_4096x2048.png", "lunar_normal_enu_4096x2048.png"],
        "REQ-9 / M3 REQ-12: texture outputs: {first_tex:?}");

    run_pipeline(&elev, &tex);
    let second_elev = listing(&elev);
    let second_tex = listing(&tex);

    // REQ-12: every output file has the same SHA-256 in both runs.
    assert_eq!(first_elev, second_elev, "REQ-12: elevation outputs differ between runs");
    assert_eq!(first_tex, second_tex, "REQ-12: albedo output differs between runs");

    // REQ-4: the raw directory is unchanged by the run (listing and sizes).
    assert_eq!(raw_before, raw_listing(), "REQ-4: raw files changed");

    // REQ-7: sizes of the three levels, and the same bytes as the committed assets.
    let expect = [(4096u64, 2048u64), (2048, 1024), (1024, 512)];
    for (name, (w, h)) in LEVEL_FILES.iter().zip(expect) {
        let size = fs::metadata(elev.join(name)).expect(name).len();
        assert_eq!(size, w * h * 4, "REQ-7: size of {name}");
        let committed = fs::read(assets_dir().join("elevation").join(name)).expect("asset");
        let fresh = fs::read(elev.join(name)).unwrap();
        assert_eq!(committed, fresh, "REQ-12: {name} differs from assets/elevation");
    }
    let committed_tex = fs::read(assets_dir().join("textures/lunar_albedo_4096x2048.png")).unwrap();
    let fresh_tex = fs::read(tex.join("lunar_albedo_4096x2048.png")).unwrap();
    assert_eq!(committed_tex, fresh_tex, "REQ-12: albedo differs from assets/textures");
}
