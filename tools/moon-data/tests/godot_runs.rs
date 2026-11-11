//! Headless runs of the Godot project (M2 REQ-16, REQ-23, REQ-31).
//!
//! These start the pinned Godot binary in `tools/godot/godot`. The tests skip
//! nothing: if the binary is missing they fail.

mod common;

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use common::{repo_root, scratch};

fn godot() -> PathBuf {
    let path = repo_root().join("tools/godot/godot");
    assert!(path.is_file(), "Godot binary missing at {} (run make setup)", path.display());
    path
}

/// Lines that Godot prints as errors (not counting the X11 display message, which is reported separately).
fn error_lines(text: &str) -> Vec<String> {
    text.lines()
        .filter(|l| l.starts_with("ERROR") || l.starts_with("SCRIPT ERROR") || l.contains("ERROR:"))
        .map(|l| l.to_string())
        .collect()
}

fn combined(out: &std::process::Output) -> String {
    format!("{}{}", String::from_utf8_lossy(&out.stdout), String::from_utf8_lossy(&out.stderr))
}

/// REQ-31 and REQ-16: 10 seconds headless without ERROR or SCRIPT ERROR lines,
/// and exactly one terrain build line.
#[test]
fn req31_req16_ten_second_headless_run_has_no_errors_and_one_build_line() {
    let out = Command::new("timeout")
        .arg("10")
        .arg(godot())
        .args(["--headless", "--path"])
        .arg(repo_root())
        .output()
        .expect("timeout and godot");
    let text = combined(&out);
    // timeout exits with 124 when it stops the process, which is the expected end of this run.
    assert_eq!(out.status.code(), Some(124), "the run should last the full 10 s; output:\n{text}");
    let errors = error_lines(&text);
    assert!(errors.is_empty(), "REQ-31: error lines: {errors:?}");
    let builds = text.lines().filter(|l| l.starts_with("terrain build ms: ")).count();
    assert_eq!(builds, 1, "REQ-16: one terrain build line");
    let x11 = text.lines().filter(|l| l.contains("X11 Display is not available")).count();
    println!("INFO  X11 display message lines in the headless run: {x11}");
}

/// REQ-23: with the 2048 x 1024 height file renamed, one ERROR line names the
/// file, no terrain is built and no fallback surface is made.
#[test]
fn req23_missing_height_file_gives_one_error_line_and_no_terrain() {
    let root = scratch("req23_project");
    let src = repo_root();
    for item in ["project.godot", "scripts", "scenes", "shaders", "assets", ".godot"] {
        copy_tree(&src.join(item), &root.join(item), &["lola_height_m_2048x1024.f32", "lola_height_m_4096x2048.f32"]);
    }
    copy_sun_helper(&src, &root);
    // The copy has no 2048 x 1024 file (as if it had been renamed away).
    assert!(!root.join("assets/elevation/lola_height_m_2048x1024.f32").exists());

    let out = Command::new("timeout")
        .arg("60")
        .arg(godot())
        .args(["--headless", "--quit-after", "30", "--path"])
        .arg(&root)
        .output()
        .expect("timeout and godot");
    let text = combined(&out);
    let errors = error_lines(&text);
    let naming: Vec<&String> = errors.iter().filter(|l| l.contains("lola_height_m_2048x1024.f32")).collect();
    assert_eq!(naming.len(), 1, "REQ-23: one ERROR line naming the file; errors: {errors:?}\n{text}");
    assert_eq!(errors.len(), 1, "REQ-23: only that ERROR line; errors: {errors:?}");
    assert!(!text.lines().any(|l| l.starts_with("terrain build ms: ")), "REQ-23: no terrain is built");
}

/// M3 REQ-17: with the normal map PNG renamed away, one ERROR line names the file,
/// the project keeps running and builds its terrain with vertex normals.
#[test]
fn req17_missing_normal_map_gives_one_error_line_and_terrain_still_builds() {
    let root = scratch("req17_project");
    let src = repo_root();
    let normal = "lunar_normal_enu_4096x2048.png";
    for item in ["project.godot", "scripts", "scenes", "shaders", "assets", ".godot"] {
        copy_tree(&src.join(item), &root.join(item), &[normal]);
    }
    copy_sun_helper(&src, &root);
    assert!(!root.join("assets/textures").join(normal).exists());

    let out = Command::new("timeout")
        .arg("60")
        .arg(godot())
        .args(["--headless", "--quit-after", "30", "--path"])
        .arg(&root)
        .output()
        .expect("timeout and godot");
    let text = combined(&out);
    let errors = error_lines(&text);
    let naming: Vec<&String> = errors.iter().filter(|l| l.contains(normal)).collect();
    assert_eq!(naming.len(), 1, "REQ-17: one ERROR line naming the normal map; errors: {errors:?}\n{text}");
    assert_eq!(errors.len(), 1, "REQ-17: only that ERROR line; errors: {errors:?}");
    assert!(text.lines().any(|l| l.starts_with("terrain build ms: ")), "REQ-17: terrain is still built");
}

/// The Sun helper is started by the project (sun spec REQ-24). Without it the copy would add a
/// second, unrelated ERROR line, so the built helper is copied as well.
fn copy_sun_helper(src: &Path, root: &Path) {
    let helper = "ephemeris/target/x86_64-unknown-linux-musl/release/moon-ephemeris";
    copy_tree(&src.join(helper), &root.join(helper), &[]);
}

/// Copies a directory tree, leaving out files whose names are in `skip`.
fn copy_tree(from: &Path, to: &Path, skip: &[&str]) {
    if from.is_file() {
        fs::create_dir_all(to.parent().unwrap()).unwrap();
        fs::copy(from, to).unwrap();
        return;
    }
    fs::create_dir_all(to).unwrap();
    for entry in fs::read_dir(from).unwrap() {
        let entry = entry.unwrap();
        let name = entry.file_name().to_string_lossy().into_owned();
        if skip.contains(&name.as_str()) {
            continue;
        }
        copy_tree(&entry.path(), &to.join(&name), skip);
    }
}
