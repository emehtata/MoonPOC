//! Reference checks from docs/specs/sun-ephemeris-and-sun-disc.md (REQ-11, REQ-12).
//! Expected values are taken from the spec and must not be changed to match the code.

use moon_ephemeris::{julian_date, sun_apparent_ra_dec, sun_from_moon, UtcTime};
use std::process::Command;

/// REQ-11: Meeus, Astronomical Algorithms 2nd ed., Example 25.a, JDE 2448908.5
/// (1992 October 13, 0h TD). Apparent RA 198.38083 deg, Dec -7.78507 deg, tolerance 0.01 deg.
#[test]
fn req_11_meeus_example_25a_apparent_sun_position() {
    let jde = 2_448_908.5;
    let (ra, dec) = sun_apparent_ra_dec(jde);
    assert!(
        (ra - 198.38083).abs() <= 0.01,
        "REQ-11: apparent RA expected 198.38083 +/- 0.01, got {ra}"
    );
    assert!(
        (dec - (-7.78507)).abs() <= 0.01,
        "REQ-11: apparent Dec expected -7.78507 +/- 0.01, got {dec}"
    );
}

/// REQ-11 (JD input): the Julian Date of 1992-10-13 0h TD is 2448908.5 (Meeus ch. 7).
#[test]
fn req_11_julian_date_of_1992_10_13_is_2448908_5() {
    let jd = julian_date(1992, 10, 13.0);
    assert!((jd - 2_448_908.5).abs() < 1e-9, "REQ-11: JD expected 2448908.5, got {jd}");
}

/// REQ-12: Selenographic Sun position, Meeus Example 53.a (1992 April 12, 0h TD).
/// l0 = 67.89 deg, b0 = 1.46 deg; the CLI/library subsolar point must be within 0.5 deg.
#[test]
fn req_12_meeus_example_53a_subsolar_point_library() {
    let utc = UtcTime::parse("1992-04-12T00:00:00Z").expect("valid time");
    let s = sun_from_moon(&utc);
    assert!(
        (s.subsolar_lon_deg - 67.89).abs() <= 0.5,
        "REQ-12: subsolar_lon_deg expected 67.89 +/- 0.5, got {}",
        s.subsolar_lon_deg
    );
    assert!(
        (s.subsolar_lat_deg - 1.46).abs() <= 0.5,
        "REQ-12: subsolar_lat_deg expected 1.46 +/- 0.5, got {}",
        s.subsolar_lat_deg
    );
}

/// REQ-12: the same check through the CLI binary (stdout JSON).
#[test]
fn req_12_meeus_example_53a_subsolar_point_cli() {
    let out = Command::new(env!("CARGO_BIN_EXE_moon-ephemeris"))
        .arg("1992-04-12T00:00:00Z")
        .output()
        .expect("run CLI");
    assert!(out.status.success(), "REQ-12: CLI exit status {:?}", out.status);
    let text = String::from_utf8(out.stdout).expect("utf8");
    let lon = json_number(&text, "subsolar_lon_deg");
    let lat = json_number(&text, "subsolar_lat_deg");
    assert!(
        (lon - 67.89).abs() <= 0.5,
        "REQ-12: CLI subsolar_lon_deg expected 67.89 +/- 0.5, got {lon}"
    );
    assert!(
        (lat - 1.46).abs() <= 0.5,
        "REQ-12: CLI subsolar_lat_deg expected 1.46 +/- 0.5, got {lat}"
    );
}

/// Extracts a numeric JSON field value by key (the CLI output is flat, one field per line).
fn json_number(text: &str, key: &str) -> f64 {
    let pat = format!("\"{key}\": ");
    let start = text
        .find(&pat)
        .unwrap_or_else(|| panic!("field {key} missing in {text}"))
        + pat.len();
    let rest = &text[start..];
    let end = rest.find([',', '\n']).unwrap_or(rest.len());
    rest[..end].trim().parse::<f64>().unwrap_or_else(|e| panic!("field {key}: {e}"))
}
