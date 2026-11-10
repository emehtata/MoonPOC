# Data sources

This file documents every external dataset used by the Moon POC. Raw downloads live in `data/raw/`, are never committed (see `.gitignore`), and are never loaded by Godot. Only the processed files under `assets/` are used by the project.

## Lunar albedo texture (Milestone 1)

| Item | Value |
|---|---|
| Product | LROC WAC Global Morphologic Mosaic (GMM), WAC 643 nm, "WAC_GLOBAL" RDR, 100 m/pixel version |
| Product page | https://data.lroc.im-ldi.com/lroc/view_rdr/WAC_GLOBAL |
| Source files (PDS archive, EXTRAS/BROWSE, full-resolution 8-bit GeoTIFF) | `https://pds.lroc.im-ldi.com/data/LRO-L-LROC-5-RDR-V1.0/LROLRC_2001/EXTRAS/BROWSE/WAC_GLOBAL/WAC_GLOBAL_<TILE>_100M.TIF` for `TILE` in `E300N0450`, `E300S0450`, `E300N1350`, `E300S1350`, `E300N2250`, `E300S2250`, `E300N3150`, `E300S3150`, `P900N0000`, `P900S0000` |
| Source readme | `https://pds.lroc.im-ldi.com/data/LRO-L-LROC-5-RDR-V1.0/LROLRC_2001/DATA/BDR/WAC_GLOBAL/WAC_GLOBAL_README.TXT` (copy kept at `data/raw/lroc_wac_gmm_100m/WAC_GLOBAL_README.TXT`) |
| Retrieval date | 2026-11-10 |
| Original resolution | 100 m/pixel, about 303.2 pixels per degree (tiles of 27291 x 18194 px for equatorial tiles, 18622 x 18622 px for polar caps) |
| Original projection | Eight equirectangular tiles covering 60 degrees latitude by 90 degrees longitude (lat 0..60 N or 0..60 S, lon 0..90, 90..180, 180..270, 270..360 E). Two polar stereographic tiles covering 60..90 degrees latitude (origin lat +90 or -90, central meridian 0, sphere radius 1737400 m, true scale at the pole). |
| Processed file | `assets/textures/lunar_albedo_4096x2048.png` |
| Processed projection | Equirectangular, 4096 x 2048 px (11.378 px/degree), 8-bit RGB PNG. Column x covers longitude `360 * (x + 0.5) / 4096` degrees East (column 0 = 0 E, column 2048 = 180 E). Row y covers latitude `90 - 180 * (y + 0.5) / 2048` degrees (row 0 = 90 N). The UV convention matches Godot's SphereMesh: u = longitude / 360, v = (90 - latitude) / 180. |
| Credit line | NASA/GSFC/Arizona State University (short form NASA/GSFC/ASU), per the LROC citation policy below |
| Tool used for processing | Rust crate `tools/texture-prep/` (Rust 1.90.0, crates `tiff` 0.9.1 and `png` 0.18.1; full list under Processing), no GDAL |
| Tool used for import | Godot 4.7.2.stable.official.ed1daf0bf, `--headless --import`; import settings in `assets/textures/lunar_albedo_4096x2048.png.import`: lossless (`compress/mode=0`), mipmaps generated (`mipmaps/generate=true`) |

### License and usage terms (read 2026-11-10)

Source: https://lroc.im-ldi.com/about/terms ("Terms & Citation", section 1 "Terms of Use" and section 2 "Citation Policy"). Quoted verbatim:

> Data products available through the LROC Data Node of the PDS or through NASA PDS interfaces are in the public domain (see list of URLs below).

The list of URLs in that section includes `pds.lroc.im-ldi.com` and `data.lroc.im-ldi.com/`. The files used here are served from `pds.lroc.im-ldi.com`, which is the PDS archive path of the LROC Data Node, so they fall under the public-domain statement above.

> Images available on the LROC website, including but not limited to Featured Images, Featured Sites, curated products, downloads and non-PDS interfaces listed above, are copyrighted.

The website's curated download package for the same product (the "WAC Global Morphologic Mosaic" card on https://lroc.im-ldi.com/images/downloads, file `WAC_GLOBAL_E000N1800_100M.zip`) is therefore not used. Only the PDS-archived copy above is used.

> Use by news agencies, schools and universities, museums or other organizations for educational purposes is encouraged and permitted without prior permission, provided images are properly cited per Section 2, Paragraph B.

