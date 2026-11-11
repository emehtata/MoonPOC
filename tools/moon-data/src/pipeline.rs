//! The full run: check the raw files, convert, then write all outputs.
//!
//! Nothing is written until every input has been read and converted. Outputs
//! are first written next to their final place with a `.tmp` suffix and then
//! renamed, so a failed run never replaces an existing output.

use std::fs::{self, File};
use std::io::{BufReader, Read};
use std::path::{Path, PathBuf};

use crate::albedo::{self, GeoRef};
use crate::dem::{BoxAccumulator, Level};
use crate::json::Json;
use crate::pds::{self, ByteOrder, DemInfo};
use crate::sha256::{self, Sha256};
use crate::Failure;

/// Sub-directory and file names inside the raw directory.
pub const DEM_DIR: &str = "lola_ldem_64";
pub const DEM_LABEL: &str = "LDEM_64.LBL";
pub const DEM_IMAGE: &str = "LDEM_64.IMG";
pub const TILE_DIR: &str = "lroc_wac_gmm_100m";

/// Output levels (width, height), largest first.
pub const LEVELS: [(usize, usize); 3] = [(4096, 2048), (2048, 1024), (1024, 512)];
pub const ALBEDO_FILE: &str = "lunar_albedo_4096x2048.png";
pub const METADATA_FILE: &str = "moon_data.json";

/// The grid convention shared by every elevation level and the albedo.
pub const GRID_CONVENTION: &str = "equirectangular, cell-centred: column x centre at longitude \
360*(x+0.5)/W deg E, row y centre at latitude 90-180*(y+0.5)/H deg; row 0 is the northernmost \
row, column 0 starts at 0 deg E";

/// The Rust toolchain pinned for this crate.
const TOOLCHAIN_FILE: &str = include_str!("../rust-toolchain.toml");

pub fn level_file_name(width: usize, height: usize) -> String {
    format!("lola_height_m_{width}x{height}.f32")
}

pub fn toolchain_version() -> String {
    TOOLCHAIN_FILE
        .lines()
        .find_map(|line| line.trim().strip_prefix("channel")?.split('"').nth(1))
        .unwrap_or("unknown")
        .to_string()
}

fn io_error(path: &Path, e: std::io::Error) -> Failure {
    Failure::Other(format!("{}: {e}", path.display()))
}

/// Path text for the metadata file: as given on the command line, with `/`.
pub(crate) fn path_text(path: &Path) -> String {
    path.to_string_lossy().replace('\\', "/")
}

fn sha256_file(path: &Path) -> Result<String, Failure> {
    let mut file = File::open(path).map_err(|e| io_error(path, e))?;
    let mut hasher = Sha256::new();
    let mut buffer = vec![0u8; 1 << 20];
    loop {
        let n = file.read(&mut buffer).map_err(|e| io_error(path, e))?;
        if n == 0 {
            break;
        }
        hasher.update(&buffer[..n]);
    }
    Ok(hasher.finish_hex())
}

/// The DEM after validation, and the tiles' georeferencing.
pub struct Checked {
    pub dem: DemInfo,
    pub label_sha256: String,
    pub tiles: Vec<GeoRef>,
}

/// Checks that every raw file exists and that its metadata is as expected.
/// Reads only the label and the TIFF tags; converts nothing.
pub fn check_sources(raw_dir: &Path) -> Result<Checked, Failure> {
    let dem_dir = raw_dir.join(DEM_DIR);
    let tile_dir = raw_dir.join(TILE_DIR);
    let mut required = vec![dem_dir.join(DEM_LABEL), dem_dir.join(DEM_IMAGE)];
    required.extend(albedo::TILES.iter().map(|(t, _)| tile_dir.join(albedo::tile_file_name(t))));
    let missing: Vec<String> =
        required.iter().filter(|p| !p.is_file()).map(|p| path_text(p)).collect();
    if !missing.is_empty() {
        return Err(Failure::Missing(missing));
    }

    let label_path = dem_dir.join(DEM_LABEL);
    let label_bytes = fs::read(&label_path).map_err(|e| io_error(&label_path, e))?;
    let label_text = String::from_utf8_lossy(&label_bytes);
    let image_path = dem_dir.join(DEM_IMAGE);
    let image_size = fs::metadata(&image_path).map_err(|e| io_error(&image_path, e))?.len();
    let dem = pds::validate_dem_label(&label_text, DEM_LABEL, image_size)?;

    let mut tiles = Vec::new();
    for (tile, extent) in albedo::TILES {
        let name = albedo::tile_file_name(tile);
        let path = tile_dir.join(&name);
        let file = File::open(&path).map_err(|e| io_error(&path, e))?;
        let geo = albedo::read_georef(&name, BufReader::new(file))?;
        albedo::validate_georef(&name, &geo, extent, albedo::SPHERE_RADIUS_M)?;
        tiles.push(geo);
    }
    Ok(Checked { dem, label_sha256: sha256::hex_digest(&label_bytes), tiles })
}

