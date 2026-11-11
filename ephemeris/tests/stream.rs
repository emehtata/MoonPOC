//! `--stream` checks from docs/specs/sun-ephemeris-and-sun-disc.md (REQ-23).

use moon_ephemeris::{sun_from_moon, to_json, UtcTime};
use std::io::{BufRead, BufReader};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const NUM_FIELDS: [&str; 7] = [
    "subsolar_lon_deg",
    "subsolar_lat_deg",
    "sun_distance_km",
    "sun_angular_diameter_deg",
    "earth_distance_km",
    "earth_subsolar_lon_deg",
    "earth_subsolar_lat_deg",
];

fn raw_value(text: &str, key: &str) -> String {
    let pat = format!("\"{key}\": ");
    let start = text.find(&pat).unwrap_or_else(|| panic!("field {key} missing in {text}")) + pat.len();
    let rest = &text[start..];
    let end = if rest.starts_with('[') {
        rest.find(']').unwrap() + 1
    } else if rest.starts_with('"') {
        rest[1..].find('"').unwrap() + 2
    } else {
        rest.find([',', '}']).unwrap()
    };
    rest[..end].trim().to_string()
}

fn num(t: &str, k: &str) -> f64 {
    raw_value(t, k).parse().unwrap()
}

fn vec3(t: &str, k: &str) -> Vec<f64> {
    let r = raw_value(t, k);
    let v: Vec<f64> = r.trim_matches(['[', ']']).split(',').map(|s| s.trim().parse().unwrap()).collect();
    assert_eq!(v.len(), 3);
    v
}

fn nums9(t: &str, k: &str) -> Vec<f64> {
    let r = raw_value(t, k);
    let v: Vec<f64> = r.trim_matches(['[', ']']).split(',').map(|s| s.trim().parse().unwrap()).collect();
    assert_eq!(v.len(), 9, "{k} has 9 entries");
    v
}

fn utc_of(t: &str) -> String {
    raw_value(t, "utc").trim_matches('"').to_string()
}

fn one_shot(utc: &str) -> String {
    let out = Command::new(env!("CARGO_BIN_EXE_moon-ephemeris")).arg(utc).output().unwrap();
    assert_eq!(out.status.code(), Some(0));
    String::from_utf8(out.stdout).unwrap()
}

/// All fifteen fields equal within 1e-6 (numbers), exactly (strings).
fn assert_same(streamed: &str, oneshot: &str) {
    assert_eq!(utc_of(streamed), utc_of(oneshot));
    assert_eq!(raw_value(streamed, "frame"), "\"IAU_MOON\"");
    assert_eq!(raw_value(oneshot, "frame"), "\"IAU_MOON\"");
    assert!((num(streamed, "jd_tt") - num(oneshot, "jd_tt")).abs() <= 1e-6);
    for k in ["sun_dir_moon_fixed", "sun_dir_godot", "earth_pos_godot", "earth_sun_dir_godot"] {
        for (a, b) in vec3(streamed, k).iter().zip(vec3(oneshot, k)) {
            assert!((a - b).abs() <= 1e-6, "{k}: {a} vs {b}");
        }
    }
    for k in NUM_FIELDS {
        let (a, b) = (num(streamed, k), num(oneshot, k));
        assert!((a - b).abs() <= 1e-6, "{k}: {a} vs {b}");
    }
    for (a, b) in nums9(streamed, "earth_basis_godot").iter().zip(nums9(oneshot, "earth_basis_godot")) {
        assert!((a - b).abs() <= 1e-6, "earth_basis_godot: {a} vs {b}");
    }
}

fn unix_now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs()
}

#[test]
fn req23_from_unix_gives_whole_second_utc() {
    assert_eq!(UtcTime::from_unix(0).to_iso(), "1970-01-01T00:00:00Z");
    assert_eq!(UtcTime::from_unix(951_782_400).to_iso(), "2000-02-29T00:00:00Z");
    assert_eq!(UtcTime::from_unix(1_794_381_172).to_iso(), "2026-11-11T07:12:52Z");
    assert_eq!(UtcTime::from_unix(4_133_980_799).to_iso(), "2100-12-31T23:59:59Z");
}

#[test]
fn req23_library_stream_time_matches_one_shot_within_1e6() {
    let t = UtcTime::from_unix(1_794_381_172);
    let lib = to_json(&t, &sun_from_moon(&t));
    let parsed = UtcTime::parse("2026-11-11T07:12:52Z").unwrap();
    assert_eq!(t, parsed);
    assert_same(&lib, &one_shot("2026-11-11T07:12:52Z"));
}

#[test]
fn req23_stream_lines_match_one_shot_and_exit_0_on_closed_stdout() {
    let mut child = Command::new(env!("CARGO_BIN_EXE_moon-ephemeris"))
        .arg("--stream")
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .unwrap();
    let mut reader = BufReader::new(child.stdout.take().unwrap());
    let mut lines = Vec::new();
    let before = unix_now();
    for _ in 0..3 {
        let mut l = String::new();
        reader.read_line(&mut l).unwrap();
        assert!(l.ends_with('\n'), "line not newline-terminated: {l:?}");
        lines.push(l.trim_end_matches('\n').to_string());
    }
    let after = unix_now();
    drop(reader); // close our end of stdout
    let start = Instant::now();
    let status = loop {
        if let Some(s) = child.try_wait().unwrap() {
            break s;
        }
        if start.elapsed() > Duration::from_secs(3) {
            child.kill().unwrap();
            child.wait().unwrap();
            panic!("--stream did not exit within 3 s of stdout closing");
        }
        std::thread::sleep(Duration::from_millis(20));
    };
    assert_eq!(status.code(), Some(0), "exit status after stdout closed");

    let mut prev: Option<u64> = None;
    for l in &lines {
        assert!(!l.contains('\n') && l.starts_with('{') && l.ends_with('}'), "compact object: {l}");
        assert_eq!(l.matches("\": ").count(), 15, "exactly fifteen fields (nine Sun + six Earth): {l}");
        let u = utc_of(l);
        let t = UtcTime::parse(&u).expect("utc parses as whole-second ISO time");
        let secs = (0..=after).rev().find(|&s| UtcTime::from_unix(s) == t && s >= before.saturating_sub(1));
        let secs = secs.unwrap_or_else(|| panic!("utc {u} not within the read window"));
        if let Some(p) = prev {
            assert_eq!(secs, p + 1, "utc must increase by 1 s");
        }
        prev = Some(secs);
        assert_same(l, &one_shot(&u));
    }
}
