# moon-data

Offline data pipeline for the Moon POC. Spec: `docs/specs/moon-elevation-milestone-2.md`.

It reads the LOLA `LDEM_64` elevation model and the ten LROC WAC GMM 100 m tiles from
`data/raw/`, checks their metadata, and writes:

| Output | Content |
|---|---|
| `assets/elevation/lola_height_m_4096x2048.f32` | Height in metres above the 1737.4 km sphere, little-endian float32 |
| `assets/elevation/lola_height_m_2048x1024.f32` | Same, the level the Godot mesh uses |
| `assets/elevation/lola_height_m_1024x512.f32` | Same |
| `assets/textures/lunar_albedo_4096x2048.png` | The albedo texture (same pixels as Milestone 1) |
| `assets/textures/lunar_normal_enu_4096x2048.png` | ENU normal map from the 4096 x 2048 level (Milestone 3; method in `docs/DATA_SOURCES.md`); the first form runs this step last |
| `assets/elevation/moon_data.json` | Size, type, grid, statistics and SHA-256 of every output; source names and SHA-256s; crate and toolchain version |

The sources, their licence and their checksums are documented in `docs/DATA_SOURCES.md`.
Godot reads only the outputs, never the raw files.

## Toolchain

- Rust **1.90.0**, pinned in `rust-toolchain.toml` (the same version as `ephemeris/`),
  installed by `make rust-setup`.
- Build target `x86_64-unknown-linux-musl`, linked with the `rust-lld` that ships with the
  toolchain (`.cargo/config.toml`). The machine has no C compiler or linker, and none is needed.
- No GDAL, no C library, no Python.

## Make targets (run from the repository root)

| Target | Action |
|---|---|
| `make moon-data-test` | `cargo test --locked` in `tools/moon-data/` with the pinned toolchain |
| `make moon-data` | `cargo build --release --locked`, then `moon-data data/raw assets/elevation assets/textures` |
| `make normal-map` | `cargo build --release --locked`, then `moon-data normal-map assets/elevation assets/textures` (Milestone 3 normal map) |

`make moon-data` takes about 50 seconds. Most of that is hashing and decoding 4.6 GB of
TIFF tiles. Running it twice gives byte-identical files.

## Command line

```
moon-data <raw_dir> <elevation_out_dir> <textures_out_dir>
moon-data inspect <raw_dir>
moon-data compare <a.png> <b.png>
moon-data normal-map <elevation_dir> <textures_dir>
```

- The first form runs the pipeline. `<raw_dir>` must contain `lola_ldem_64/LDEM_64.LBL`,
  `lola_ldem_64/LDEM_64.IMG` and `lroc_wac_gmm_100m/WAC_GLOBAL_<TILE>_100M.TIF` for the ten tiles.
- `inspect` runs only the checks and prints the label values and each tile's tie point and
  pixel scale.
- `compare` decodes two PNG files and prints the number of differing pixels and the maximum
  difference.

Exit codes:

| Code | Meaning |
|---|---|
| 0 | Success (`compare`: the images are identical) |
| 1 | I/O or decoding error (`compare`: the images differ) |
| 2 | A raw file is missing (one `error: missing source file: <path>` line per file), a metadata check failed (one `error: <file>: <field>: ...` line), or wrong usage |

Nothing is written before every input has been read and converted. Outputs are written
under a `.tmp` name and then renamed, so a failed run leaves existing outputs unchanged.

## Checks before converting

DEM label (`LDEM_64.LBL`), all read from the label and not hard-coded:

- `LINE_SAMPLES`, `LINES`: positive, and equal to `MAP_RESOLUTION` times the longitude and
  latitude extents.
- `SAMPLE_TYPE` is a signed integer type (`LSB_INTEGER` or `MSB_INTEGER`; the byte order is
  taken from it) and `SAMPLE_BITS` is 16.
- `SCALING_FACTOR` and `OFFSET` are present and positive; `UNIT` is `METER`.
- `MAP_PROJECTION_TYPE` is `SIMPLE CYLINDRICAL`; `POSITIVE_LONGITUDE_DIRECTION` is `EAST`.
- `MAXIMUM_LATITUDE` 90, `MINIMUM_LATITUDE` -90, `WESTERNMOST_LONGITUDE` 0,
  `EASTERNMOST_LONGITUDE` 360.
