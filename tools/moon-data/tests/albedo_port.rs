//! REQ-9 and REQ-10: the albedo regenerated from the ten LROC WAC tiles, compared
//! with the committed texture pixel by pixel.
//!
//! The Milestone 1 PNG (SHA-256 007f09f0...63fd, as first documented) is not in
//! this repository any more: the committed history starts with the texture-prep
//! output (SHA-256 fa62317f...). The reference used here is therefore the
//! committed `assets/textures/lunar_albedo_4096x2048.png`, whose SHA-256 is the
//! one `docs/DATA_SOURCES.md` documents as the `make texture` output.

mod common;

use moon_data::albedo;
use moon_data::sha256;

const COMMITTED_SHA256: &str = "fa62317f9fa40e87a23260adcbd32bf4b1d26e3ca900b0adf6c04d0acba19043";

#[test]
fn req9_regenerated_albedo_has_the_required_size_and_ten_tiles() {
    assert_eq!(albedo::TILES.len(), 10, "REQ-9: ten LROC WAC GMM 100 m tiles");
    assert_eq!((albedo::W, albedo::H), (4096, 2048), "REQ-8: 4096 x 2048 grid");
    let grey = common::regenerate_albedo_grey();
    assert_eq!(grey.len(), albedo::W * albedo::H);
    // Recorded for the report only: the grey values of the source are not checked here.
    let zero = grey.iter().filter(|&&v| v == 0).count();
    println!("REQ-9: {} of {} grey pixels are 0 ({:.4} %)", zero, grey.len(), 100.0 * zero as f64 / grey.len() as f64);
}

#[test]
fn req10_regenerated_albedo_matches_the_committed_texture_pixel_for_pixel() {
    let committed_path = common::assets_dir().join("textures/lunar_albedo_4096x2048.png");
    let committed = std::fs::read(&committed_path).expect("committed albedo PNG");
    assert_eq!(
        sha256::hex_digest(&committed),
        COMMITTED_SHA256,
        "the committed texture is not the documented make-texture output"
    );

    let reference = albedo::decode_png("committed", &committed).expect("decode committed PNG");
    assert_eq!((reference.width, reference.height, reference.channels), (4096, 2048, 3));

    // Rebuild the 8-bit grey and store it as RGB, as the pipeline does.
    let grey = common::regenerate_albedo_grey();
    let png = albedo::encode_rgb_png(&grey).expect("encode");
    let regenerated = albedo::decode_png("regenerated", &png).expect("decode regenerated");

    let diff = albedo::compare_png(&reference, &regenerated).expect("same format");
    println!(
        "REQ-10: pixels compared {}, differing pixels {}, maximum difference {}",
        diff.pixels, diff.differing_pixels, diff.max_difference
    );
    assert_eq!(diff.pixels, 4096 * 2048);
    assert_eq!(diff.differing_pixels, 0, "REQ-10: differing pixels");
    assert_eq!(diff.max_difference, 0, "REQ-10: maximum difference");
}

#[test]
fn req10_comparison_detects_a_single_changed_pixel() {
    // Guards the comparison itself: a one-grey-level change must be counted.
    let grey = vec![100u8; albedo::W * albedo::H];
    let a = albedo::decode_png("a", &albedo::encode_rgb_png(&grey).unwrap()).unwrap();
    let mut changed = grey.clone();
    changed[12345] = 101;
    let b = albedo::decode_png("b", &albedo::encode_rgb_png(&changed).unwrap()).unwrap();
    let diff = albedo::compare_png(&a, &b).unwrap();
    assert_eq!(diff.differing_pixels, 1);
    assert_eq!(diff.max_difference, 1);
}

#[test]
fn req10_encoded_albedo_is_8_bit_rgb_with_equal_channels() {
    let grey: Vec<u8> = (0..albedo::W * albedo::H).map(|i| (i % 251) as u8).collect();
    let png = albedo::decode_png("grey", &albedo::encode_rgb_png(&grey).unwrap()).unwrap();
    assert_eq!((png.channels, png.bit_depth), (3, 8));
    for (k, px) in png.data.chunks_exact(3).enumerate() {
        assert!(px[0] == px[1] && px[1] == px[2], "pixel {k} is not grey");
        assert_eq!(px[0], grey[k]);
    }
}
