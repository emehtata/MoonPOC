extends Node3D
## First-person fly camera and floating origin (spec lunar-surface-procedural, REQ-4 to REQ-6).
## Key F toggles between the orbit camera (CameraRig, unchanged) and this camera.
## The true position is kept in Moon-fixed kilometres as three doubles (GDScript floats), so
## centimetres survive. Below 100 km altitude the Moon (and Earth) are shifted by -origin and the
## camera node sits at position - origin; above 100 km the origin is 0 and the Moon is at identity.

const REFERENCE_RADIUS := 1737.4
const DEG_PER_PX := 0.2
const PITCH_LIMIT_DEG := 89.0
const MIN_SPEED_MS := 0.05
const MAX_SPEED_MS := 2000.0
const SPEED_NOTCH := 1.25
const FLOOR_M := 0.05
const NEAR_FAR_CAM := 0.05
const NEAR_CAM_NEAR := 1e-6
const NEAR_CAM_FAR := 20.0
const FAR := 440000.0
## Near camera cull mask: layer 1 + terrain layer 2 (Moon chunks, D9). Layer 2 alone renders the chunks unlit
## (black) in the overlay; layer 1 content is beyond the 20 km near-camera far plane, so it is not drawn.
const TERRAIN_LAYER_MASK := 3
const REBASE_DISTANCE_KM := 1.0
const FLOATING_ALTITUDE_KM := 100.0
## Quadtree depth used for the generated-surface height (finest LOLA depth, spec D4).
const SURFACE_DEPTH := 18
## REQ-25: below this altitude the shadow splits are fixed distances (km); above it M3 REQ-5 splits apply.
const CLOSE_SHADOW_ALTITUDE_KM := 10.0
const CLOSE_SPLITS_KM := [0.02, 0.2, 2.0]
const M3_SPLITS := [0.1, 0.2, 0.5]
## Sun shadow biases. Godot scales them by the light-space depth range (20 km pancake in this km-unit scene), so the
## defaults (0.1, 2.0) push shadows ~20 m and hide every rock and rim shadow; close to the ground use small ones.
const CLOSE_SHADOW_BIAS := 0.003
const CLOSE_SHADOW_NORMAL_BIAS := 0.5
const DEFAULT_SHADOW_BIAS := 0.1
const DEFAULT_SHADOW_NORMAL_BIAS := 2.0

signal toggled(fly: bool)
## Emitted after the floating origin moved (near-world nodes re-place themselves).
signal rebased

var terrain  # LunarTerrain (native); null when the library is missing
var active := false
## Moon-fixed position in km (doubles).
var px := 0.0
var py := 0.0
var pz := REFERENCE_RADIUS
## Look direction relative to the local horizon: yaw from north towards east, pitch up.
var yaw_deg := 0.0
var pitch_deg := 0.0
## Wheel multiplier on the automatic speed.
var speed_scale := 1.0
var origin := Vector3.ZERO  # integer km, exact in float32
var rebase_count := 0
## D9: transparent full-window SubViewport with the near camera, overlaid on the main viewport.
var near_viewport: SubViewport
var near_camera: Camera3D
var _overlay: CanvasLayer

@onready var camera: Camera3D = $Camera3D
@onready var _orbit: Node3D = get_node("../CameraRig")
@onready var _moon: Node3D = get_node("../Moon")
@onready var _earth: Node3D = get_node_or_null("../EarthRoot")
@onready var _sun: DirectionalLight3D = get_node_or_null("../Sun")


func _ready() -> void:
	camera.near = NEAR_FAR_CAM
	camera.far = FAR
	camera.current = false
	var layer := CanvasLayer.new()
	var container := SubViewportContainer.new()
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	near_viewport = SubViewport.new()
	near_viewport.transparent_bg = true
	near_viewport.world_3d = get_viewport().world_3d
	near_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	near_camera = Camera3D.new()
	near_camera.near = NEAR_CAM_NEAR
	near_camera.far = NEAR_CAM_FAR
	near_camera.cull_mask = TERRAIN_LAYER_MASK
	near_viewport.add_child(near_camera)
	container.add_child(near_viewport)
	layer.add_child(container)
	layer.visible = false
	add_child(layer)
	_overlay = layer


