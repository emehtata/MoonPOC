extends Node
## Applies streamed Earth data (from the Sun controller's line_applied signal) to EarthRoot:
## global transform from earth_pos_godot / earth_basis_godot, and the monthly Blue Marble
## image for the UTC month of the line (hard switch, one texture at a time).
## EarthRoot's local frame is the Earth-fixed frame; EarthSurface is rotated in the scene so the
## sphere mesh (pole +Y, u = 0 at +Z) matches it (pole +Z, u = 0.5 at lon 0, +x = 0 deg E).

const TEXTURE_DIR := "res://assets/earth/bmng/"
const FILES := ["world.200401.3x5400x2700.jpg", "world.200402.3x5400x2700.jpg",
	"world.200403.3x5400x2700.jpg", "world.200404.3x5400x2700.jpg",
	"world.200405.3x5400x2700.jpg", "world.200406.3x5400x2700.jpg",
	"world.200407.3x5400x2700.jpg", "world.200408.3x5400x2700.jpg",
	"world.200409.3x5400x2700.jpg", "world.200410.3x5400x2700.jpg",
	"world.200411.3x5400x2700.jpg", "world.200412.3x5400x2700.jpg"]

@export var sun_path: NodePath = ^"../../Sun"

## Month (1..12) of the shown image, 0 before the first line.
var month := 0
var _missing_reported := false

@onready var _root: Node3D = get_parent()
@onready var _surface: MeshInstance3D = get_node("../EarthSurface")


func _ready() -> void:
	_root.visible = false
	get_node(sun_path).line_applied.connect(apply_line)


func apply_line(data: Dictionary) -> void:
	var p: Array = data["earth_pos_godot"]
	var b: Array = data["earth_basis_godot"]
	# earth_basis_godot is row-major; Basis(x, y, z) takes columns.
	var basis := Basis(Vector3(b[0], b[1], b[2]), Vector3(b[3], b[4], b[5]), Vector3(b[6], b[7], b[8])).transposed()
	_root.global_transform = Transform3D(basis, Vector3(p[0], p[1], p[2]))
	_root.visible = true
	for layer in ["CloudLower", "CloudUpper"]:
		get_node("../" + layer).apply_utc(data["utc"])
	var m := String(data["utc"]).substr(5, 2).to_int()
	if m != month:
		month = m
		_load_month(m)


func _load_month(m: int) -> void:
	var mat := _surface.get_surface_override_material(0) as StandardMaterial3D
	var path: String = TEXTURE_DIR + FILES[m - 1]
	var image: Image = Image.load_from_file(path) if FileAccess.file_exists(path) else null
	if image == null:
		mat.albedo_texture = null
		if not _missing_reported:
			_missing_reported = true
			push_error("Earth texture missing: %s. Run 'make earth-texture'." % path)
		return
	image.generate_mipmaps()
	mat.albedo_texture = ImageTexture.create_from_image(image)
