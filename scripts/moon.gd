extends MeshInstance3D
## Lunar sphere: applies the processed LROC albedo texture with a matte
## StandardMaterial3D. The mesh is an undisplaced sphere (REQ-5).

const ALBEDO_PATH := "res://assets/textures/lunar_albedo_4096x2048.png"


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.metallic = 0.0
	material.roughness = 1.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if ResourceLoader.exists(ALBEDO_PATH):
		material.albedo_texture = load(ALBEDO_PATH)
	else:
		# No procedural fallback is allowed: the Moon renders plain and the error is visible.
		push_error("Moon albedo texture missing: %s" % ALBEDO_PATH)
	mesh.material = material
