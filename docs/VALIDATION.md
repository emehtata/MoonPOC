# Validation

Measured checks of the Milestone 2 elevation data and mesh against known lunar landmarks. Spec: `docs/specs/moon-elevation-milestone-2.md`, REQ-24 to REQ-31.

The numbers below were measured by the implementer on 2026-11-10 from the generated files (SHA-256 values in `docs/DATA_SOURCES.md`). The tester's automated tests repeat these measurements independently; this file records the method and the values to expect. Visual checks (REQ-32) are made by the user and are not recorded here as passed.

## Landmark coordinates

Centres and diameters are those given in the spec, from the IAU Gazetteer of Planetary Nomenclature. Longitudes are east-positive, 0 to 360.

| Feature | Centre | Diameter |
|---|---|---|
| Tycho | 43.31 S, 348.64 E | 86 km |
| Copernicus | 9.62 N, 339.92 E | 96 km |
| Theophilus | 11.45 S, 26.28 E | 99 km |
| Highest point (near Engel'gardt) | 5.4 N, 201.4 E | |
| Lowest point (in Antoniadi) | 70.4 S, 187.5 E | |

## Method

All landmark measurements use `assets/elevation/lola_height_m_4096x2048.f32` (heights in metres above the 1737.4 km sphere). Cell (x, y) has its centre at longitude `360 (x + 0.5) / 4096` E and latitude `90 - 180 (y + 0.5) / 2048`. Distances are great-circle angles between cell centres and the landmark centre. A crater radius R in degrees is `(diameter / 2) / 1737.4` radians.

- **Global extremes (REQ-26):** the cells with the largest and smallest value, and their great-circle distance from the reference points.
- **Crater depth (REQ-27):** mean height of the cells between 0.9 R and 1.1 R from the centre, minus the smallest height within 0.3 R. The offset is the distance of that lowest cell from the Gazetteer centre.
- **Maria versus highlands (REQ-28):** unweighted mean of the cells whose centres lie in each box.
- **Albedo alignment (REQ-29):** in `assets/textures/lunar_albedo_4096x2048.png`, the albedo-weighted centroid (on the sphere) of the pixels within 1.5 R of the Copernicus elevation centre (the lowest cell found for Copernicus in REQ-27) that are brighter than the mean albedo of the 1.5 R to 3 R annulus around that same cell, compared with that cell. This is the method of the automated test `tools/moon-data/tests/landmarks.rs`.
- **Mesh (REQ-25, REQ-30):** every chunk vertex of the running scene. The expected radius is `1737.4 + h / 1000`, with `h` sampled as in REQ-15 at the vertex's own latitude and longitude.

## Results

### Global extremes (4096 x 2048 level)

| Quantity | Value | Location | Distance from reference | Requirement |
|---|---|---|---|---|
| Maximum | +10662.1 m | 5.405 N, 201.401 E | 0.005 degrees | at least 9000 m, within 3 degrees |
| Minimum | -9063.1 m | 70.356 S, 187.515 E | 0.044 degrees | at most -8000 m, within 3 degrees |

The source label gives the full-resolution range as -9125.5 m to +10773 m; averaging to 4096 x 2048 reduces the extremes slightly.

### Craters (4096 x 2048 level)

| Crater | Rim ring mean | Lowest within 0.3 R | Depth | Required | Lowest cell | Offset from centre |
|---|---|---|---|---|---|---|
| Tycho | +828.6 m (445 cells) | -3489.0 m | 4317.5 m | at least 3000 m | 42.935 S, 348.794 E | 0.276 R |
| Copernicus | -46.5 m (411 cells) | -3564.2 m | 3517.8 m | at least 2500 m | 9.976 N, 339.829 E | 0.232 R |
| Theophilus | -897.5 m (439 cells) | -4749.3 m | 3851.8 m | at least 2500 m | 11.118 S, 26.587 E | 0.274 R |

The offsets are below the 0.5 R limit. They are not near zero because each crater has a central peak, so the lowest floor cell lies beside the centre.

### Maria versus highlands

| Box | Mean height |
|---|---|
| Mare Imbrium, 25 N to 45 N, 330 E to 350 E | -2283.1 m |
| Far-side highlands, 0 to 20 N, 180 E to 200 E | +4282.5 m |

Difference 6565.6 m (requirement: at least 1500 m).

### Albedo and elevation alignment

`moon_data.json` lists the same `grid_convention` string and the same `extent` (0 to 360 E, 90 N to 90 S) for the albedo and for every elevation level.

Copernicus: mean albedo of the 1.5 R to 3 R annulus is 52.97 grey levels (6978 pixels). The albedo-weighted centroid of the 2103 brighter pixels within 1.5 R is at 10.069 N, 339.843 E. It lies 0.095 degrees from the lowest elevation cell of Copernicus (9.976 N, 339.829 E); with unit weights instead of albedo weights the offset is 0.106 degrees. Requirement: within 0.5 degrees.

### Mesh

| Quantity | Value | Requirement |
|---|---|---|
| Chunks | 96, each 65 x 65 vertices | 96, 65 x 65 |
| Vertices | 405 600 (393 218 distinct points) | 405 600 |
| Mean vertex radius | 1737.149 units | 1737.4 +/- 2 |
| Smallest and largest vertex radius | 1728.921 and 1747.732 units | within 1728.2 to 1748.2 |
| Largest difference between vertex radius and `1737.4 + h / 1000` | 0.00022 units (22 cm) | at most 0.001 |
| Longest to shortest triangle edge over the whole mesh, undisplaced | 2.30 (7.54 km to 17.37 km) | at most 3 |
| Largest longest-to-shortest edge ratio inside one triangle, undisplaced (the figure `tests/run_tests.gd` prints for REQ-21) | 1.849 | |
| Largest `u` difference inside a triangle | 0.25 | at most 0.5 |
| Shared edge points: largest position and normal difference between chunks | 0 and 0 | 1e-4 and 1e-3 |
| Vertices nearest +Y, +Z, +X | 90 N; (0 N, 0 E); (0 N, 90 E) with u = 0.25 | within 1 degree |
| Build time | 977 to 989 ms | measured, no limit |

Two notes on the method, for anyone repeating it:

- **Latitude of a vertex near a pole.** Vertex positions are 32-bit floats. Computing latitude as `asin(y / r)` loses precision near the poles (an error of about 1e-5 radians, 17 m on the ground, at 0.35 degrees from the pole), which moves the sampled height by up to 2.7 m at 30 vertices. Computing it as `atan2(y, sqrt(x^2 + z^2))` does not have this problem; the 22 cm figure above uses that form.
- **Normals at Tycho.** On the 7.5 to 10.7 km vertex grid, the vertices on Tycho's inner wall (about 24 to 40 km from the centre, for example 43.24 S, 347.34 E and 43.17 S, 350.16 E) have normals 10 to 16 degrees away from the radial direction. Vertices on the crater floor (within about 20 km of the centre) have normals 0.2 to 3 degrees from radial. The point 43.31 S, 347.9 E is 16 km from the centre, on the floor near the foot of the wall; the nearest vertex (43.32 S, 348.05 E) deviates by 0.47 degrees and the next one to the west (43.28 S, 347.70 E) by 6.57 degrees.

## Pending user checks (REQ-32)

These are visual and are not claimed as passed: (a) Tycho, Copernicus and the Imbrium basin recognisable as relief under low Sun; (b) no seam visible at 0 E or at cube-face edges; (c) no pinching or spikes near the poles; (d) albedo features sit on the matching relief.
