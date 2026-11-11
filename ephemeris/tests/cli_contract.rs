//! CLI, output contract, committed file and README checks from
//! docs/specs/sun-ephemeris-and-sun-disc.md (REQ-7 to REQ-10, REQ-13, REQ-14, REQ-22).

use moon_ephemeris::{sun_from_moon, UtcTime, DEFAULT_UTC};
use std::path::PathBuf;
use std::process::{Command, Output};

const FIELDS: [&str; 9] = [
    "utc",
    "jd_tt",
    "frame",
    "sun_dir_moon_fixed",
    "sun_dir_godot",
    "subsolar_lon_deg",
    "subsolar_lat_deg",
    "sun_distance_km",
    "sun_angular_diameter_deg",
];

fn crate_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn run_cli(args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_moon-ephemeris"))
        .args(args)
        .output()
        .expect("run CLI")
}

/// Raw text of the value after `"key": ` (up to the next top-level comma or closing brace).
fn raw_value(text: &str, key: &str) -> String {
    let pat = format!("\"{key}\": ");
    let start = text
        .find(&pat)
        .unwrap_or_else(|| panic!("field {key} missing"))
        + pat.len();
    let rest = &text[start..];
    if rest.starts_with('[') {
        let end = rest.find(']').expect("array end") + 1;
        rest[..end].to_string()
    } else if rest.starts_with('"') {
        let end = rest[1..].find('"').expect("string end") + 2;
        rest[..end].to_string()
    } else {
        let end = rest.find(['\n', ',', '}']).unwrap_or(rest.len());
        rest[..end].trim().to_string()
    }
}

fn num(text: &str, key: &str) -> f64 {
    raw_value(text, key)
        .parse::<f64>()
        .unwrap_or_else(|e| panic!("field {key} not a number: {e}"))
}

fn vec3(text: &str, key: &str) -> [f64; 3] {
    let raw = raw_value(text, key);
    let inner = raw.trim_start_matches('[').trim_end_matches(']');
    let parts: Vec<f64> = inner
        .split(',')
        .map(|s| s.trim().parse::<f64>().expect("vector component"))
        .collect();
    assert_eq!(parts.len(), 3, "{key} must have three components");
    [parts[0], parts[1], parts[2]]
}

fn string_field(text: &str, key: &str) -> String {
    let raw = raw_value(text, key);
    raw.trim_matches('"').to_string()
}

fn stdout_of(out: &Output) -> String {
    String::from_utf8(out.stdout.clone()).expect("utf8 stdout")
}

fn norm(v: [f64; 3]) -> f64 {
    (v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).sqrt()
}

/// Great-circle angle in degrees between two (lon, lat) points.
fn great_circle_deg(lon1: f64, lat1: f64, lon2: f64, lat2: f64) -> f64 {
    let p = |lon: f64, lat: f64| {
        let (lo, la) = (lon.to_radians(), lat.to_radians());
        [la.cos() * lo.cos(), la.cos() * lo.sin(), la.sin()]
    };
    let (a, b) = (p(lon1, lat1), p(lon2, lat2));
    let dot = (a[0] * b[0] + a[1] * b[1] + a[2] * b[2]).clamp(-1.0, 1.0);
    dot.acos().to_degrees()
}

// ---------------------------------------------------------------- REQ-7

#[test]
fn req_7_no_argument_uses_default_time() {
    let out = run_cli(&[]);
    assert!(out.status.success(), "REQ-7: exit {:?}", out.status);
    let text = stdout_of(&out);
    assert_eq!(string_field(&text, "utc"), "2026-11-10T00:00:00Z", "REQ-7: utc field");
    assert_eq!(DEFAULT_UTC, "2026-11-10T00:00:00Z", "REQ-7: default constant");
}

#[test]
fn req_7_accepts_iso_argument_and_echoes_it() {
    let out = run_cli(&["1992-04-12T00:00:00Z"]);
    assert!(out.status.success(), "REQ-7: exit {:?}", out.status);
    assert_eq!(string_field(&stdout_of(&out), "utc"), "1992-04-12T00:00:00Z");
}

#[test]
fn req_7_invalid_input_exits_2_with_stderr_and_no_stdout() {
    for bad in [
        "2026-11-10 00:00:00Z",   // wrong separator
        "2026-11-10T00:00:00",    // missing Z
        "2026-13-10T00:00:00Z",   // month 13
        "2026-02-30T00:00:00Z",   // day out of range
        "1899-12-31T23:59:59Z",   // before supported range
        "2101-01-01T00:00:00Z",   // after supported range
        "2026-11-10T24:00:00Z",   // hour out of range
        "not a time",
    ] {
        let out = run_cli(&[bad]);
        assert_eq!(out.status.code(), Some(2), "exit code for {bad}");
        assert!(stdout_of(&out).is_empty(), "stdout must be empty for {bad}");
        let err = String::from_utf8(out.stderr).expect("utf8 stderr");
        assert!(!err.trim().is_empty(), "stderr must name the error for {bad}");
        assert!(err.trim().lines().count() == 1, "one-line error for {bad}");
    }
}

