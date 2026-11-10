extends SceneTree
## Headless tests for docs/specs/moon-globe-milestone-1.md (REQ-1..REQ-25, except REQ-8 visual and REQ-24 run-time).
## Run with: make test   (godot --headless --path . --script tests/run_tests.gd)
## Input is delivered by calling _unhandled_input on the rig and the sun (the
## viewport is not inside the tree during _initialize, so push_input cannot be used).

const MAIN_SCENE := "res://scenes/main.tscn"
const TEXTURE := "res://assets/textures/lunar_albedo_4096x2048.png"
const DATA_SOURCES := "res://docs/DATA_SOURCES.md"
const RAW_DIR := "res://data/raw/lroc_wac_gmm_100m/"

var _passed := 0
var _main: Node = null
var _failed := 0


func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("PASS  %s" % name)
	else:
		_failed += 1
		print("FAIL  %s  (%s)" % [name, detail])


func near(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol


func vec_near(a: Vector3, b: Vector3, tol: float) -> bool:
	return a.distance_to(b) <= tol


func spawn_main() -> Node:
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(main)
	_main = main
	return main


func free_main(main: Node) -> void:
	# Free immediately so no stale rig or sun receives later input.
	root.remove_child(main)
	main.free()


func send_key(e: InputEventKey) -> void:
	_main.get_node("Sun")._unhandled_input(e)


func send_mouse(e: InputEvent) -> void:
	_main.get_node("CameraRig")._unhandled_input(e)


func mouse_button(btn: int, pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = pressed
	e.position = Vector2.ZERO
	return e


func mouse_motion(rel: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.relative = rel
	e.position = Vector2.ZERO
	return e


func key_press(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	e.echo = false
	return e


var _started := false


func _initialize() -> void:
	# Nodes added during _initialize are not ready yet, so the tests run on the first frame.
	pass


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	run_all()
	return false


func run_all() -> void:
	test_project()
	test_scene()
	test_moon_geometry()
	test_moon_material_and_texture()
	test_texture_seam()
	test_sun()
	test_sun_ephemeris_and_disc()
	test_audit()
	test_camera()
	test_data_sources()
	test_repo_scan()
	print("RESULT: %d total, %d passed, %d failed" % [_passed + _failed, _passed, _failed])
	quit(1 if _failed > 0 else 0)


# ---------------------------------------------------------------- project

func test_project() -> void:
	check("REQ-1: project name is 'Moon POC'",
		ProjectSettings.get_setting("application/config/name") == "Moon POC",
		str(ProjectSettings.get_setting("application/config/name")))

	var text := FileAccess.get_file_as_string("res://project.godot")
	var lines := text.split("\n")
	var has_cv5 := false
	for line in lines:
		if line.strip_edges() == "config_version=5":
			has_cv5 = true
	check("REQ-1: project.godot has config_version=5", has_cv5)

	check("REQ-2: project.godot contains renderer/rendering_method=\"forward_plus\"",
		text.contains("renderer/rendering_method=\"forward_plus\""))
	check("REQ-2: project.godot contains rendering_device/driver=\"vulkan\"",
		text.contains("rendering_device/driver=\"vulkan\""))
	check("REQ-2: project settings report forward_plus and vulkan",
		ProjectSettings.get_setting("rendering/renderer/rendering_method") == "forward_plus"
		and ProjectSettings.get_setting("rendering/rendering_device/driver") == "vulkan")

	# REQ-3 needs a real Vulkan device; headless runs use the dummy driver.
	check("REQ-3: RenderingServer reports forward_plus at runtime",
		RenderingServer.get_current_rendering_method() == "forward_plus",
		"reported '%s'" % RenderingServer.get_current_rendering_method())
	check("REQ-3: RenderingServer reports vulkan driver at runtime",
		RenderingServer.get_current_rendering_driver_name() == "vulkan",
		"reported '%s'" % RenderingServer.get_current_rendering_driver_name())

	check("REQ-4: main scene setting points at res://scenes/main.tscn",
		ProjectSettings.get_setting("application/run/main_scene") == MAIN_SCENE)


# ---------------------------------------------------------------- scene tree

func test_scene() -> void:
	var main := spawn_main()
	check("REQ-4: scene contains Moon (MeshInstance3D)",
		main.get_node_or_null("Moon") is MeshInstance3D)
	check("REQ-4: scene contains CameraRig with a Camera3D child",
		main.get_node_or_null("CameraRig") is Node3D
		and main.get_node_or_null("CameraRig/Camera3D") is Camera3D)
	check("REQ-4: scene contains Sun (DirectionalLight3D)",
		main.get_node_or_null("Sun") is DirectionalLight3D)
	check("REQ-4: scene contains WorldEnvironment",
		main.get_node_or_null("WorldEnvironment") is WorldEnvironment)

	var sun := main.get_node_or_null("Sun") as DirectionalLight3D
	check("REQ-10: Sun is a DirectionalLight3D named Sun with shadow_enabled",
		sun != null and sun.name == "Sun" and sun.shadow_enabled)
	check("REQ-10: Sun is controlled by scripts/sun_controller.gd",
		sun != null and sun.get_script() != null
		and str(sun.get_script().resource_path).ends_with("scripts/sun_controller.gd"))

	var env_node := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var env: Environment = env_node.environment if env_node else null
	check("REQ-14: environment exists", env != null)
	if env != null:
		check("REQ-14: background mode is solid color",
			env.background_mode == Environment.BG_COLOR)
		check("REQ-14: background color is black",
			env.background_color.is_equal_approx(Color(0, 0, 0, 1)),
			str(env.background_color))
		check("REQ-14: ambient light source is disabled",
			env.ambient_light_source == Environment.AMBIENT_SOURCE_DISABLED,
			str(env.ambient_light_source))
		check("REQ-14: fog is disabled", not env.fog_enabled)
		check("REQ-14: glow is disabled", not env.glow_enabled)
	free_main(main)


# ---------------------------------------------------------------- moon geometry

func test_moon_geometry() -> void:
	var main := spawn_main()
	var moon := main.get_node("Moon") as MeshInstance3D
	var sphere := moon.mesh as SphereMesh
	check("REQ-5: Moon mesh is a SphereMesh", sphere != null)
	if sphere == null:
		free_main(main)
		return
	check("REQ-5: sphere radius is 1737.4", near(sphere.radius, 1737.4, 0.0001), str(sphere.radius))
	check("REQ-5: sphere segments meet the assumed minimum (>=256 radial, >=128 rings)",
		sphere.radial_segments >= 256 and sphere.rings >= 128,
		"radial %d rings %d" % [sphere.radial_segments, sphere.rings])

	var verts: PackedVector3Array = moon.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var max_dev := 0.0
	var min_r := INF
	var max_r := -INF
	for v in verts:
		var r := v.length()
		max_dev = maxf(max_dev, absf(r - 1737.4))
		min_r = minf(min_r, r)
		max_r = maxf(max_r, r)
	check("REQ-5: all %d sampled vertices lie within 1737.4 +/- 0.1 of the center" % verts.size(),
		max_dev <= 0.1, "min %.4f max %.4f" % [min_r, max_r])
	check("REQ-5: no displacement (min and max radius equal within 0.1)",
		max_r - min_r <= 0.2, "min %.4f max %.4f" % [min_r, max_r])

	# Moon at identity transform, so local orientation equals world orientation.
	check("REQ-7: Moon node is at identity transform",
		moon.transform.is_equal_approx(Transform3D.IDENTITY))

	var uvs: PackedVector2Array = moon.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	# North pole: the vertex with the highest y must be at direction +Y.
	var top := verts[0]
	for v in verts:
		if v.y > top.y:
			top = v
	check("REQ-7: north pole direction maps to +Y",
		vec_near(top.normalized(), Vector3.UP, 0.001), str(top.normalized()))

	# Vertex nearest UV (u=0, v=0.5) is (0 N, 0 E); u wraps, so use wrapped distance.
	var best_i := _nearest_uv(uvs, Vector2(0.0, 0.5))
	# The mesh has no vertex exactly on the equator (rings sit about 0.35 deg off), so use an angular tolerance.
	check("REQ-7: (0 N, 0 E) direction maps to +Z (within 0.5 deg)",
		verts[best_i].normalized().angle_to(Vector3.BACK) < deg_to_rad(0.5),
		str(verts[best_i].normalized()))

	# Equirectangular UV: longitude 90 E (u=0.25) lies on +X (east), consistent with +Z and +Y.
	var east_i := _nearest_uv(uvs, Vector2(0.25, 0.5))
	check("REQ-6: u=0.25 (90 E on equator) maps to +X (east), so texture is not mirrored (within 0.5 deg)",
		verts[east_i].normalized().angle_to(Vector3.RIGHT) < deg_to_rad(0.5),
		str(verts[east_i].normalized()))

	# Full mapping check: every vertex must sit at the equirectangular position of its own UV.
	# u = longitude/360 (east = +X at 90 E, prime meridian = +Z), v = (90 - latitude)/180 (v=0 at +Y).
	var worst := 0.0
	for i in verts.size():
		var lon := uvs[i].x * TAU
		var lat := (0.5 - uvs[i].y) * PI
		var expected := Vector3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon))
		worst = maxf(worst, verts[i].normalized().distance_to(expected))
	check("REQ-6: every vertex matches the equirectangular mapping of its UV (max error %.5f)" % worst,
		worst < 0.002, "max error %.5f" % worst)
	free_main(main)


func load_png_image(path: String) -> Image:
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	return img


func _nearest_uv(uvs: PackedVector2Array, target: Vector2) -> int:
	var best := 0
	var best_d := INF
	for i in uvs.size():
		var du := absf(uvs[i].x - target.x)
		du = minf(du, 1.0 - du)
		var d := du * du + (uvs[i].y - target.y) * (uvs[i].y - target.y)
		if d < best_d:
			best_d = d
			best = i
	return best


# ---------------------------------------------------------------- material and texture

func test_moon_material_and_texture() -> void:
	var main := spawn_main()
	var moon := main.get_node("Moon") as MeshInstance3D
	var mat := moon.mesh.material as StandardMaterial3D
	check("REQ-9: Moon uses a StandardMaterial3D", mat != null)
	if mat != null:
		check("REQ-9: metallic == 0.0", mat.metallic == 0.0, str(mat.metallic))
		check("REQ-9: roughness >= 0.9", mat.roughness >= 0.9, str(mat.roughness))
		check("REQ-6: albedo texture is assets/textures/lunar_albedo_4096x2048.png",
			mat.albedo_texture != null
			and str(mat.albedo_texture.resource_path) == TEXTURE,
			"resource_path '%s'" % (str(mat.albedo_texture.resource_path) if mat.albedo_texture else "null"))
		if mat.albedo_texture != null:
			check("REQ-6: albedo texture is 4096 x 2048 pixels",
				mat.albedo_texture.get_width() == 4096 and mat.albedo_texture.get_height() == 2048,
				"%d x %d" % [mat.albedo_texture.get_width(), mat.albedo_texture.get_height()])
	var img := load_png_image(TEXTURE)
	check("REQ-6: texture file loads and is 4096 x 2048",
		img != null and img.get_width() == 4096 and img.get_height() == 2048)
	check("REQ-6: texture file exists in the project (no procedural fallback)",
		FileAccess.file_exists(TEXTURE))
	free_main(main)


# ---------------------------------------------------------------- REQ-8 seam

func test_texture_seam() -> void:
	var img := load_png_image(TEXTURE)
	if img == null:
		check("REQ-8: texture loads for seam check", false, "no image")
		return
	var w := img.get_width()
	var h := img.get_height()
	var means := PackedFloat64Array()
	means.resize(w - 1)
	var signed_means := PackedFloat64Array()
	signed_means.resize(w - 1)
	for c in range(w - 1):
		var s := 0.0
		var sg := 0.0
		var n := 0
		for r in range(0, h, 4):
			var a := img.get_pixel(c, r).r * 255.0
			var b := img.get_pixel(c + 1, r).r * 255.0
			s += absf(a - b)
			sg += b - a
			n += 1
		means[c] = s / n
		signed_means[c] = sg / n
	# Seam between column 2047 (179.98 E) and 2048 (180 E).
	var seam := means[2047]
	var others: Array[float] = []
	for c in range(w - 1):
		if c != 2047:
			others.append(means[c])
	others.sort()
	var p99: float = others[int(0.99 * others.size())]
	var median: float = others[others.size() / 2]
	var wrap := means[w - 1 - 1]  # column 4094 vs 4095 is not the wrap; compute wrap below
	var wrap_img_diff := 0.0
	for r in range(0, h, 4):
		wrap_img_diff += absf(img.get_pixel(w - 1, r).r - img.get_pixel(0, r).r) * 255.0
	wrap_img_diff /= float(h / 4)
	# REQ-8 is a human visual check on the target display. The spec states there is
	# no numeric or automated seam threshold, so no pass/fail assertion is made here.
	# The metrics are printed for the record only and do not count as a pass.
	print("INFO  REQ-8 (visual check pending, performed by user): seam metrics only, not a pass/fail test")
	print("INFO  REQ-8 seam column 2047|2048 mean|diff| %.2f, other-column median %.2f, p99 %.2f, signed step %.2f grey levels" % [
		seam, median, p99, signed_means[2047]])
	print("INFO  REQ-8 wrap column 4095|0 mean|diff| %.2f, p99 %.2f" % [wrap_img_diff, p99])


# ---------------------------------------------------------------- sun

func test_sun() -> void:
	var main := spawn_main()
	var sun := main.get_node("Sun") as DirectionalLight3D
	var ctl = sun
	# TEST_ISSUE fix: M1 REQ-12 (45/20) is replaced by sun-ephemeris REQ-15. The startup
	# values are the subsolar longitude and latitude in assets/ephemeris/sun_moon_fixed.json.
	var eph := read_ephemeris()
	check("REQ-12 (replaced by sun-ephemeris REQ-15): default azimuth and elevation are the ephemeris subsolar values",
		near(ctl.azimuth_deg, float(eph["subsolar_lon_deg"]), 0.0001)
		and near(ctl.elevation_deg, float(eph["subsolar_lat_deg"]), 0.0001),
		"az %.3f el %.3f" % [ctl.azimuth_deg, ctl.elevation_deg])

	ctl.set_sun(90.0, 30.0)
	var fwd := -sun.global_basis.z
	check("REQ-11: az 90, el 30 gives forward = -(0.866, 0.5, 0) within 0.001",
		vec_near(fwd, Vector3(-0.866025, -0.5, 0.0), 0.001), str(fwd))

	var cases := [[0.0, 0.0], [123.0, -60.0], [270.0, 45.0], [359.0, 89.0], [200.0, -10.0]]
	for c in cases:
		ctl.set_sun(c[0], c[1])
		var az := deg_to_rad(c[0])
		var el := deg_to_rad(c[1])
		var d := Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az))
		check("REQ-11: az %s el %s forward equals -d" % [c[0], c[1]],
			vec_near(-sun.global_basis.z, -d, 0.001),
			str(-sun.global_basis.z))

	for el in [90.0, -90.0]:
		ctl.set_sun(77.0, el)
		var f := -sun.global_basis.z
		check("REQ-11: elevation %s gives finite direction, azimuth still applied" % el,
			is_finite(f.x) and is_finite(f.y) and is_finite(f.z)
			and near(ctl.azimuth_deg, 77.0, 0.0001) and near(f.y, -signf(el), 0.001),
			str(f))

	# Keyboard controls (REQ-13), routed through the viewport input pipeline.
	ctl.set_sun(45.0, 20.0)
	send_key(key_press(KEY_RIGHT))
	check("REQ-13: Right arrow changes azimuth by +5 (45 -> 50)",
		near(ctl.azimuth_deg, 50.0, 0.0001), str(ctl.azimuth_deg))
	send_key(key_press(KEY_UP))
	check("REQ-13: Up arrow changes elevation by +5 (20 -> 25)",
		near(ctl.elevation_deg, 25.0, 0.0001), str(ctl.elevation_deg))
	send_key(key_press(KEY_LEFT))
	check("REQ-13: Left arrow changes azimuth by -5 (50 -> 45)",
		near(ctl.azimuth_deg, 45.0, 0.0001), str(ctl.azimuth_deg))
	send_key(key_press(KEY_DOWN))
	check("REQ-13: Down arrow changes elevation by -5 (25 -> 20)",
		near(ctl.elevation_deg, 20.0, 0.0001), str(ctl.elevation_deg))

	ctl.set_sun(358.0, 88.0)
	send_key(key_press(KEY_RIGHT))
	send_key(key_press(KEY_UP))
	send_key(key_press(KEY_UP))
	send_key(key_press(KEY_UP))
	check("REQ-13: wrap and clamp: az 358 Right then el 88 Up x3 gives az 3 and el 90",
		near(ctl.azimuth_deg, 3.0, 0.0001) and near(ctl.elevation_deg, 90.0, 0.0001),
		"az %.3f el %.3f" % [ctl.azimuth_deg, ctl.elevation_deg])

	ctl.set_sun(2.0, -88.0)
	send_key(key_press(KEY_LEFT))
	check("REQ-13: azimuth wraps below 0 (2 Left gives 357)",
		near(ctl.azimuth_deg, 357.0, 0.0001), str(ctl.azimuth_deg))
	send_key(key_press(KEY_DOWN))
	send_key(key_press(KEY_DOWN))
	check("REQ-13: elevation clamps at -90",
		near(ctl.elevation_deg, -90.0, 0.0001), str(ctl.elevation_deg))
	free_main(main)


