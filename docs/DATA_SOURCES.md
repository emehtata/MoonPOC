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

#### Milestone 2: the texture is also written by `make moon-data`

Since Milestone 2 the pipeline crate `tools/moon-data/` regenerates this texture together with the elevation levels, on the same grid:

```
make moon-data
```

There is no Python script in this project; all data preparation is Rust. `tools/moon-data/` applies the processing described above and compiles the same resampler source file (`tools/texture-prep/src/resample.rs`), with the same PNG encoder and settings. In addition it checks each tile's GeoTIFF tie point and pixel scale against the tile extents in the table above before converting.

Port equivalence, measured on 2026-11-10 with `moon-data compare`: the reference is the committed texture `assets/textures/lunar_albedo_4096x2048.png` (the `make texture` output, SHA-256 `fa62317f9fa40e87a23260adcbd32bf4b1d26e3ca900b0adf6c04d0acba19043`), copied before regeneration. The texture written by `make moon-data` and that copy both decode to 4096 x 2048, 8-bit RGB. Of 8388608 pixels compared, the count of differing pixels is 0 and the maximum difference is 0. The regenerated PNG file is also byte-identical to the reference (same SHA-256). The original Milestone 1 PNG is not stored in the repository and is not the reference for this check.

### Known data properties (not corrected)

- **No-data pixels.** The raw polar tiles contain value 0 for pixels with no LROC coverage (about 29 percent of sampled pixels in the north polar tile). These stay black in the processed texture, mostly in the pole rows (roughly rows 0 to 10 and 2040 to 2047). This is a property of the source mosaic, not a processing error.
- **Brightness step at 180 degrees East.** The mosaic tiles were built from different acquisition periods. At 180 E, which is column 2048 of the 4096-wide texture (the boundary between columns 2047 and 2048), the source mosaic has a brightness step of about 8 grey levels on average: column 2048 is on average 8.4 grey levels darker than column 2047 over rows 11 to 2039. The step varies with latitude. It is present in the raw data and was not corrected: no tonal correction beyond downsampling is applied. The REQ-8 visual check is made with this step present.
- **Longitude wrap.** Column 0 and column 4095 (0 E and 360 E) are adjacent in the source, and the texture is continuous there. The mesh UV seam lies at 0 E (+Z) and renders without a visible discontinuity from the texture itself.

## Elevation (Milestone 2)

The Moon's geometry is displaced by real elevation from the NASA LOLA instrument. The raw files are in `data/raw/lola_ldem_64/` (not committed). The values below were read from the product label `LDEM_64.LBL` on the retrieval date; the pipeline reads them from the label at every run and does not hard-code them.

