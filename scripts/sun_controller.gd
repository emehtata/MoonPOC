extends DirectionalLight3D
## Sun direction from azimuth and elevation in the Moon's frame.
## d = (cos(el) sin(az), sin(el), cos(el) cos(az)) points from the Moon to the Sun;
## the light's forward (-Z) vector is -d.
## Startup azimuth/elevation come from the generated ephemeris file
## (azimuth = subsolar east longitude, elevation = subsolar latitude).

const AZIMUTH_STEP_DEG := 5.0
const ELEVATION_STEP_DEG := 5.0
const EPHEMERIS_PATH := "res://assets/ephemeris/sun_moon_fixed.json"
const FALLBACK_AZIMUTH_DEG := 45.0
const FALLBACK_ELEVATION_DEG := 20.0
const AU_KM := 149597870.7
const SUN_RADIUS_KM := 695700.0

@export var azimuth_deg: float = 45.0
@export var elevation_deg: float = 20.0

## Moon-to-Sun distance from the ephemeris file (1 AU if the file is unusable).
var sun_distance_km: float = AU_KM
var ephemeris_loaded := false


func _ready() -> void:
	_load_ephemeris()
	_apply()


func _load_ephemeris() -> void:
	var data = _read_ephemeris()
	if data == null:
		push_error("Ephemeris file missing or invalid: %s (falling back to azimuth 45, elevation 20, 1 AU)" % EPHEMERIS_PATH)
		set_sun(FALLBACK_AZIMUTH_DEG, FALLBACK_ELEVATION_DEG)
		sun_distance_km = AU_KM
		return
	sun_distance_km = data["sun_distance_km"]
	set_sun(data["subsolar_lon_deg"], data["subsolar_lat_deg"])
	ephemeris_loaded = true


## Returns the parsed dictionary, or null if the file is missing, unparsable,
## lacks a field, or holds a non-unit direction vector.
func _read_ephemeris() -> Variant:
	if not FileAccess.file_exists(EPHEMERIS_PATH):
		return null
	var text := FileAccess.get_file_as_string(EPHEMERIS_PATH)
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return null
	for key in ["subsolar_lon_deg", "subsolar_lat_deg", "sun_distance_km"]:
		if not (parsed.get(key) is float or parsed.get(key) is int):
			return null
	if float(parsed["sun_distance_km"]) <= SUN_RADIUS_KM:
		return null
	for key in ["sun_dir_moon_fixed", "sun_dir_godot"]:
		var v = parsed.get(key)
		if not (v is Array) or v.size() != 3:
			return null
		for c in v:
			if not (c is float or c is int):
				return null
		if absf(Vector3(v[0], v[1], v[2]).length() - 1.0) > 1e-6:
			return null
	return {
		"subsolar_lon_deg": float(parsed["subsolar_lon_deg"]),
		"subsolar_lat_deg": float(parsed["subsolar_lat_deg"]),
		"sun_distance_km": float(parsed["sun_distance_km"]),
	}


## True angular diameter of the Sun in degrees, 2 asin(R_sun / distance).
func sun_angular_diameter_deg() -> float:
	return rad_to_deg(2.0 * asin(SUN_RADIUS_KM / sun_distance_km))


func _unhandled_input(event: InputEvent) -> void:
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
