extends MeshInstance3D
## One procedural cloud shell (spec: docs/specs/earth-milestone-2-clouds.md). It only passes numbers to
## shaders/cloud.gdshader: the user settings and the drift / time-axis state derived from the streamed UTC.
## No wall-clock time source, no image or texture, no per-frame work.

const J2000_UNIX := 946728000.0  # 2000-01-01T12:00:00Z

## Share of the sphere that is cloud, 0..1 (values outside are clamped).
@export var coverage := 0.55:
	set(v):
		coverage = clampf(v, 0.0, 1.0)
		_push("coverage", coverage)
## Opacity scale, 0..1 (values outside are clamped).
@export var density := 1.0:
	set(v):
		density = clampf(v, 0.0, 1.0)
		_push("density", density)
## Drift about Earth-fixed +z in degrees per second, eastward positive (REQ-5).
@export var drift_deg_per_s := -9.0e-5
## Seconds for the noise to turn over completely along the time axis (REQ-6).
@export var shape_period_s := 21600.0

## Drift angle in degrees (0..360) and time-axis cell of the last applied time.
var drift_deg := 0.0
var time_cell := 0.0
var time_frac := 0.0


func _ready() -> void:
	_push("coverage", coverage)
	_push("density", density)


## Called with the `utc` string of each applied streamed line.
func apply_utc(utc: String) -> void:
	var t := Time.get_unix_time_from_datetime_string(utc) - J2000_UNIX
	# Doubles here; only reduced values reach the GPU, so float32 keeps sub-second resolution.
	drift_deg = fposmod(drift_deg_per_s * t, 360.0)
	var w := t / shape_period_s
	time_cell = floorf(w)
	time_frac = w - time_cell
	_push("drift_rad", deg_to_rad(drift_deg))
	_push("time_cell", time_cell)
	_push("time_frac", time_frac)


func _push(param: String, value: float) -> void:
	var mat := material_override as ShaderMaterial
	if mat:
		mat.set_shader_parameter(param, value)