/// Reads the DEM in row strips and builds every level. Returns the levels and
/// the SHA-256 of the raster file.
fn convert_dem(image_path: &Path, dem: &DemInfo) -> Result<(Vec<Level>, String), Failure> {
    let mut accumulators: Vec<BoxAccumulator> = LEVELS
        .iter()
        .map(|&(w, h)| BoxAccumulator::new(dem.samples, dem.lines, w, h, dem.missing_constant))
        .collect();
    let file = File::open(image_path).map_err(|e| io_error(image_path, e))?;
    let mut reader = BufReader::with_capacity(1 << 20, file);
    let mut hasher = Sha256::new();
    let mut bytes = vec![0u8; dem.samples * 2];
    let mut row = vec![0i16; dem.samples];
    for y in 0..dem.lines {
        reader.read_exact(&mut bytes).map_err(|e| io_error(image_path, e))?;
        hasher.update(&bytes);
        for (dn, pair) in row.iter_mut().zip(bytes.chunks_exact(2)) {
            let pair = [pair[0], pair[1]];
            *dn = match dem.byte_order {
                ByteOrder::Little => i16::from_le_bytes(pair),
                ByteOrder::Big => i16::from_be_bytes(pair),
            };
        }
        for acc in &mut accumulators {
            acc.add_row(y, &row);
        }
    }
    let levels = accumulators.into_iter().map(|acc| acc.finish(dem.scaling_factor)).collect();
    Ok((levels, hasher.finish_hex()))
}

/// Builds the grey albedo image. Returns it with each tile's SHA-256.
fn convert_albedo(tile_dir: &Path, tiles: &[GeoRef]) -> Result<(Vec<u8>, Vec<String>), Failure> {
    let mut grey = vec![0u8; albedo::W * albedo::H];
    let mut hashes = Vec::new();
    for ((tile, extent), geo) in albedo::TILES.iter().zip(tiles) {
        let name = albedo::tile_file_name(tile);
        let path = tile_dir.join(&name);
        hashes.push(sha256_file(&path)?);
        let file = File::open(&path).map_err(|e| io_error(&path, e))?;
        let reader = BufReader::with_capacity(1 << 20, file);
        albedo::add_tile(&mut grey, &name, reader, geo, *extent, albedo::SPHERE_RADIUS_M)?;
    }
    Ok((grey, hashes))
}

fn extent_json() -> Json {
    Json::Obj(vec![
        ("lon_west_deg", Json::Num(0.0)),
        ("lon_east_deg", Json::Num(360.0)),
        ("lat_north_deg", Json::Num(90.0)),
        ("lat_south_deg", Json::Num(-90.0)),
    ])
}

fn source_file_json(path: &Path, sha: &str) -> Json {
    Json::Obj(vec![("path", Json::str(path_text(path))), ("sha256", Json::str(sha))])
}

/// Where the outputs go.
pub struct Outputs {
    pub elevation_dir: PathBuf,
    pub textures_dir: PathBuf,
}

/// One produced file.
pub struct Written {
    pub path: PathBuf,
    pub bytes: u64,
    pub sha256: String,
}

