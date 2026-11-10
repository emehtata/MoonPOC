# Project: Moon POC – Realistic 3D Moon Renderer

## 1. Objective

Create a standalone Godot 4 project whose sole purpose is to render a realistic, three-dimensional Moon using the Godot Forward+ renderer with Vulkan.

This is a technical proof of concept for a future lunar taxi simulation game.

The immediate goal is to produce a visually convincing Moon with:
- Accurate lunar surface texture.
- Real elevation data.
- Visible craters, mountains, valleys and maria.
- Realistic directional sunlight and surface shadows.
- A freely controllable camera.
- Good rendering performance.

This is NOT a game yet.

Do not implement:
- Vehicles.
- Characters.
- Physics or collision systems.
- Gameplay.
- NPCs.
- Networking.
- User interfaces beyond basic debugging controls.

However, the underlying architecture must support future surface-level exploration and driving.

## 2. Technology requirements

- Godot 4.x.
- Renderer: Forward+.
- Rendering backend: Vulkan.
- GDScript for application logic.
- Rust is used for all offline geospatial data preparation. No Python anywhere in the project.
- Use native Godot rendering capabilities wherever possible.

Do not introduce unnecessary third-party rendering frameworks.

## 3. Scientific data sources

Investigate and use real NASA lunar datasets.

### Elevation data

Primary candidates:

- NASA LOLA (Lunar Orbiter Laser Altimeter).
- SLDEM2015 (combined LOLA and Kaguya elevation model).

Sources:
- https://pds-geosciences.wustl.edu/missions/lro/lola.htm
- https://pgda.gsfc.nasa.gov/products/54

Target resolution:
- 512 pixels per degree where available.

Requirements:
- Preserve real elevation values.
- Correctly interpret the original coordinate reference system.
- Handle NoData values.
- Document elevation units and vertical reference.
- Do not invent or procedurally replace missing elevation data without explicitly documenting it.

For the initial POC, a regional DEM is acceptable if a complete global DEM is too large or difficult to process.

### Surface texture

Investigate:
- LROC WAC Global Morphologic Mosaic.
- LROC WAC global imagery.
- NASA lunar surface imagery.

Sources:
- https://lroc.im-ldi.com/images/downloads
- https://data.lroc.im-ldi.com/

Requirements:
- Use genuine lunar imagery.
- Preserve the original texture projection.
- Avoid stretching or distorting the surface texture.
- Document the source, resolution and license of every dataset.

Do not assume that every NASA-hosted dataset has identical licensing or redistribution conditions.

## 4. Data preparation pipeline

Create an offline Rust tool (Cargo crate):

tools/moon-data/

Its responsibilities:

1. Read source DEM files.
2. Read source lunar imagery.
3. Inspect and validate geospatial metadata.
4. Convert data into formats suitable for Godot.
5. Generate appropriate resolution levels.
6. Generate normal maps where useful.
7. Preserve geographic alignment between elevation and imagery.
8. Generate a metadata file describing the processed datasets.

Prefer GDAL and rasterio for geospatial processing.

Do not load enormous source GeoTIFF files directly into Godot.

The preprocessing pipeline must be repeatable.

Keep source data separate from generated assets.

## 5. Moon geometry

Implement a spherical lunar terrain renderer.

Requirements:

- Use the real mean lunar radius of approximately 1,737.4 km.
- Use real elevation values to displace the lunar surface.
- Correctly map latitude and longitude to spherical coordinates.
- Avoid visible seams at the longitude boundary.
- Handle polar distortion appropriately.
- Preserve the correct orientation of the Moon.

Do not implement the Moon as a flat plane or a simple sphere with a displacement texture that only creates an illusion of elevation.

The geometry must represent actual surface elevation.

### Geometry architecture

Do not create one enormous, permanently subdivided mesh.

Design the geometry so it can eventually support:
- Multiple terrain chunks.
- Camera-dependent level of detail.
- High-resolution local terrain.
- Low-resolution distant terrain.
- Future surface-level camera movement.
- Future vehicle navigation.

For the initial POC, a simplified global mesh with a limited number of terrain subdivisions is acceptable.

Document the transition path to chunk-based terrain streaming.

## 6. Materials and lighting

Create a lunar surface material using Godot ShaderLanguage where appropriate.

Initial requirements:
- Genuine lunar surface albedo texture.
- Real geometric surface displacement.
- Physically plausible roughness.
- Directional sunlight.
- Strong crater shadows.
- No atmospheric scattering.
- No blue sky.
- No Earth-like environmental lighting.