## Loads the native terrain on first use (so a missing library or data gives its ERROR line when fly
## mode is first requested, not at start-up). Fly mode stays disabled if it fails.
func _ensure_terrain() -> void:
	if terrain != null:
		return
	if not ClassDB.class_exists("LunarTerrain"):
		push_error("lunar-terrain native library missing: fly mode disabled, M2 mesh without procedural detail")
		return
	var t = ClassDB.instantiate("LunarTerrain")
	var problem: String = t.load_data(ProjectSettings.globalize_path("res://"))
	if problem != "":
		push_error("lunar-terrain data not loaded: %s" % problem)
		return
	terrain = t


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_F:
			set_active(not active)
			return
	if not active:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		yaw_deg = fposmod(yaw_deg + motion.relative.x * DEG_PER_PX, 360.0)
		pitch_deg = clampf(pitch_deg - motion.relative.y * DEG_PER_PX, -PITCH_LIMIT_DEG, PITCH_LIMIT_DEG)
		_apply()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			speed_scale *= SPEED_NOTCH
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			speed_scale /= SPEED_NOTCH


func _process(delta: float) -> void:
	if not active:
		return
	var m := Vector3.ZERO
	m.x = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
	m.y = float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q))
	m.z = float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S))
	advance(delta, m)


## Enters or leaves fly mode. Entering copies the orbit camera's position and view.
## Without the native library fly mode stays disabled (spec, edge cases).
func set_active(on: bool) -> void:
	if on == active:
		return
	if on:
		_ensure_terrain()
		if terrain == null:
			return
		var c: Camera3D = _orbit.camera
		set_position_km(c.global_position.x, c.global_position.y, c.global_position.z)
		_set_view_from(-c.global_basis.z)
		enter()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_set_origin(Vector3.ZERO)
		_set_bias(false)
		active = false
		_set_overlay(false)
		camera.current = false
		_orbit.camera.current = true
		toggled.emit(false)


## Switches to the fly camera at the current fly position.
func enter() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	active = true
	_set_overlay(true)
	camera.current = true
	_orbit.camera.current = false
	toggled.emit(true)
	_apply()


func _set_overlay(on: bool) -> void:
	_overlay.visible = on
	near_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	near_camera.current = on


## Sets the true position (km, Moon-fixed) and refreshes origin, camera and near plane.
func set_position_km(x: float, y: float, z: float) -> void:
	px = x
	py = y
	pz = z
	_apply()


## Places the camera at a point on the surface, `altitude_m` above the generated surface.
func place_at(lat_deg: float, lon_deg: float, altitude_m: float) -> void:
	var up := up_at(lat_deg, lon_deg)
	var r: float = REFERENCE_RADIUS + (terrain.height_m(lat_deg, lon_deg, SURFACE_DEPTH) + altitude_m) / 1000.0
	set_position_km(up.x * r, up.y * r, up.z * r)


func up_at(lat_deg: float, lon_deg: float) -> Vector3:
	var la := deg_to_rad(lat_deg)
	var lo := deg_to_rad(lon_deg)
	return Vector3(cos(la) * sin(lo), sin(la), cos(la) * cos(lo))


func _frame() -> Basis:
	# Columns: east, up, south (so -Z is north); +X east, +Y up, +Z back.
	var up := Vector3(px, py, pz).normalized()
	var east := Vector3.UP.cross(up)
	if east.length() < 1e-6:
		east = Vector3.RIGHT
	east = east.normalized()
	return Basis(east, up, east.cross(up))


func _set_view_from(forward: Vector3) -> void:
	var up := Vector3(px, py, pz).normalized()
	var f := forward.normalized()
	var fb := _frame()
	var h := f - up * f.dot(up)
	pitch_deg = clampf(rad_to_deg(asin(clampf(f.dot(up), -1.0, 1.0))), -PITCH_LIMIT_DEG, PITCH_LIMIT_DEG)
	yaw_deg = fposmod(rad_to_deg(atan2(h.dot(fb.x), h.dot(-fb.z))), 360.0) if h.length() > 1e-9 else 0.0


func view_basis() -> Basis:
	return _frame() * Basis(Vector3.UP, deg_to_rad(-yaw_deg)) * Basis(Vector3.RIGHT, deg_to_rad(pitch_deg))


## Height above the generated surface in km.
func height_above_ground_km() -> float:
	var r := sqrt(px * px + py * py + pz * pz)
	return r - REFERENCE_RADIUS - _surface_m() / 1000.0


func _surface_m() -> float:
	var r := sqrt(px * px + py * py + pz * pz)
	var lat := rad_to_deg(asin(clampf(py / r, -1.0, 1.0)))
	var lon := rad_to_deg(atan2(px, pz))
	return terrain.height_m(lat, fposmod(lon, 360.0), SURFACE_DEPTH)