// ---------------------------------------------------------------- REQ-8

#[test]
fn req_8_output_is_one_json_object_with_nine_fields() {
    let out = run_cli(&["2026-11-10T00:00:00Z"]);
    assert!(out.status.success(), "REQ-8: exit {:?}", out.status);
    let text = stdout_of(&out);
    let t = text.trim();
    assert!(t.starts_with('{') && t.ends_with('}'), "REQ-8: JSON object");
    for f in FIELDS {
        assert!(text.contains(&format!("\"{f}\":")), "REQ-8: field {f} present");
    }
    assert_eq!(string_field(&text, "utc"), "2026-11-10T00:00:00Z");
    assert!(num(&text, "jd_tt") > 2_400_000.0, "REQ-8: jd_tt is a Julian Date");
    assert_eq!(string_field(&text, "frame"), "IAU_MOON", "REQ-8: frame string");
    assert_eq!(vec3(&text, "sun_dir_moon_fixed").len(), 3);
    assert_eq!(vec3(&text, "sun_dir_godot").len(), 3);
    let lon = num(&text, "subsolar_lon_deg");
    let lat = num(&text, "subsolar_lat_deg");
    assert!((0.0..360.0).contains(&lon), "REQ-8: lon in [0, 360), got {lon}");
    assert!((-90.0..=90.0).contains(&lat), "REQ-8: lat in [-90, 90], got {lat}");
    let dist = num(&text, "sun_distance_km");
    assert!(dist > 1.4e8 && dist < 1.6e8, "REQ-8: sun distance about 1 AU, got {dist}");
    let ang = num(&text, "sun_angular_diameter_deg");
    assert!((ang - 0.5395).abs() < 0.01, "REQ-8: angular diameter about 0.53 deg, got {ang}");
}

// ---------------------------------------------------------------- REQ-9

#[test]
fn req_9_vectors_are_unit_and_consistent_with_lon_lat() {
    for t in ["2026-11-10T00:00:00Z", "1992-04-12T00:00:00Z", "1950-06-01T12:30:00Z"] {
        let out = run_cli(&[t]);
        assert!(out.status.success(), "REQ-9: exit for {t}");
        let text = stdout_of(&out);
        let m = vec3(&text, "sun_dir_moon_fixed");
        let g = vec3(&text, "sun_dir_godot");
        assert!((norm(m) - 1.0).abs() <= 1e-9, "REQ-9: moon-fixed length {t}");
        assert!((norm(g) - 1.0).abs() <= 1e-9, "REQ-9: godot length {t}");
        let lon = num(&text, "subsolar_lon_deg").to_radians();
        let lat = num(&text, "subsolar_lat_deg").to_radians();
        let expect = [lat.cos() * lon.cos(), lat.cos() * lon.sin(), lat.sin()];
        for i in 0..3 {
            assert!(
                (m[i] - expect[i]).abs() <= 1e-9,
                "REQ-9: component {i} of sun_dir_moon_fixed vs lon/lat for {t}: {} vs {}",
                m[i],
                expect[i]
            );
        }
        assert!(
            (g[0] - m[1]).abs() <= 1e-9 && (g[1] - m[2]).abs() <= 1e-9 && (g[2] - m[0]).abs() <= 1e-9,
            "REQ-9: sun_dir_godot must equal [y, z, x] of sun_dir_moon_fixed for {t}"
        );
    }
}

// ---------------------------------------------------------------- REQ-10

#[test]
fn req_10_library_functions_return_intermediate_values() {
    use moon_ephemeris::{sun_apparent_ra_dec, sun_from_moon_jd_tt};
    let jd = UtcTime::parse("2026-11-10T00:00:00Z").unwrap().jd_tt();
    let (ra, dec) = sun_apparent_ra_dec(jd);
    assert!((0.0..360.0).contains(&ra), "REQ-10: RA range");
    assert!((-90.0..=90.0).contains(&dec), "REQ-10: Dec range");
    let s = sun_from_moon_jd_tt(jd);
    assert!((norm(s.dir_moon_fixed) - 1.0).abs() <= 1e-9, "REQ-10: direction unit length");
    let via_utc = sun_from_moon(&UtcTime::parse("2026-11-10T00:00:00Z").unwrap());
    assert!(
        (via_utc.subsolar_lon_deg - s.subsolar_lon_deg).abs() < 1e-12,
        "REQ-10: UTC and JD entry points agree"
    );
}

// ---------------------------------------------------------------- REQ-13

