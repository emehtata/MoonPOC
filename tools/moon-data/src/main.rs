//! Command-line entry of the Moon data pipeline.
//!
//! Usage:
//!   moon-data <raw_dir> <elevation_out_dir> <textures_out_dir>
//!   moon-data inspect <raw_dir>
//!   moon-data compare <a.png> <b.png>
//!   moon-data normal-map <elevation_dir> <textures_dir>
//!
//! Exit codes: 0 success; 1 I/O or decoding error, or `compare` found a
//! difference; 2 missing source file, failed metadata check, or wrong usage.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use moon_data::pipeline::{self, Outputs};
use moon_data::{albedo, normal, Failure};

fn build(raw_dir: &str, elevation_dir: &str, textures_dir: &str) -> Result<bool, Failure> {
    let outputs = Outputs {
        elevation_dir: PathBuf::from(elevation_dir),
        textures_dir: PathBuf::from(textures_dir),
    };
    print_written(&pipeline::run(Path::new(raw_dir), &outputs)?);
    // REQ-12: the normal map step runs last, the same as `moon-data normal-map`.
    normal_map(elevation_dir, textures_dir)
}

fn print_written(files: &[pipeline::Written]) {
    for file in files {
        println!("{}  {}  ({} bytes)", file.sha256, file.path.display(), file.bytes);
    }
}

/// Builds the ENU normal map from the 4096 x 2048 level and adds it to moon_data.json.
fn normal_map(elevation_dir: &str, textures_dir: &str) -> Result<bool, Failure> {
    print_written(&normal::run(Path::new(elevation_dir), Path::new(textures_dir))?);
    Ok(true)
}

/// Prints the validated DEM label values and each tile's georeferencing.
fn inspect(raw_dir: &str) -> Result<bool, Failure> {
    let checked = pipeline::check_sources(Path::new(raw_dir))?;
    println!("{}: sha256 {}", pipeline::DEM_LABEL, checked.label_sha256);
    println!("{:#?}", checked.dem);
    for ((tile, _), geo) in albedo::TILES.iter().zip(&checked.tiles) {
        println!(
            "{}: {} x {} px, tie point {:?}, pixel scale {:?}",
            albedo::tile_file_name(tile),
            geo.width,
            geo.height,
            geo.tiepoint,
            geo.pixel_scale
        );
    }
    Ok(true)
}

/// Decodes two PNG files and compares format and every sample.
fn compare(a_path: &str, b_path: &str) -> Result<bool, Failure> {
    let read = |path: &str| {
        let bytes = fs::read(path).map_err(|e| Failure::Other(format!("{path}: {e}")))?;
        albedo::decode_png(path, &bytes)
    };
    let (a, b) = (read(a_path)?, read(b_path)?);
    for (label, p) in [("a", &a), ("b", &b)] {
        println!(
            "{label}: {}x{}, {} channels, {}-bit",
            p.width, p.height, p.channels, p.bit_depth
        );
    }
    match albedo::compare_png(&a, &b) {
        None => {
            println!("format differs");
            Ok(false)
        }
        Some(diff) => {
            println!("pixels compared: {}", diff.pixels);
            println!("differing pixels: {}", diff.differing_pixels);
            println!("maximum difference: {}", diff.max_difference);
            Ok(diff.differing_pixels == 0)
        }
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let result = match args.as_slice() {
        [cmd, raw_dir] if cmd == "inspect" => inspect(raw_dir),
        [cmd, a, b] if cmd == "compare" => compare(a, b),
        [cmd, e, t] if cmd == "normal-map" => normal_map(e, t),
        [raw_dir, elevation_dir, textures_dir] => build(raw_dir, elevation_dir, textures_dir),
        _ => {
            eprintln!("usage: moon-data <raw_dir> <elevation_out_dir> <textures_out_dir>");
            eprintln!("       moon-data inspect <raw_dir>");
            eprintln!("       moon-data compare <a.png> <b.png>");
            eprintln!("       moon-data normal-map <elevation_dir> <textures_dir>");
            return ExitCode::from(2);
        }
    };
    match result {
        Ok(true) => ExitCode::SUCCESS,
        Ok(false) => ExitCode::FAILURE,
        Err(failure) => {
            for line in failure.lines() {
                eprintln!("{line}");
            }
            ExitCode::from(failure.exit_code())
        }
    }
}