## REQ-5: v = clamp(2 x height above ground, 0.05 m/s, 2000 m/s), times the wheel multiplier. In m/s.
func speed_ms() -> float:
	return clampf(2.0 * height_above_ground_km() * 1000.0, MIN_SPEED_MS, MAX_SPEED_MS) * speed_scale


## Moves by `delta` seconds; `m` = (right, up, forward) in [-1, 1]. Up is the local vertical.
func advance(delta: float, m: Vector3) -> void:
	var b := view_basis()
	var up := Vector3(px, py, pz).normalized()
	var dir := b.x * m.x + up * m.y + (-b.z) * m.z
	var step := speed_ms() / 1000.0 * delta
	px += dir.x * step
	py += dir.y * step
	pz += dir.z * step
	_apply()


## REQ-4 rendering: shifts the Moon (and Earth) so the camera stays near the origin.
func _set_origin(o: Vector3) -> void:
	if o == origin:
		return
	var delta := origin - o  # change of the world offset
	origin = o
	_moon.position = -o
	if _earth:
		_earth.position += delta
		var controller := _earth.get_node_or_null("EarthController")
		if controller:
			controller.world_offset = -o
	rebase_count += 1
	rebased.emit()


func _apply() -> void:
	if not active or terrain == null:
		return
	var r := sqrt(px * px + py * py + pz * pz)
	var altitude := r - REFERENCE_RADIUS
	var ground_m := _surface_m()
	# Camera stays at least 5 cm above the generated surface (REQ-5).
	var min_r := REFERENCE_RADIUS + (ground_m + FLOOR_M) / 1000.0
	if r < min_r:
		var k := min_r / r
		px *= k
		py *= k
		pz *= k
		r = min_r
	if altitude > FLOATING_ALTITUDE_KM:
		_set_origin(Vector3.ZERO)
	else:
		var off := Vector3(px - origin.x, py - origin.y, pz - origin.z)
		if off.length() > REBASE_DISTANCE_KM:
			_set_origin(Vector3(roundf(px), roundf(py), roundf(pz)))
	camera.transform = Transform3D(view_basis(), Vector3(px - origin.x, py - origin.y, pz - origin.z))
	_update_shadow(r, altitude)
	# REQ-6: the near camera shares the far camera's transform and field of view.
	near_camera.global_transform = camera.global_transform
	near_camera.fov = camera.fov


## REQ-25: the orbit rig's S(D) maximum distance (M3 REQ-6) with split fractions that give 0.02, 0.2 and 2 km
## below 10 km altitude. The orbit rig skips its own shadow update while this camera is active.
## shortcut: Godot clamps the shadow distance to each camera's far plane, so the 20 km near camera sees splits of
## 20 km x fraction, not the stated km values; upgrade by sizing the fractions per camera.
func _update_shadow(r: float, altitude: float) -> void:
	if _sun == null:
		return
	var max_d: float = load("res://scripts/moon_camera.gd").shadow_max_distance(r)
	_sun.directional_shadow_max_distance = max_d
	_set_bias(altitude < CLOSE_SHADOW_ALTITUDE_KM)
	_set_splits(CLOSE_SPLITS_KM.map(func(km): return km / max_d) if altitude < CLOSE_SHADOW_ALTITUDE_KM else M3_SPLITS)


func _set_bias(close: bool) -> void:
	if _sun:
		_sun.shadow_bias = CLOSE_SHADOW_BIAS if close else DEFAULT_SHADOW_BIAS
		_sun.shadow_normal_bias = CLOSE_SHADOW_NORMAL_BIAS if close else DEFAULT_SHADOW_NORMAL_BIAS


func _set_splits(f: Array) -> void:
	if _sun:
		_sun.directional_shadow_split_1 = f[0]
		_sun.directional_shadow_split_2 = f[1]
		_sun.directional_shadow_split_3 = f[2]


## Rendered position of a Moon-fixed point (km, doubles) relative to the camera: the world position
## (point - origin, subtracted in doubles) minus the camera node position.
func view_position(x: float, y: float, z: float) -> Vector3:
	return Vector3(x - origin.x, y - origin.y, z - origin.z) - camera.global_position


## Latitude and east longitude (degrees) below the camera.
func lat_lon() -> Array:
	var r := sqrt(px * px + py * py + pz * pz)
	return [rad_to_deg(asin(clampf(py / r, -1.0, 1.0))), fposmod(rad_to_deg(atan2(px, pz)), 360.0)]
