//! Command-line behaviour (REQ-5 CLI, REQ-13), and the Makefile, toolchain and
//! layout requirements (REQ-3, REQ-4, REQ-35).

mod common;

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use common::{repo_root, scratch};

const TILE_NAMES: [&str; 10] = [
    "E300N0450", "E300N1350", "E300N2250", "E300N3150", "E300S0450", "E300S1350", "E300S2250",
    "E300S3150", "P900N0000", "P900S0000",
];

fn binary() -> &'static str {
    env!("CARGO_BIN_EXE_moon-data")
}

/// Builds a raw directory whose files are symlinks to the real data, except
/// the files named in `skip` (file names), and an optional replacement label.
fn raw_dir_with(root: &Path, skip: &[&str], label_override: Option<String>) -> PathBuf {
    let raw = root.join("raw");
    let dem = raw.join("lola_ldem_64");
    let tiles = raw.join("lroc_wac_gmm_100m");
    fs::create_dir_all(&dem).unwrap();
    fs::create_dir_all(&tiles).unwrap();
    let img = common::dem_image();
    if !skip.contains(&"LDEM_64.IMG") {
        std::os::unix::fs::symlink(&img, dem.join("LDEM_64.IMG")).unwrap();
    }
    match label_override {
        Some(text) => fs::write(dem.join("LDEM_64.LBL"), text).unwrap(),
        None => {
            if !skip.contains(&"LDEM_64.LBL") {
                std::os::unix::fs::symlink(common::dem_label(), dem.join("LDEM_64.LBL")).unwrap();
            }
        }
    }
    for tile in TILE_NAMES {
        let name = format!("WAC_GLOBAL_{tile}_100M.TIF");
        if skip.contains(&name.as_str()) {
            continue;
        }
        std::os::unix::fs::symlink(common::tile_dir().join(&name), tiles.join(&name)).unwrap();
    }
    raw
}

fn run(raw: &Path, elev: &Path, tex: &Path) -> std::process::Output {
    Command::new(binary())
        .arg(raw)
        .arg(elev)
        .arg(tex)
        .output()
        .expect("run moon-data")
}

fn error_lines(out: &std::process::Output) -> Vec<String> {
    String::from_utf8_lossy(&out.stderr)
        .lines()
        .filter(|l| !l.trim().is_empty())
        .map(|l| l.to_string())
        .collect()
}

fn dir_entries(dir: &Path) -> Vec<String> {
    match fs::read_dir(dir) {
        Ok(rd) => {
            let mut names: Vec<String> =
                rd.map(|e| e.unwrap().file_name().to_string_lossy().into_owned()).collect();
            names.sort();
            names
        }
        Err(_) => Vec::new(),
    }
}

// ------------------------------------------------------------------ REQ-5 (CLI)

#[test]
fn req5_cli_label_with_lines_11519_exits_2_names_file_and_field_and_writes_nothing() {
    let root = scratch("req5_cli");
    let label = fs::read_to_string(common::dem_label()).unwrap();
    let mut changed = String::new();
    for line in label.lines() {
        if line.trim_start().starts_with("LINES ") {
            changed.push_str("    LINES                 = 11519\n");
        } else {
            changed.push_str(line);
            changed.push('\n');
        }
    }
    let raw = raw_dir_with(&root, &[], Some(changed));
    let elev = root.join("elev");
    let tex = root.join("tex");
    let out = run(&raw, &elev, &tex);
    let lines = error_lines(&out);
    assert_eq!(out.status.code(), Some(2), "exit code; stderr: {lines:?}");
    assert_eq!(lines.len(), 1, "one error line: {lines:?}");
    assert!(lines[0].contains("LDEM_64"), "{lines:?}");
    assert!(lines[0].contains("LINES"), "{lines:?}");
    assert!(dir_entries(&elev).is_empty(), "no elevation output");
    assert!(dir_entries(&tex).is_empty(), "no texture output");
}

// ------------------------------------------------------------------ REQ-13

#[test]
fn req13_missing_tile_exits_2_with_one_error_line_and_keeps_existing_outputs() {
    let root = scratch("req13_missing_tile");
    let raw = raw_dir_with(&root, &["WAC_GLOBAL_P900S0000_100M.TIF"], None);
    let elev = root.join("elev");
    let tex = root.join("tex");
    fs::create_dir_all(&elev).unwrap();
    fs::create_dir_all(&tex).unwrap();
    let sentinels = [
        (elev.join("lola_height_m_4096x2048.f32"), b"old elevation".to_vec()),
        (elev.join("moon_data.json"), b"{\"old\": true}".to_vec()),
        (tex.join("lunar_albedo_4096x2048.png"), b"old albedo".to_vec()),
    ];
    for (path, bytes) in &sentinels {
        fs::write(path, bytes).unwrap();
    }
    let before = dir_entries(&elev).len() + dir_entries(&tex).len();

    let out = run(&raw, &elev, &tex);
    let lines = error_lines(&out);
    assert_eq!(out.status.code(), Some(2), "exit code; stderr: {lines:?}");
    assert_eq!(lines.len(), 1, "one error line per missing file: {lines:?}");
    assert!(lines[0].contains("WAC_GLOBAL_P900S0000_100M.TIF"), "{lines:?}");

    for (path, bytes) in &sentinels {
        assert_eq!(&fs::read(path).unwrap(), bytes, "{} was changed", path.display());
    }
    let after = dir_entries(&elev).len() + dir_entries(&tex).len();
    assert_eq!(before, after, "no file was added or removed");
    assert!(dir_entries(&elev).iter().all(|n| !n.ends_with(".tmp")));
}

