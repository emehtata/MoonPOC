extends SceneTree
## Scenario loader (spec lunar-surface-procedural, REQ-7).
## make scenario N=<1..11> CAM=<orbit|high|ground|1m|10cm|rock|ground_sun|ground_sun_close>   (HEADLESS=1 prints and exits 0)
## Run as: godot --path . --script scripts/scenario.gd -- N CAM [SUN_EL]
## SUN_EL (REQ-7a, degrees -90..90) replaces the scenario's Sun elevation; the azimuth stays.
## Optional 4th argument PT (1-based) picks that table point of the scenario (default 1); pass SUN_EL too, e.g. 10 ground 10 2.

const MAIN_SCENE := "res://scenes/main.tscn"
const REFERENCE_RADIUS := 1737.4
const AU_KM := 149597870.7
const SURFACE_DEPTH := 18
const CAMS := ["orbit", "high", "ground", "1m", "10cm", "rock", "ground_sun", "ground_sun_close"]
## Camera altitudes above the generated surface in metres; orbit is a distance of 6000 km.
## Scenario 6 CAM=rock: gap from the boulder surface so the ~22 m rock fits the frame.
const ROCK6_GAP_M := 45.0
## Scenario 6 CAM=ground: 30 m off the boulder surface, 12 m up, pitch -15 deg: looks down so the base and the cast shadow
## are in frame; at 75 deg vertical FOV the view spans -52..+22 deg, the 14 m top is about +3 deg.
const ROCK6_GROUND_GAP_M := 30.0
const ROCK6_GROUND_ALT_M := 12.0
const ROCK6_GROUND_PITCH_DEG := -15.0
## Scenario 6 CAM=ground_sun_close: same Sun side (yaw 315), 8 m off the boulder surface, 3 m up, pitch -15 deg: the view
## spans -52..+22 deg, the soil at the base lies at about -20 deg, so the base contact and the soil under it fill the lower frame.
const ROCK6_CLOSE_GAP_M := 8.0
const ROCK6_CLOSE_ALT_M := 3.0
const ROCK6_CLOSE_PITCH_DEG := -15.0
const ALTITUDE_M := {"high": 50000.0, "ground": 1.7, "1m": 1.0, "10cm": 0.1, "rock": 0.3}
const PITCH_DEG := -20.0
const D_MIN_M := 0.5
const COUNT_BOX_HALF_KM := 0.1

## [name, seed, [[lat, lon], ...], sun elevation, sun azimuth, crater density scale]
const SCENARIOS := {
	1: ["Flat plains", 1, [[0.674, 23.473]], 10.0, 90.0, 1.0],
	2: ["Dense small craters", 2, [[-8.973, 15.5]], 10.0, 90.0, 1.0],
	3: ["Large impact crater", 3, [[-43.31, 348.64]], 5.0, 90.0, 1.0],
	4: ["Overlapping craters", 4, [[-8.973, 15.5]], 15.0, 270.0, 3.0],
	5: ["Rocky terrain", 5, [[0.674, 23.473]], 10.0, 90.0, 1.0],
	6: ["Large boulders", 6, [[0.674, 23.473]], 8.0, 90.0, 1.0],
	7: ["Rim and interior", 7, [[0.674, 23.473]], 15.0, 90.0, 1.0],
	8: ["Steep terrain", 8, [[-43.24, 347.34]], 20.0, 90.0, 1.0],
	9: ["DEM-to-procedural", 9, [[26.13, 3.63]], 10.0, 90.0, 1.0],
	10: ["Chunk boundaries", 10, [[0.0, 45.0], [35.264, 45.0]], 10.0, 90.0, 1.0],
	11: ["Extreme close", 11, [[0.674, 23.473]], 10.0, 90.0, 1.0],
}

