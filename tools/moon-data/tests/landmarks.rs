//! REQ-26 to REQ-29: measured landmark checks on the generated 4096 x 2048
//! level and the albedo texture. Landmark coordinates are the spec's (IAU
//! Gazetteer). Cell centres follow the REQ-8 convention.

mod common;

use std::f64::consts::PI;

use common::{assets_dir, col_centre_lon, great_circle_deg, read_f32_le, row_centre_lat, RADIUS_KM};
use moon_data::albedo;

const W: usize = 4096;
const H: usize = 2048;

struct Level {
    values: Vec<f32>,
}

impl Level {
    fn load() -> Level {
        let values = read_f32_le(&assets_dir().join("elevation/lola_height_m_4096x2048.f32"));
        assert_eq!(values.len(), W * H);
        Level { values }
    }

    fn at(&self, x: usize, y: usize) -> f32 {
        self.values[y * W + x]
    }
}

/// Crater radius in degrees of arc: half the diameter over the sphere radius.
fn radius_deg(diameter_km: f64) -> f64 {
    (diameter_km / 2.0) / RADIUS_KM * 180.0 / PI
}

struct CraterMeasure {
    ring_mean: f64,
    ring_cells: usize,
    lowest: f64,
    lowest_lat: f64,
    lowest_lon: f64,
    offset_in_r: f64,
    depth: f64,
}

/// REQ-27: depth = mean of the ring 0.9 R to 1.1 R minus the lowest cell within 0.3 R.
fn measure_crater(level: &Level, lat: f64, lon: f64, diameter_km: f64) -> CraterMeasure {
    let r = radius_deg(diameter_km);
    let mut ring_sum = 0.0f64;
    let mut ring_cells = 0usize;
    let mut lowest = f64::INFINITY;
    let mut lowest_lat = f64::NAN;
    let mut lowest_lon = f64::NAN;
    for y in 0..H {
        let cell_lat = row_centre_lat(y, H);
        if (cell_lat - lat).abs() > 1.2 * r {
            continue;
        }
        for x in 0..W {
            let cell_lon = col_centre_lon(x, W);
            let d = great_circle_deg(lat, lon, cell_lat, cell_lon);
            if d >= 0.9 * r && d <= 1.1 * r {
                ring_sum += f64::from(level.at(x, y));
                ring_cells += 1;
            }
            if d <= 0.3 * r && f64::from(level.at(x, y)) < lowest {
                lowest = f64::from(level.at(x, y));
                lowest_lat = cell_lat;
                lowest_lon = cell_lon;
            }
        }
    }
    let ring_mean = ring_sum / ring_cells as f64;
    let offset_deg = great_circle_deg(lat, lon, lowest_lat, lowest_lon);
    CraterMeasure {
        ring_mean,
        ring_cells,
        lowest,
        lowest_lat,
        lowest_lon,
        offset_in_r: offset_deg / r,
        depth: ring_mean - lowest,
    }
}

#[test]
fn req26_global_maximum_is_near_engelgardt_and_high_enough() {
    let level = Level::load();
    let (mut best, mut at) = (f32::NEG_INFINITY, (0, 0));
    for y in 0..H {
        for x in 0..W {
            let v = level.at(x, y);
            if v > best {
                best = v;
                at = (x, y);
            }
        }
    }
    let (lat, lon) = (row_centre_lat(at.1, H), col_centre_lon(at.0, W));
    let dist = great_circle_deg(lat, lon, 5.4, 201.4);
    println!("REQ-26: maximum {best:.1} m at {lat:.3} N, {lon:.3} E, {dist:.3} deg from 5.4 N 201.4 E");
    assert!(dist <= 3.0, "REQ-26: maximum {dist:.3} deg from the highest point");
    assert!(best >= 9000.0, "REQ-26: maximum {best} m is below 9000 m");
}

#[test]
fn req26_global_minimum_is_in_antoniadi_and_deep_enough() {
    let level = Level::load();
    let (mut best, mut at) = (f32::INFINITY, (0, 0));
    for y in 0..H {
        for x in 0..W {
            let v = level.at(x, y);
            if v < best {
                best = v;
                at = (x, y);
            }
        }
    }
    let (lat, lon) = (row_centre_lat(at.1, H), col_centre_lon(at.0, W));
    let dist = great_circle_deg(lat, lon, -70.4, 187.5);
    println!("REQ-26: minimum {best:.1} m at {lat:.3} N, {lon:.3} E, {dist:.3} deg from 70.4 S 187.5 E");
    assert!(dist <= 3.0, "REQ-26: minimum {dist:.3} deg from the Antoniadi point");
    assert!(best <= -8000.0, "REQ-26: minimum {best} m is above -8000 m");
}

#[test]
fn req27_tycho_depth_and_lowest_cell() {
    check_crater("Tycho", -43.31, 348.64, 86.0, 3000.0);
}

#[test]
fn req27_copernicus_depth_and_lowest_cell() {
    check_crater("Copernicus", 9.62, 339.92, 96.0, 2500.0);
}

#[test]
fn req27_theophilus_depth_and_lowest_cell() {
    check_crater("Theophilus", -11.45, 26.28, 99.0, 2500.0);
}

