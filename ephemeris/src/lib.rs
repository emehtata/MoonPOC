//! Low-precision Sun direction as seen from the Moon, in the IAU Moon-fixed frame.
//!
//! Methods and references are listed in `ephemeris/README.md`.

use std::f64::consts::PI;

/// Fixed Delta T = TT - UTC in seconds.
pub const DELTA_T_SECONDS: f64 = 69.2;
/// Astronomical unit in km.
pub const AU_KM: f64 = 149_597_870.7;
/// IAU 2015 nominal solar radius in km.
pub const SUN_RADIUS_KM: f64 = 695_700.0;
/// Earth equatorial radius used by the Astronomical Almanac low-precision Moon formula, km.
pub const EARTH_RADIUS_KM: f64 = 6378.14;
/// Julian Date of J2000.0 (TT).
pub const J2000: f64 = 2_451_545.0;
/// Default time used by the CLI.
pub const DEFAULT_UTC: &str = "2026-11-10T00:00:00Z";

pub type Vec3 = [f64; 3];
type Mat3 = [[f64; 3]; 3];

fn rad(d: f64) -> f64 {
    d * PI / 180.0
}

fn deg(r: f64) -> f64 {
    r * 180.0 / PI
}

fn norm360(d: f64) -> f64 {
    let x = d.rem_euclid(360.0);
    if x >= 360.0 {
        0.0
    } else {
        x
    }
}

/// A UTC calendar time.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct UtcTime {
    pub year: i32,
    pub month: u32,
    pub day: u32,
    pub hour: u32,
    pub minute: u32,
    pub second: u32,
}

