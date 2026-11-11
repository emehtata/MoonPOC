//! Earth Milestone 1 automated checks: docs/specs/earth-milestone-1-basic-earth.md REQ-1 to REQ-6 and REQ-24 (ephemeris part).
//! Output of the built CLI is parsed as text; intermediate values come from the public library functions.

use moon_ephemeris::{earth_from_moon, earth_rotation_angle_rad, geocentric_moon_j2000_km, moon_rotation_elements,
    moon_to_sun_j2000_km, UtcTime, AU_KM};
use std::f64::consts::PI;
use std::path::PathBuf;
use std::process::Command;

type M3 = [[f64; 3]; 3];

const TIMES: [&str; 5] = [
    "2026-11-10T00:00:00Z",
    "2026-03-20T00:00:00Z",
    "2026-06-21T12:00:00Z",
    "2026-09-23T00:00:00Z",
    "1992-04-12T00:00:00Z",
];

fn r1(a: f64) -> M3 {
    let (s, c) = a.sin_cos();
    [[1.0, 0.0, 0.0], [0.0, c, s], [0.0, -s, c]]
}

fn r3(a: f64) -> M3 {
    let (s, c) = a.sin_cos();
    [[c, s, 0.0], [-s, c, 0.0], [0.0, 0.0, 1.0]]
}

fn mul(a: &M3, b: &M3) -> M3 {
    let mut m = [[0.0; 3]; 3];
    for i in 0..3 {
        for j in 0..3 {
            m[i][j] = (0..3).map(|k| a[i][k] * b[k][j]).sum();
        }
    }
    m
}

fn transpose(m: &M3) -> M3 {
    let mut t = [[0.0; 3]; 3];
    for i in 0..3 {
        for j in 0..3 {
            t[i][j] = m[j][i];
        }
    }
    t
}

fn apply(m: &M3, v: [f64; 3]) -> [f64; 3] {
    let mut o = [0.0; 3];
    for i in 0..3 {
        o[i] = m[i][0] * v[0] + m[i][1] * v[1] + m[i][2] * v[2];
    }
    o
}

fn norm(v: [f64; 3]) -> f64 {
    (v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).sqrt()
}

fn dot(a: [f64; 3], b: [f64; 3]) -> f64 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}

