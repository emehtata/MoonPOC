# moon-ephemeris

Low-precision direction and distance of the Sun as seen from the Moon's centre, in the
IAU Moon-fixed frame. Spec: `docs/specs/sun-ephemeris-and-sun-disc.md`.

The crate uses only the Rust standard library (no dependencies). `Cargo.lock` is committed.

## Toolchain

- Rust **1.90.0** (stable), pinned in `rust-toolchain.toml`, installed by `make rust-setup`
  (rustup from https://sh.rustup.rs with `--default-toolchain none --profile minimal
  --no-modify-path`, then `rustup toolchain install 1.90.0`).
- Build target `x86_64-unknown-linux-musl`, linked with the `rust-lld` that ships with the
  toolchain (`.cargo/config.toml`). This produces a static binary and needs no system C
  compiler or linker (the machine has no `cc`).

## Make targets

| Target | Action |
|---|---|
| `make rust-setup` | Install rustup (if missing) and the pinned toolchain plus musl target. Idempotent. |
| `make ephemeris-test` | `cargo test` in `ephemeris/` with the pinned toolchain. |
| `make ephemeris` | Build the CLI and write `assets/ephemeris/sun_moon_fixed.json` for `EPHEMERIS_UTC` (default `2026-11-10T00:00:00Z`; override with `make ephemeris EPHEMERIS_UTC=...`). |

## CLI usage

```
moon-ephemeris [YYYY-MM-DDTHH:MM:SSZ]
```

With no argument the time is `2026-11-10T00:00:00Z`. Years 1900 to 2100 are accepted.
Invalid input (wrong format, invalid date, missing `Z`, out-of-range year) prints one
error line to standard error, nothing to standard output, and exits with code 2.

Output is one JSON object with the fields `utc`, `jd_tt`, `frame` (`"IAU_MOON"`),
`sun_dir_moon_fixed`, `sun_dir_godot`, `subsolar_lon_deg`, `subsolar_lat_deg`,
`sun_distance_km`, `sun_angular_diameter_deg`.

## Methods and references

- **Time.** Input is UTC. TT = UTC + ΔT with a fixed **ΔT = 69.2 s**. Julian Date from the
  Gregorian calendar date by Meeus, *Astronomical Algorithms*, 2nd ed., chapter 7 (formula 7.1).
  TDB is taken equal to TT.
- **Sun.** Apparent geocentric position by Meeus chapter 25, "low accuracy" method: geometric
  mean longitude L0, mean anomaly M, eccentricity e, equation of centre C, true longitude,
  radius vector R; apparent longitude λ = ☉ − 0.00569° − 0.00478° sin Ω (nutation in
  longitude and aberration); true obliquity ε = ε0 + 0.00256° cos Ω with ε0 from Meeus 22.2.
  RA and Dec of date by 25.6 and 25.7. Distance in AU with 1 AU = 149 597 870.7 km.
- **Moon.** Geocentric ecliptic longitude, latitude and horizontal parallax by the
  Astronomical Almanac low-precision formula (section D), mean equinox of date; distance =
  6378.14 km / sin π.
- **Moon-to-Sun vector.** Both positions are converted from the ecliptic of date to the
  equator of date (Sun with true obliquity, Moon with mean obliquity), then precessed to
  J2000 with the IAU 1976 angles ζ, z, θ of Meeus chapter 21 (21.2, 21.3, rigorous method).
  The vector is Sun minus Moon, in the ICRF/J2000 equatorial frame (the frame bias is ignored).
- **Moon-fixed frame.** IAU WGCCRE 2009 lunar rotation model (Archinal et al. 2011, "Report
  of the IAU Working Group on Cartographic Coordinates and Rotational Elements: 2009",
  Table 2): pole α0, δ0 and prime meridian W with all periodic terms E1 to E13. The rotation
  is r_fixed = R3(W) · R1(90° − δ0) · R3(90° + α0) · r_J2000.
- **Sun radius.** R_sun = 695 700 km (IAU 2015 Resolution B3). Angular diameter
  = 2·asin(R_sun / distance).

## Frames and Godot mapping

- `IAU_MOON` (mean-Earth/polar-axis approximation): +x toward (0° N, 0° E), +z toward the
  north pole, +y toward (0° N, 90° E).
- Subsolar point: east longitude 0 ≤ lon < 360 and latitude of the Moon-to-Sun direction.
  `sun_dir_moon_fixed` is computed from lon/lat, so x = cos(lat)cos(lon), y = cos(lat)sin(lon),
  z = sin(lat) holds to rounding.
- Godot local axes: (X, Y, Z) = (y, z, x) (a cyclic permutation, handedness preserved).
  Godot +X is 90° E, +Y is the north pole, +Z is 0° E, which matches the M1 texture
  orientation. M1 azimuth = subsolar longitude, M1 elevation = subsolar latitude.

## Reference checks

| Check | Reference | Tolerance | This crate |
|---|---|---|---|
| REQ-11 Sun RA/Dec, Meeus Ex. 25.a, JDE 2448908.5 | RA 198.38083°, Dec −7.78507° | 0.01° | RA 198.380825°, Dec −7.785070° |
| REQ-12 Selenographic Sun, Meeus Ex. 53.a, `1992-04-12T00:00:00Z` | l0 = 67.89°, b0 = 1.46° | 0.5° | lon 67.8896°, lat 1.4509° |
| REQ-13 JPL Horizons, `2026-11-10T00:00:00Z` | lon 175.405935°, lat −1.544939° | 0.5° great circle | lon 175.408215°, lat −1.545934° (separation ≈ 0.0025°) |

### CLI output for the default date

```json
{
  "utc": "2026-11-10T00:00:00Z",
  "jd_tt": 2461354.500800926,
  "frame": "IAU_MOON",
  "sun_dir_moon_fixed": [-0.9964275535234517, 0.0800268613163577, -0.026978362573017247],
  "sun_dir_godot": [0.0800268613163577, -0.026978362573017247, -0.9964275535234517],
  "subsolar_lon_deg": 175.40821536021815,
  "subsolar_lat_deg": -1.545933882331383,
  "sun_distance_km": 147771651.3542463,
  "sun_angular_diameter_deg": 0.5394921244144147
}
```

### JPL Horizons value (fetched 2026-11-10)

Result: **SunSub-LON 175.405935°, SunSub-LAT −1.544939°** at 2026-Nov-10 00:00 UT
(ephemeris DE441, target pole/equator `MOON_ME`, spherical radii 1737.4 km).

Query settings (Horizons API, `https://ssd.jpl.nasa.gov/api/horizons.api`):

```
format=text  COMMAND='301'  EPHEM_TYPE='OBSERVER'  CENTER='500@399'
START_TIME='2026-11-10 00:00'  STOP_TIME='2026-11-10 00:01'  STEP_SIZE='1m'
QUANTITIES='15'  TIME_TYPE='UT'  ANG_FORMAT='DEG'  EXTRA_PREC='YES'
```

Target 301 (Moon), quantity 15 "Sun sub-longitude & sub-latitude", output columns
`SunSub-LON` and `SunSub-LAT` (the sub-solar point on the Moon). Horizons reports these in
its `MOON_ME` body-fixed frame, which differs from the IAU model frame (`IAU_MOON`) used by
this crate by well under the 0.5° tolerance.
