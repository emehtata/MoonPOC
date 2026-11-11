extends DirectionalLight3D
## Sun direction from azimuth and elevation in the Moon's frame.
## d = (cos(el) sin(az), sin(el), cos(el) cos(az)) points from the Moon to the Sun;
## the light's forward (-Z) vector is -d.
## Azimuth/elevation come from the live stream of `moon-ephemeris --stream`
## (azimuth = subsolar east longitude, elevation = subsolar latitude), one line per second.
## Until the first line arrives there is no Sun: the light is hidden and the arrow keys do nothing.

const AZIMUTH_STEP_DEG := 5.0
const ELEVATION_STEP_DEG := 5.0
const HELPER_PATH := "res://ephemeris/target/x86_64-unknown-linux-musl/release/moon-ephemeris"
const SUN_RADIUS_KM := 695700.0
const FIELDS := ["utc", "jd_tt", "frame", "sun_dir_moon_fixed", "sun_dir_godot",
	"subsolar_lon_deg", "subsolar_lat_deg", "sun_distance_km", "sun_angular_diameter_deg",
	"earth_pos_godot", "earth_distance_km", "earth_basis_godot", "earth_sun_dir_godot",
	"earth_subsolar_lon_deg", "earth_subsolar_lat_deg"]

## Emitted after every applied streamed line (the Earth controller listens).
signal line_applied(data: Dictionary)

@export var azimuth_deg: float = 0.0
@export var elevation_deg: float = 0.0

## True once a streamed line has been applied.
var has_sun := false
## Values of the latest applied streamed line.
var sun_distance_km: float = 0.0
var utc: String = ""
var helper_pid: int = -1

var _stdio: FileAccess
var _buffer := PackedByteArray()
var _failed := false


func _ready() -> void:
	visible = false
	_start_helper()


func _start_helper() -> void:
	# REQ-24: MOON_SUN_HELPER overrides the helper path only.
	var path := OS.get_environment("MOON_SUN_HELPER")
	if path.is_empty():
		path = ProjectSettings.globalize_path(HELPER_PATH)
	if not FileAccess.file_exists(path):
		_fail("binary missing at %s" % path)
		return
	var info := OS.execute_with_pipe(path, ["--stream"], false)
	if info.is_empty():
		_fail("could not start %s" % path)
		return
	_stdio = info["stdio"]
	helper_pid = info["pid"]


## REQ-25: one ERROR line, no restart; the Sun keeps its last streamed position.
func _fail(cause: String) -> void:
	_failed = true
	push_error("Sun helper moon-ephemeris --stream: %s" % cause)
	_stop_helper(false)


func _process(_delta: float) -> void:
	if _failed or _stdio == null:
		return
	while true:
		var chunk := _stdio.get_buffer(4096)
		if chunk.is_empty():
			break
		_buffer.append_array(chunk)
	var nl := _buffer.find(10)
	while nl >= 0:
		var line := _buffer.slice(0, nl).get_string_from_utf8()
		_buffer = _buffer.slice(nl + 1)
		var data = parse_line(line)
		if data == null:
			_fail("invalid line: %s" % line.left(200))
			return
		apply_line(data)
		nl = _buffer.find(10)
	if not OS.is_process_running(helper_pid):
		_fail("helper process %d stopped" % helper_pid)


## Returns the parsed dictionary, or null if the line is unparsable, lacks a
## field, or holds a non-unit direction vector.
static func parse_line(text: String) -> Variant:
	# JSON.parse() returns an error code without printing, unlike parse_string (REQ-25: one ERROR line).
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	var parsed = json.data
	if not (parsed is Dictionary):
		return null
	for key in FIELDS:
		if not parsed.has(key):
			return null
	for key in ["subsolar_lon_deg", "subsolar_lat_deg", "sun_distance_km"]:
		if not (parsed[key] is float or parsed[key] is int):
			return null
	if not (parsed["utc"] is String) or float(parsed["sun_distance_km"]) <= SUN_RADIUS_KM:
		return null
	for key in ["sun_dir_moon_fixed", "sun_dir_godot"]:
		var v = parsed[key]
		if not (v is Array) or v.size() != 3:
			return null
		for c in v:
			if not (c is float or c is int):
				return null
		if absf(Vector3(v[0], v[1], v[2]).length() - 1.0) > 1e-6:
			return null
	return parsed if _earth_fields_valid(parsed) else null