var _n := 0
var _cam := ""
var _sun_el := 0.0
var _pt := 0
var _terrain
var _frames := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or args.size() > 4 or not args[0].is_valid_int() or int(args[0]) < 1 or int(args[0]) > 11 or not CAMS.has(args[1]):
		printerr("usage: make scenario N=<1..11> CAM=<%s> [SUN_EL=<-90..90> [PT]]" % "|".join(CAMS))
		quit(2)
		return
	_n = int(args[0])
	_cam = args[1]
	_sun_el = SCENARIOS[_n][3]
	if args.size() >= 3:
		if not args[2].is_valid_float() or absf(args[2].to_float()) > 90.0:
			printerr("ERROR: SUN_EL must be a number from -90 to 90, got '%s'" % args[2])
			quit(2)
			return
		_sun_el = args[2].to_float()
	if args.size() == 4:
		if not args[3].is_valid_int() or int(args[3]) < 1 or int(args[3]) > SCENARIOS[_n][2].size():
			printerr("ERROR: PT must be 1..%d for scenario %d, got '%s'" % [SCENARIOS[_n][2].size(), _n, args[3]])
			quit(2)
			return
		_pt = int(args[3]) - 1
	if not ClassDB.class_exists("LunarTerrain"):
		printerr("ERROR: lunar-terrain native library missing (run 'make native')")
		quit(1)
		return
	_terrain = ClassDB.instantiate("LunarTerrain")
	var problem: String = _terrain.load_data(ProjectSettings.globalize_path("res://"))
	if problem != "":
		printerr("ERROR: %s" % problem)
		quit(1)
		return
	_terrain.seed = SCENARIOS[_n][1]
	_terrain.density_scale = SCENARIOS[_n][5]
	if DisplayServer.get_name() == "headless":
		_report()
		quit(0)
		return
	change_scene_to_file(MAIN_SCENE)


## Sun direction (Moon-fixed) for a local elevation/azimuth at a point (azimuth from north towards east).
static func sun_direction_at(lat_deg: float, lon_deg: float, elevation_deg: float, azimuth_deg: float) -> Vector3:
	var la := deg_to_rad(lat_deg)
	var lo := deg_to_rad(lon_deg)
	var up := Vector3(cos(la) * sin(lo), sin(la), cos(la) * cos(lo))
	var east := Vector3(cos(lo), 0.0, -sin(lo))
	var north := Vector3(-sin(la) * sin(lo), cos(la), -sin(la) * cos(lo))
	var el := deg_to_rad(elevation_deg)
	var az := deg_to_rad(azimuth_deg)
	return up * sin(el) + (north * cos(az) + east * sin(az)) * cos(el)


## Picks a crater within 1 km of a point (spec scenario table). Searches from the largest diameters down so
## the lattice scan stays small. `max_age` limits the age; returns [] if none, else the crater values.
func _pick_crater(lat: float, lon: float, min_d: float, max_age: float) -> Array:
	var here: Vector3 = _surface_unit(lat, lon) * REFERENCE_RADIUS
	var d := 256.0
	while d >= min_d * 0.999:
		var list: PackedFloat64Array = _terrain.crater_list(lat, lon, 1.0, d)
		var best := []
		for i in list.size() / 12:
			var c := list.slice(i * 12, i * 12 + 12)
			var centre := Vector3(c[5], c[6], c[7])
			if centre.distance_to(here) <= 1.0 and c[9] < max_age and c[8] >= min_d and (best.is_empty() or c[8] > best[8]):
				best = Array(c)
		if not best.is_empty():
			return best
		d /= 2.0
	return []


static func _surface_unit(lat: float, lon: float) -> Vector3:
	var la := deg_to_rad(lat)
	var lo := deg_to_rad(lon)
	return Vector3(cos(la) * sin(lo), sin(la), cos(la) * cos(lo))


## Latitude and longitude (degrees) of the east rim point of a crater (values as `crater_list`).
func _rim_point(c: Array) -> Array:
	var centre := Vector3(c[5], c[6], c[7])
	var up := centre.normalized()
	var east := Vector3.UP.cross(up).normalized()
	var rim_km: float = _terrain.crater_rim_m(c[8], int(c[10]), c[11], 0.0) / 1000.0
	var p: Vector3 = centre + east * rim_km
	return [rad_to_deg(asin(p.y / p.length())), fposmod(rad_to_deg(atan2(p.x, p.z)), 360.0)]


## Target point of the scenario: the table point, or the rim of the picked crater (scenarios 5 and 7).
## Scenario 6 takes the largest rock within 500 m (large rocks first, then medium).
func _target() -> Array:
	var point: Array = SCENARIOS[_n][2][_pt]
	var pick := []
	if _n == 6:
		var rock := _pick_rock(point[0], point[1], 0.5, [2, 1])
		if not rock.is_empty():
			var ll := _rock_lat_lon(rock)
			return [ll[0], ll[1], rock[19]]
	if _n == 5:
		pick = _pick_crater(point[0], point[1], D_MIN_M, 0.3)
	elif _n == 7:
		pick = _pick_crater(point[0], point[1], 100.0, 2.0)
	if pick.is_empty():
		return [point[0], point[1], 0.0]
	var rim := _rim_point(pick)
	return [rim[0], rim[1], pick[8]]

