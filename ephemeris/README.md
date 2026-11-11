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
| `make ephemeris` | Build the CLI and write `assets/ephemeris/sun_moon_fixed.json` for `EPHEMERIS_UTC` (default: the current UTC time, from `date -u +%Y-%m-%dT%H:%M:%SZ`; an explicit value overrides it, e.g. `make ephemeris EPHEMERIS_UTC=2026-11-10T00:00:00Z`). |

## CLI usage

```
moon-ephemeris [YYYY-MM-DDTHH:MM:SSZ]
```

With no argument the time is `2026-11-10T00:00:00Z`. Years 1900 to 2100 are accepted.
Invalid input (wrong format, invalid date, missing `Z`, out-of-range year) prints one
error line to standard error, nothing to standard output, and exits with code 2.

Output is one JSON object with the fields `utc`, `jd_tt`, `frame` (`"IAU_MOON"`),
`sun_dir_moon_fixed`, `sun_dir_godot`, `subsolar_lon_deg`, `subsolar_lat_deg`,
`sun_distance_km`, `sun_angular_diameter_deg`, and the six Earth fields below
(fifteen fields in total).

```
moon-ephemeris --stream
```

Streaming mode (used by Godot at runtime): once per second prints one compact JSON line
with the same fifteen fields for the current system UTC time truncated to whole seconds,
flushing after each line. It runs until it gets a signal or its standard output is
closed (then it exits 0). `make run` builds this binary before starting Godot;
nothing at runtime reads `assets/ephemeris/sun_moon_fixed.json`, which is a committed
reference sample of one-shot output.

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

## Earth fields (Earth Milestone 1)

Spec: `docs/specs/earth-milestone-1-basic-earth.md`. Added to the one-shot output and to every
`--stream` line; the nine Sun fields are unchanged.

| Field | Meaning |
|---|---|
| `earth_pos_godot` | [X, Y, Z] km, Moon centre to Earth centre, Godot mapping of the Moon-fixed frame (the negated geocentric Moon vector, rotated by the same IAU lunar rotation as the Sun) |
| `earth_distance_km` | Length of that vector |
| `earth_basis_godot` | 9 numbers, row-major rotation matrix taking Earth-fixed vectors to Godot vectors |
| `earth_sun_dir_godot` | Unit vector Earth centre to Sun centre, Godot mapping: (Moon-to-Sun minus Moon-to-Earth), normalised |
| `earth_subsolar_lon_deg` | East longitude of the subsolar point on Earth, −180 < value ≤ 180 |
| `earth_subsolar_lat_deg` | Geocentric latitude of the subsolar point on Earth |

`earth_sun_dir_godot` is built from the subsolar lon/lat and `earth_basis_godot`, so the four agree to rounding.

### Earth rotation model and constants

- Earth-fixed frame: +x toward (0° N, 0° E), +z toward the north pole.
- Pole fixed along the ICRF/J2000 +z axis. The axial tilt of 23.44° is the angle between that pole and the
  J2000 ecliptic pole (obliquity 23.4393°); it is not set by hand.
- Prime meridian angle = Earth Rotation Angle (IAU 2000): ERA = 2π · (0.7790572732640 +
  1.00273781191135448 · (JD_UT1 − 2451545.0)), with UT1 = UTC (error below 1 s, about 0.004°).
  One sidereal rotation is 86164.0905 s.
- Earth-fixed to ICRF is a rotation by ERA about +z; ICRF to Moon-fixed is the lunar rotation used for the Sun;
  the Godot mapping is (X, Y, Z) = (y, z, x).
- Fixed-pole approximation: precession and nutation of Earth's axis are ignored. Precession since J2000 is about
  0.36° by 2026, inside the 0.5° tolerance of the Horizons checks below.
- Earth mean radius for rendering and apparent size: 6371.0 km.

### Earth reference checks (JPL Horizons, values retrieved 2026-11-11 for 2026-11-10 00:00 UT)

Common parameters: `format=text OBJ_DATA='NO' MAKE_EPHEM='YES' EPHEM_TYPE='OBSERVER' CSV_FORMAT='NO' ANG_FORMAT='DEG'`,
`START_TIME='2026-11-10 00:00'` (the Earth subsolar query uses `2026-06-21 12:00`), `TIME_TYPE='UT'`.

| Check | Query | Horizons reference | This crate | Tolerance |
|---|---|---|---|---|
| Sub-Earth point on the Moon | `COMMAND='301' CENTER='500@399' QUANTITIES='14'` (`ObsSub-LON`, `ObsSub-LAT`, frame MOON_ME, east-positive) | lon 3.450226°, lat 6.565800° | lon 3.4173°, lat 6.5481° (separation 0.037°) | 0.5° great circle |
| Sun sub-point on the Moon | `COMMAND='301' CENTER='500@399' QUANTITIES='15'` | lon 175.405935°, lat −1.544939° | lon 175.4082°, lat −1.5459° (see the table above) | 0.5° |
| Earth distance from the Moon | `COMMAND='399' CENTER='500@301' QUANTITIES='20'` (`delta`) | 0.00267226337481 au (about 399 765 km at 1 au = 149 597 870.7 km) | 399 298.17 km (−0.117 %) | 0.2 % |
| Earth apparent diameter from the Moon | `COMMAND='399' CENTER='500@301' QUANTITIES='13'` (`Ang-diam`) | 6582.073″ (1.8284°) | 2·asin(6371 / 399 298.17) = 1.8284° | Reference only; the scene value is checked against geometry (REQ-19). A difference of about 0.11 % from Horizons is expected and is not a failure |
| Earth subsolar point, `2026-06-21T12:00:00Z` | `COMMAND='399' CENTER='500@301' QUANTITIES='15'` (`SunSub-LON`, `SunSub-LAT`, frame ITRF93, east-positive, geodetic latitude) | lon 0.459544°, lat 23.578619° | lon 0.3960°, lat 23.4379° geocentric (separation 0.152°) | 0.5° great circle |

The sub-Earth query uses the geocentre as observer because Horizons does not allow the Moon as both target and
centre. The geocentre's sub-observer point lies on the Moon-centre-to-Earth-centre line, so it is the same
direction as `earth_pos_godot` apart from light-time and aberration (well under 0.01°). The CLI latitude of the
Earth subsolar point is geocentric; at this latitude it is about 0.14° below the geodetic value, inside the tolerance.

Status: the Horizons reference values above are the ones supplied in the spec. They were not re-queried by the
implementer; re-running the five queries is a user check and is pending.
