# Project Extension: Living Earth – Realistic Procedural Planet Rendering

## 1. Objective

Implement a realistic, living Earth as a visible celestial body in the existing Moon POC project.

The Moon remains the primary object and stays at the center of the scene.

Earth must appear in the lunar sky as a fully rendered 3D planet, not as a skybox, billboard or static background image.

The goal is to create a visually convincing Earth with:

- Realistic continents and oceans.
- Procedurally generated cloud formations.
- Independently moving cloud layers.
- Seasonal snow and ice coverage.
- Correct Earth's axial tilt.
- Realistic solar illumination.
- Day and night transitions.
- Earth's rotation.
- A subtle atmospheric blue glow.

The implementation must use Godot 4 Forward+ with Vulkan.

Prioritize visual quality, scientific plausibility and rendering performance.

## 2. Earth architecture

Create a modular Earth rendering system.

Suggested scene structure:

EarthRoot
├── EarthSurface
├── EarthSeasonalSnow
├── EarthPermanentIce
├── EarthSeaIce
├── EarthClouds
│   ├── CloudLayerLow
│   └── CloudLayerHigh
├── EarthAtmosphere
└── EarthController

Each component should have a clearly defined responsibility.

Keep the implementation independent of the Moon terrain rendering system, while sharing the same astronomical coordinate system and simulation clock.

## 3. Earth surface texture

Use one high-quality, geographically accurate global Earth texture as the base surface.

Recommended source:
NASA Blue Marble.

https://science.nasa.gov/earth/earth-observatory/blue-marble-next-generation/base-map/

Requirements:

- Use a neutral global surface texture.
- Include recognizable continents, oceans, deserts and vegetation.
- Avoid a strongly seasonal base texture.
- Use equirectangular projection or another projection supported by the rendering implementation.
- Preserve correct geographic alignment.
- Use appropriate mipmaps.
- Avoid unnecessary texture resolution.

A 5400 × 2700 texture is sufficient for the initial implementation.

Higher resolution can be introduced later if visual testing demonstrates a need.

Do not use 12 separate monthly surface textures.

Seasonal changes must be implemented as separate material layers.

## 4. Procedural cloud generation

Clouds must be generated procedurally rather than relying on a static cloud texture.

Implement at least two independently controlled cloud layers.

### Lower cloud layer

Characteristics:
- Large cloud formations.
- Broad cloud systems.
- Relatively dense cloud coverage.
- Soft cloud boundaries.

### Upper cloud layer

Characteristics:
- Smaller cloud formations.
- Thin cloud structures.
- More fragmented patterns.
- Different movement speed and direction.

### Procedural generation

Use shader-based procedural noise.

Suitable techniques include:
- 3D Perlin noise.
- Simplex noise.
- Fractal Brownian Motion (FBM).
- Multiple noise frequencies.
- Domain warping where appropriate.

Important requirements:

- Generate noise using spherical direction coordinates rather than simple UV coordinates.
- Avoid visible seams at the longitude boundary.
- Avoid polar distortion.
- Ensure continuous cloud patterns across the entire sphere.
- Support adjustable cloud coverage and density.
- Animate cloud movement continuously.
- Allow different movement speeds for different layers.

Clouds should rotate independently of the Earth's surface.

Cloud movement should be subtle and organic, not resemble a rotating static pattern.

Clouds must receive realistic solar illumination.

Their appearance should change naturally between the illuminated and dark sides of Earth.

Do not make the cloud layers unnecessarily thick or opaque.

## 5. Seasonal snow and ice system

Implement a procedural seasonal surface system.

Do not switch between monthly Earth textures.

Instead, create separate masks and material layers.

Distinguish three types of snow and ice:

### A. Permanent ice

Represent relatively permanent ice coverage, particularly:

- Antarctica.
- Greenland.
- Major permanent glacial regions.

Use a geographically accurate base mask.

This coverage should not disappear simply because the simulation date changes.

### B. Seasonal continental snow

Create a procedural seasonal snow mask.

The mask must account for:

- Latitude.
- Hemisphere.
- Simulation date.
- Seasonal temperature approximation.
- Land distribution.
- Elevation.
- Geographic variation.
- Procedural noise.

Northern and Southern Hemisphere seasons must be opposite.