## Rock (22 values as rock_list) with the largest diameter within `half_km` metres of a point, trying the
## categories in order. [] if none.
func _pick_rock(lat: float, lon: float, half_km: float, categories: Array) -> Array:
	var here: Vector3 = _surface_unit(lat, lon) * REFERENCE_RADIUS
	for cat in categories:
		var list: PackedFloat64Array = _terrain.rock_list(lat, lon, half_km, cat)
		var best := []
		for i in list.size() / 22:
			var r := list.slice(i * 22, i * 22 + 22)
			if (Vector3(r[7], r[8], r[9]).normalized() * REFERENCE_RADIUS).distance_to(here) <= half_km and (best.is_empty() or r[19] > best[19]):
				best = Array(r)
		if not best.is_empty():
			return best
	return []


func _rock_lat_lon(r: Array) -> Array:
	var p := Vector3(r[7], r[8], r[9])
	return [rad_to_deg(asin(p.y / p.length())), fposmod(rad_to_deg(atan2(p.x, p.z)), 360.0)]


func _report() -> void:
	var s: Array = SCENARIOS[_n]
	print("scenario %d \"%s\" cam=%s seed=%d crater_density_scale=%s" % [_n, s[0], _cam, s[1], s[5]])
	var target := _target()
	print("  target lat=%.6f lon=%.6f (picked feature D=%.1f m, 0 = table point)" % [target[0], target[1], target[2]])
	# Local Sun elevation and azimuth read back from the direction that _setup() gives the Sun.
	var d := sun_direction_at(target[0], target[1], _sun_el, s[4])
	var up := _surface_unit(target[0], target[1])
	var east := Vector3(cos(deg_to_rad(target[1])), 0.0, -sin(deg_to_rad(target[1])))
	var north := up.cross(east)
	print("  sun local elevation=%.4f azimuth=%.4f" % [rad_to_deg(asin(clampf(d.dot(up), -1.0, 1.0))), fposmod(rad_to_deg(atan2(d.dot(east), d.dot(north))), 360.0)])
	for point in s[2]:
		var lat: float = point[0]
		var lon: float = point[1]
		print("  point lat=%s lon=%s height_m depth2=%.3f depth18=%.3f max_depth=%d" % [lat, lon,
			_terrain.height_m(lat, lon, 2), _terrain.height_m(lat, lon, SURFACE_DEPTH), _terrain.max_depth(lat, lon)])
		var craters: PackedFloat64Array = _terrain.crater_list(lat, lon, COUNT_BOX_HALF_KM, 0.0)
		print("  craters in a %d m box: %d" % [int(COUNT_BOX_HALF_KM * 2000.0), craters.size() / 12])
		# Small rocks are dense and slow to place, so they are counted in a 25 m box.
		print("  rocks: small (25 m box) %d, medium (200 m box) %d, large (200 m box) %d" % [
			_terrain.rock_list(lat, lon, 0.0125, 0).size() / 22, _terrain.rock_list(lat, lon, COUNT_BOX_HALF_KM, 1).size() / 22,
			_terrain.rock_list(lat, lon, COUNT_BOX_HALF_KM, 2).size() / 22])


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 3:
		_setup(root.get_child(root.get_child_count() - 1))
	return false


