# MoonPOC

A real-scale 3D Moon renderer in Godot 4 (Forward+/Vulkan). The terrain is displaced by real LOLA elevation data and textured with LROC WAC imagery. The Sun is live, driven by a Rust ephemeris helper. It is a technical proof of concept for a future lunar taxi game, not a game (project goal: `docs/init-moon-poc.md`). The project follows a milestone plan. Earth is in its first milestone.

## Status

Built:

- Milestone 1: textured globe, orbit camera, adjustable Sun.
- Milestone 2: real LOLA elevation on a 96-chunk cube-sphere mesh (405 600 vertices, no vertical exaggeration). Landmark measurements (Tycho, Copernicus, Theophilus, global extremes, maria vs highlands, albedo alignment) are in `docs/VALIDATION.md`.
- Milestone 3: lunar surface shader and an ENU normal map made from the elevation data.
- Milestone 4 (partly): headless performance numbers and a written chunk/LOD/streaming design. The design is not implemented.
- Sun from the Rust ephemeris (`moon-ephemeris --stream`).
- Earth Milestone 1: Earth sphere with monthly Blue Marble images.

Pending user checks:

- Visual checks (REQ-32 of the Milestone 2 spec): Tycho, Copernicus and Imbrium recognisable under low Sun; no seam at 0 E or at cube-face edges; no pinching near the poles; albedo features on the matching relief.
- Windowed performance run (`make perf`): FPS, frame times, draw calls and memory are pending.
- Earth Milestone 1 visual checks: not recorded as passed.

## Requirements

- Godot 4.7 (4.7.2-stable, pinned in the `Makefile`; `make setup` installs it into `tools/godot/`).
- A Rust toolchain, pinned to 1.90 in the crates (`make rust-setup` installs it with rustup).
- `make`, plus `curl`, `unzip` and `sha512sum`/`sha256sum` as used by the Makefile targets.

Network access is needed for: `make setup` (downloads Godot), `make rust-setup` (downloads rustup and the toolchain), and `make earth-texture` (downloads 12 Blue Marble images). The raw LOLA and LROC files for `make moon-data` go in `data/raw/`; no make target downloads them (URLs are in `docs/DATA_SOURCES.md`).

## Quick start

```
make setup
make rust-setup
make earth-texture   # optional, for the Earth textures
make run
```

`make run` builds the Sun helper, then starts the main scene. The processed elevation and texture files are under `assets/`.

## Make targets

Run `make help` for the full list.

| Target | Description |
|---|---|
| `setup` | Download the pinned Godot into `tools/godot/` and verify its SHA-512 |
| `rust-setup` | Install rustup (if missing) and the pinned Rust toolchain |
| `run` | Build the Sun helper, then run the main scene |
| `editor` | Open the project in the Godot editor |
| `import` | Headless import to generate resources |
| `check` | Headless load check; fails on script errors |
| `test` | Run `tests/run_tests.gd` headless |
| `sun-helper-test` | Live check of the Sun helper with a fake helper |
| `ephemeris` / `ephemeris-test` | Generate the fixed Sun/Moon JSON; run the ephemeris crate tests |
| `moon-data` | Build elevation levels, albedo, normal map and `moon_data.json` from `data/raw/` |
| `moon-data-test` | Run the moon-data crate tests |
| `normal-map` | Build only the normal map from the 4096 x 2048 height level |
| `texture` | Rebuild the albedo texture with `tools/texture-prep` |
| `earth-texture` | Download and verify the 12 monthly Earth images |
| `visual-check` | User-run GPU checks (`HEADLESS=1` prints not-available lines) |
| `perf` | Measure performance (`HEADLESS=1` for headless values only) |
| `clean` | Remove Godot's `.godot/` cache |

## Project layout

```
project.godot
scenes/        main.tscn, moon.tscn
scripts/       moon.gd, moon_camera.gd, sun_controller.gd, sun_disc.gd, earth_controller.gd
shaders/       lunar surface shader
assets/        elevation/, textures/, ephemeris/ (earth/ is downloaded, not committed)
ephemeris/     Rust crate: Sun/Moon/Earth ephemeris (moon-ephemeris)
tools/         moon-data/ and texture-prep/ (Rust data preparation); godot/ after make setup
tests/         Godot test, perf and check scripts
docs/          documentation and specs/
data/raw/      raw source data (not committed)
```

## Data sources and licences

Details, checksums and licence notes are in [docs/DATA_SOURCES.md](docs/DATA_SOURCES.md). Sources:

- LROC WAC Global Morphologic Mosaic (NASA/GSFC/ASU), the albedo texture.
- LOLA `LDEM_64` gridded elevation data (NASA/GSFC LOLA team, PDS Geosciences Node), the elevation.
- Blue Marble: Next Generation (NASA Earth Observatory), the Earth textures.

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): mesh layout, Earth, and the chunk/LOD/streaming design
- [docs/PERFORMANCE.md](docs/PERFORMANCE.md): performance method and measured values
- [docs/VALIDATION.md](docs/VALIDATION.md): landmark validation of data and mesh
- [docs/DATA_SOURCES.md](docs/DATA_SOURCES.md): datasets, processing and licences
- [docs/specs/](docs/specs/): one spec per feature
- [AGENTS.md](AGENTS.md): the spec, implement, test pipeline

## Licence

MIT. See [LICENSE.md](LICENSE.md).