/// Runs the whole pipeline. On any failure no output file is created or replaced.
pub fn run(raw_dir: &Path, outputs: &Outputs) -> Result<Vec<Written>, Failure> {
    let checked = check_sources(raw_dir)?;
    let dem = &checked.dem;
    let dem_dir = raw_dir.join(DEM_DIR);
    let tile_dir = raw_dir.join(TILE_DIR);

    let (levels, image_sha) = convert_dem(&dem_dir.join(DEM_IMAGE), dem)?;
    let (grey, tile_shas) = convert_albedo(&tile_dir, &checked.tiles)?;
    let png = albedo::encode_rgb_png(&grey)?;

    let mut files: Vec<(PathBuf, Vec<u8>)> = Vec::new();
    let mut level_entries = Vec::new();
    for level in &levels {
        let path = outputs.elevation_dir.join(level_file_name(level.width, level.height));
        let bytes = level.to_le_bytes();
        let stats = level.stats();
        let stat = |pick: fn(&(f32, f32, f64)) -> f64| stats.as_ref().map_or(Json::Null, |s| Json::Num(pick(s)));
        level_entries.push(Json::Obj(vec![
            ("path", Json::str(path_text(&path))),
            ("width", Json::Int(level.width as u64)),
            ("height", Json::Int(level.height as u64)),
            ("data_type", Json::str("float32")),
            ("byte_order", Json::str("little-endian")),
            ("units", Json::str("m")),
            ("quantity", Json::str("height above the reference sphere")),
            ("grid_convention", Json::str(GRID_CONVENTION)),
            ("extent", extent_json()),
            ("reference_radius_m", Json::Num(dem.offset_m)),
            ("min", stat(|s| f64::from(s.0))),
            ("max", stat(|s| f64::from(s.1))),
            ("mean", stat(|s| s.2)),
            ("nodata_value", Json::str("NaN")),
            ("nodata_count", Json::Int(level.nodata_count)),
            ("sha256", Json::str(sha256::hex_digest(&bytes))),
        ]));
        files.push((path, bytes));
    }

    let albedo_path = outputs.textures_dir.join(ALBEDO_FILE);
    let grey_sum: u64 = grey.iter().map(|&v| u64::from(v)).sum();
    let albedo_entry = Json::Obj(vec![
        ("path", Json::str(path_text(&albedo_path))),
        ("width", Json::Int(albedo::W as u64)),
        ("height", Json::Int(albedo::H as u64)),
        ("data_type", Json::str("uint8 RGB PNG (R = G = B)")),
        ("byte_order", Json::str("not applicable (8-bit samples)")),
        ("units", Json::str("8-bit grey level of the source mosaic")),
        ("grid_convention", Json::str(GRID_CONVENTION)),
        ("extent", extent_json()),
        ("reference_radius_m", Json::Num(albedo::SPHERE_RADIUS_M)),
        ("min", Json::Num(f64::from(grey.iter().copied().min().unwrap_or(0)))),
        ("max", Json::Num(f64::from(grey.iter().copied().max().unwrap_or(0)))),
        ("mean", Json::Num(grey_sum as f64 / grey.len() as f64)),
        ("nodata_value", Json::Null),
        ("nodata_count", Json::Int(0)),
        ("sha256", Json::str(sha256::hex_digest(&png))),
    ]);
    files.push((albedo_path, png));

    let metadata = Json::Obj(vec![
        (
            "generator",
            Json::Obj(vec![
                ("crate", Json::str(env!("CARGO_PKG_NAME"))),
                ("version", Json::str(env!("CARGO_PKG_VERSION"))),
                ("rust_toolchain", Json::str(toolchain_version())),
            ]),
        ),
        ("grid_convention", Json::str(GRID_CONVENTION)),
        ("reference_radius_m", Json::Num(dem.offset_m)),
        (
            "sources",
            Json::Obj(vec![
                (
                    "elevation",
                    Json::Obj(vec![
                        ("product", Json::str(format!("LRO LOLA GDR {}", dem.product_id))),
                        ("product_id", Json::str(&dem.product_id)),
                        ("product_version_id", Json::str(&dem.product_version_id)),
                        ("data_set_id", Json::str(&dem.data_set_id)),
                        ("samples", Json::Int(dem.samples as u64)),
                        ("lines", Json::Int(dem.lines as u64)),
                        ("pixels_per_degree", Json::Num(dem.pixels_per_degree)),
                        ("projection", Json::str(&dem.projection)),
                        ("coordinate_system", Json::str(&dem.coordinate_system)),
                        ("scaling_factor_m_per_dn", Json::Num(dem.scaling_factor)),
                        ("offset_m", Json::Num(dem.offset_m)),
                        (
                            "missing_constant",
                            dem.missing_constant.map_or(Json::Null, |v| Json::Num(f64::from(v))),
                        ),
                        (
                            "files",
                            Json::Arr(vec![
                                source_file_json(&dem_dir.join(DEM_LABEL), &checked.label_sha256),
                                source_file_json(&dem_dir.join(DEM_IMAGE), &image_sha),
                            ]),
                        ),
                    ]),
                ),
                (
                    "albedo",
                    Json::Obj(vec![
                        (
                            "product",
                            Json::str("LROC WAC Global Morphologic Mosaic (WAC_GLOBAL), 100 m/pixel"),
                        ),
                        (
                            "files",
                            Json::Arr(
                                albedo::TILES
                                    .iter()
                                    .zip(&tile_shas)
                                    .map(|((tile, _), sha)| {
                                        source_file_json(
                                            &tile_dir.join(albedo::tile_file_name(tile)),
                                            sha,
                                        )
                                    })
                                    .collect(),
                            ),
                        ),
                    ]),
                ),
            ]),
        ),
        ("elevation_levels", Json::Arr(level_entries)),
        ("albedo", albedo_entry),
    ]);
    files.push((
        outputs.elevation_dir.join(METADATA_FILE),
        metadata.to_pretty_string().into_bytes(),
    ));

    write_all(&files)
}

fn tmp_path(path: &Path) -> PathBuf {
    let mut name = path.as_os_str().to_owned();
    name.push(".tmp");
    PathBuf::from(name)
}

/// Writes every file under a temporary name, then renames them all.
pub(crate) fn write_all(files: &[(PathBuf, Vec<u8>)]) -> Result<Vec<Written>, Failure> {
    let staged = (|| {
        for (path, bytes) in files {
            if let Some(dir) = path.parent() {
                fs::create_dir_all(dir).map_err(|e| io_error(dir, e))?;
            }
            let tmp = tmp_path(path);
            fs::write(&tmp, bytes).map_err(|e| io_error(&tmp, e))?;
        }
        Ok(())
    })();
    if let Err(failure) = staged {
        for (path, _) in files {
            let _ = fs::remove_file(tmp_path(path));
        }
        return Err(failure);
    }
    let mut written = Vec::new();
    for (path, bytes) in files {
        fs::rename(tmp_path(path), path).map_err(|e| io_error(path, e))?;
        written.push(Written {
            path: path.clone(),
            bytes: bytes.len() as u64,
            sha256: sha256::hex_digest(bytes),
        });
    }
    Ok(written)
}
