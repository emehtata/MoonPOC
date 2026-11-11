extends Node3D
## Orbit camera rig. The rig sits on `pivot`; the child Camera3D orbits it at
## `distance` along `orbit_basis`'s +Z axis, and looks at the pivot, turned by the
## look-mode `tilt_deg` and `heading_deg` (spec visual-quality-milestone-3, REQ-9 to REQ-11).
## Each frame it also sets the Sun's maximum shadow distance from the camera's
## distance to the Moon's centre (REQ-6).

const DRAG_DEG_PER_PX := 0.2
const ZOOM_STEP := 0.95
const FINE_ZOOM_ALTITUDE := 500.0  # at or below this altitude a notch is sqrt(ZOOM_STEP)
const MIN_DISTANCE := 1748.232  # from the Moon's centre: highest terrain radius 1747.732 + 0.5 km margin
const MAX_DISTANCE := 20000.0
const PAN_PER_DISTANCE_PX := 0.0001
const MAX_TILT_DEG := 85.0
const REFERENCE_RADIUS := 1737.4
## Default altitude A0 = 6000 - 1737.4; rates are scaled by min(1, altitude / A0).
const DEFAULT_ALTITUDE := 4262.6
const TERRAIN_MIN_RADIUS := 1728.2
const TERRAIN_MAX_RADIUS := 1747.732

@export var pivot: Vector3 = Vector3.ZERO

var distance: float = 6000.0
## Orientation of the camera-to-pivot view before look mode; identity = M1 REQ-21 start.
## Left drag is a trackball (M1 REQ-16): it rotates this basis about the camera's screen axes.
var orbit_basis := Basis.IDENTITY
var tilt_deg: float = 0.0
var heading_deg: float = 0.0

var _left_drag := false
var _middle_drag := false
var _right_drag := false

@onready var camera: Camera3D = $Camera3D
@onready var _moon: Node3D = get_node_or_null("../Moon")
@onready var _sun: DirectionalLight3D = get_node_or_null("../Sun")


func _ready() -> void:
	_apply()


func _process(_delta: float) -> void:
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				_left_drag = button.pressed
			MOUSE_BUTTON_MIDDLE:
				_middle_drag = button.pressed
			MOUSE_BUTTON_RIGHT:
				_right_drag = button.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					_zoom(1.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					_zoom(-1.0)
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _left_drag:
			var rate := DRAG_DEG_PER_PX * _rate_scale()
			# Screen axes of the (look-tilted) camera, re-read each event; the camera orbits opposite to the Moon.
			var screen := camera.global_basis
			var turn := Basis(screen.y, deg_to_rad(-motion.relative.x * rate)) * Basis(screen.x, deg_to_rad(-motion.relative.y * rate))
			orbit_basis = (turn * orbit_basis).orthonormalized()
		elif _middle_drag:
			var step := distance * PAN_PER_DISTANCE_PX * _rate_scale()
			var cam_basis := camera.global_basis
			pivot += (-cam_basis.x * motion.relative.x + cam_basis.y * motion.relative.y) * step
		elif _right_drag:
			tilt_deg = clampf(tilt_deg + motion.relative.y * DRAG_DEG_PER_PX, 0.0, MAX_TILT_DEG)
			heading_deg = fposmod(heading_deg - motion.relative.x * DRAG_DEG_PER_PX + 180.0, 360.0) - 180.0
		else:
			return
		_apply()


func _moon_centre() -> Vector3:
	return _moon.global_position if _moon else Vector3.ZERO


## Camera distance from the Moon's centre minus 1737.4.
func altitude() -> float:
	return camera.global_position.distance_to(_moon_centre()) - REFERENCE_RADIUS


func _rate_scale() -> float:
	return minf(1.0, altitude() / DEFAULT_ALTITUDE)


## Unit vector from the pivot to the camera.
func _offset_dir() -> Vector3:
	return orbit_basis.z


## REQ-9: one wheel notch sets distance * f^exponent (+1 in, -1 out), f chosen from the
## altitude before the step, then clamps so the camera stays >= MIN_DISTANCE from the Moon's centre.
func _zoom(exponent: float) -> void:
	var old := distance
	var f := ZOOM_STEP if altitude() > FINE_ZOOM_ALTITUDE else sqrt(ZOOM_STEP)
	var new_distance := minf(old * pow(f, exponent), MAX_DISTANCE)
	# Camera = pivot + dir * d; solve |p + dir * d| = MIN_DISTANCE with p relative to the centre.
	# shortcut: assumes the rig's parent has an identity transform (Main does); use its global transform if that changes.
	var p := pivot - _moon_centre()
	var dir := _offset_dir()
	if (p + dir * new_distance).length() < MIN_DISTANCE:
		var b := p.dot(dir)
		var root := sqrt(maxf(0.0, b * b - (p.length_squared() - MIN_DISTANCE * MIN_DISTANCE)))
		# Stop on the sphere at the side the camera came from.
		var far_root := -b + root
		distance = far_root if old >= far_root - 1e-6 else maxf(0.0, -b - root)
	else:
		distance = new_distance
	_apply()


func _apply() -> void:
	var offset := _offset_dir() * distance
	position = pivot
	var look := orbit_basis
	# REQ-11: heading about the camera-to-pivot axis, then tilt about the camera's own X axis.
	look = look * Basis(Vector3.FORWARD, deg_to_rad(heading_deg)) * Basis(Vector3.RIGHT, deg_to_rad(tilt_deg))
	camera.transform = Transform3D(look, offset)
	if _sun:
		_sun.directional_shadow_max_distance = shadow_max_distance(camera.global_position.distance_to(_moon_centre()))


## REQ-6: tangent distance to the lowest terrain sphere plus the distance from
## that tangent point to the highest terrain sphere.
static func shadow_max_distance(d_c: float) -> float:
	var near := sqrt(d_c * d_c - TERRAIN_MIN_RADIUS * TERRAIN_MIN_RADIUS) if d_c >= TERRAIN_MIN_RADIUS else 0.0
	return near + sqrt(TERRAIN_MAX_RADIUS * TERRAIN_MAX_RADIUS - TERRAIN_MIN_RADIUS * TERRAIN_MIN_RADIUS)