Use a DirectionalLight3D to represent the Sun.

Allow the Sun's direction to be adjusted during testing.

The Moon should look like a real airless rocky body, not a stylized planet or a glossy sphere.

Do not artificially exaggerate surface colors or elevation.

## 7. Camera

Implement a freely controllable camera.

Required functionality:
- Orbit around the Moon.
- Zoom in and out.
- Rotate freely.
- Move closer to the surface.
- Inspect craters and terrain details.

Support both:
- Global orbital view.
- Close-up surface inspection.

Use an appropriate camera control scheme for desktop testing.

The camera architecture must not assume that the Moon's center is always the camera's reference point.

## 8. Performance

The POC must use GPU rendering through Forward+/Vulkan.

Investigate:
- Mesh subdivision cost.
- Vertex displacement cost.
- Texture memory consumption.
- Draw calls.
- Shader complexity.
- LOD requirements.

Avoid unnecessary CPU-side per-frame terrain calculations.

Do not prematurely implement a complex terrain streaming system, but make sure the initial implementation does not prevent one.

Provide basic FPS and rendering statistics for testing.

## 9. Project structure

Use a clean project structure, for example:

MoonPOC/
├── project.godot
├── scenes/
│   ├── main.tscn
│   └── moon.tscn
├── scripts/
│   ├── moon.gd
│   ├── moon_camera.gd
│   └── sun_controller.gd
├── shaders/
│   └── lunar_surface.gdshader
├── assets/
│   ├── textures/
│   ├── elevation/
│   └── materials/
├── tools/
│   └── moon-data/          (Rust crate)
└── docs/
    ├── DATA_SOURCES.md
    ├── ARCHITECTURE.md
    └── PERFORMANCE.md

Adjust the structure if there is a clear technical reason.

## 10. Testing and validation

Do not consider the POC complete merely because a sphere appears on screen.

Validate:

1. The Moon has the correct spherical shape.
2. Elevation data produces visible and geographically correct terrain.
3. Major lunar craters are recognizable.
4. Surface textures align with elevation data.
5. The longitude seam is not visible.
6. The poles do not contain catastrophic mapping artifacts.
7. Sunlight produces convincing crater shadows.
8. Camera movement remains stable at both orbital and surface distances.
9. The renderer actually uses Forward+/Vulkan.
10. Performance is measured and documented.

Use known lunar landmarks to validate geographic accuracy.

Do not create arbitrary test scenarios that do not represent meaningful lunar terrain.

## 11. Development workflow

Work incrementally.

Suggested milestones:

### Milestone 1 – Basic lunar globe
- Create the Godot project.
- Configure Forward+/Vulkan.
- Render a textured Moon.
- Implement camera controls.
- Implement adjustable sunlight.

### Milestone 2 – Real elevation
- Acquire a suitable DEM.
- Implement the data preparation pipeline.
- Generate displaced lunar geometry.
- Validate major surface features.

### Milestone 3 – Visual quality
- Improve lunar material.
- Improve shadows.
- Improve camera controls.
- Add appropriate normal mapping if useful.

### Milestone 4 – Performance and architecture
- Measure performance.
- Document geometry limitations.
- Define the future terrain chunk and LOD architecture.
- Document how high-resolution regional data can be streamed.

Each milestone should result in a working project.

## 12. Important constraints

- Do not build gameplay.
- Do not implement vehicle physics.
- Do not introduce a procedural substitute for real lunar elevation data.
- Do not use BIN technology for map-data architecture.
- Do not assume that the complete Moon must be rendered at maximum resolution simultaneously.
- Do not sacrifice scientific accuracy for visual shortcuts.
- Do not introduce unnecessary dependencies.
- Keep the project independent of any existing Road Rage Taxi codebase.

If a dataset is unavailable, requires authentication, has unclear licensing, or cannot be processed reliably, document the problem and investigate alternatives rather than silently substituting another dataset.

## 13. Final deliverables

The completed POC must include:

1. A working Godot project.
2. A realistic textured 3D Moon.
3. Real elevation-based terrain.
4. Adjustable sunlight.
5. Free camera controls.
6. A repeatable data preparation pipeline.
7. Documentation of all source datasets.
8. A performance report.
9. A documented architecture for future lunar terrain streaming.

The final result should provide a convincing visual foundation for a future Moon-based driving simulation.