- `LINE_PROJECTION_OFFSET` and `SAMPLE_PROJECTION_OFFSET` agree with a grid whose first line is
  the northernmost row and whose first sample starts at the western extent.
- `A_AXIS_RADIUS` equals `OFFSET`.
- The size of `LDEM_64.IMG` equals `LINE_SAMPLES` x `LINES` x 2 bytes.
- A missing-data keyword (`MISSING_CONSTANT`, `MISSING`, `NULL_CONSTANT`, `NULL`,
  `CORE_NULL`) is looked for. The current label has none.

LROC tiles: `ModelPixelScaleTag` is 100 m, the raster tie point is pixel (0, 0), and the
tie point's map coordinates and the tile's size in metres match the tile's extent from
`docs/DATA_SOURCES.md` on the 1 737 400 m sphere, to within one pixel (two pixels for the size).

## Elevation levels

Each level is made directly from the 23040 x 11520 source grid. A source sample belongs
to the output cell that contains its centre, and the output value is the plain mean of
those samples times `SCALING_FACTOR`. In integers: source index `i` of `S` goes to output
index `floor((2 i + 1) O / (2 S))` of `O`. The ratios are 5.625, 11.25 and 22.5, so cells
hold 5 or 6, 11 or 12, and 22 or 23 samples per axis. A sample centre that lies exactly
on a cell boundary belongs to the cell that starts there (the eastern or southern one).
Samples equal to the label's missing constant are left out of the mean; a cell with no
valid sample is written as NaN and counted in `nodata_count`. No value is filled in.

Grid of every level and of the albedo: column `x` centre at longitude
`360 (x + 0.5) / W` degrees East, row `y` centre at latitude `90 - 180 (y + 0.5) / H` degrees.

## Albedo

The processing is the Milestone 1 processing (see `docs/DATA_SOURCES.md`). The box-filter
resampler is not copied: `src/lib.rs` compiles `tools/texture-prep/src/resample.rs` into
this crate, so both tools use the same code. The PNG encoder and its settings are also the
same, and the PNG file is byte-identical to the one `make texture` writes.

## Memory and time

Measured with `/usr/bin/time -v make moon-data` on the development machine (4 cores):
peak resident memory 553 MB, wall time 52 s. The DEM is read one row at a time (46 080
bytes). The peak comes from one decoded equatorial tile (27291 x 18194 bytes).

## Dependencies

Direct dependencies are pinned to exact versions in `Cargo.toml`; all others are fixed by
the committed `Cargo.lock`, and builds use `--locked`.

| Crate | Version | Reason |
|---|---|---|
| `tiff` | 0.9.1 | Decodes the LROC GeoTIFF tiles and reads the `ModelTiepointTag` and `ModelPixelScaleTag` values |
| `png` | 0.18.1 | Writes the albedo PNG; reads PNG files for `compare` |

Transitive: `adler2` 2.0.1, `bitflags` 2.13.2, `cfg-if` 1.0.5, `crc32fast` 1.4.2,
`fdeflate` 0.3.7, `flate2` 1.1.11, `jpeg-decoder` 0.3.2, `miniz_oxide` 0.8.9 and 0.9.1,
`simd-adler32` 0.3.10, `weezl` 0.1.12. These are the versions `tools/texture-prep/` uses.

Crates the spec allows but this crate does not use:

- `serde` / `serde_json` and `sha2`: their dependency trees contain build scripts or
  procedural macros. Those are compiled for the host and need a host C linker, which this
  machine does not have (the same reason `tiff` stays at 0.9.1). The metadata file is
  written by the small writer in `src/json.rs`, and SHA-256 is implemented in
  `src/sha256.rs` (FIPS 180-4). The pipeline's SHA-256 values agree with `sha256sum` for
  every raw and generated file.

The PDS3 label reader (`src/pds.rs`) and the raw-grid reader are written here and use only
the standard library.