fn check_crater(name: &str, lat: f64, lon: f64, diameter_km: f64, min_depth: f64) {
    let level = Level::load();
    let m = measure_crater(&level, lat, lon, diameter_km);
    println!(
        "REQ-27: {name}: rim ring {:.1} m ({} cells), lowest {:.1} m at {:.3}, {:.3}, depth {:.1} m, offset {:.3} R",
        m.ring_mean, m.ring_cells, m.lowest, m.lowest_lat, m.lowest_lon, m.depth, m.offset_in_r
    );
    assert!(m.depth >= min_depth, "REQ-27: {name} depth {:.1} m is below {min_depth} m", m.depth);
    assert!(m.offset_in_r <= 0.5, "REQ-27: {name} lowest cell is {:.3} R from the centre", m.offset_in_r);
}

#[test]
fn req28_imbrium_is_at_least_1500_m_lower_than_the_far_side_highlands() {
    let level = Level::load();
    let mean_in = |lat0: f64, lat1: f64, lon0: f64, lon1: f64| -> f64 {
        let (mut sum, mut n) = (0.0f64, 0usize);
        for y in 0..H {
            let la = row_centre_lat(y, H);
            if la < lat0 || la > lat1 {
                continue;
            }
            for x in 0..W {
                let lo = col_centre_lon(x, W);
                if lo >= lon0 && lo <= lon1 {
                    sum += f64::from(level.at(x, y));
                    n += 1;
                }
            }
        }
        sum / n as f64
    };
    let imbrium = mean_in(25.0, 45.0, 330.0, 350.0);
    let highlands = mean_in(0.0, 20.0, 180.0, 200.0);
    println!("REQ-28: Imbrium mean {imbrium:.1} m, far-side highlands mean {highlands:.1} m, difference {:.1} m", highlands - imbrium);
    assert!(
        highlands - imbrium >= 1500.0,
        "REQ-28: difference {:.1} m is below 1500 m",
        highlands - imbrium
    );
}

/// Unit vector of a latitude and longitude in degrees (east-positive).
fn unit(lat: f64, lon: f64) -> [f64; 3] {
    let (p, l) = (lat.to_radians(), lon.to_radians());
    [p.cos() * l.sin(), p.cos() * l.cos(), p.sin()]
}

#[test]
fn req29_copernicus_albedo_ejecta_centre_is_within_half_a_degree_of_the_elevation_centre() {
    let level = Level::load();
    let copernicus = measure_crater(&level, 9.62, 339.92, 96.0);
    let (clat, clon) = (copernicus.lowest_lat, copernicus.lowest_lon);
    let r = radius_deg(96.0);

    let png_bytes = std::fs::read(assets_dir().join("textures/lunar_albedo_4096x2048.png")).expect("albedo PNG");
    let png = albedo::decode_png("lunar_albedo_4096x2048.png", &png_bytes).expect("decode albedo");
    assert_eq!((png.width as usize, png.height as usize), (W, H), "REQ-8: albedo is 4096 x 2048");
    let stride = png.channels;

    let albedo_at = |x: usize, y: usize| f64::from(png.data[(y * W + x) * stride]);

    // Mean albedo of the 1.5 R to 3 R annulus around the Copernicus centre.
    let (mut ann_sum, mut ann_n) = (0.0f64, 0usize);
    let mut inner: Vec<(usize, usize, f64, f64)> = Vec::new(); // x, y, albedo, distance in deg
    for y in 0..H {
        let la = row_centre_lat(y, H);
        if (la - clat).abs() > 3.0 * r + 0.1 {
            continue;
        }
        for x in 0..W {
            let lo = col_centre_lon(x, W);
            let d = great_circle_deg(clat, clon, la, lo);
            if d >= 1.5 * r && d <= 3.0 * r {
                ann_sum += albedo_at(x, y);
                ann_n += 1;
            }
            if d <= 1.5 * r {
                inner.push((x, y, albedo_at(x, y), d));
            }
        }
    }
    let ann_mean = ann_sum / ann_n as f64;

    // Albedo-weighted centroid (on the sphere) of the pixels within 1.5 R that are
    // brighter than the annulus mean. The weight is the albedo value.
    let mut acc = [0.0f64; 3];
    let mut acc_unit = [0.0f64; 3];
    let mut used = 0usize;
    for &(x, y, a, _) in &inner {
        if a > ann_mean {
            let u = unit(row_centre_lat(y, H), col_centre_lon(x, W));
            for k in 0..3 {
                acc[k] += a * u[k];
                acc_unit[k] += u[k];
            }
            used += 1;
        }
    }
    let centroid = |v: [f64; 3]| {
        let lat = v[2].atan2((v[0] * v[0] + v[1] * v[1]).sqrt()).to_degrees();
        // unit() is [cos lat sin lon, cos lat cos lon, sin lat], so lon = atan2(x, y).
        let lon = v[0].atan2(v[1]).to_degrees().rem_euclid(360.0);
        (lat, lon)
    };
    let (wlat, wlon) = centroid(acc);
    let (ulat, ulon) = centroid(acc_unit);
    let off_w = great_circle_deg(clat, clon, wlat, wlon);
    let off_u = great_circle_deg(clat, clon, ulat, ulon);
    println!(
        "REQ-29: annulus mean albedo {ann_mean:.2} ({ann_n} px), {used} bright px within 1.5 R; albedo-weighted centroid {wlat:.3}, {wlon:.3}, offset {off_w:.3} deg from the elevation centre {clat:.3}, {clon:.3}; unit-weight centroid offset {off_u:.3} deg"
    );
    assert!(off_w <= 0.5, "REQ-29: albedo ring centre is {off_w:.3} deg from the elevation centre");
}