# ---------------------------------------------------------------- sun ephemeris and sun disc (sun-ephemeris spec)

const EPHEMERIS := "res://assets/ephemeris/sun_moon_fixed.json"
const SUN_DISC_DISTANCE := 40000.0
const SUN_RADIUS_KM := 695700.0


func read_ephemeris() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(EPHEMERIS))
	if parsed is Dictionary:
		return parsed
	return {}


func test_sun_ephemeris_and_disc() -> void:
	var eph := read_ephemeris()
	check("sun-ephemeris REQ-14: committed ephemeris file has utc 2026-11-10T00:00:00Z",
		eph.get("utc") == "2026-11-10T00:00:00Z", str(eph.get("utc")))
	var lon := float(eph["subsolar_lon_deg"])
	var lat := float(eph["subsolar_lat_deg"])
	var gd: Array = eph["sun_dir_godot"]
	var dist_km := float(eph["sun_distance_km"])
	var ang_deg := float(eph["sun_angular_diameter_deg"])

	var main := spawn_main()
	var sun := main.get_node("Sun") as DirectionalLight3D
	var ctl = sun
	var disc = main.get_node("SunDisc")  # untyped: update_disc() is defined by sun_disc.gd
	var rig := main.get_node("CameraRig") as Node3D
	var cam := rig.get_node("Camera3D") as Camera3D

	# REQ-15: startup values come from the file and the light follows M1 REQ-11.
	check("sun-ephemeris REQ-15: startup azimuth equals subsolar_lon_deg (+/- 0.001)",
		near(ctl.azimuth_deg, lon, 0.001), "%s vs %s" % [ctl.azimuth_deg, lon])
	check("sun-ephemeris REQ-15: startup elevation equals subsolar_lat_deg (+/- 0.001)",
		near(ctl.elevation_deg, lat, 0.001), "%s vs %s" % [ctl.elevation_deg, lat])
	var fwd := -sun.global_basis.z
	check("sun-ephemeris REQ-15: light forward equals -sun_dir_godot per component (+/- 0.001)",
		absf(fwd.x + gd[0]) <= 0.001 and absf(fwd.y + gd[1]) <= 0.001 and absf(fwd.z + gd[2]) <= 0.001,
		str(fwd))

	# REQ-16: Right arrow once from the ephemeris start, then the disc follows the new direction.
	send_key(key_press(KEY_RIGHT))
	check("sun-ephemeris REQ-16: Right arrow once gives azimuth = subsolar_lon_deg + 5 (mod 360)",
		near(ctl.azimuth_deg, fposmod(lon + 5.0, 360.0), 0.0001), str(ctl.azimuth_deg))
	disc.update_disc()
	var d: Vector3 = ctl.sun_direction()
	var from_cam: Vector3 = (disc.global_position - cam.global_position) / SUN_DISC_DISTANCE
	check("sun-ephemeris REQ-16: SunDisc direction from the camera equals the new d (+/- 0.001 per component)",
		absf(from_cam.x - d.x) <= 0.001 and absf(from_cam.y - d.y) <= 0.001 and absf(from_cam.z - d.z) <= 0.001,
		"%s vs %s" % [from_cam, d])
	send_key(key_press(KEY_UP))
	check("sun-ephemeris REQ-16: Up arrow once gives elevation = subsolar_lat_deg + 5",
		near(ctl.elevation_deg, lat + 5.0, 0.0001), str(ctl.elevation_deg))
	# Restore the ephemeris start state for the remaining checks.
	ctl.set_sun(lon, lat)
	disc.update_disc()
	d = ctl.sun_direction()

	# REQ-17: position, orientation, material and shadow settings at the default camera state.
	check("sun-ephemeris REQ-17: SunDisc position = camera + 40000 d (+/- 1 unit), default camera state",
		disc.global_position.distance_to(cam.global_position + d * SUN_DISC_DISTANCE) <= 1.0,
		str(disc.global_position))
	var normal: Vector3 = disc.global_basis.z.normalized()
	var to_cam: Vector3 = (cam.global_position - disc.global_position).normalized()
	check("sun-ephemeris REQ-17: disc normal points to the camera", normal.dot(to_cam) > 0.9999,
		"normal %s to_cam %s" % [normal, to_cam])
	var mat := disc.material_override as BaseMaterial3D
	check("sun-ephemeris REQ-17: disc material is unshaded",
		mat != null and mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED)
	check("sun-ephemeris REQ-17: disc does not cast shadows",
		disc.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, str(disc.cast_shadow))

	# REQ-17 after zooming to the minimum distance (1737.9): centre still at camera + 40000 d.
	for i in 50:
		send_mouse(mouse_button(MOUSE_BUTTON_WHEEL_UP, true))
	check("sun-ephemeris REQ-17: after zooming in, camera distance is 1737.9 (minimum)",
		near(cam.global_position.distance_to(rig.position), 1737.9, 0.01), str(cam.global_position))
	disc.update_disc()
	check("sun-ephemeris REQ-17: after zoom, SunDisc position = camera + 40000 d (+/- 1 unit)",
		disc.global_position.distance_to(cam.global_position + d * SUN_DISC_DISTANCE) <= 1.0,
		str(disc.global_position))
	to_cam = (cam.global_position - disc.global_position).normalized()
	check("sun-ephemeris REQ-17: after zoom, disc normal points to the camera",
		disc.global_basis.z.normalized().dot(to_cam) > 0.9999)

	# REQ-18: world-space radius gives the true angular diameter from the camera.
	var r: float = disc.global_basis.x.length()
	check("sun-ephemeris REQ-18: disc scale is uniform (x, y, z lengths equal)",
		near(disc.global_basis.y.length(), r, r * 1e-6) and near(disc.global_basis.z.length(), r, r * 1e-6),
		"x %s y %s z %s" % [r, disc.global_basis.y.length(), disc.global_basis.z.length()])
	var r_expected := SUN_DISC_DISTANCE * SUN_RADIUS_KM / dist_km
	check("sun-ephemeris REQ-18: disc radius = 40000 * R_sun / sun_distance_km (+/- 1e-6 relative)",
		near(r, r_expected, r_expected * 1e-6), "%s vs %s" % [r, r_expected])
	var disc_ang := rad_to_deg(2.0 * atan(r / SUN_DISC_DISTANCE))
	check("sun-ephemeris REQ-18: 2 atan(r / 40000) equals sun_angular_diameter_deg (+/- 0.001 deg)",
		near(disc_ang, ang_deg, 0.001), "%s vs %s" % [disc_ang, ang_deg])
	check("sun-ephemeris REQ-18: angular diameter is about 0.53 deg for the default date",
		near(disc_ang, 0.53, 0.01), str(disc_ang))
	ctl.set_sun(lon, lat)

	# REQ-19 geometry (occlusion by the Moon itself is a render check, see pending list).
	check("sun-ephemeris REQ-19: far edge of the disc (D + r) is at most 40200 units",
		SUN_DISC_DISTANCE + r <= 40200.0, str(SUN_DISC_DISTANCE + r))
	check("sun-ephemeris REQ-19: camera far plane (>= 50000) contains the far edge of the disc (D + r)",
		cam.far >= 50000.0 and cam.far >= SUN_DISC_DISTANCE + r, str(cam.far))

	# REQ-20: disc colour is white or near-white.
	if mat != null:
		var c := mat.albedo_color
		check("sun-ephemeris REQ-20: disc albedo channels are each >= 0.9",
			c.r >= 0.9 and c.g >= 0.9 and c.b >= 0.9, str(c))
	else:
		check("sun-ephemeris REQ-20: disc albedo channels are each >= 0.9", false, "no BaseMaterial3D on SunDisc")
	free_main(main)