func _setup(main: Node) -> void:
	var s: Array = SCENARIOS[_n]
	var target := _target()
	var lat: float = target[0]
	var lon: float = target[1]
	# The live Sun is stopped only as a test step (M3 REQ-20); the fixed Sun is then set.
	var sun = main.get_node("Sun")
	sun._stop_helper(false)
	sun.has_sun = true
	sun.visible = true
	if sun.sun_distance_km == 0.0:
		sun.sun_distance_km = AU_KM
	var d := sun_direction_at(lat, lon, _sun_el, s[4])
	sun.set_sun(rad_to_deg(atan2(d.x, d.z)), rad_to_deg(asin(clampf(d.y, -1.0, 1.0))))
	var fly = main.get_node("FlyCamera")
	fly.terrain = _terrain
	_terrain.seed = s[1]
	if _cam == "orbit":
		var dir: Vector3 = fly.up_at(lat, lon)
		var rig = main.get_node("CameraRig")
		rig.distance = 6000.0
		rig.orbit_basis = Basis.looking_at(-dir, Vector3.UP if absf(dir.y) < 0.999 else Vector3.FORWARD)
		rig._apply()
		return
	fly.enter()
	if _cam == "rock":
		_place_at_rock(fly, lat, lon, ALTITUDE_M["rock"], ROCK6_GAP_M if _n == 6 else 0.3)  # scenario 6: whole boulder in view
		return
	if _n == 6 and _cam == "ground_sun_close":  # closer Sun-side view of the base contact (S7)
		_place_at_rock(fly, lat, lon, ROCK6_CLOSE_ALT_M, ROCK6_CLOSE_GAP_M, ROCK6_CLOSE_PITCH_DEG)
		return
	if _n == 6 and _cam == "ground_sun":  # Sun side (south-east, yaw 315, looks north-west): the lit east face and lit soil are in frame (S7)
		_place_at_rock(fly, lat, lon, ROCK6_GROUND_ALT_M, ROCK6_GROUND_GAP_M, ROCK6_GROUND_PITCH_DEG)
		return
	if _n == 6 and _cam == "ground":  # the table point is the rock's centre: stand ROCK6_GROUND_GAP_M off its surface instead
		_place_at_rock(fly, lat, lon, ROCK6_GROUND_ALT_M, ROCK6_GROUND_GAP_M, ROCK6_GROUND_PITCH_DEG)
		return
	fly.place_at(lat, lon, ALTITUDE_M["ground" if _cam.begins_with("ground_sun") else _cam])  # ground_sun only differs in scenario 6
	fly.yaw_deg = 0.0
	fly.pitch_deg = -90.0 if _cam == "high" else PITCH_DEG
	fly._apply()


## CAM=rock: 0.3 m from the surface of the picked rock (scenario 6) or the nearest medium rock. The camera
## stands on the Sun side (south-east of the rock, Sun in the east) and looks north-west at it, so it sees the
## lit east faces and the shadow that falls west of the rock. `gap_m` is the distance from the rock's surface.
func _place_at_rock(fly: Node3D, lat: float, lon: float, altitude_m: float = ALTITUDE_M["rock"], gap_m: float = 0.3, pitch_deg: float = -5.0) -> void:
	var rock := _pick_rock(lat, lon, 0.5, [2, 1]) if _n == 6 else _nearest_medium_rock(lat, lon)
	if rock.is_empty():
		push_warning("no medium rock within 100 m of the point; camera placed %s m above the ground" % altitude_m)
		fly.place_at(lat, lon, altitude_m)
		return
	var ll := _rock_lat_lon(rock)
	var dist_km: float = (rock[19] * 0.75 + gap_m) / 1000.0 * 0.7071
	var cam_lat: float = ll[0] - rad_to_deg(dist_km / REFERENCE_RADIUS)
	# scenario 6 ground stands south-west (looks north-east, yaw 45) so the west shadow lies left of the rock
	var east := -1.0 if _n == 6 and _cam == "ground" else 1.0
	var cam_lon: float = ll[1] + east * rad_to_deg(dist_km / (REFERENCE_RADIUS * cos(deg_to_rad(ll[0]))))
	fly.place_at(cam_lat, cam_lon, altitude_m)
	fly.yaw_deg = 45.0 if east < 0.0 else 315.0
	fly.pitch_deg = pitch_deg
	fly._apply()


func _nearest_medium_rock(lat: float, lon: float) -> Array:
	var here: Vector3 = _surface_unit(lat, lon) * REFERENCE_RADIUS
	var list: PackedFloat64Array = _terrain.rock_list(lat, lon, 0.1, 1)
	var best := []
	var best_d := INF
	for i in list.size() / 22:
		var r := list.slice(i * 22, i * 22 + 22)
		var dist := (Vector3(r[7], r[8], r[9]).normalized() * REFERENCE_RADIUS).distance_to(here)
		if dist < best_d:
			best_d = dist
			best = Array(r)
	return best