## Earth fields: numbers, unit sun direction, orthonormal basis (tolerance 1e-6).
static func _earth_fields_valid(d: Dictionary) -> bool:
	for key in ["earth_distance_km", "earth_subsolar_lon_deg", "earth_subsolar_lat_deg"]:
		if not (d[key] is float or d[key] is int):
			return false
	for key in ["earth_pos_godot", "earth_sun_dir_godot", "earth_basis_godot"]:
		var v = d[key]
		if not (v is Array) or v.size() != (9 if key == "earth_basis_godot" else 3):
			return false
		for c in v:
			if not (c is float or c is int):
				return false
	var s: Array = d["earth_sun_dir_godot"]
	if absf(Vector3(s[0], s[1], s[2]).length() - 1.0) > 1e-6:
		return false
	var b: Array = d["earth_basis_godot"]
	var rows := [Vector3(b[0], b[1], b[2]), Vector3(b[3], b[4], b[5]), Vector3(b[6], b[7], b[8])]
	for i in 3:
		if absf(rows[i].length() - 1.0) > 1e-6 or absf(rows[i].dot(rows[(i + 1) % 3])) > 1e-6:
			return false
	return true


func apply_line(data: Dictionary) -> void:
	utc = data["utc"]
	sun_distance_km = float(data["sun_distance_km"])
	has_sun = true
	visible = true
	set_sun(float(data["subsolar_lon_deg"]), float(data["subsolar_lat_deg"]))
	line_applied.emit(data)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_stop_helper(true)


func _exit_tree() -> void:
	_stop_helper(true)


## REQ-26: kill by PID, then confirm it is gone within 2 s.
func _stop_helper(report: bool) -> void:
	_stdio = null
	if helper_pid <= 0:
		return
	var pid := helper_pid
	helper_pid = -1
	if OS.is_process_running(pid):
		# OS.kill also reaps the child, after which OS.is_process_running prints an engine error.
		OS.execute("kill", ["-TERM", str(pid)])
	var deadline := Time.get_ticks_msec() + 2000
	while OS.is_process_running(pid):
		if Time.get_ticks_msec() > deadline:
			if report:
				push_error("Sun helper moon-ephemeris --stream (PID %d) still running 2 s after kill" % pid)
			return
		OS.delay_msec(10)


## True angular diameter of the Sun in degrees, 2 asin(R_sun / distance).
func sun_angular_diameter_deg() -> float:
	return rad_to_deg(2.0 * asin(SUN_RADIUS_KM / sun_distance_km))


func _unhandled_input(event: InputEvent) -> void:
	if not has_sun:
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_LEFT:
			set_sun(azimuth_deg - AZIMUTH_STEP_DEG, elevation_deg)
		KEY_RIGHT:
			set_sun(azimuth_deg + AZIMUTH_STEP_DEG, elevation_deg)
		KEY_UP:
			set_sun(azimuth_deg, elevation_deg + ELEVATION_STEP_DEG)
		KEY_DOWN:
			set_sun(azimuth_deg, elevation_deg - ELEVATION_STEP_DEG)


func set_sun(azimuth: float, elevation: float) -> void:
	azimuth_deg = fposmod(azimuth, 360.0)
	elevation_deg = clampf(elevation, -90.0, 90.0)
	_apply()


func sun_direction() -> Vector3:
	var az := deg_to_rad(azimuth_deg)
	var el := deg_to_rad(elevation_deg)
	return Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az))


func _apply() -> void:
	var d := sun_direction()
	var up := Vector3.UP
	if absf(d.y) > 0.999:
		up = Vector3.FORWARD
	global_basis = Basis.looking_at(-d, up)