# ---------------------------------------------------------------- audit (sun-ephemeris REQ-1..REQ-4)

func test_audit() -> void:
	var main := spawn_main()
	var moon := main.get_node("Moon") as MeshInstance3D
	var mat := moon.mesh.surface_get_material(0) as StandardMaterial3D
	check("sun-ephemeris REQ-1: Moon has no displacement material input (height map off) and no ShaderMaterial",
		mat != null and not mat.heightmap_enabled and not (moon.mesh.surface_get_material(0) is ShaderMaterial)
		and moon.material_override == null and not (moon.material_override is ShaderMaterial))
	var sphere := moon.mesh as SphereMesh
	check("sun-ephemeris REQ-2: Moon mesh radius is 1737.4", sphere != null and near(sphere.radius, 1737.4, 0.0001))

	var text := FileAccess.get_file_as_string(DATA_SOURCES)
	check("sun-ephemeris REQ-3: DATA_SOURCES states no elevation data is used yet",
		text.contains("No elevation data is used yet"))
	check("sun-ephemeris REQ-3: DATA_SOURCES says LOLA or SLDEM is planned for Milestone 2",
		text.contains("LOLA or SLDEM") and text.contains("Milestone 2"))
	var extra: Array = []
	var dir := DirAccess.open("res://assets/elevation")
	if dir != null:
		for f in dir.get_files():
			if f != ".gitkeep":
				extra.append(f)
	check("sun-ephemeris REQ-3: assets/elevation holds no file other than .gitkeep (found %s)" % str(extra),
		dir != null and extra.is_empty() and FileAccess.file_exists("res://assets/elevation/.gitkeep"))

	# REQ-4: texture orientation at identity transform.
	var verts: PackedVector3Array = moon.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = moon.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var ex := verts[_nearest_uv(uvs, Vector2(0.25, 0.5))]
	check("sun-ephemeris REQ-4: point at 90 E (u = 0.25) lies on local +X (within 0.5 deg)",
		ex.normalized().angle_to(Vector3.RIGHT) < deg_to_rad(0.5), str(ex.normalized()))
	var iz := _nearest_uv(uvs, Vector2(0.0, 0.5))
	var uz := uvs[iz].x
	check("sun-ephemeris REQ-4: point at (0 N, 0 E) lies on local +Z with u = 0 or 1",
		verts[iz].normalized().angle_to(Vector3.BACK) < deg_to_rad(0.5)
		and (absf(uz) < 0.001 or absf(uz - 1.0) < 0.001), "u %s" % uz)
	var top := 0
	for i in verts.size():
		if verts[i].y > verts[top].y:
			top = i
	check("sun-ephemeris REQ-4: north pole lies on local +Y with v = 0",
		verts[top].normalized().angle_to(Vector3.UP) < deg_to_rad(0.5) and absf(uvs[top].y) < 0.001,
		"v %s" % uvs[top].y)
	free_main(main)


