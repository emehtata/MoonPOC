extends RefCounted
## Test-only GDScript copy of the cloud opacity in shaders/cloud.gdshader (spec: earth-milestone-2-clouds.md, REQ-20).
## Used by tests/run_tests.gd (test_cloud_sampling) to evaluate opacity headless with the spec's small sample counts.
## Each function names the shader function it copies. SHADER_LINES lists every formula line of the copy; the test
## checks each one is present in shaders/cloud.gdshader, so an edited shader line fails the test.
## Differences: float64 here, float32 in the shader; uint32 wrap is emulated with masks; the shader's
## interpolated mesh direction is replaced by the exact unit direction.

const M32 := 0xFFFFFFFF
const INV_2_32 := 2.3283064e-10
const HALF_PI_SHADER := 1.5707963


## (a * b) mod 2^32 for a, b in [0, 2^32), without int64 overflow.
static func mul32(a: int, b: int) -> int:
	var al := a & 0xFFFF
	var ah := a >> 16
	return (al * b + (((ah * b) & 0xFFFF) << 16)) & M32


## hash3(ivec3 c, uint salt): uvec3 arithmetic with 32-bit wrap.
static func hash3(cx: int, cy: int, cz: int, salt: int) -> Vector3:
	var vx := (mul32(cx & M32, 1664525) + 1013904223 + salt) & M32
	var vy := (mul32(cy & M32, 1664525) + 1013904223 + salt) & M32
	var vz := (mul32(cz & M32, 1664525) + 1013904223 + salt) & M32
	vx = (vx + mul32(vy, vz)) & M32
	vy = (vy + mul32(vz, vx)) & M32
	vz = (vz + mul32(vx, vy)) & M32
	vx ^= vx >> 16
	vy ^= vy >> 16
	vz ^= vz >> 16
	vx = (vx + mul32(vy, vz)) & M32
	vy = (vy + mul32(vz, vx)) & M32
	vz = (vz + mul32(vx, vy)) & M32
	return Vector3(vx, vy, vz) * INV_2_32


## vnoise(vec3 p, uint salt): value noise, returns the trilinear mix of the .x hash at the 8 corners.
static func vnoise(p: Vector3, salt: int) -> float:
	var i := Vector3(floorf(p.x), floorf(p.y), floorf(p.z))
	var f := p - i  # shader: fract(p)
	f = f * f * f * (f * (f * 6.0 - Vector3(15.0, 15.0, 15.0)) + Vector3(10.0, 10.0, 10.0))
	var cx := int(i.x)
	var cy := int(i.y)
	var cz := int(i.z)
	var x00 := mixf(hash3(cx, cy, cz, salt).x, hash3(cx + 1, cy, cz, salt).x, f.x)
	var x10 := mixf(hash3(cx, cy + 1, cz, salt).x, hash3(cx + 1, cy + 1, cz, salt).x, f.x)
	var x01 := mixf(hash3(cx, cy, cz + 1, salt).x, hash3(cx + 1, cy, cz + 1, salt).x, f.x)
	var x11 := mixf(hash3(cx, cy + 1, cz + 1, salt).x, hash3(cx + 1, cy + 1, cz + 1, salt).x, f.x)
	return mixf(mixf(x00, x10, f.y), mixf(x01, x11, f.y), f.z)


## fbm(vec3 p): four octaves, each centred on zero.
static func fbm(p_in: Vector3) -> float:
	var p := p_in
	var sum := 0.0
	var amp := 1.0
	for k in 4:
		sum += amp * (vnoise(p, 7) - 0.5)
		p = p * 2.03 + Vector3(17.1, 31.7, 5.3)
		amp *= 0.5
	return sum


## time_offset(float cell)
static func time_offset(cell: float) -> Vector3:
	return hash3(int(cell), 11, 23, 99) * 64.0


static func mixf(a: float, b: float, t: float) -> float:
	return a * (1.0 - t) + b * t


## Fragment up to u. m_in is the mesh-frame direction (pole +Y, as VERTEX). Returns u in 0..1.
static func u_mesh(m_in: Vector3, drift_rad: float, time_cell: float, time_frac: float,
		frequency: float, spread: float) -> float:
	var m := m_in.normalized()
	var ef := Vector3(-m.z, -m.x, m.y)
	var c := cos(drift_rad)
	var s := sin(drift_rad)
	var p := Vector3(c * ef.x + s * ef.y, -s * ef.x + c * ef.y, ef.z) * frequency
	var a := cos(HALF_PI_SHADER * time_frac)
	var b := sin(HALF_PI_SHADER * time_frac)
	var n := a * fbm(p + time_offset(time_cell)) + b * fbm(p + time_offset(time_cell + 1.0))
	return 1.0 / (1.0 + exp(-clampf(n / spread, -30.0, 30.0)))


## ALPHA from u, coverage, density, cap and softness (the shader's edge and ALPHA lines).
static func alpha_from_u(u: float, coverage: float, density: float, cap: float, softness: float) -> float:
	var edge := (u - (1.0 - clampf(coverage, 0.0, 1.0)) + 0.05 * softness) / softness
	var step_cov := 1.0 if coverage >= 0.001 else 0.0
	return cap * clampf(density, 0.0, 1.0) * clampf(edge, 0.0, 1.0) * step_cov


## Every formula line the copy above depends on, copied from shaders/cloud.gdshader.
const SHADER_LINES := [
	"uvec3 v = uvec3(c) * 1664525u + 1013904223u + uvec3(salt);",
	"v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;",
	"v ^= v >> 16u;",
	"return vec3(v) * 2.3283064e-10;",
	"f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);",
	"return mix(mix(x00, x10, f.y), mix(x01, x11, f.y), f.z);",
	"sum += amp * (vnoise(p, 7u) - 0.5);",
	"p = p * 2.03 + vec3(17.1, 31.7, 5.3);",
	"amp *= 0.5;",
	"return hash3(ivec3(int(cell), 11, 23), 99u) * 64.0;",
	"vec3 m = normalize(mesh_dir);",
	"vec3 ef = vec3(-m.z, -m.x, m.y);",
	"float c = cos(drift_rad);",
	"float s = sin(drift_rad);",
	"vec3 p = vec3(c * ef.x + s * ef.y, -s * ef.x + c * ef.y, ef.z) * frequency;",
	"float a = cos(1.5707963 * time_frac);",
	"float b = sin(1.5707963 * time_frac);",
	"float n = a * fbm(p + time_offset(time_cell)) + b * fbm(p + time_offset(time_cell + 1.0));",
	"float u = 1.0 / (1.0 + exp(-clamp(n / spread, -30.0, 30.0)));",
	"float edge = (u - (1.0 - clamp(coverage, 0.0, 1.0)) + 0.05 * softness) / softness;",
	"ALPHA = cap * clamp(density, 0.0, 1.0) * clamp(edge, 0.0, 1.0) * step(0.001, coverage);",
]
