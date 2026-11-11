extends SceneTree
var _frames := 0
func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
func _process(_d: float) -> bool:
	_frames += 1
	var main := root.get_child(root.get_child_count() - 1)
	if _frames == 60:
		var sun = main.get_node("Sun"); sun.set_sun(0.0, 0.0)
		var rig = main.get_node("CameraRig"); rig.distance = 6000.0; rig.orbit_basis = Basis.IDENTITY; rig._apply()
	if _frames == 90:
		root.get_texture().get_image().save_png("user://front_default.png")
		var sun = main.get_node("Sun"); sun.set_sun(180.0, 0.0)
		var rig = main.get_node("CameraRig"); rig.orbit_basis = Basis(Vector3.UP, PI); rig._apply()
	if _frames == 120:
		root.get_texture().get_image().save_png("user://seam_yaw180.png")
		print("SHOT_DONE")
		quit()
	return false