# ---------------------------------------------------------------- camera

func test_camera() -> void:
	var main := spawn_main()
	var rig := main.get_node("CameraRig") as Node3D
	var cam := rig.get_node("Camera3D") as Camera3D
	var ctl = rig

	check("REQ-20: camera near <= 0.01 and far >= 50000",
		cam.near <= 0.01 and cam.far >= 50000.0, "near %s far %s" % [cam.near, cam.far])

	# REQ-21 defaults
	check("REQ-21: default distance is 6000 and default yaw and pitch are 0",
		near(ctl.distance, 6000.0, 0.0001) and near(ctl.yaw_deg, 0.0, 0.0001)
		and near(ctl.pitch_deg, 0.0, 0.0001), "d %s y %s p %s" % [ctl.distance, ctl.yaw_deg, ctl.pitch_deg])
	check("REQ-21: default pivot is the Moon center (origin)",
		vec_near(ctl.pivot, Vector3.ZERO, 0.0001), str(ctl.pivot))
	check("REQ-21: camera is 6000 from the pivot",
		near(cam.global_position.distance_to(ctl.pivot), 6000.0, 0.01),
		str(cam.global_position))
	check("REQ-21: camera is on the local +Z side",
		cam.global_position.z > 0.0 and near(cam.global_position.x, 0.0, 0.01)
		and near(cam.global_position.y, 0.0, 0.01), str(cam.global_position))
	var to_pivot: Vector3 = (ctl.pivot - cam.global_position).normalized()
	check("REQ-21: camera looks at the pivot",
		-cam.global_basis.z.dot(to_pivot) > 0.9999, str(-cam.global_basis.z))

	# REQ-16 grab direction: from the default view, (0 N, 0 E) is on the local +Z
	# surface point. A 100 px right drag moves it right of screen centre; a 100 px
	# down drag moves it below screen centre.
	var moon_node := main.get_node("Moon") as Node3D
	var surf_pt: Vector3 = moon_node.global_transform * Vector3(0, 0, 1737.4)
	var vp_centre: Vector2 = cam.get_viewport().get_visible_rect().size * 0.5
	var default_px: Vector2 = cam.unproject_position(surf_pt)
	check("REQ-16: default view has (0 N, 0 E) at screen centre",
		default_px.distance_to(vp_centre) < 1.0, "%s vs %s" % [default_px, vp_centre])
	send_mouse(mouse_button(MOUSE_BUTTON_LEFT, true))
	send_mouse(mouse_motion(Vector2(100, 0)))
	send_mouse(mouse_button(MOUSE_BUTTON_LEFT, false))
	var right_px: Vector2 = cam.unproject_position(surf_pt)
	check("REQ-16 grab: 100 px right drag moves (0 N, 0 E) right of screen centre",
		right_px.x > vp_centre.x, "%s vs %s" % [right_px, vp_centre])
	ctl.yaw_deg = 0.0
	ctl.pitch_deg = 0.0
	ctl._apply()
	send_mouse(mouse_button(MOUSE_BUTTON_LEFT, true))
	send_mouse(mouse_motion(Vector2(0, 100)))
	send_mouse(mouse_button(MOUSE_BUTTON_LEFT, false))
	var down_px: Vector2 = cam.unproject_position(surf_pt)
	check("REQ-16 grab: 100 px down drag moves (0 N, 0 E) below screen centre",
		down_px.y > vp_centre.y, "%s vs %s" % [down_px, vp_centre])
	ctl.yaw_deg = 0.0
	ctl.pitch_deg = 0.0
	ctl._apply()

	# REQ-16 orbit drag: 100 px right gives -20 degrees of yaw (grab rule: camera orbits opposite the drag).
	send_mouse(mouse_button(MOUSE_BUTTON_LEFT, true))
	send_mouse(mouse_motion(Vector2(100, 0)))
	check("REQ-16: left drag 100 px right changes yaw by -20 (+/- 0.5)",
		near(ctl.yaw_deg, -20.0, 0.5), str(ctl.yaw_deg))
	send_mouse(mouse_motion(Vector2(0, 1000)))
	check("REQ-16: drag 1000 px down clamps pitch at +89 (dragging down raises pitch)",
		near(ctl.pitch_deg, 89.0, 0.0001), str(ctl.pitch_deg))
	check("REQ-16: at pitch +89 the view is not flipped (camera up stays with world up)",
		cam.global_basis.y.dot(Vector3.UP) > 0.0, str(cam.global_basis.y))
	send_mouse(mouse_motion(Vector2(0, -3000)))
	check("REQ-16: drag up clamps pitch at -89",
		near(ctl.pitch_deg, -89.0, 0.0001), str(ctl.pitch_deg))
	check("REQ-16: pitch-clamped camera still at distance 6000",
		near(cam.global_position.distance_to(ctl.pivot), 6000.0, 0.01))
	send_mouse(mouse_button(MOUSE_BUTTON_LEFT, false))
	var yaw_before: float = ctl.yaw_deg
	send_mouse(mouse_motion(Vector2(200, 0)))
	check("REQ-16: motion after button release does not orbit",
		near(ctl.yaw_deg, yaw_before, 0.0001), str(ctl.yaw_deg))

	# REQ-17 zoom in and out by one notch.
	ctl.distance = 6000.0
	send_mouse(mouse_button(MOUSE_BUTTON_WHEEL_UP, true))
	check("REQ-17: one wheel notch in gives distance 5400 (+/- 0.5)",
		near(ctl.distance, 5400.0, 0.5), str(ctl.distance))
	send_mouse(mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true))
	check("REQ-17: one notch out from 5400 gives 6000 (+/- 0.5)",
		near(ctl.distance, 6000.0, 0.5), str(ctl.distance))

	# REQ-18 limits.
	for i in 50:
		send_mouse(mouse_button(MOUSE_BUTTON_WHEEL_UP, true))
	check("REQ-18: 50 notches in clamps distance at 1737.9",
		near(ctl.distance, 1737.9, 0.001), str(ctl.distance))
	for i in 50:
		send_mouse(mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true))
	check("REQ-18: 50 notches out clamps distance at 20000",
		near(ctl.distance, 20000.0, 0.001), str(ctl.distance))

	# REQ-19 pan: 100 px right at distance 6000 moves pivot 60 units along camera left (grab rule).
	ctl.distance = 6000.0
	ctl.pivot = Vector3.ZERO
	ctl.yaw_deg = 0.0
	ctl.pitch_deg = 0.0
	ctl._apply()
	send_mouse(mouse_button(MOUSE_BUTTON_LEFT, false))
	send_mouse(mouse_button(MOUSE_BUTTON_MIDDLE, true))
	var right := cam.global_basis.x
	send_mouse(mouse_motion(Vector2(100, 0)))
	check("REQ-19: middle drag 100 px right moves pivot 60 units in camera-left (+/- 0.5)",
		vec_near(ctl.pivot, -right * 60.0, 0.5), str(ctl.pivot))
	check("REQ-19: middle drag at yaw 0 moves pivot to (-60, 0, 0) (+/- 0.5)",
		vec_near(ctl.pivot, Vector3(-60, 0, 0), 0.5), str(ctl.pivot))
	send_mouse(mouse_button(MOUSE_BUTTON_MIDDLE, false))

	# REQ-15 orbit about an exported pivot that is not the origin.
	ctl.pivot = Vector3(10, 0, 0)
	ctl.distance = 6000.0
	ctl.yaw_deg = 0.0
	ctl.pitch_deg = 0.0
	ctl._apply()
	send_mouse(mouse_button(MOUSE_BUTTON_LEFT, true))
	send_mouse(mouse_motion(Vector2(50, 20)))
	send_mouse(mouse_button(MOUSE_BUTTON_LEFT, false))
	check("REQ-15: after pivot set to (10, 0, 0) and drag, camera stays 6000 from that pivot",
		near(cam.global_position.distance_to(Vector3(10, 0, 0)), 6000.0, 0.01),
		str(cam.global_position))
	check("REQ-15: camera looks at the non-origin pivot (10, 0, 0)",
		-cam.global_basis.z.dot((Vector3(10, 0, 0) - cam.global_position).normalized()) > 0.9999)
	check("REQ-15: rig is positioned at the pivot",
		vec_near(rig.position, Vector3(10, 0, 0), 0.0001), str(rig.position))
	free_main(main)