| Item | Value |
|---|---|
| Product | LRO LOLA Gridded Data Record, global cylindrical DEM `LDEM_64` (`PRODUCT_ID = "LDEM_64"`, `PRODUCT_VERSION_ID = "V3.1"`, `PRODUCT_CREATION_TIME = 2019-03-15`), PDS data set `LRO-L-LOLA-4-GDR-V1.0` ("LRO MOON LASER ALTIMETER 4 GDR V1.0") |
| Source | PDS Geosciences Node (Washington University in St. Louis) |
| URLs (file names are lower case on the server) | `https://pds-geosciences.wustl.edu/lro/lro-l-lola-3-rdr-v1/lrolol_1xxx/data/lola_gdr/cylindrical/img/ldem_64.img` and `https://pds-geosciences.wustl.edu/lro/lro-l-lola-3-rdr-v1/lrolol_1xxx/data/lola_gdr/cylindrical/img/ldem_64.lbl` |
| Local names | `data/raw/lola_ldem_64/LDEM_64.IMG` and `data/raw/lola_ldem_64/LDEM_64.LBL` (upper case, as in the label's `FILE_NAME = "LDEM_64.IMG"`) |
| Retrieval date | 2026-11-10 |
| Samples and lines | `LINE_SAMPLES = 23040`, `LINES = 11520` (file size 530 841 600 bytes = 23040 x 11520 x 2) |
| Resolution | `MAP_RESOLUTION = 64 <pix/deg>`, `MAP_SCALE = 473.802 <m/pix>` |
| Projection | `MAP_PROJECTION_TYPE = "SIMPLE CYLINDRICAL"` (equirectangular), `POSITIVE_LONGITUDE_DIRECTION = "EAST"`, `CENTER_LATITUDE = 0`, `CENTER_LONGITUDE = 180`, `LINE_PROJECTION_OFFSET = 5759.5`, `SAMPLE_PROJECTION_OFFSET = 11519.5`; pixel registered: line 1 is the northernmost row (centre 89.9921875 N), sample 1 is centred at 0.0078125 E |
| Extents | `MAXIMUM_LATITUDE = 90`, `MINIMUM_LATITUDE = -90`, `WESTERNMOST_LONGITUDE = 0`, `EASTERNMOST_LONGITUDE = 360` (degrees) |
| Coordinate system | `COORDINATE_SYSTEM_NAME = "MEAN EARTH/POLAR AXIS OF DE421"`, planetocentric latitude on a sphere (`A_AXIS_RADIUS = B_AXIS_RADIUS = C_AXIS_RADIUS = 1737.4 <km>`) |
| Sample type | `SAMPLE_TYPE = LSB_INTEGER`, `SAMPLE_BITS = 16` (signed 16-bit, little-endian) |
| Units | `UNIT = METER` |
| Scaling factor | `SCALING_FACTOR = 0.5` (height in metres = DN x 0.5) |
| Offset | `OFFSET = 1737400.` (metres; radius of the reference sphere) |
| Label value range | `MINIMUM = -18251`, `MAXIMUM = 21546` (digital numbers, so -9125.5 m to +10773 m) |
| Vertical reference | Sphere of radius 1737.4 km centred at the Moon's centre of mass. The label says: "Map values are relative to a radius of 1737.4 km." Heights are not relative to a geoid. |
| NoData | The label has no missing-constant keyword (`MISSING_CONSTANT`, `MISSING`, `NULL` and `CORE_NULL` are all absent). Every sample is a height. The label notes that gaps in coverage were interpolated by the LOLA team ("the GMT5.4.2 program 'surface' was used to compensate for incomplete coverage"). The generated levels contain 0 NoData cells. |
| Credit | NASA / GSFC LOLA team (producer: David E. Smith, Goddard Space Flight Center), distributed by the PDS Geosciences Node |

### Resolution decision: 64 ppd LOLA, not 512 ppd SLDEM2015

Milestone 2 uses the global LOLA grid at 64 pixels per degree (about 474 m per pixel at the equator). It does not use SLDEM2015 at 512 pixels per degree. Reasons:

- The Milestone 2 mesh has a vertex spacing of about 7.5 to 10.7 km, so data finer than about 5 km per pixel cannot show on it. 64 ppd is already 11 to 22 times finer than the height levels the mesh can use.
- SLDEM2015 covers only latitudes 60 S to 60 N. It has no poles, so it cannot fill a globe by itself.
- A global 512 ppd grid would be about 184 320 x 92 160 samples, tens of gigabytes. `LDEM_64` is global, includes the poles, and is 531 MB.
- The 512 ppd data is the planned regional source for the chunk and LOD work in Milestones 3 and 4 (SLDEM2015 for the band between 60 S and 60 N, LOLA for the poles), produced by the same Rust pipeline. See `docs/ARCHITECTURE.md`.

### License and usage terms (read 2026-11-10)

Source: PDS Geosciences Node, "Frequently Asked Questions", https://pds-geosciences.wustl.edu/faq.html. Quoted verbatim:

> How much does it cost to obtain PDS data? Data sets archived in the PDS are in the public domain. Almost all PDS data sets are online and may be downloaded by anyone for free.

> Are there any restrictions on the use of PDS data? PDS data sets are classified TSPA (Technology and Software Publicly Available) by the U.S. Department of Commerce, Bureau of Export Administration, and may be exported outside the United States as public open literature. When PDS data sets are used in published literature or other applications, they should be cited appropriately (see below).

Interpretation: `LDEM_64` is a data set archived in the PDS, so it is in the public domain. The derived height files under `assets/elevation/` are redistributed in the repository on that basis, with the citation below.

Citation of the data set, copied verbatim from the data set catalog file `https://pds-geosciences.wustl.edu/lro/lro-l-lola-3-rdr-v1/lrolol_1xxx/catalog/gdr_ds.cat` (`CITATION_DESC`):

> Neumann, G.A., 2009 Lunar Orbiter Laser Altimeter Raw Data Set, LRO-L-LOLA-4-GDR-V1.0, NASA Planetary Data System, 2010.

Instrument reference named by the same catalog file (`REFERENCE_KEY_ID = "SMITHETAL2009"`), copied verbatim from `catalog/ref.cat`:

> Smith, D.E., M.T. Zuber, G.B. Jackson, G.A. Neumann,H. Riris, X. Sun, R.S. Zellar, C. Coltharp, J. Connelly, R.B. Katz, I. Kleyner, P. Liiva, A. Matuszeski, E.M. Mazarico, J.F. McGarry, A.-M. Novo-Gradac, M.N. Ott, C. Peters, L.A. Ramos-Izquierdo, L. Ramsey, D.D. Rowlands, S. Schmidt, V.S. Scott III, G.B. Shaw, J.C. Smith, J.-P. Swinski, M.H. Torrence, G. Unger, A.W. Yu, T.W. Zagwodzki, The Lunar Orbiter Laser Altimeter Investigation on the Lunar Reconnaissance Orbiter Mission, Space Science Reviews, 16 May 2009.

The catalog's own citation names G. A. Neumann, not D. E. Smith, as the author of the data set record. D. E. Smith is the product's `PRODUCER_FULL_NAME` in the label.

### Raw file checksums (SHA-256)

```
1c4958699d4cffd7e777d51421b6044bba300aa0bef286a544309efb082cdbd6  LDEM_64.IMG
4e7a94c76c716a147b21ccf07669d004246b0d1b017b7d63d50befaa1a34142d  LDEM_64.LBL
```

### Processed files

All are written by `make moon-data` (Rust crate `tools/moon-data/`, Rust 1.90.0). Sizes, statistics and SHA-256 values are also in `assets/elevation/moon_data.json`.

| File | Size (bytes) | Minimum (m) | Maximum (m) | NoData cells |
|---|---|---|---|---|
| `assets/elevation/lola_height_m_4096x2048.f32` | 33 554 432 | -9063.06 | 10662.07 | 0 |
| `assets/elevation/lola_height_m_2048x1024.f32` | 8 388 608 | -8817.11 | 10575.05 | 0 |
| `assets/elevation/lola_height_m_1024x512.f32` | 2 097 152 | -8472.11 | 9993.20 | 0 |

```
88d4c5b5269e1a6a5d67fa735caf86c37f70b2eec3b4e5f6c62335f63e6b8512  assets/elevation/lola_height_m_4096x2048.f32
97c6854f2a50a0e948fe9d650979a7c82d4122e4528fa73dcac501b42316eabd  assets/elevation/lola_height_m_2048x1024.f32
30e836e84bec102bca88d07e258c13307a511a4d282e65b62c6e99b421323a04  assets/elevation/lola_height_m_1024x512.f32
```

`assets/elevation/moon_data.json` holds these checksums and those of the raw files, so its own SHA-256 is not listed inside it; print it with `sha256sum assets/elevation/moon_data.json`.

Format: raw little-endian 32-bit floats, row 0 = northernmost row, column 0 starting at 0 E. The value is the height in metres above the sphere of radius 1 737 400 m. NoData would be stored as NaN; there is none. The grid is the same as the albedo texture's: column x centre at longitude `360 * (x + 0.5) / W` degrees East, row y centre at latitude `90 - 180 * (y + 0.5) / H` degrees.

### Processing

- Each level is made directly from the 23040 x 11520 source grid by a box filter: an output cell is the plain mean of the source samples whose centres fall inside it, times the scaling factor. A sample centre that lies exactly on a cell boundary belongs to the cell that starts there (the eastern or southern one). The exact index rule is in `tools/moon-data/README.md`.
- No smoothing, no vertical exaggeration, no filling and no other change is applied.
- Before converting, the pipeline checks the label and the file size, and each LROC tile's GeoTIFF tie point and pixel scale. A mismatch stops the run with exit code 2. The checks are listed in `tools/moon-data/README.md`.

### Command

Run from the repository root (install the toolchain once with `make rust-setup`):

```
make moon-data
```

This runs exactly:

```
cd tools/moon-data && RUSTUP_TOOLCHAIN=1.90.0 cargo build --release --locked
tools/moon-data/target/x86_64-unknown-linux-musl/release/moon-data data/raw assets/elevation assets/textures
```

It reads only `data/raw/` and writes only the three height levels and `moon_data.json` in `assets/elevation/` and the albedo texture in `assets/textures/`. It takes about 50 seconds. Running it twice gives byte-identical files.

## Normal map (Milestone 3)

Spec: `docs/specs/visual-quality-milestone-3.md`, REQ-12 to REQ-18.

| Item | Value |
|---|---|
| Source level | `assets/elevation/lola_height_m_4096x2048.f32` |
| Source SHA-256 | `88d4c5b5269e1a6a5d67fa735caf86c37f70b2eec3b4e5f6c62335f63e6b8512` |
| Output | `assets/textures/lunar_normal_enu_4096x2048.png` |
| Output SHA-256 | `bedaa5676e425a3a8b503ffd407b56ef0ea1aa4c1f501fd9b750403aad7f2f7f` |
| Output size | 10 108 231 bytes |
| Resolution | 4096 x 2048, the same grid as the source level and the albedo |
| Encoding | `enu_rgb8`: 8-bit RGB, R = round((n_e·0.5 + 0.5)·255), G and B the same for n_n and n_u |
| Tool | `moon-data` 0.1.0 (`tools/moon-data/`), Rust 1.90.0 |

### Method

Per texel (x, y) of the 4096 x 2048 grid (row 0 north, column 0 at 0° E), h in metres, R = 1 737 400 m, φ_y the row's centre latitude:

- Δy = π R / 2048 (1332.6 m); Δx₁ = 2 π R cos φ_y / 4096.
- k rule: k = max(1, ceil(Δy / Δx₁)) columns, so the east baseline is never shorter than the north one.
- g_e = (h[x+k] − h[x−k]) / (2 k Δx₁), columns wrapping modulo 4096.
- g_n = (h[y−1] − h[y+1]) / (2 Δy), row y−1 north; on the first and last row the one-sided difference toward the interior, divided by Δy.
- n = normalize(−g_e, −g_n, 1) in the local east-north-up frame.

No smoothing, no scaling, no vertical exaggeration and no invented data are used. Before computing, the tool checks the source level's size and SHA-256 against `moon_data.json` and stops with exit code 2 if they differ; a NaN height also stops it with exit code 2 naming the texel. The `normal_map` entry in `moon_data.json` records the path, size, encoding, frame, source path and SHA-256, method and the PNG's SHA-256.

### Commands

```
make normal-map
```

runs `moon-data normal-map assets/elevation assets/textures` after a `cargo build --release --locked`, reads only the 4096 x 2048 level and `moon_data.json`, and writes the PNG and the updated `moon_data.json`. `make moon-data` runs the same step last, so both write byte-identical output.

## Earth surface textures (Earth Milestone 1)

Spec: `docs/specs/earth-milestone-1-basic-earth.md` (REQ-12 to REQ-17). The files are not committed (`assets/earth/bmng/`
is in `.gitignore`). `make earth-texture` downloads them, checks size and SHA-256 against the table below, and skips valid files.

- Product: Blue Marble: Next Generation (base map), JPG, the lowest resolution NASA offers for each month.
- NASA page: <https://science.nasa.gov/earth/earth-observatory/blue-marble-next-generation/>
- Resolution and projection: 5400 x 2700 pixels, equirectangular (plate carree), longitude -180 to 180, latitude 90 to -90.
  The size is from the file names and was confirmed by decoding all 12 files.
- Directory: `assets/earth/bmng/`.

| Month | File | Folder | Date code | Bytes | SHA-256 | Direct download URL |
|---|---|---|---|---|---|---|
| January | `world.200401.3x5400x2700.jpg` | january | 200401 | 1884678 | `99f5faad74efe985fbf1714c8be7296ca9999759a1215b65f99b7f1df278dde5` | <https://assets.science.nasa.gov/content/dam/science/esd/eo/images/bmng/bmng-base/january/world.200401.3x5400x2700.jpg> |
| February | `world.200402.3x5400x2700.jpg` | february | 200402 | 1865311 | `252444b224c7dc10289616fb5e3cd85c3738fca9ddbdc267775cd22a748bbfbe` | <https://assets.science.nasa.gov/content/dam/science/esd/eo/images/bmng/bmng-base/february/world.200402.3x5400x2700.jpg> |
| March | `world.200403.3x5400x2700.jpg` | march | 200403 | 1830489 | `0d9967be048b5e2ba62195dd610042c9e0926b4eb9d1e9ae53dbf20eaadd9228` | <https://assets.science.nasa.gov/content/dam/science/esd/eo/images/bmng/bmng-base/march/world.200403.3x5400x2700.jpg> |
| April | `world.200404.3x5400x2700.jpg` | april | 200404 | 1774173 | `8db8d5e545b31cde0e4e5dfa46cb116bf485243a0200c2d6e4b04b4e6937f669` | <https://assets.science.nasa.gov/content/dam/science/esd/eo/images/bmng/bmng-base/april/world.200404.3x5400x2700.jpg> |
| May | `world.200405.3x5400x2700.jpg` | may | 200405 | 1735263 | `d9a8dfc0a3e54775c3a4aeb547c729f710bb588d82d4602252d7cd7bf43a38ef` | <https://assets.science.nasa.gov/content/dam/science/esd/eo/images/bmng/bmng-base/may/world.200405.3x5400x2700.jpg> |
| June | `world.200406.3x5400x2700.jpg` | june | 200406 | 1692239 | `dc059529b8ed1cfcdd59747a7c3f259c93c1322bf88ca1ec8bab1dd71fcc57f5` | <https://assets.science.nasa.gov/content/dam/science/esd/eo/images/bmng/bmng-base/june/world.200406.3x5400x2700.jpg> |
| July | `world.200407.3x5400x2700.jpg` | july | 200407 | 1617810 | `f55226d46d27e05511f2118dc6aa24f5dbf9b6b2cddc87cc6e0e7dd067c00b11` | <https://assets.science.nasa.gov/content/dam/science/esd/eo/images/bmng/bmng-base/july/world.200407.3x5400x2700.jpg> |
| August | `world.200408.3x5400x2700.jpg` | august | 200408 | 1616254 | `2048023ccc62250c677c0f4b03d4362f997b130eb0154a6cad00aa1b27c390b9` | <https://assets.science.nasa.gov/content/dam/science/esd/eo/images/bmng/bmng-base/august/world.200408.3x5400x2700.jpg> |
| September | `world.200409.3x5400x2700.jpg` | september | 200409 | 1709729 | `ed72e87674861f72e2a6e5df52f0cc6bf3df1edd9b862664cf18ac423e2e9e0e` | <https://assets.science.nasa.gov/content/dam/science/esd/eo/images/bmng/bmng-base/september/world.200409.3x5400x2700.jpg> |
| October | `world.200410.3x5400x2700.jpg` | october | 200410 | 1766694 | `ccfd9b7a5e5ee601e1466556716bba50ea418f3a8e068ab0194ae0425815b1b0` | <https://assets.science.nasa.gov/content/dam/science/esd/eo/images/bmng/bmng-base/october/world.200410.3x5400x2700.jpg> |
| November | `world.200411.3x5400x2700.jpg` | november | 200411 | 1851209 | `d63de0bb4274a7d9df08d2f69eeffc849d0f7aca157c4401f9bd2e41af63b178` | <https://assets.science.nasa.gov/content/dam/science/esd/eo/images/bmng/bmng-base/november/world.200411.3x5400x2700.jpg> |
| December | `world.200412.3x5400x2700.jpg` | december | 200412 | 1878742 | `3d38a8ecaceb1cdb51ced7f831e9ac18d261950049616feff6892efcae0dcc26` | <https://assets.science.nasa.gov/content/dam/science/esd/eo/images/bmng/bmng-base/december/world.200412.3x5400x2700.jpg> |

### Licence and usage terms (read 2026-11-11)

There is no separate licence file, and neither page says "public domain". Recorded verbatim:

- <https://science.nasa.gov/earth/faq/>, heading "May I reuse imagery that is on your site?": "Most materials published under science.nasa.gov/earth, including images, are freely available for re-publication or re-use, including commercial purposes, except for where copyright is indicated. In those cases, you must obtain the copyright holder’s permission; we usually provide the name (and link, when possible) to the person or organization that holds the copyright." and "We ask that NASA be given credit for its original materials."
- <https://science.nasa.gov/earth/earth-observatory/blue-marble-next-generation/>, heading "Credits": "Anyone using or republishing Blue Marble: Next Generation please credit “NASA Earth Observatory.”"

### Required credit line

"Earth imagery: Blue Marble: Next Generation, NASA Earth Observatory, NASA Goddard Space Flight Center. Produced by Reto Stöckli. https://science.nasa.gov/earth/earth-observatory/blue-marble-next-generation/"

### Processing

None. The textures are used as downloaded, with no colour correction. At runtime Godot decodes the JPG and generates mipmaps.

### Override

This section overrides the single-neutral-texture rule of `docs/earth-sky.md` sections 3 and 14 (user decision, for Earth Milestone 1 only): all 12 monthly images are used, and the one for the UTC month of the latest streamed line is shown.
