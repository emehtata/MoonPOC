extends MeshInstance3D
## Sun disc: a filled, unshaded, camera-facing circle drawn in the current Sun
## direction d. Centre = camera position + d * DISC_DISTANCE; radius
## r = DISC_DISTANCE * R_sun / sun_distance_km, so 2 atan(r / D) equals the
## Sun's true angular diameter (uniform scale k = D / sun_distance_km).

const DISC_DISTANCE := 40000.0
const SEGMENTS := 256
const SUN_RADIUS_KM := 695700.0

@export var sun_path: NodePath = ^"../Sun"
@export var camera_path: NodePath = ^"../CameraRig/Camera3D"

var radius: float = 0.0

@onready var _sun: Node = get_node(sun_path)
@onready var _camera: Camera3D = get_node(camera_path)


func _ready() -> void:
	# Run after the camera rig has updated the camera for this frame.
	process_priority = 1000
	mesh = _build_disc_mesh()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1, 1, 1, 1)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	update_disc()


func _process(_delta: float) -> void:
	update_disc()


## Places and scales the disc from the current camera position and Sun direction.
func update_disc() -> void:
	visible = _sun.has_sun
	if not visible:
		return
	radius = DISC_DISTANCE * SUN_RADIUS_KM / _sun.sun_distance_km
	var d: Vector3 = _sun.sun_direction()
	var active_camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var cam_pos := (active_camera if active_camera else _camera).global_position
	var centre := cam_pos + d * DISC_DISTANCE
	var up := Vector3.UP
	if absf(d.y) > 0.999:
		up = Vector3.FORWARD
	# looking_at points -Z at the target; aim -Z away from the camera so the
	# disc normal (+Z) faces the camera.
	global_transform = Transform3D(Basis.looking_at(d, up).scaled(Vector3.ONE * radius), centre)


## Triangle fan in the local XY plane, radius 1, normal +Z.
func _build_disc_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	for i in SEGMENTS:
		var a0 := TAU * i / SEGMENTS
		var a1 := TAU * (i + 1) / SEGMENTS
		verts.append(Vector3.ZERO)
		verts.append(Vector3(cos(a1), sin(a1), 0.0))
		verts.append(Vector3(cos(a0), sin(a0), 0.0))
	for i in verts.size():
		normals.append(Vector3.BACK)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m