# ---------------------------------------------------------------- data sources

func test_data_sources() -> void:
	var text := FileAccess.get_file_as_string(DATA_SOURCES)
	check("REQ-22: DATA_SOURCES.md exists and is readable", text.length() > 0)
	check("REQ-25: documents the 180 E brightness step at column 2048 of the 4096-wide texture",
		text.contains("180 degrees East") and text.contains("column 2048 of the 4096-wide texture"))
	check("REQ-25: documents the step size as about 8 grey levels",
		text.contains("about 8 grey levels"))
	check("REQ-25: states the 180 E step was not corrected",
		text.contains("was not corrected"))
	var required := {
		"product name": "LROC WAC Global Morphologic Mosaic",
		"URL": "https://",
		"retrieval date": "Retrieval date",
		"original resolution": "Original resolution",
		"pixels per degree": "pixels per degree",
		"projection": "projection",
		"license text": "License and usage terms",
		"verbatim license clause": "public domain",
		"credit line": "NASA/GSFC/Arizona State University",
		"processing command": "```\nmake texture\n```",
		"tool name and version": "Rust 1.90.0, crates `tiff` 0.9.1 and `png` 0.18.1",
		"Godot version used": "4.7.2",
	}
	for k in required:
		check("REQ-22: documents %s" % k, text.contains(required[k]))

	var re := RegEx.new()
	re.compile("([0-9a-f]{64})\\s+(\\S+)")
	var entries: Array = re.search_all(text)
	check("REQ-22: lists SHA-256 values for raw and processed files",
		entries.size() >= 11, "found %d" % entries.size())

	var processed_sha := FileAccess.get_sha256(TEXTURE)
	check("REQ-22: processed texture SHA-256 matches the documented value",
		text.contains(processed_sha) and processed_sha != "",
		"actual %s" % processed_sha)

	# Raw files: checked against the local data/raw copy when present.
	var raw_checked := 0
	var raw_bad := []
	for m in entries:
		var fname: String = m.get_string(2)
		if not fname.ends_with("_100M.TIF"):
			continue
		var path := RAW_DIR + fname
		if not FileAccess.file_exists(path):
			continue
		raw_checked += 1
		if FileAccess.get_sha256(path) != m.get_string(1):
			raw_bad.append(fname)
	check("REQ-22: raw SHA-256 values match local data/raw files (%d checked)" % raw_checked,
		raw_checked > 0 and raw_bad.is_empty(),
		"checked %d, mismatched %s" % [raw_checked, str(raw_bad)])


