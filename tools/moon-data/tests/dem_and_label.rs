//! REQ-5 (label validation), REQ-6 (NoData in the downsampler) and REQ-7
//! (source index rule and per-cell sample counts).

mod common;

use moon_data::dem::{downsample, target_index};
use moon_data::pds::{self, ByteOrder};
use moon_data::Failure;

const LABEL_FILE: &str = "LDEM_64.LBL";

fn real_label() -> String {
    std::fs::read_to_string(common::dem_label()).expect("data/raw/lola_ldem_64/LDEM_64.LBL")
}

/// Replaces the value of the first `KEY = value` line whose key is exactly `key`.
fn set_value(label: &str, key: &str, value: &str) -> String {
    let mut done = false;
    let mut out = String::new();
    for line in label.lines() {
        let trimmed = line.trim_start();
        let is_key = trimmed
            .split_once('=')
            .map(|(k, _)| k.trim() == key)
            .unwrap_or(false);
        if is_key && !done {
            let indent = &line[..line.len() - trimmed.len()];
            out.push_str(&format!("{indent}{key} = {value}\n"));
            done = true;
        } else {
            out.push_str(line);
            out.push('\n');
        }
    }
    assert!(done, "key {key} not found in the label");
    out
}

fn expect_invalid(text: &str, img_size: u64) -> String {
    match pds::validate_dem_label(text, LABEL_FILE, img_size) {
        Err(Failure::Invalid(message)) => message,
        Err(other) => panic!("expected a metadata failure, got {other:?}"),
        Ok(_) => panic!("expected the label to be rejected"),
    }
}

fn real_img_size() -> u64 {
    (common::DEM_SAMPLES * common::DEM_LINES * 2) as u64
}

#[test]
fn req5_real_label_passes_and_values_come_from_the_label() {
    let info = pds::validate_dem_label(&real_label(), LABEL_FILE, real_img_size())
        .expect("the real LDEM_64 label must validate");
    assert_eq!(info.samples, common::DEM_SAMPLES);
    assert_eq!(info.lines, common::DEM_LINES);
    assert_eq!(info.byte_order, ByteOrder::Little, "SAMPLE_TYPE LSB_INTEGER");
    assert_eq!(info.scaling_factor, common::SCALE_M_PER_DN);
    assert_eq!(info.offset_m, 1_737_400.0);
    assert_eq!(info.projection, "SIMPLE CYLINDRICAL");
    assert_eq!(info.pixels_per_degree, 64.0);
    assert_eq!((info.min_lat_deg, info.max_lat_deg), (-90.0, 90.0));
    assert_eq!((info.west_lon_deg, info.east_lon_deg), (0.0, 360.0));
    assert_eq!(info.missing_constant, None, "the label has no missing-constant keyword");
}

#[test]
fn req5_changed_lines_names_file_and_field() {
    // Spec REQ-5 acceptance: LINES changed to 11519 is rejected, naming LDEM_64 and LINES.
    let text = set_value(&real_label(), "LINES", "11519");
    let message = expect_invalid(&text, real_img_size());
    assert!(message.contains("LDEM_64"), "message: {message}");
    assert!(message.contains("LINES"), "message: {message}");
}

#[test]
fn req5_wrong_sample_type_is_rejected_naming_the_field() {
    let text = set_value(&real_label(), "SAMPLE_TYPE", "IEEE_REAL");
    let message = expect_invalid(&text, real_img_size());
    assert!(message.contains("SAMPLE_TYPE"), "message: {message}");
}

#[test]
fn req5_wrong_sample_bits_is_rejected_naming_the_field() {
    let text = set_value(&real_label(), "SAMPLE_BITS", "32");
    let message = expect_invalid(&text, real_img_size());
    assert!(message.contains("SAMPLE_BITS"), "message: {message}");
}

#[test]
fn req5_wrong_projection_is_rejected_naming_the_field() {
    let text = set_value(&real_label(), "MAP_PROJECTION_TYPE", "\"EQUIRECTANGULAR\"");
    let message = expect_invalid(&text, real_img_size());
    assert!(message.contains("MAP_PROJECTION_TYPE"), "message: {message}");
}

#[test]
fn req5_wrong_units_are_rejected_naming_the_field() {
    let text = set_value(&real_label(), "UNIT", "KILOMETER");
    let message = expect_invalid(&text, real_img_size());
    assert!(message.contains("UNIT"), "message: {message}");
}

#[test]
fn req5_wrong_resolution_is_rejected_naming_the_field() {
    let text = set_value(&real_label(), "MAP_RESOLUTION", "128 <pix/deg>");
    let message = expect_invalid(&text, real_img_size());
    assert!(message.contains("LINES"), "message: {message}");
}

#[test]
fn req5_wrong_extent_is_rejected_naming_the_field() {
    let text = set_value(&real_label(), "EASTERNMOST_LONGITUDE", "359");
    let message = expect_invalid(&text, real_img_size());
    assert!(message.contains("EASTERNMOST_LONGITUDE"), "message: {message}");
}

#[test]
fn req5_file_size_must_equal_samples_times_lines_times_two() {
    let message = expect_invalid(&real_label(), real_img_size() - 2);
    assert!(message.contains("file size"), "message: {message}");
    assert!(message.contains("LDEM_64"), "message: {message}");
}