#[test]
fn req13_missing_dem_image_names_the_file() {
    let root = scratch("req13_missing_dem");
    let raw = raw_dir_with(&root, &["LDEM_64.IMG"], None);
    let out = run(&raw, &root.join("elev"), &root.join("tex"));
    let lines = error_lines(&out);
    assert_eq!(out.status.code(), Some(2));
    assert_eq!(lines.len(), 1, "{lines:?}");
    assert!(lines[0].contains("LDEM_64.IMG"), "{lines:?}");
}

#[test]
fn req13_two_missing_files_give_two_error_lines() {
    let root = scratch("req13_two_missing");
    let raw = raw_dir_with(&root, &["WAC_GLOBAL_P900S0000_100M.TIF", "WAC_GLOBAL_E300N0450_100M.TIF"], None);
    let out = run(&raw, &root.join("elev"), &root.join("tex"));
    let lines = error_lines(&out);
    assert_eq!(out.status.code(), Some(2));
    assert_eq!(lines.len(), 2, "{lines:?}");
}

#[test]
fn req4_usage_error_exits_2() {
    let out = Command::new(binary()).output().unwrap();
    assert_eq!(out.status.code(), Some(2));
}

// ------------------------------------------------------------------ REQ-3, REQ-35 (Makefile and toolchain)

fn makefile() -> String {
    fs::read_to_string(repo_root().join("Makefile")).expect("Makefile")
}

#[test]
fn req35_make_help_lists_both_moon_data_targets() {
    let out = Command::new("make")
        .arg("-s")
        .arg("help")
        .current_dir(repo_root())
        .output()
        .expect("make help");
    let text = String::from_utf8_lossy(&out.stdout).to_string();
    assert!(out.status.success(), "make help failed: {text}");
    assert!(text.lines().any(|l| l.trim_start().starts_with("moon-data ")), "{text}");
    assert!(text.lines().any(|l| l.trim_start().starts_with("moon-data-test ")), "{text}");
}

#[test]
fn req35_moon_data_targets_depend_on_require_rust_and_use_the_pinned_toolchain() {
    let mk = makefile();
    assert!(mk.lines().any(|l| l.starts_with("moon-data-test:") && l.contains("require-rust")));
    assert!(mk.lines().any(|l| l.starts_with("moon-data:") && l.contains("require-rust")));
    assert!(mk.contains("tools/moon-data/rust-toolchain.toml"), "toolchain taken from the crate");
    assert!(mk.contains("cargo test --locked") || mk.contains("\"$(CARGO)\" test --locked"), "REQ-3: cargo test --locked");
    assert!(
        mk.contains("build --release --locked"),
        "REQ-4: the build uses --locked"
    );
    let phony = mk.lines().find(|l| l.starts_with(".PHONY")).unwrap_or("");
    assert!(phony.contains("moon-data") && phony.contains("moon-data-test"), ".PHONY: {phony}");
}

#[test]
fn req35_no_python_target_or_script_in_the_moon_pipeline() {
    let mk = makefile().to_lowercase();
    for word in ["python", "venv", "requirements.txt", "prepare_moon_data", "pip "] {
        assert!(!mk.contains(word), "Makefile mentions '{word}'");
    }
    let crate_dir = repo_root().join("tools/moon-data");
    let mut stack = vec![crate_dir.clone()];
    let mut found = Vec::new();
    while let Some(dir) = stack.pop() {
        for entry in fs::read_dir(&dir).unwrap() {
            let path = entry.unwrap().path();
            if path.is_dir() {
                if path.file_name().map_or(false, |n| n != "target") {
                    stack.push(path);
                }
            } else if path.extension().map_or(false, |e| e == "py") {
                found.push(path);
            }
        }
    }
    assert!(found.is_empty(), "Python files in tools/moon-data: {found:?}");
    let root_py = repo_root().join("tools/prepare_moon_data.py");
    assert!(!root_py.exists(), "the retired Python script must not exist");
}

#[test]
fn req35_pinned_toolchain_matches_the_ephemeris_crate() {
    let moon = fs::read_to_string(repo_root().join("tools/moon-data/rust-toolchain.toml")).unwrap();
    let eph = fs::read_to_string(repo_root().join("ephemeris/rust-toolchain.toml")).unwrap();
    let channel = |t: &str| t.lines().find(|l| l.starts_with("channel")).unwrap().to_string();
    assert_eq!(channel(&moon), channel(&eph), "A8: same pinned Rust version");
}

#[test]
fn req4_crate_has_a_committed_lockfile_and_no_build_script() {
    let crate_dir = repo_root().join("tools/moon-data");
    assert!(crate_dir.join("Cargo.lock").is_file(), "Cargo.lock is committed");
    assert!(!crate_dir.join("build.rs").exists(), "no build script");
}

/// Stack and constraints section (not a numbered REQ): extra crates are justified.
#[test]
fn stack_readme_justifies_each_extra_crate() {
    let readme = fs::read_to_string(repo_root().join("tools/moon-data/README.md")).expect("README.md");
    for name in ["tiff", "png"] {
        assert!(readme.contains(&format!("`{name}`")), "README must justify crate {name}");
    }
}