# ---------------------------------------------------------------- repo scan (REQ-23)

func test_repo_scan() -> void:
	check("REQ-23: no addons/ directory",
		not DirAccess.dir_exists_absolute("res://addons"))

	var files: Array[String] = []
	_collect("res://", files)
	var text_exts := ["gd", "tscn", "tres", "godot", "import", "uid", "cfg", "md", "txt",
		"json", "gdshader", "sh", "py", "tmpl"]
	var hits: Array[String] = []
	var scanned := 0
	for f in files:
		var ext: String = f.get_extension().to_lower()
		var base: String = f.get_file()
		if not (ext in text_exts or base == "Makefile" or base == ".gitignore"):
			continue
		scanned += 1
		var body: String = FileAccess.get_file_as_string(f)
		if body.to_lower().contains("road rage"):
			hits.append(f)
	check("REQ-23: no 'Road Rage' text in project code and assets (%d text files scanned)" % scanned,
		hits.is_empty(), str(hits))


func _collect(dir_path: String, out: Array[String]) -> void:
	var skip := [".godot", "data", "tools", "tests", ".git", ".claude", "docs"]
	var da: DirAccess = DirAccess.open(dir_path)
	if da == null:
		return
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		var full: String = dir_path.path_join(name)
		if da.current_is_dir():
			if not (name in skip) and not name.begins_with("."):
				_collect(full, out)
		else:
			out.append(full)
		name = da.get_next()
	da.list_dir_end()
	# docs/DATA_SOURCES.md is project documentation and is in scope.
	if dir_path == "res://":
		out.append("res://docs/DATA_SOURCES.md")
		out.append("res://Makefile")