#[test]
fn req5_label_value_is_used_not_the_expected_one() {
    // Spec edge case: a scaling factor other than 0.5 is used as the label says.
    let text = set_value(&real_label(), "SCALING_FACTOR", "0.25");
    let info = pds::validate_dem_label(&text, LABEL_FILE, real_img_size())
        .expect("a positive scaling factor from the label is accepted");
    assert_eq!(info.scaling_factor, 0.25);
}

#[test]
fn req5_missing_constant_keyword_is_read_when_present() {
    let text = format!("{}MISSING_CONSTANT = -32768\n", real_label());
    let info = pds::validate_dem_label(&text, LABEL_FILE, real_img_size()).unwrap();
    assert_eq!(info.missing_constant, Some(-32768));
}

#[test]
fn req5_msb_sample_type_is_big_endian() {
    let text = set_value(&real_label(), "SAMPLE_TYPE", "MSB_INTEGER");
    let info = pds::validate_dem_label(&text, LABEL_FILE, real_img_size()).unwrap();
    assert_eq!(info.byte_order, ByteOrder::Big);
}

// ------------------------------------------------------------------ REQ-6

#[test]
fn req6_block_with_one_missing_cell_is_the_mean_of_its_three_valid_cells() {
    // 4 x 4 source, missing constant -9999 at (0, 0). Block (0..2, 0..2) has 3 valid
    // cells with heights 1, 2, 3 (DN), scaling 1.0, so its mean is 2.0.
    const MISSING: i16 = -9999;
    #[rustfmt::skip]
    let src: Vec<i16> = vec![
        MISSING, 1,      10, 10,
        2,       3,      10, 10,
        20,      20,     30, 30,
        20,      20,     30, 30,
    ];
    let level = downsample(&src, 4, 4, 2, 2, 1.0, Some(MISSING));
    assert_eq!(level.values[0], 2.0, "missing cell must be left out of the mean");
    assert_eq!(level.values[1], 10.0);
    assert_eq!(level.values[2], 20.0);
    assert_eq!(level.values[3], 30.0);
    assert_eq!(level.nodata_count, 0);
}

#[test]
fn req6_all_missing_block_is_nan_and_counted() {
    const MISSING: i16 = -9999;
    #[rustfmt::skip]
    let src: Vec<i16> = vec![
        MISSING, MISSING, 10, 10,
        MISSING, MISSING, 10, 10,
        20,      20,      30, 30,
        20,      20,      30, 30,
    ];
    let level = downsample(&src, 4, 4, 2, 2, 1.0, Some(MISSING));
    assert!(level.values[0].is_nan(), "an all-missing block must be NaN, not a height");
    assert_eq!(level.nodata_count, 1);
    // The missing value itself must never appear as a height.
    assert!(level.values.iter().all(|v| v.is_nan() || *v > -9999.0));
}

#[test]
fn req6_no_missing_constant_means_every_sample_is_a_height() {
    let src: Vec<i16> = vec![-9999, 1, 2, 3];
    let level = downsample(&src, 2, 2, 1, 1, 1.0, None);
    assert_eq!(level.nodata_count, 0);
    assert_eq!(level.values[0], (-9999.0 + 1.0 + 2.0 + 3.0) / 4.0);
}

#[test]
fn req6_scaling_is_applied_to_the_mean_in_metres() {
    let src: Vec<i16> = vec![2, 4, 6, 8];
    let level = downsample(&src, 2, 2, 1, 1, 0.5, None);
    assert_eq!(level.values[0], 2.5);
}

// ------------------------------------------------------------------ REQ-7

/// The REQ-7 index rule written out separately from the library.
fn spec_index(i: usize, s: usize, o: usize) -> usize {
    ((2 * i + 1) * o) / (2 * s)
}

#[test]
fn req7_index_rule_matches_the_spec_formula() {
    for &(s, o) in &[(23040usize, 4096usize), (11520, 2048), (5760, 1024), (8, 4), (7, 3)] {
        for i in 0..s {
            assert_eq!(target_index(i, s, o), spec_index(i, s, o), "i {i} S {s} O {o}");
        }
    }
}

#[test]
fn req7_centre_on_a_cell_boundary_goes_to_the_eastern_or_southern_cell() {
    // 23040 -> 4096: source centre 22.5 is exactly 4 x 5.625, a cell boundary.
    assert_eq!(target_index(22, 23040, 4096), 4);
    // 11520 -> 2048 along latitude: centre 22.5 is also on a boundary (4 x 5.625).
    assert_eq!(target_index(22, 11520, 2048), 4);
}

#[test]
fn req7_each_cell_gets_five_or_six_samples_per_axis_at_4096_wide() {
    for (s, o) in [(common::DEM_SAMPLES, 4096usize), (common::DEM_LINES, 2048usize)] {
        let mut counts = vec![0usize; o];
        for i in 0..s {
            counts[target_index(i, s, o)] += 1;
        }
        assert!(counts.iter().all(|&c| c == 5 || c == 6), "counts {:?}", &counts[..8]);
        assert_eq!(counts.iter().sum::<usize>(), s, "every source sample is used once");
    }
}

#[test]
fn req7_every_output_index_is_reached_in_order() {
    let (s, o) = (common::DEM_SAMPLES, 1024usize);
    let mut last = 0usize;
    for i in 0..s {
        let t = target_index(i, s, o);
        assert!(t >= last && t < o, "index {i} maps to {t}");
        last = t;
    }
    assert_eq!(last, o - 1);
}