fn cross(a: [f64; 3], b: [f64; 3]) -> [f64; 3] {
    [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
}

/// ICRF -> IAU Moon-fixed, rebuilt from the public IAU WGCCRE elements (same chain as the crate's lunar rotation).
fn icrf_to_moon(jd_tt: f64) -> M3 {
    let (a0, d0, w) = moon_rotation_elements(jd_tt);
    mul(&mul(&r3(w.to_radians()), &r1((90.0 - d0).to_radians())), &r3((90.0 + a0).to_radians()))
}

/// Moon-fixed (x, y, z) -> Godot (X, Y, Z) = (y, z, x).
fn to_godot(v: [f64; 3]) -> [f64; 3] {
    [v[1], v[2], v[0]]
}

/// Godot (X, Y, Z) -> Moon-fixed (x, y, z).
fn from_godot(g: [f64; 3]) -> [f64; 3] {
    [g[2], g[0], g[1]]
}

fn lon_lat_of_moon_fixed(v: [f64; 3]) -> (f64, f64) {
    let lat = (v[2] / norm(v)).asin().to_degrees();
    let lon = v[1].atan2(v[0]).to_degrees();
    (lon, lat)
}

/// Great-circle angle in degrees between two (lon, lat) points.
fn great_circle_deg(lon1: f64, lat1: f64, lon2: f64, lat2: f64) -> f64 {
    let (a, b) = (lon1.to_radians(), lat1.to_radians());
    let (c, d) = (lon2.to_radians(), lat2.to_radians());
    let v = dot([a.cos() * b.cos(), a.sin() * b.cos(), b.sin()], [c.cos() * d.cos(), c.sin() * d.cos(), d.sin()]);
    v.clamp(-1.0, 1.0).acos().to_degrees()
}

fn cli(utc: &str) -> String {
    let out = Command::new(env!("CARGO_BIN_EXE_moon-ephemeris")).arg(utc).output().unwrap();
    assert_eq!(out.status.code(), Some(0), "CLI exit code for {utc}");
    String::from_utf8(out.stdout).unwrap()
}

/// Raw value text after `"key": ` (scalar, string or one-line array).
fn raw(text: &str, key: &str) -> String {
    let pat = format!("\"{key}\": ");
    let start = text.find(&pat).unwrap_or_else(|| panic!("field {key} missing")) + pat.len();
    let rest = &text[start..];
    let end = if rest.starts_with('[') {
        rest.find(']').unwrap() + 1
    } else {
        rest.find([',', '\n']).unwrap_or(rest.len())
    };
    rest[..end].trim().to_string()
}

fn num(text: &str, key: &str) -> f64 {
    raw(text, key).parse().unwrap_or_else(|e| panic!("{key} not a number: {e}"))
}

fn arr(text: &str, key: &str) -> Vec<f64> {
    let r = raw(text, key);
    assert!(r.starts_with('[') && r.ends_with(']'), "{key} is not an array: {r}");
    r[1..r.len() - 1].split(',').map(|s| s.trim().parse().unwrap()).collect()
}

fn v3(text: &str, key: &str) -> [f64; 3] {
    let a = arr(text, key);
    assert_eq!(a.len(), 3, "{key} has 3 entries");
    [a[0], a[1], a[2]]
}

/// Row-major 3x3 from the 9-number `earth_basis_godot` field.
fn basis(text: &str) -> M3 {
    let b = arr(text, "earth_basis_godot");
    assert_eq!(b.len(), 9, "earth_basis_godot has 9 entries");
    [[b[0], b[1], b[2]], [b[3], b[4], b[5]], [b[6], b[7], b[8]]]
}

fn mat_mul_vec(m: &M3, v: [f64; 3]) -> [f64; 3] {
    apply(m, v)
}

const FIFTEEN: [&str; 15] = [
    "utc", "jd_tt", "frame", "sun_dir_moon_fixed", "sun_dir_godot", "subsolar_lon_deg", "subsolar_lat_deg",
    "sun_distance_km", "sun_angular_diameter_deg", "earth_pos_godot", "earth_distance_km", "earth_basis_godot",
    "earth_sun_dir_godot", "earth_subsolar_lon_deg", "earth_subsolar_lat_deg",
];

// ---------------------------------------------------------------- REQ-1

#[test]
fn req1_cli_output_has_nine_sun_fields_and_six_earth_fields_with_types() {
    let text = cli("2026-11-10T00:00:00Z");
    assert_eq!(text.matches("\": ").count(), 15, "REQ-1: fifteen fields");
    for k in FIFTEEN {
        assert!(text.contains(&format!("\"{k}\": ")), "REQ-1: field {k} present");
    }
    assert_eq!(v3(&text, "earth_pos_godot").len(), 3);
    assert!(num(&text, "earth_distance_km") > 3.5e5 && num(&text, "earth_distance_km") < 4.1e5, "REQ-1: distance range");
    assert_eq!(basis(&text).len(), 3);
    assert_eq!(v3(&text, "earth_sun_dir_godot").len(), 3);
    let lon = num(&text, "earth_subsolar_lon_deg");
    let lat = num(&text, "earth_subsolar_lat_deg");
    assert!(lon > -180.0 && lon <= 180.0, "REQ-1: earth_subsolar_lon_deg in (-180, 180], got {lon}");
    assert!((-90.0..=90.0).contains(&lat), "REQ-1: earth_subsolar_lat_deg in [-90, 90], got {lat}");
}

#[test]
fn req1_old_nine_fields_equal_committed_reference_sample_within_1e12() {
    // Values of the nine Sun fields in the committed sample for 2026-11-10T00:00:00Z, before the Earth fields were added.
    let text = cli("2026-11-10T00:00:00Z");
    let jd = num(&text, "jd_tt");
    assert!((jd - 2461354.500800926).abs() <= 1e-12, "REQ-1: jd_tt {jd}");
    let sm = v3(&text, "sun_dir_moon_fixed");
    let want = [-0.9964275535234517, 0.0800268613163577, -0.026978362573017247];
    for k in 0..3 {
        assert!((sm[k] - want[k]).abs() <= 1e-12, "REQ-1: sun_dir_moon_fixed[{k}]");
    }
    let sg = v3(&text, "sun_dir_godot");
    let want_g = [0.0800268613163577, -0.026978362573017247, -0.9964275535234517];
    for k in 0..3 {
        assert!((sg[k] - want_g[k]).abs() <= 1e-12, "REQ-1: sun_dir_godot[{k}]");
    }
    assert!((num(&text, "subsolar_lon_deg") - 175.40821536021815).abs() <= 1e-12, "REQ-1: subsolar_lon_deg");
    assert!((num(&text, "subsolar_lat_deg") + 1.545933882331383).abs() <= 1e-12, "REQ-1: subsolar_lat_deg");
    assert!((num(&text, "sun_distance_km") - 147771651.3542463).abs() <= 1e-12 * 1.5e8, "REQ-1: sun_distance_km");
    assert!((num(&text, "sun_angular_diameter_deg") - 0.5394921244144147).abs() <= 1e-12, "REQ-1: sun_angular_diameter_deg");
    assert_eq!(raw(&text, "frame"), "\"IAU_MOON\"");
}

// ---------------------------------------------------------------- REQ-2

#[test]
fn req2_earth_vectors_are_consistent_for_several_times() {
    for utc in TIMES {
        let text = cli(utc);
        let p = v3(&text, "earth_pos_godot");
        let d = num(&text, "earth_distance_km");
        assert!((d - norm(p)).abs() <= 1e-6, "REQ-2 {utc}: distance {d} vs |pos| {}", norm(p));
        let b = basis(&text);
        for i in 0..3 {
            for j in 0..3 {
                let g: f64 = (0..3).map(|k| b[i][k] * b[j][k]).sum();
                let want = if i == j { 1.0 } else { 0.0 };
                assert!((g - want).abs() <= 1e-9, "REQ-2 {utc}: basis orthonormal [{i}][{j}] = {g}");
            }
        }
        let det = b[0][0] * (b[1][1] * b[2][2] - b[1][2] * b[2][1]) - b[0][1] * (b[1][0] * b[2][2] - b[1][2] * b[2][0])
            + b[0][2] * (b[1][0] * b[2][1] - b[1][1] * b[2][0]);
        assert!((det - 1.0).abs() <= 1e-9, "REQ-2 {utc}: det {det}");
        let s = v3(&text, "earth_sun_dir_godot");
        assert!((norm(s) - 1.0).abs() <= 1e-9, "REQ-2 {utc}: earth_sun_dir length {}", norm(s));
        let lon = num(&text, "earth_subsolar_lon_deg").to_radians();
        let lat = num(&text, "earth_subsolar_lat_deg").to_radians();
        let local = [lat.cos() * lon.cos(), lat.cos() * lon.sin(), lat.sin()];
        let expect = mat_mul_vec(&b, local);
        for k in 0..3 {
            assert!((s[k] - expect[k]).abs() <= 1e-9, "REQ-2 {utc}: earth_sun_dir[{k}] vs basis*lonlat");
        }
    }
}

// ---------------------------------------------------------------- REQ-3

#[test]
fn req3_earth_position_is_negated_geocentric_moon_rotated_by_lunar_rotation() {
    for utc in TIMES {
        let t = UtcTime::parse(utc).unwrap();
        let e = earth_from_moon(&t);
        let moon = geocentric_moon_j2000_km(t.jd_tt());
        let want = to_godot(apply(&icrf_to_moon(t.jd_tt()), [-moon[0], -moon[1], -moon[2]]));
        for k in 0..3 {
            assert!((e.pos_godot[k] - want[k]).abs() <= 1e-6, "REQ-3 {utc}: pos[{k}] {} vs {}", e.pos_godot[k], want[k]);
        }
    }
}

#[test]
fn req3_earth_sun_direction_is_normalised_moon_to_sun_minus_moon_to_earth() {
    for utc in TIMES {
        let t = UtcTime::parse(utc).unwrap();
        let e = earth_from_moon(&t);
        let m2s = moon_to_sun_j2000_km(t.jd_tt());
        let moon = geocentric_moon_j2000_km(t.jd_tt());
        // Earth centre -> Sun = Moon-to-Sun minus Moon-to-Earth (= -geocentric Moon).
        let v = [m2s[0] + moon[0], m2s[1] + moon[1], m2s[2] + moon[2]];
        let n = norm(v);
        let want = to_godot(apply(&icrf_to_moon(t.jd_tt()), [v[0] / n, v[1] / n, v[2] / n]));
        for k in 0..3 {
            assert!((e.sun_dir_godot[k] - want[k]).abs() <= 1e-9, "REQ-3 {utc}: earth_sun_dir[{k}]");
        }
    }
}

// ---------------------------------------------------------------- REQ-4

#[test]
fn req4_earth_pole_is_23_44_deg_from_ecliptic_pole_and_fixed_in_icrf() {
    let eps = 23.4392911_f64.to_radians(); // J2000 mean obliquity
    let ecl_pole_icrf = [0.0, -eps.sin(), eps.cos()];
    let mut icrf_poles = Vec::new();
    for utc in ["2026-03-20T00:00:00Z", "2026-09-23T00:00:00Z"] {
        let t = UtcTime::parse(utc).unwrap();
        let e = earth_from_moon(&t);
        let b = e.basis_godot;
        // Earth pole (0, 0, 1) in Godot: third column of the row-major basis.
        let pole_godot = [b[2], b[5], b[8]];
        let m = icrf_to_moon(t.jd_tt());
        let ecl_godot = to_godot(apply(&m, ecl_pole_icrf));
        let tilt = (dot(pole_godot, ecl_godot) / (norm(pole_godot) * norm(ecl_godot))).clamp(-1.0, 1.0).acos().to_degrees();
        assert!((tilt - 23.44).abs() <= 0.01, "REQ-4 {utc}: tilt {tilt}");
        icrf_poles.push(apply(&transpose(&m), from_godot(pole_godot)));
    }
    for k in 0..3 {
        assert!((icrf_poles[0][k] - icrf_poles[1][k]).abs() <= 1e-9, "REQ-4: ICRF pole identical at both times [{k}]");
    }
}

// ---------------------------------------------------------------- REQ-5

fn earth_x_icrf(utc: &str) -> [f64; 3] {
    let t = UtcTime::parse(utc).unwrap();
    let e = earth_from_moon(&t);
    // Earth-fixed +x in Godot is column 0 of the basis.
    let x_godot = [e.basis_godot[0], e.basis_godot[3], e.basis_godot[6]];
    apply(&transpose(&icrf_to_moon(t.jd_tt())), from_godot(x_godot))
}

#[test]
fn req5_axes_after_one_sidereal_day_agree_within_0_01_deg() {
    let a = earth_x_icrf("2026-11-10T00:00:00Z");
    let b = earth_x_icrf("2026-11-10T23:56:04Z"); // +86164 s
    let ang = dot(a, b).clamp(-1.0, 1.0).acos().to_degrees();
    assert!(ang <= 0.01, "REQ-5: prime meridian moved {ang} deg after one sidereal day");
    let t1 = UtcTime::parse("2026-11-10T00:00:00Z").unwrap();
    let t2 = UtcTime::parse("2026-11-10T23:56:04Z").unwrap();
    assert!((t2.jd_utc() - t1.jd_utc() - 86164.0 / 86400.0).abs() < 1e-9);
}

#[test]
fn req5_prime_meridian_turns_90_deg_east_after_quarter_sidereal_day() {
    let a = earth_x_icrf("2026-11-10T00:00:00Z");
    let b = earth_x_icrf("2026-11-10T05:59:01Z"); // +21541 s
    let z = [0.0, 0.0, 1.0];
    let east = cross(a, b);
    let signed = dot(east, z).atan2(dot(a, b)).to_degrees();
    assert!((signed - 90.0).abs() <= 0.01, "REQ-5: eastward turn {signed} deg (expect 90 +/- 0.01)");
    // Model check on the library function itself.
    let t1 = UtcTime::parse("2026-11-10T00:00:00Z").unwrap();
    let t2 = UtcTime::parse("2026-11-10T05:59:01Z").unwrap();
    let d = (earth_rotation_angle_rad(t2.jd_utc()) - earth_rotation_angle_rad(t1.jd_utc())).rem_euclid(2.0 * PI);
    assert!((d.to_degrees() - 90.0).abs() <= 0.01, "REQ-5: ERA step {}", d.to_degrees());
}

// ---------------------------------------------------------------- REQ-6 (recorded values and the CLI comparison; the live Horizons re-query is pending)

fn readme() -> String {
    let p: PathBuf = [env!("CARGO_MANIFEST_DIR"), "README.md"].iter().collect();
    // README writes negative values with the typographic minus sign (U+2212); compare as ASCII.
    std::fs::read_to_string(p).unwrap().replace('\u{2212}', "-")
}

#[test]
fn req6_readme_records_all_five_horizons_queries_and_settings() {
    let r = readme();
    for s in [
        "COMMAND='301'", "CENTER='500@399'", "QUANTITIES='14'", "COMMAND='399'", "CENTER='500@301'",
        "QUANTITIES='20'", "QUANTITIES='13'", "QUANTITIES='15'", "format=text", "OBJ_DATA='NO'", "MAKE_EPHEM='YES'",
        "EPHEM_TYPE='OBSERVER'", "CSV_FORMAT='NO'", "ANG_FORMAT='DEG'", "3.450226", "6.565800", "175.405935",
        "-1.544939", "0.00267226337481", "6582.073", "0.459544", "23.578619", "ITRF93", "MOON_ME", "0.11",
    ] {
        assert!(r.contains(s), "REQ-6: README records {s}");
    }
}

#[test]
fn req6_cli_values_are_within_tolerance_of_recorded_horizons_values() {
    // Sub-Earth point on the Moon (geocentre observer, Horizons Q14): Moon-fixed direction of earth_pos_godot.
    let text = cli("2026-11-10T00:00:00Z");
    let (lon, lat) = lon_lat_of_moon_fixed(from_godot(v3(&text, "earth_pos_godot")));
    let sep = great_circle_deg(lon, lat, 3.450226, 6.565800);
    assert!(sep <= 0.5, "REQ-6: sub-Earth point separation {sep} deg");
    // Sun sub-point on the Moon (Q15).
    let sun_sep = great_circle_deg(num(&text, "subsolar_lon_deg"), num(&text, "subsolar_lat_deg"), 175.405935, -1.544939);
    assert!(sun_sep <= 0.5, "REQ-6: Sun sub-point separation {sun_sep} deg");
    // Earth distance from the Moon (Q20, delta in au).
    let ref_km = 0.00267226337481 * AU_KM;
    let rel = (num(&text, "earth_distance_km") - ref_km).abs() / ref_km;
    assert!(rel <= 0.002, "REQ-6: distance relative difference {rel}");
    // Apparent diameter (Q13) reference only: the 0.11 % known difference is recorded, not a failure.
    let horizons_deg = 6582.073 / 3600.0;
    let scene_deg = 2.0 * (6371.0 / num(&text, "earth_distance_km")).asin().to_degrees();
    let diff = (horizons_deg - scene_deg).abs() / horizons_deg * 100.0;
    eprintln!("REQ-6 info: apparent diameter scene {scene_deg} deg, Horizons {horizons_deg} deg, difference {diff} % (recorded, not a failure)");
    // Earth subsolar point at 2026-06-21 12:00 UT (Q15, ITRF93, geodetic; CLI geocentric within the tolerance).
    let sub = cli("2026-06-21T12:00:00Z");
    let e_sep = great_circle_deg(num(&sub, "earth_subsolar_lon_deg"), num(&sub, "earth_subsolar_lat_deg"), 0.459544, 23.578619);
    assert!(e_sep <= 0.5, "REQ-6: Earth subsolar separation {e_sep} deg");
}

// ---------------------------------------------------------------- REQ-24 (ephemeris README part)

#[test]
fn req24_ephemeris_readme_documents_earth_model_constants_and_precession_size() {
    let r = readme();
    for s in ["6371.0", "86164.0905", "23.44", "0.7790572732640", "1.00273781191135448", "0.36"] {
        assert!(r.contains(s), "REQ-24: README documents {s}");
    }
    assert!(r.to_lowercase().contains("fixed-pole"), "REQ-24: README documents the fixed-pole approximation");
    assert!(r.contains("Earth fields") && r.contains("earth_pos_godot") && r.contains("earth_subsolar_lat_deg"),
        "REQ-24: README documents the new fields");
}