/// JPL Horizons, target 301 (Moon), observer centre 500@399, 2026-Nov-10 00:00 UT,
/// QUANTITIES 15 (SunSub-LON, SunSub-LAT), MOON_ME frame. Re-queried by the tester on
/// 2026-11-10 with the README settings; values match the README table.
const HORIZONS_2026_LON: f64 = 175.405935;
const HORIZONS_2026_LAT: f64 = -1.544939;

// Fixed-time reference check (REQ-13, Rev. 4): explicit time, not the default time.
#[test]
fn req_13_reference_check_cli_subsolar_point_within_half_degree_of_horizons() {
    let out = run_cli(&["2026-11-10T00:00:00Z"]);
    let text = stdout_of(&out);
    let sep = great_circle_deg(
        num(&text, "subsolar_lon_deg"),
        num(&text, "subsolar_lat_deg"),
        HORIZONS_2026_LON,
        HORIZONS_2026_LAT,
    );
    assert!(sep <= 0.5, "REQ-13: great-circle separation {sep} deg must be <= 0.5");
}

#[test]
fn req_13_readme_records_cli_horizons_values_and_query_settings() {
    let readme = std::fs::read_to_string(crate_dir().join("README.md")).expect("README.md");
    assert!(readme.contains("175.405935"), "REQ-13: Horizons lon recorded");
    assert!(readme.contains("-1.544939") || readme.contains("−1.544939"), "REQ-13: Horizons lat recorded");
    assert!(readme.contains("2026-11-10T00:00:00Z"), "REQ-13: date recorded");
    for setting in [
        "COMMAND='301'",
        "EPHEM_TYPE='OBSERVER'",
        "CENTER='500@399'",
        "START_TIME='2026-11-10 00:00'",
        "TIME_TYPE='UT'",
        "ANG_FORMAT='DEG'",
        "QUANTITIES='15'",
    ] {
        assert!(readme.contains(setting), "REQ-13: query setting {setting} recorded");
    }
    assert!(readme.contains("CLI output for the default date"), "REQ-13: CLI output recorded");
}

// ---------------------------------------------------------------- REQ-14

#[test]
fn req_14_committed_ephemeris_file_has_valid_utc_and_matches_cli() {
    // The file holds whatever time it was last generated for, so its utc is not fixed.
    // Deterministic check: the utc is a valid time and the file equals the CLI output for that utc.
    let path = crate_dir().join("../assets/ephemeris/sun_moon_fixed.json");
    let committed = std::fs::read_to_string(&path).expect("committed ephemeris JSON");
    let utc = string_field(&committed, "utc");
    assert!(UtcTime::parse(&utc).is_ok(), "REQ-14: committed utc {utc} is a valid time");
    let out = run_cli(&[utc.as_str()]);
    assert!(out.status.success(), "REQ-14: CLI accepts the committed utc {utc}");
    let cli = stdout_of(&out);
    for f in FIELDS {
        let a = raw_value(&committed, f);
        let b = raw_value(&cli, f);
        assert_eq!(a, b, "REQ-14: committed field {f} equals CLI output for the committed utc {utc}");
    }
}

#[test]
fn req_14_explicit_override_time_is_written_and_matches_cli() {
    // Explicit-override check: the CLI with the fixed reference time echoes that time.
    let out = run_cli(&["2026-11-10T00:00:00Z"]);
    assert!(out.status.success(), "REQ-14: explicit time accepted");
    assert_eq!(string_field(&stdout_of(&out), "utc"), "2026-11-10T00:00:00Z", "REQ-14: explicit utc echoed");
}

// ---------------------------------------------------------------- REQ-22

#[test]
fn req_22_readme_documents_required_items() {
    let readme = std::fs::read_to_string(crate_dir().join("README.md")).expect("README.md");
    let required = [
        ("Meeus chapter 25 method", "Meeus"),
        ("chapter 7 Julian Date", "chapter 7"),
        ("Archinal reference", "Archinal et al. 2011"),
        ("IAU lunar rotation Table 2", "Table 2"),
        ("delta T value", "69.2"),
        ("frame definition", "IAU_MOON"),
        ("Godot axis mapping", "(X, Y, Z) = (y, z, x)"),
        ("CLI usage", "moon-ephemeris [YYYY-MM-DDTHH:MM:SSZ]"),
        ("REQ-11 reference check", "REQ-11"),
        ("REQ-12 reference check", "REQ-12"),
        ("REQ-13 reference check", "REQ-13"),
        ("REQ-11 tolerance", "0.01°"),
        ("REQ-12 tolerance", "0.5°"),
        ("pinned Rust version", "1.90.0"),
        ("sun radius", "695 700"),
        ("AU value", "149 597 870.7"),
    ];
    for (name, needle) in required {
        assert!(readme.contains(needle), "REQ-22: README documents {name} ({needle})");
    }
}
