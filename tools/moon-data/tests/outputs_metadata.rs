//! REQ-7, REQ-8, REQ-11 (text level): sizes and grid convention of the generated
//! files, and the SHA-256 values recorded in `moon_data.json`. The full field
//! check, including min, max and mean recomputed from the files, is in the
//! Godot suite (`tests/run_tests.gd`).

mod common;

use std::fs;

use common::assets_dir;
use moon_data::sha256;

const LEVELS: [(&str, u64, u64); 3] = [
    ("lola_height_m_4096x2048.f32", 4096, 2048),
    ("lola_height_m_2048x1024.f32", 2048, 1024),
    ("lola_height_m_1024x512.f32", 1024, 512),
];

fn metadata() -> String {
    fs::read_to_string(assets_dir().join("elevation/moon_data.json")).expect("moon_data.json")
}

#[test]
fn req7_level_files_have_the_required_byte_sizes() {
    for (name, w, h) in LEVELS {
        let size = fs::metadata(assets_dir().join("elevation").join(name)).expect(name).len();
        assert_eq!(size, w * h * 4, "REQ-7: {name}");
    }
}

#[test]
fn req8_grid_convention_is_written_for_every_level_and_the_albedo() {
    let json = metadata();
    let convention = "360*(x+0.5)/W deg E, row y centre at latitude 90-180*(y+0.5)/H deg";
    // Three elevation levels, the albedo, and the top-level grid_convention field.
    let count = json.matches(convention).count();
    assert_eq!(count, 5, "REQ-8: convention string in 3 levels, the albedo and the top level, found {count}");
    assert_eq!(json.matches("\"lon_west_deg\": 0.0").count(), 4, "REQ-8: extents of every entry");
    assert_eq!(json.matches("\"lon_east_deg\": 360.0").count(), 4);
    assert_eq!(json.matches("\"lat_north_deg\": 90.0").count(), 4);
    assert_eq!(json.matches("\"lat_south_deg\": -90.0").count(), 4);
}

#[test]
fn req11_metadata_records_the_sha256_of_every_output_file() {
    let json = metadata();
    for (name, _, _) in LEVELS {
        let bytes = fs::read(assets_dir().join("elevation").join(name)).unwrap();
        let sha = sha256::hex_digest(&bytes);
        assert!(json.contains(&sha), "REQ-11: SHA-256 of {name} is in moon_data.json");
    }
    let png = fs::read(assets_dir().join("textures/lunar_albedo_4096x2048.png")).unwrap();
    assert!(json.contains(&sha256::hex_digest(&png)), "REQ-11: SHA-256 of the albedo");
}

#[test]
fn req11_metadata_records_source_hashes_and_generator_versions() {
    let json = metadata();
    for key in ["\"generator\"", "\"crate\": \"moon-data\"", "\"version\": \"0.1.0\"", "\"rust_toolchain\": \"1.90.0\"",
        "\"reference_radius_m\": 1737400.0", "\"nodata_count\"", "\"product_id\": \"LDEM_64\"", "\"sources\""]
    {
        assert!(json.contains(key), "REQ-11: {key} is missing");
    }
    for name in ["LDEM_64.LBL", "LDEM_64.IMG"] {
        let bytes = fs::read(common::raw_dir().join("lola_ldem_64").join(name)).unwrap();
        assert!(json.contains(&sha256::hex_digest(&bytes)), "REQ-11: SHA-256 of {name}");
    }
}