fn is_leap(y: i32) -> bool {
    (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
}

fn days_in_month(y: i32, m: u32) -> u32 {
    match m {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 if is_leap(y) => 29,
        _ => 28,
    }
}

impl UtcTime {
    /// UTC time for whole seconds since the Unix epoch (civil-from-days, H. Hinnant).
    pub fn from_unix(secs: u64) -> UtcTime {
        let days = (secs / 86400) as i64;
        let sod = (secs % 86400) as u32;
        let z = days + 719_468;
        let era = z.div_euclid(146_097);
        let doe = z - era * 146_097;
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        let mp = (5 * doy + 2) / 153;
        let day = (doy - (153 * mp + 2) / 5 + 1) as u32;
        let month = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
        let year = (yoe + era * 400 + i64::from(month <= 2)) as i32;
        UtcTime { year, month, day, hour: sod / 3600, minute: sod / 60 % 60, second: sod % 60 }
    }

    /// Parses `YYYY-MM-DDTHH:MM:SSZ`, years 1900 to 2100.
    pub fn parse(s: &str) -> Result<UtcTime, String> {
        let b = s.as_bytes();
        let shape_ok = b.len() == 20
            && b[4] == b'-'
            && b[7] == b'-'
            && b[10] == b'T'
            && b[13] == b':'
            && b[16] == b':'
            && b[19] == b'Z'
            && [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18]
                .iter()
                .all(|&i| b[i].is_ascii_digit());
        if !shape_ok {
            return Err(format!(
                "invalid time '{s}': expected YYYY-MM-DDTHH:MM:SSZ"
            ));
        }
        let num = |a: usize, e: usize| s[a..e].parse::<u32>().unwrap();
        let t = UtcTime {
            year: num(0, 4) as i32,
            month: num(5, 7),
            day: num(8, 10),
            hour: num(11, 13),
            minute: num(14, 16),
            second: num(17, 19),
        };
        if !(1900..=2100).contains(&t.year) {
            return Err(format!("invalid time '{s}': year must be 1900 to 2100"));
        }
        if !(1..=12).contains(&t.month) {
            return Err(format!("invalid time '{s}': month out of range"));
        }
        if t.day < 1 || t.day > days_in_month(t.year, t.month) {
            return Err(format!("invalid time '{s}': day out of range"));
        }
        if t.hour > 23 || t.minute > 59 || t.second > 59 {
            return Err(format!("invalid time '{s}': time of day out of range"));
        }
        Ok(t)
    }

    pub fn to_iso(&self) -> String {
        format!(
            "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z",
            self.year, self.month, self.day, self.hour, self.minute, self.second
        )
    }

    /// Julian Date of this UTC time (Meeus ch. 7, Gregorian calendar).
    pub fn jd_utc(&self) -> f64 {
        let day = self.day as f64
            + (self.hour as f64 + (self.minute as f64 + self.second as f64 / 60.0) / 60.0) / 24.0;
        julian_date(self.year, self.month, day)
    }

    /// Julian Date in TT = UTC + Delta T.
    pub fn jd_tt(&self) -> f64 {
        self.jd_utc() + DELTA_T_SECONDS / 86_400.0
    }
}

/// Meeus ch. 7, formula 7.1, Gregorian calendar. `day` may have a fraction.
pub fn julian_date(year: i32, month: u32, day: f64) -> f64 {
    let (mut y, mut m) = (year as f64, month as f64);
    if month <= 2 {
        y -= 1.0;
        m += 12.0;
    }
    let a = (y / 100.0).floor();
    let b = 2.0 - a + (a / 4.0).floor();
    (365.25 * (y + 4716.0)).floor() + (30.6001 * (m + 1.0)).floor() + day + b - 1524.5
}

fn centuries(jd_tt: f64) -> f64 {
    (jd_tt - J2000) / 36_525.0
}

/// Mean obliquity of the ecliptic in degrees (Meeus 22.2).
pub fn mean_obliquity_deg(jd_tt: f64) -> f64 {
    let t = centuries(jd_tt);
    23.0 + 26.0 / 60.0 + 21.448 / 3600.0
        - (46.8150 * t + 0.00059 * t * t - 0.001813 * t * t * t) / 3600.0
}

struct SunOfDate {
    /// Apparent longitude, degrees (mean equinox of date + nutation + aberration).
    lambda: f64,
    /// Obliquity corrected for nutation (Meeus 25.8), degrees.
    eps: f64,
    /// Radius vector in AU.
    r_au: f64,
}

/// Meeus ch. 25, "low accuracy" method.
fn sun_of_date(jd_tt: f64) -> SunOfDate {
    let t = centuries(jd_tt);
    let l0 = 280.46646 + 36000.76983 * t + 0.0003032 * t * t;
    let m = 357.52911 + 35999.05029 * t - 0.0001537 * t * t;
    let e = 0.016708634 - 0.000042037 * t - 0.0000001267 * t * t;
    let mr = rad(m);
    let c = (1.914602 - 0.004817 * t - 0.000014 * t * t) * mr.sin()
        + (0.019993 - 0.000101 * t) * (2.0 * mr).sin()
        + 0.000289 * (3.0 * mr).sin();
    let true_long = l0 + c;
    let v = rad(m + c);
    let r_au = 1.000001018 * (1.0 - e * e) / (1.0 + e * v.cos());
    let omega = rad(125.04 - 1934.136 * t);
    let lambda = true_long - 0.00569 - 0.00478 * omega.sin();
    let eps = mean_obliquity_deg(jd_tt) + 0.00256 * omega.cos();
    SunOfDate { lambda, eps, r_au }
}

/// Apparent geocentric right ascension and declination of the Sun, of date, in degrees,
/// for a TT (TD) Julian Date. Meeus ch. 25 low accuracy (25.6, 25.7).
pub fn sun_apparent_ra_dec(jd_tt: f64) -> (f64, f64) {
    let s = sun_of_date(jd_tt);
    let (l, e) = (rad(s.lambda), rad(s.eps));
    let ra = (e.cos() * l.sin()).atan2(l.cos());
    let dec = (e.sin() * l.sin()).asin();
    (norm360(deg(ra)), deg(dec))
}

/// Geocentric Sun distance in km.
pub fn sun_distance_km(jd_tt: f64) -> f64 {
    sun_of_date(jd_tt).r_au * AU_KM
}

/// Geocentric Moon ecliptic longitude, latitude (degrees, mean equinox of date) and distance (km).
/// Astronomical Almanac low-precision formula (section D).
pub fn moon_ecliptic(jd_tt: f64) -> (f64, f64, f64) {
    let t = centuries(jd_tt);
    let s = |a: f64, b: f64| rad(a + b * t).sin();
    let c = |a: f64, b: f64| rad(a + b * t).cos();
    let lambda = 218.32 + 481_267.881 * t + 6.29 * s(135.0, 477_198.87)
        - 1.27 * s(259.3, -413_335.36)
        + 0.66 * s(235.7, 890_534.22)
        + 0.21 * s(269.9, 954_397.74)
        - 0.19 * s(357.5, 35_999.05)
        - 0.11 * s(186.5, 966_404.03);
    let beta = 5.13 * s(93.3, 483_202.02) + 0.28 * s(228.2, 960_400.89)
        - 0.28 * s(318.3, 6_003.15)
        - 0.17 * s(217.6, -407_332.21);
    let parallax = 0.9508
        + 0.0518 * c(135.0, 477_198.87)
        + 0.0095 * c(259.3, -413_335.36)
        + 0.0078 * c(235.7, 890_534.22)
        + 0.0028 * c(269.9, 954_397.74);
    let dist = EARTH_RADIUS_KM / rad(parallax).sin();
    (norm360(lambda), beta, dist)
}

// Passive (frame) rotation matrices.
fn r1(a: f64) -> Mat3 {
    let (s, c) = a.sin_cos();
    [[1.0, 0.0, 0.0], [0.0, c, s], [0.0, -s, c]]
}
fn r2(a: f64) -> Mat3 {
    let (s, c) = a.sin_cos();
    [[c, 0.0, -s], [0.0, 1.0, 0.0], [s, 0.0, c]]
}
fn r3(a: f64) -> Mat3 {
    let (s, c) = a.sin_cos();
    [[c, s, 0.0], [-s, c, 0.0], [0.0, 0.0, 1.0]]
}
fn mul(a: &Mat3, b: &Mat3) -> Mat3 {
    let mut m = [[0.0; 3]; 3];
    for i in 0..3 {
        for j in 0..3 {
            m[i][j] = (0..3).map(|k| a[i][k] * b[k][j]).sum();
        }
    }
    m
}
fn transpose(a: &Mat3) -> Mat3 {
    let mut m = [[0.0; 3]; 3];
    for i in 0..3 {
        for j in 0..3 {
            m[i][j] = a[j][i];
        }
    }
    m
}
fn apply(a: &Mat3, v: &Vec3) -> Vec3 {
    [
        a[0][0] * v[0] + a[0][1] * v[1] + a[0][2] * v[2],
        a[1][0] * v[0] + a[1][1] * v[1] + a[1][2] * v[2],
        a[2][0] * v[0] + a[2][1] * v[1] + a[2][2] * v[2],
    ]
}

fn spherical(lon_deg: f64, lat_deg: f64, r: f64) -> Vec3 {
    let (lo, la) = (rad(lon_deg), rad(lat_deg));
    [r * la.cos() * lo.cos(), r * la.cos() * lo.sin(), r * la.sin()]
}

/// Precession matrix from the equator of date to J2000 (Meeus ch. 21, IAU 1976, 21.2/21.3).
fn precession_date_to_j2000(jd_tt: f64) -> Mat3 {
    let t = centuries(jd_tt);
    let asec = |x: f64| rad(x / 3600.0);
    let zeta = asec(2306.2181 * t + 0.30188 * t * t + 0.017998 * t * t * t);
    let z = asec(2306.2181 * t + 1.09468 * t * t + 0.018203 * t * t * t);
    let theta = asec(2004.3109 * t - 0.42665 * t * t - 0.041833 * t * t * t);
    // J2000 -> date is R3(-z) R2(theta) R3(-zeta); invert by transposing.
    transpose(&mul(&mul(&r3(-z), &r2(theta)), &r3(-zeta)))
}

/// Ecliptic-of-date vector to J2000 equatorial vector, using obliquity `eps_deg`.
fn ecliptic_of_date_to_j2000(v: &Vec3, eps_deg: f64, jd_tt: f64) -> Vec3 {
    let eq_date = apply(&r1(-rad(eps_deg)), v);
    apply(&precession_date_to_j2000(jd_tt), &eq_date)
}

/// IAU WGCCRE 2009 lunar rotation (Archinal et al. 2011, Table 2): α0, δ0, W in degrees.
pub fn moon_rotation_elements(jd_tt: f64) -> (f64, f64, f64) {
    let d = jd_tt - J2000;
    let t = d / 36_525.0;
    let e = [
        125.045 - 0.0529921 * d,
        250.089 - 0.1059842 * d,
        260.008 + 13.0120009 * d,
        176.625 + 13.3407154 * d,
        357.529 + 0.9856003 * d,
        311.589 + 26.4057084 * d,
        134.963 + 13.0649930 * d,
        276.617 + 0.3287146 * d,
        34.226 + 1.7484877 * d,
        15.134 - 0.1589763 * d,
        119.743 + 0.0036096 * d,
        239.961 + 0.1643573 * d,
        25.053 + 12.9590088 * d,
    ];
    let s = |i: usize| rad(e[i - 1]).sin();
    let c = |i: usize| rad(e[i - 1]).cos();
    let alpha0 = 269.9949 + 0.0031 * t - 3.8787 * s(1) - 0.1204 * s(2) + 0.0700 * s(3)
        - 0.0172 * s(4)
        + 0.0072 * s(6)
        - 0.0052 * s(10)
        + 0.0043 * s(13);
    let delta0 = 66.5392 + 0.0130 * t + 1.5419 * c(1) + 0.0239 * c(2) - 0.0278 * c(3)
        + 0.0068 * c(4)
        - 0.0029 * c(6)
        + 0.0009 * c(7)
        + 0.0008 * c(10)
        - 0.0009 * c(13);
    let w = 38.3213 + 13.17635815 * d - 1.4e-12 * d * d + 3.5610 * s(1) + 0.1208 * s(2)
        - 0.0642 * s(3)
        + 0.0158 * s(4)
        + 0.0252 * s(5)
        - 0.0066 * s(6)
        - 0.0047 * s(7)
        - 0.0046 * s(8)
        + 0.0028 * s(9)
        + 0.0052 * s(10)
        + 0.0040 * s(11)
        + 0.0019 * s(12)
        - 0.0044 * s(13);
    (alpha0, delta0, norm360(w))
}

/// Rotation matrix ICRF/J2000 equatorial -> IAU Moon-fixed.
fn icrf_to_moon_fixed(jd_tt: f64) -> Mat3 {
    let (a0, d0, w) = moon_rotation_elements(jd_tt);
    mul(
        &mul(&r3(rad(w)), &r1(rad(90.0 - d0))),
        &r3(rad(90.0 + a0)),
    )
}

/// Moon-to-Sun result.
#[derive(Debug, Clone, Copy)]
pub struct SunFromMoon {
    pub jd_tt: f64,
    /// Unit vector Moon centre -> Sun centre, IAU Moon-fixed frame.
    pub dir_moon_fixed: Vec3,
    pub subsolar_lon_deg: f64,
    pub subsolar_lat_deg: f64,
    pub distance_km: f64,
    pub angular_diameter_deg: f64,
}

impl SunFromMoon {
    /// Godot local axes: (X, Y, Z) = (y, z, x).
    pub fn dir_godot(&self) -> Vec3 {
        let v = self.dir_moon_fixed;
        [v[1], v[2], v[0]]
    }
}

/// Geocentric Moon vector (Earth centre -> Moon centre) in ICRF/J2000, km, for a TT Julian Date.
pub fn geocentric_moon_j2000_km(jd_tt: f64) -> Vec3 {
    let (ml, mb, md) = moon_ecliptic(jd_tt);
    let moon_ecl = spherical(ml, mb, md);
    ecliptic_of_date_to_j2000(&moon_ecl, mean_obliquity_deg(jd_tt), jd_tt)
}

/// Geocentric Sun vector (Earth centre -> Sun centre) in ICRF/J2000, km.
fn geocentric_sun_j2000_km(jd_tt: f64) -> Vec3 {
    let sun = sun_of_date(jd_tt);
    let sun_ecl = spherical(sun.lambda, 0.0, sun.r_au * AU_KM);
    ecliptic_of_date_to_j2000(&sun_ecl, sun.eps, jd_tt)
}

/// Moon-to-Sun vector in ICRF/J2000 (km) for a TT Julian Date.
pub fn moon_to_sun_j2000_km(jd_tt: f64) -> Vec3 {
    let sun_eq = geocentric_sun_j2000_km(jd_tt);
    let moon_eq = geocentric_moon_j2000_km(jd_tt);
    [
        sun_eq[0] - moon_eq[0],
        sun_eq[1] - moon_eq[1],
        sun_eq[2] - moon_eq[2],
    ]
}

/// Sun direction from the Moon in the Moon-fixed frame for a TT Julian Date.
pub fn sun_from_moon_jd_tt(jd_tt: f64) -> SunFromMoon {
    let v = apply(&icrf_to_moon_fixed(jd_tt), &moon_to_sun_j2000_km(jd_tt));
    let dist = (v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).sqrt();
    let lat = deg((v[2] / dist).asin());
    let lon = norm360(deg(v[1].atan2(v[0])));
    // Direction built from lon/lat so that the vector and angles agree exactly.
    let dir = spherical(lon, lat, 1.0);
    SunFromMoon {
        jd_tt,
        dir_moon_fixed: dir,
        subsolar_lon_deg: lon,
        subsolar_lat_deg: lat,
        distance_km: dist,
        angular_diameter_deg: deg(2.0 * (SUN_RADIUS_KM / dist).asin()),
    }
}

/// Sun direction from the Moon in the Moon-fixed frame for a UTC time.
pub fn sun_from_moon(utc: &UtcTime) -> SunFromMoon {
    sun_from_moon_jd_tt(utc.jd_tt())
}

/// Earth Rotation Angle (IAU 2000) in radians for a UT1 Julian Date (UT1 = UTC here).
pub fn earth_rotation_angle_rad(jd_ut1: f64) -> f64 {
    let turns = 0.7790572732640 + 1.00273781191135448 * (jd_ut1 - J2000);
    2.0 * PI * turns.rem_euclid(1.0)
}

/// Earth as seen from the Moon: position, orientation and Sun direction at Earth.
#[derive(Debug, Clone, Copy)]
pub struct EarthFromMoon {
    /// Moon centre -> Earth centre, km, Godot mapping of the Moon-fixed frame.
    pub pos_godot: Vec3,
    pub distance_km: f64,
    /// Row-major rotation matrix, Earth-fixed -> Godot.
    pub basis_godot: [f64; 9],
    /// Unit vector Earth centre -> Sun centre, Godot mapping.
    pub sun_dir_godot: Vec3,
    pub subsolar_lon_deg: f64,
    pub subsolar_lat_deg: f64,
}

fn to_godot(v: &Vec3) -> Vec3 {
    [v[1], v[2], v[0]]
}

/// Earth data for a UTC time. Pole fixed along ICRF +z, prime meridian angle = ERA.
pub fn earth_from_moon(utc: &UtcTime) -> EarthFromMoon {
    let jd_tt = utc.jd_tt();
    let to_moon = icrf_to_moon_fixed(jd_tt);
    let moon_geo = geocentric_moon_j2000_km(jd_tt);
    let to_earth_fixed = r3(earth_rotation_angle_rad(utc.jd_utc())); // ICRF -> Earth-fixed (passive)
    let earth_fixed_to_moon = mul(&to_moon, &transpose(&to_earth_fixed));
    let m = |i: usize| earth_fixed_to_moon[i];
    // Godot row X = Moon-fixed y, row Y = Moon-fixed z, row Z = Moon-fixed x.
    let rows = [m(1), m(2), m(0)];
    let basis_godot = [
        rows[0][0], rows[0][1], rows[0][2], rows[1][0], rows[1][1], rows[1][2], rows[2][0],
        rows[2][1], rows[2][2],
    ];
    let earth_moon_fixed = apply(&to_moon, &[-moon_geo[0], -moon_geo[1], -moon_geo[2]]);
    let pos_godot = to_godot(&earth_moon_fixed);
    let moon_to_sun = moon_to_sun_j2000_km(jd_tt);
    let toward_sun = [
        moon_to_sun[0] + moon_geo[0],
        moon_to_sun[1] + moon_geo[1],
        moon_to_sun[2] + moon_geo[2],
    ];
    let len = (toward_sun[0].powi(2) + toward_sun[1].powi(2) + toward_sun[2].powi(2)).sqrt();
    let sun_ef = apply(&to_earth_fixed, &toward_sun);
    let lat = deg((sun_ef[2] / len).asin());
    let mut lon = deg(sun_ef[1].atan2(sun_ef[0]));
    if lon <= -180.0 {
        lon += 360.0;
    }
    let local = spherical(lon, lat, 1.0);
    let sun_dir_godot = [
        basis_godot[0] * local[0] + basis_godot[1] * local[1] + basis_godot[2] * local[2],
        basis_godot[3] * local[0] + basis_godot[4] * local[1] + basis_godot[5] * local[2],
        basis_godot[6] * local[0] + basis_godot[7] * local[1] + basis_godot[8] * local[2],
    ];
    EarthFromMoon {
        pos_godot,
        distance_km: (pos_godot[0].powi(2) + pos_godot[1].powi(2) + pos_godot[2].powi(2)).sqrt(),
        basis_godot,
        sun_dir_godot,
        subsolar_lon_deg: lon,
        subsolar_lat_deg: lat,
    }
}

/// JSON object written by the CLI.
pub fn to_json(utc: &UtcTime, s: &SunFromMoon) -> String {
    let v = |a: Vec3| format!("[{}, {}, {}]", a[0], a[1], a[2]);
    let e = earth_from_moon(utc);
    let b = e.basis_godot.iter().map(|x| x.to_string()).collect::<Vec<_>>().join(", ");
    format!(
        "{{\n  \"utc\": \"{}\",\n  \"jd_tt\": {},\n  \"frame\": \"IAU_MOON\",\n  \"sun_dir_moon_fixed\": {},\n  \"sun_dir_godot\": {},\n  \"subsolar_lon_deg\": {},\n  \"subsolar_lat_deg\": {},\n  \"sun_distance_km\": {},\n  \"sun_angular_diameter_deg\": {},\n  \"earth_pos_godot\": {},\n  \"earth_distance_km\": {},\n  \"earth_basis_godot\": [{}],\n  \"earth_sun_dir_godot\": {},\n  \"earth_subsolar_lon_deg\": {},\n  \"earth_subsolar_lat_deg\": {}\n}}",
        utc.to_iso(),
        s.jd_tt,
        v(s.dir_moon_fixed),
        v(s.dir_godot()),
        s.subsolar_lon_deg,
        s.subsolar_lat_deg,
        s.distance_km,
        s.angular_diameter_deg,
        v(e.pos_godot),
        e.distance_km,
        b,
        v(e.sun_dir_godot),
        e.subsolar_lon_deg,
        e.subsolar_lat_deg
    )
}