> All commercial use of LROC images not downloaded from the LROC PDS archive require prior permission.

Citation policy (section 2, paragraph B):

> For news media or educational purposes, credit LROC images with the text tag NASA/GSFC/Arizona State University. If space is limited, the shorter credit NASA/GSFC/ASU is also acceptable.

Research citation for the product (from the PDS readme):

> Speyerer, E. J., Robinson, M. S., Denevi, B. W., & LROC Team. (2011). Lunar Reconnaissance Orbiter Camera Morphological Map of the Moon. In Lunar and Planetary Science Conference (Vol. 42, abstract #2387). https://www.lpi.usra.edu/meetings/lpsc2011/pdf/2387.pdf

Interpretation: the texture is redistributed in the repository under the public-domain statement for PDS-archived LROC data. Credit is given in this file and in the project. Anyone using the texture commercially should still check the LROC terms page at the time of use.

### Raw file checksums (SHA-256)

Files are in `data/raw/lroc_wac_gmm_100m/` (not committed).

```
7628283ecf8fd7f458c2b7ddaa608c81131671ca9536793020bbb05c06555bdf  WAC_GLOBAL_E300N0450_100M.TIF
278b11a148753466b1d50c48d6b6cea43418dbd4172552c9a3977d032b74c2e1  WAC_GLOBAL_E300N1350_100M.TIF
5ee3c6a66134fddbb80c5e34925ff54aa29f2543fa7bde4f62a02e14d3a98941  WAC_GLOBAL_E300N2250_100M.TIF
20e2160c4837ed0e97ab540e08e8b770d33d0309bb32e836b28502dcbf2c7c6f  WAC_GLOBAL_E300N3150_100M.TIF
132db1800f6572cdb8c1dff225856df3f0a3d3c5bd3cae475624cc92775068a0  WAC_GLOBAL_E300S0450_100M.TIF
6f81bd2f64587a5217f8ad9765256b341c773196ce165f9011f34f6e80814eaa  WAC_GLOBAL_E300S1350_100M.TIF
7fbd10527e29a5860772fc71b27b1a98a21f14b741f32622ef230246a73eefbb  WAC_GLOBAL_E300S2250_100M.TIF
2353c356c1e3a7b70661240f3b417a6eeb60630c729fa4d3d0d4574f4bb8fb39  WAC_GLOBAL_E300S3150_100M.TIF
93254c705f9bbd53dd41bb680045f42814f5cd3f4a6f5ad6704529154307006c  WAC_GLOBAL_P900N0000_100M.TIF
cf835f350046bba7bf8b5d856bd02a3d671cf7a39b0b8a848d51a4c2b3b0a101  WAC_GLOBAL_P900S0000_100M.TIF
48570b8b896febab6440e54ad192c54fb99ab9873f3466ecf5c0dd8fb30c9865  WAC_GLOBAL_README.TXT
```

Processed file:

```
fa62317f9fa40e87a23260adcbd32bf4b1d26e3ca900b0adf6c04d0acba19043  assets/textures/lunar_albedo_4096x2048.png
```

The SHA-256 of the processed file changed on 2026-11-10 from `007f09f04121db1e8a4c9dbcfa2cf84784d2a03e5dd459c77d244b872fbf63fd` to the value above. Reason: different PNG encoder, same decoded pixels. The file is now written by the Rust tool `tools/texture-prep/` (crate `png` 0.18.1) instead of the earlier encoder. Both files decode to 4096 x 2048, 8-bit RGB, and a comparison of all 8388608 pixels found 0 differing pixels (maximum difference 0).

### Processing

Processing is downsampling plus the polar reprojection needed to fill the pole rows. No colour grading, contrast stretch or other tonal change is applied. The GeoTIFF's GDAL scale/offset metadata (SCALE 1.00395, OFFSET -0.00395) is not applied; the raw 8-bit values are used as-is.

- Equatorial tiles: each tile is area-averaged (box filter) into the output rows whose centre latitude lies inside that tile's latitude range and the output columns for its longitude range. The tile edges fall exactly on output column boundaries; latitude boundaries are fractional and handled by the box.
- Polar caps: each output pixel's centre is mapped to polar stereographic coordinates on the sphere (R = 1737400 m), then bilinearly sampled from a 1 km/pixel box-averaged copy of the 100 m tile. The forward formulas are the standard spherical polar stereographic projection with the tile's own origin (north: `y = -rho cos(lon)`; south: `y = +rho cos(lon)`). The orientation was checked by comparing the cap edge at 60 degrees against the equatorial tile edge.

The box filter is a two-pass (horizontal, then vertical) fixed-point average with 22 fractional bits, each pass rounded to 8 bits. The bilinear result is rounded to the nearest integer, ties to even. The code is in `tools/texture-prep/src/resample.rs` and `tools/texture-prep/src/main.rs`.

#### Tool

The tool is the Rust Cargo crate `tools/texture-prep/` (binary `texture-prep`). It uses pure-Rust readers and writers only: no GDAL, no C library and no C toolchain.

| Item | Version |
|---|---|
| Rust toolchain | 1.90.0 (the channel pinned in `ephemeris/rust-toolchain.toml`), target `x86_64-unknown-linux-musl`, linker `rust-lld` (set in `tools/texture-prep/.cargo/config.toml`) |
| `tiff` (GeoTIFF reader, direct dependency) | 0.9.1 |
| `png` (PNG encoder and decoder, direct dependency) | 0.18.1 |
| `adler2` (transitive) | 2.0.1 |
| `bitflags` (transitive) | 2.13.2 |
| `cfg-if` (transitive) | 1.0.5 |
| `crc32fast` (transitive) | 1.4.2 |
| `fdeflate` (transitive) | 0.3.7 |
| `flate2` (transitive) | 1.1.11 |
| `jpeg-decoder` (transitive) | 0.3.2 |
| `miniz_oxide` (transitive, two versions) | 0.8.9 and 0.9.1 |
| `simd-adler32` (transitive) | 0.3.10 |
| `weezl` (transitive) | 0.1.12 |

The direct dependencies are pinned with exact versions in `tools/texture-prep/Cargo.toml`. Every transitive version is fixed by `tools/texture-prep/Cargo.lock`, and the build uses `--locked`. `tiff` is held at 0.9.1 and `crc32fast` at 1.4.2 because later releases need a host C linker to build (proc macro or build script).

#### Command

Run from the repository root (install the toolchain once with `make rust-setup`):

```
make texture
```

This runs exactly:

```
cd tools/texture-prep && RUSTUP_TOOLCHAIN=1.90.0 cargo build --release --locked
tools/texture-prep/target/x86_64-unknown-linux-musl/release/texture-prep data/raw/lroc_wac_gmm_100m assets/textures/lunar_albedo_4096x2048.png.tmp && mv assets/textures/lunar_albedo_4096x2048.png.tmp assets/textures/lunar_albedo_4096x2048.png
```

It takes about 15 seconds on a desktop CPU and reads only the raw TIFFs. The output is deterministic (rerunning gives the same PNG SHA-256). `make texture TEXTURE_PNG=<path>` writes to another path.

To check that two PNG files decode to the same pixels (size, colour type, bit depth and every value), run:

```
tools/texture-prep/target/x86_64-unknown-linux-musl/release/texture-prep compare <a.png> <b.png>
```

It prints the number of differing pixels and the maximum difference, and exits with status 0 only when the two images are identical.

### Known data properties (not corrected)

- **No-data pixels.** The raw polar tiles contain value 0 for pixels with no LROC coverage (about 29 percent of sampled pixels in the north polar tile). These stay black in the processed texture, mostly in the pole rows (roughly rows 0 to 10 and 2040 to 2047). This is a property of the source mosaic, not a processing error.
- **Brightness step at 180 degrees East.** The mosaic tiles were built from different acquisition periods. At 180 E, which is column 2048 of the 4096-wide texture (the boundary between columns 2047 and 2048), the source mosaic has a brightness step of about 8 grey levels on average: column 2048 is on average 8.4 grey levels darker than column 2047 over rows 11 to 2039. The step varies with latitude. It is present in the raw data and was not corrected: no tonal correction beyond downsampling is applied. The REQ-8 visual check is made with this step present.
- **Longitude wrap.** Column 0 and column 4095 (0 E and 360 E) are adjacent in the source, and the texture is continuous there. The SphereMesh UV seam lies at 0 E (+Z) and renders without a visible discontinuity from the texture itself.

## Elevation

No elevation data is used yet. The Moon is a plain, undisplaced sphere of radius 1737.4 km (1 unit = 1 km). `assets/elevation/` holds no elevation file (only `.gitkeep`). Real elevation from LOLA or SLDEM is planned for Milestone 2.
