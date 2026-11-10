extends Node3D
## Orbit camera rig. The rig sits on `pivot`; the child Camera3D orbits it at
## `distance`, with yaw/pitch in degrees, and always looks at the pivot.

const DRAG_DEG_PER_PX := 0.2
const ZOOM_STEP := 0.9
const MIN_DISTANCE := 1737.9  # 0.5 km above the mean radius (REQ-18)
const MAX_DISTANCE := 20000.0
const PAN_PER_DISTANCE_PX := 0.0001
const MAX_PITCH_DEG := 89.0

@export var pivot: Vector3 = Vector3.ZERO

var distance: float = 6000.0
var yaw_deg: float = 0.0
var pitch_deg: float = 0.0

var _left_drag := false
var _middle_drag := false

@onready var camera: Camera3D = $Camera3D


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
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					_zoom(ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					_zoom(1.0 / ZOOM_STEP)
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _left_drag:
			yaw_deg = fposmod(yaw_deg - motion.relative.x * DRAG_DEG_PER_PX + 180.0, 360.0) - 180.0
			pitch_deg = clampf(pitch_deg + motion.relative.y * DRAG_DEG_PER_PX, -MAX_PITCH_DEG, MAX_PITCH_DEG)
		elif _middle_drag:
			var step := distance * PAN_PER_DISTANCE_PX
			var cam_basis := camera.global_basis
			pivot += (-cam_basis.x * motion.relative.x + cam_basis.y * motion.relative.y) * step
		else:
			return
		_apply()


func _zoom(factor: float) -> void:
	distance = clampf(distance * factor, MIN_DISTANCE, MAX_DISTANCE)
	_apply()


func _apply() -> void:
	var yaw := deg_to_rad(yaw_deg)
	var pitch := deg_to_rad(pitch_deg)
	var offset := Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw)) * distance
	position = pivot
	camera.transform = Transform3D(Basis.looking_at(-offset, Vector3.UP), offset)