Examples:

- January: Northern Hemisphere winter.
- July: Southern Hemisphere winter.
- March and September: seasonal transitions.

Snow coverage should gradually expand and contract rather than changing abruptly.

Use geographically varying thresholds to avoid perfectly circular snow boundaries.

Do not simply paint white bands around the poles.

### C. Seasonal sea ice

Create a separate sea ice mask for:

- Arctic Ocean.
- Antarctic Ocean.

Sea ice must:
- Expand during the local winter.
- Contract during the local summer.
- Respect ocean boundaries.
- Follow the correct seasonal cycle in both hemispheres.

Use procedural geographic variation to create natural-looking boundaries.

### Material blending

Blend snow and ice into the underlying surface.

Requirements:
- Natural transitions.
- No hard circular boundaries.
- Appropriate brightness and roughness.
- Correct solar illumination.
- No visible texture alignment artifacts.

Keep snow, permanent ice and sea ice as separate systems so they can be independently adjusted.

The initial implementation is a visual seasonal approximation, not a full climate simulation.

Document this limitation.

## 6. Earth's axial tilt and rotation

Implement Earth's actual astronomical orientation.

Important constants:

- Axial tilt: approximately 23.44 degrees.
- Sidereal rotation period: approximately 23 hours, 56 minutes.
- Mean Earth radius: approximately 6,371 km.

Requirements:

- Represent Earth's rotation axis explicitly.
- Maintain its orientation in the inertial astronomical coordinate system.
- Do not tilt the axis back and forth during the year.
- Rotate Earth independently around its own axis.
- Ensure geographic coordinates remain consistent with the rotation.
- Calculate the orientation from the simulation date and time.

The axial tilt must influence actual solar illumination.

Validate:

- June solstice: Northern Hemisphere tilted toward the Sun.
- December solstice: Southern Hemisphere tilted toward the Sun.
- March equinox: neither hemisphere preferentially tilted toward the Sun.
- September equinox: neither hemisphere preferentially tilted toward the Sun.

Do not simulate seasons by artificially changing surface colors or lighting intensity.

## 7. Solar illumination

Use the same Sun and astronomical coordinate system as the Moon.

Earth and Moon must share a common solar direction.

Requirements:

- Correct day/night boundary.
- Correct terminator position.
- Correct hemisphere illumination.
- Realistic night-side darkness.
- Appropriate ocean and land material response.
- Cloud illumination based on the same Sun direction.

The Earth's visible phase from the Moon must emerge naturally from the relative positions of the Sun, Earth and Moon.

Do not implement Earth phases as manually selected textures.

Optional:
Add subtle night-side city illumination using a separate low-intensity emission texture.

Do not let night lights overpower the natural appearance of Earth.

## 8. Atmospheric rendering

Create a separate atmospheric shell.

Use a shader-based Fresnel effect or another suitable approximation.

Requirements:

- Thin blue atmospheric rim.
- Stronger visible rim near the planet's edge.
- Subtle atmospheric scattering approximation.
- Correct illumination dependence.
- No exaggerated neon-blue glow.

The atmosphere should make Earth recognizable as a living planet without looking stylized.

## 9. Earth position relative to the Moon

Earth must be positioned in the Moon-centered astronomical coordinate system.

Do not attach Earth to the camera.

Do not use a skybox or billboard.

Use real astronomical dimensions and distances.

Reference values:

- Mean Earth radius: approximately 6,371 km.
- Mean lunar distance: approximately 384,400 km.
- Earth angular diameter as seen from the Moon: approximately 1.9 degrees.

The apparent size must result from the actual geometry and camera projection.

The Moon must correctly occlude Earth when the camera moves to the far side.

For a lunar surface observer:

- Earth should remain approximately fixed in the sky.
- Implement lunar libration if practical.
- Account for the observer's position on the lunar surface.
- Earth should be below the horizon on the far side of the Moon.

Do not artificially move Earth across the lunar sky to create an Earthrise effect.

## 10. Shared astronomical clock

Create or reuse one central simulation time system.

All celestial rendering components must use the same simulation date and time.

The clock must control:

- Earth's rotation.
- Earth's seasonal snow coverage.
- Seasonal sea ice.
- Cloud animation.
- Solar position.
- Earth's illumination.
- Earth's visible phase.
- Moon illumination.

Provide a simple debugging interface or configuration mechanism for changing simulation time.

Support:
- Arbitrary dates.
- Arbitrary times.
- Time acceleration.
- Time reversal.

Test at least:

- January 15.
- March equinox.
- June solstice.
- September equinox.
- December solstice.

The implementation must work for arbitrary dates, not only predefined seasonal test dates.

## 11. Performance requirements

The system must be suitable for real-time rendering.

Use GPU shaders for procedural cloud and seasonal mask calculations wherever practical.

Avoid:
- Per-frame CPU generation of large textures.
- Unnecessary texture switching.
- Excessive transparent overdraw.
- Excessively detailed Earth geometry.
- Unnecessary draw calls.
- Expensive noise calculations where simpler alternatives produce equivalent visual quality.

Use appropriate texture resolution and mipmapping.

Provide adjustable quality settings for:
- Cloud complexity.
- Cloud coverage.
- Earth surface resolution.
- Atmospheric effects.
- Seasonal mask resolution.

Measure actual GPU and CPU performance.

## 12. Testing and validation

Create repeatable visual tests.

Test the following:

1. Earth is correctly positioned relative to the Moon.
2. Earth has the correct apparent size.
3. The Moon correctly occludes Earth.
4. Earth's rotation works correctly.
5. Axial tilt is correct.
6. Seasonal snow coverage changes appropriately.
7. Permanent ice remains present.
8. Arctic and Antarctic sea ice follow opposite seasonal cycles.
9. Cloud layers move independently.
10. Cloud patterns contain no visible spherical seams.
11. Solar illumination is consistent between Earth and Moon.
12. Earth phases emerge naturally from astronomical geometry.
13. Atmospheric rendering looks realistic.
14. Performance remains acceptable.

Use meaningful astronomical test dates rather than arbitrary camera positions.

Document known visual and scientific approximations.

## 13. Development milestones

### Milestone 1 – Basic Earth

- Create EarthRoot.
- Render a textured Earth sphere.
- Implement correct scale and position.
- Implement Earth's rotation.
- Connect Earth to the shared Sun direction.

### Milestone 2 – Procedural clouds

- Implement lower cloud layer.
- Implement upper cloud layer.
- Implement spherical noise.
- Add independent cloud animation.
- Validate seams and polar behavior.

### Milestone 3 – Seasonal appearance

- Implement permanent ice.
- Implement seasonal continental snow.
- Implement seasonal sea ice.
- Connect all seasonal calculations to simulation date.
- Validate both hemispheres.

### Milestone 4 – Atmospheric effects and optimization

- Implement atmospheric rim.
- Improve cloud lighting.
- Optimize shaders.
- Measure performance.
- Adjust visual quality.

Each milestone must produce a working and testable result.

## 14. Important constraints

- Do not modify or replace the existing Moon terrain implementation.
- Do not introduce gameplay features.
- Do not use a skybox or billboard for Earth.
- Do not use 12 monthly Earth surface textures.
- Do not use static cloud images as the primary cloud rendering solution.
- Do not artificially animate Earth's axial tilt.
- Do not independently calculate solar direction in different components.
- Do not introduce arbitrary astronomical offsets.
- Do not sacrifice correct geographic orientation for visual shortcuts.
- Keep the implementation modular and suitable for future expansion.

Use NASA and other scientifically reliable sources for geographic and astronomical reference data.

Document all external data sources, licenses, assumptions and approximations.

## 15. Final deliverables

The completed implementation must include:

1. A realistic 3D Earth visible from the Moon.
2. A geographically accurate base surface texture.
3. Two procedural animated cloud layers.
4. A procedural seasonal snow system.
5. Permanent polar ice.
6. Seasonal Arctic and Antarctic sea ice.
7. Correct axial tilt.
8. Correct Earth rotation.
9. Shared solar illumination.
10. Atmospheric blue rim.
11. Correct apparent size and position relative to the Moon.
12. Performance measurements.
13. Technical documentation.

The final result should make Earth look like a living, slowly changing planet in the lunar sky.

Scientific plausibility and visual realism take priority over unnecessary complexity.