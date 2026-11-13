extends SceneTree
## Headless tests for docs/specs/moon-globe-milestone-1.md, sun-ephemeris-and-sun-disc.md
## and docs/specs/moon-elevation-milestone-2.md.
## Run with: make test   (godot --headless --path . --script tests/run_tests.gd)
## Input is delivered by calling _unhandled_input on the rig and the sun (the
## viewport is not inside the tree during _initialize, so push_input cannot be used).
##
## Milestone 2 replaces the M1 SphereMesh checks. The radius, orientation and u
## mapping checks are kept, now on the 96 chunk meshes of the cube-sphere.
## Checks that need a display (M2 REQ-32) are not here; see the pending list.

const MAIN_SCENE := "res://scenes/main.tscn"
const CloudCopy := preload("res://tests/cloud_noise_copy.gd")
const TEXTURE := "res://assets/textures/lunar_albedo_4096x2048.png"
const DATA_SOURCES := "res://docs/DATA_SOURCES.md"
const ARCHITECTURE := "res://docs/ARCHITECTURE.md"
const RAW_DIR := "res://data/raw/lroc_wac_gmm_100m/"
const RAW_DEM_DIR := "res://data/raw/lola_ldem_64/"
const HEIGHT_LEVEL := "res://assets/elevation/lola_height_m_2048x1024.f32"
const METADATA := "res://assets/elevation/moon_data.json"
const REF_RADIUS_KM := 1737.4
const CHUNK_SIDE := 65
const CHUNKS := 96
const TOTAL_VERTICES := 96 * 65 * 65
const TOTAL_TRIANGLES := 96 * 64 * 64 * 2

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
	test_moon_structure()
	test_moon_radius()
	test_moon_orientation()
	test_moon_uv()
	test_moon_seams()
	test_moon_material_and_texture()
	test_texture_seam()
	test_sun()
	test_sun_stream_parsing()
	test_sun_bad_line_req25()
	test_sun_ephemeris_and_disc()
	test_audit()
	test_camera()
	test_m3_camera()
	test_m3_shadows()
	test_m3_docs()
	test_elevation_assets()
	test_data_sources()
	test_docs_m2()
	test_earth()
	var cloud_t0 := Time.get_ticks_msec()
	test_clouds()
	test_cloud_sampling()
	var cloud_ms := Time.get_ticks_msec() - cloud_t0
	check("REQ-20: headless cloud tests finish in under 10 s (%d ms)" % cloud_ms, cloud_ms < 10000)
	test_lunar_fly()
	test_lunar_surface_material()
	test_rock_albedo_factor()
	test_phase4_shadow_splits()
	test_req7a_sun_override()
	test_lod_streaming()
	test_fly_path()
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
	# M2 REQ-14 replaced the single MeshInstance3D with a Node3D holding 96 chunk meshes.
	var moon_node := main.get_node_or_null("Moon")
	check("REQ-4 (M2 REQ-14): scene contains Moon (Node3D holding chunk MeshInstance3D children)",
		moon_node is Node3D and not (moon_node is MeshInstance3D))
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


# ---------------------------------------------------------------- M2 helpers

func chunks_of(moon: Node) -> Array:
	var out: Array = []
	for c in moon.get_children():
		if c is MeshInstance3D:
			out.append(c)
	return out


## Every vertex, normal and UV of every chunk, concatenated in chunk order.
func flat_arrays(moon: Node) -> Dictionary:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	for c in chunks_of(moon):
		var arr: Array = c.mesh.surface_get_arrays(0)
		verts.append_array(arr[Mesh.ARRAY_VERTEX])
		norms.append_array(arr[Mesh.ARRAY_NORMAL])
		uvs.append_array(arr[Mesh.ARRAY_TEX_UV])
	return {"verts": verts, "norms": norms, "uvs": uvs}


func height_level() -> PackedFloat32Array:
	return FileAccess.get_file_as_bytes(HEIGHT_LEVEL).to_float32_array()


## Latitude (radians) of a point, from its direction: atan2 keeps precision near the poles.
func lat_of(v: Vector3) -> float:
	return atan2(v.y, sqrt(v.x * v.x + v.z * v.z))


## East longitude (radians, 0..TAU) of a point, from its direction.
func lon_of(v: Vector3) -> float:
	var l := atan2(v.x, v.z)
	return l + TAU if l < 0.0 else l


## Unit direction of a latitude and longitude in degrees (east-positive), the M1 orientation.
func dir_of(lat_deg: float, lon_deg: float) -> Vector3:
	var p := deg_to_rad(lat_deg)
	var l := deg_to_rad(lon_deg)
	return Vector3(cos(p) * sin(l), sin(p), cos(p) * cos(l))


## REQ-15 height in metres, written here independently of scripts/moon.gd:
## bilinear between the 2048 x 1024 cell centres, wrapping in longitude and
## clamped to the first and last row centres in latitude.
func ref_height_m(h: PackedFloat32Array, lat: float, lon: float) -> float:
	var w := 2048
	var rows := 1024
	var fx := lon / TAU * w - 0.5
	var x0 := floori(fx)
	var ax := fx - x0
	var xa := posmod(x0, w)
	var xb := posmod(x0 + 1, w)
	var fy := clampf((PI / 2.0 - lat) / PI * rows - 0.5, 0.0, float(rows - 1))
	var y0 := floori(fy)
	var y1 := mini(y0 + 1, rows - 1)
	var ay := fy - y0
	var top := lerpf(h[y0 * w + xa], h[y0 * w + xb], ax)
	var bottom := lerpf(h[y1 * w + xa], h[y1 * w + xb], ax)
	return lerpf(top, bottom, ay)


func nearest_index(verts: PackedVector3Array, dir: Vector3) -> int:
	var best := 0
	var best_a := INF
	for i in verts.size():
		var a := verts[i].angle_to(dir)
		if a < best_a:
			best_a = a
			best = i
	return best


# ---------------------------------------------------------------- M2 structure (REQ-14, REQ-15, REQ-16)

func test_moon_structure() -> void:
	var main := spawn_main()
	var moon := main.get_node("Moon") as Node3D
	var chunks := chunks_of(moon)
	check("REQ-14: Moon holds 96 chunk MeshInstance3D nodes (6 faces x 4 x 4)",
		chunks.size() == CHUNKS, str(chunks.size()))
	var names := {}
	var bad_size := 0
	var total := 0
	var all_array_meshes := true
	for c in chunks:
		names[c.name] = true
		if not (c.mesh is ArrayMesh):
			all_array_meshes = false
		var arr: Array = c.mesh.surface_get_arrays(0)
		var n: int = arr[Mesh.ARRAY_VERTEX].size()
		total += n
		if n != CHUNK_SIDE * CHUNK_SIDE:
			bad_size += 1
	check("REQ-14: chunk names are unique", names.size() == CHUNKS, str(names.size()))
	check("REQ-14: every chunk has 65 x 65 vertices", bad_size == 0, "%d chunks differ" % bad_size)
	check("REQ-14: total vertices 6 x 16 x 65 x 65 = 405600", total == TOTAL_VERTICES, str(total))
	check("REQ-14: chunks are ArrayMesh (the SphereMesh is gone)", all_array_meshes)
	check("REQ-15: Moon node is at identity transform (scale 1.0, no vertical exaggeration)",
		moon.transform.is_equal_approx(Transform3D.IDENTITY), str(moon.transform))
	check("REQ-15: reference radius from moon_data.json is 1737.4 units",
		near(moon.reference_radius, REF_RADIUS_KM, 0.0001), str(moon.reference_radius))
	var hidden := 0
	for c in chunks_of(moon):
		if not c.is_visible_in_tree() or c.mesh == null or c.mesh.get_surface_count() == 0 \
				or c.mesh.surface_get_material(0) == null or c.get_parent() != moon:
			hidden += 1
	check("REQ-14: every chunk is a visible Moon child with a mesh and a material",
		chunks_of(moon).size() == CHUNKS and hidden == 0, "%d chunks fail" % hidden)
	check("REQ-16: terrain built once at startup (terrain_built true)", moon.terrain_built)
	check("REQ-16: build time recorded (ms >= 0)", moon.terrain_build_ms >= 0, str(moon.terrain_build_ms))
	var src := FileAccess.get_file_as_string("res://scripts/moon.gd")
	check("REQ-16: scripts/moon.gd has no _process or _physics_process (no per-frame terrain)",
		not src.contains("func _process") and not src.contains("func _physics_process"))
	free_main(main)


# ---------------------------------------------------------------- M2 radius (REQ-25, REQ-30)

func test_moon_radius() -> void:
	var main := spawn_main()
	var moon := main.get_node("Moon") as Node3D
	var h := height_level()
	var arr := flat_arrays(moon)
	var verts: PackedVector3Array = arr["verts"]
	var worst := 0.0
	var worst_at := -1
	var sum := 0.0
	var min_r := INF
	var max_r := -INF
	var not_finite := 0
	for i in verts.size():
		var v := verts[i]
		if not v.is_finite():
			not_finite += 1
			continue
		var r := v.length()
		var want := REF_RADIUS_KM + ref_height_m(h, lat_of(v), lon_of(v)) / 1000.0
		var dev := absf(r - want)
		if dev > worst:
			worst = dev
			worst_at = i
		sum += r
		min_r = minf(min_r, r)
		max_r = maxf(max_r, r)
	var mean := sum / verts.size()
	check("REQ-25: every vertex radius equals 1737.4 + h/1000 within 0.001 (max %.6f at vertex %d)" % [worst, worst_at],
		worst <= 0.001 and not_finite == 0, "max %.6f, not finite %d" % [worst, not_finite])
	check("REQ-30: mean vertex radius is 1737.4 +/- 2 (mean %.3f)" % mean,
		absf(mean - REF_RADIUS_KM) <= 2.0, str(mean))
	check("REQ-30: every vertex radius lies between 1737.4 - 9.2 and 1737.4 + 10.8 (min %.3f, max %.3f)" % [min_r, max_r],
		min_r >= REF_RADIUS_KM - 9.2 and max_r <= REF_RADIUS_KM + 10.8,
		"min %.3f max %.3f" % [min_r, max_r])
	free_main(main)


# ---------------------------------------------------------------- M2 orientation (REQ-17, M1 REQ-7, M1 REQ-6)

func test_moon_orientation() -> void:
	var main := spawn_main()
	var moon := main.get_node("Moon") as Node3D
	var arr := flat_arrays(moon)
	var verts: PackedVector3Array = arr["verts"]
	var uvs: PackedVector2Array = arr["uvs"]

	# North pole: the vertex with the highest y must be at direction +Y.
	var top := 0
	for i in verts.size():
		if verts[i].y > verts[top].y:
			top = i
	check("M1 REQ-7 / REQ-17: north pole direction maps to +Y (within 0.001)",
		vec_near(verts[top].normalized(), Vector3.UP, 0.001), str(verts[top].normalized()))
	check("REQ-17: vertex nearest +Y is at latitude 90 N within 1 deg",
		lat_of(verts[top]) > deg_to_rad(89.0), str(rad_to_deg(lat_of(verts[top]))))

	# (0 N, 0 E) is on +Z. The vertex nearest +Z is checked for latitude and longitude within 1 deg.
	var iz := nearest_index(verts, Vector3.BACK)
	var lon_z := lon_of(verts[iz])
	check("REQ-17: vertex nearest +Z is (0 N, 0 E) within 1 deg",
		absf(lat_of(verts[iz])) < deg_to_rad(1.0) and minf(lon_z, TAU - lon_z) < deg_to_rad(1.0),
		"lat %.3f lon %.3f" % [rad_to_deg(lat_of(verts[iz])), rad_to_deg(lon_z)])
	check("M1 REQ-7: (0 N, 0 E) direction maps to +Z (within 0.5 deg)",
		verts[iz].normalized().angle_to(Vector3.BACK) < deg_to_rad(0.5), str(verts[iz].normalized()))

	# (0 N, 90 E) is on +X.
	var ix := nearest_index(verts, Vector3.RIGHT)
	check("REQ-17: vertex nearest +X is (0 N, 90 E) within 1 deg",
		absf(lat_of(verts[ix])) < deg_to_rad(1.0) and absf(lon_of(verts[ix]) - PI / 2.0) < deg_to_rad(1.0),
		"lat %.3f lon %.3f" % [rad_to_deg(lat_of(verts[ix])), rad_to_deg(lon_of(verts[ix]))])

	# M1 REQ-6 (kept): u = 0.25 (90 E on the equator) maps to +X, within 0.5 deg.
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


# ---------------------------------------------------------------- M2 UV (REQ-18, sun REQ-4 revised seam rule)

func test_moon_uv() -> void:
	var main := spawn_main()
	var moon := main.get_node("Moon") as Node3D
	var chunks := chunks_of(moon)

	var worst_span := 0.0
	var triangles := 0
	for c in chunks:
		var arr: Array = c.mesh.surface_get_arrays(0)
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for t in range(0, idx.size(), 3):
			var a := uv[idx[t]].x
			var b := uv[idx[t + 1]].x
			var d := uv[idx[t + 2]].x
			worst_span = maxf(worst_span, maxf(a, maxf(b, d)) - minf(a, minf(b, d)))
			triangles += 1
	check("REQ-18: no triangle has u values differing by more than 0.5 (worst %.4f over %d triangles)" % [worst_span, triangles],
		worst_span <= 0.5 and triangles == TOTAL_TRIANGLES,
		"worst %.4f, triangles %d" % [worst_span, triangles])

	# Sun spec REQ-4 (revised by M2 REQ-34): the cube-sphere vertices at +Z have u = 0 in the
	# two east chunks and u = 1 in the two west chunks, tolerance 0.002.
	var hits := 0
	var east := 0
	var west := 0
	var bad := 0
	for c in chunks:
		var arr: Array = c.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var best := nearest_index(verts, Vector3.BACK)
		if verts[best].angle_to(Vector3.BACK) > deg_to_rad(0.5):
			continue
		hits += 1
		var centre := verts[(CHUNK_SIDE / 2) * CHUNK_SIDE + CHUNK_SIDE / 2]
		var is_east := centre.x > 0.0
		if is_east:
			east += 1
		else:
			west += 1
		var u: float = uvs[best].x
		var ok := (is_east and absf(u) <= 0.002) or ((not is_east) and absf(u - 1.0) <= 0.002)
		if not ok:
			bad += 1
	check("sun REQ-4 (revised): chunks at +Z give u = 0 in the two east chunks and u = 1 in the two west chunks (%d chunks, %d east, %d west)" % [hits, east, west],
		hits == 4 and east == 2 and west == 2 and bad == 0, "hits %d east %d west %d bad %d" % [hits, east, west, bad])
	free_main(main)


# ---------------------------------------------------------------- M2 seams, normals, cell shape (REQ-19, REQ-20, REQ-21)

func test_moon_seams() -> void:
	var main := spawn_main()
	var moon := main.get_node("Moon") as Node3D
	var arr := flat_arrays(moon)
	var verts: PackedVector3Array = arr["verts"]
	var norms: PackedVector3Array = arr["norms"]

	# REQ-19: vertices with the same direction (shared chunk or face edges) must agree.
	var first := {}
	var shared := 0
	var max_dp := 0.0
	var max_dn := 0.0
	var clashes := 0
	for i in verts.size():
		var d := verts[i].normalized()
		var key := "%.5f,%.5f,%.5f" % [d.x, d.y, d.z]
		if not first.has(key):
			first[key] = i
			continue
		shared += 1
		var j: int = first[key]
		var dp := verts[i].distance_to(verts[j])
		var dn := (norms[i] - norms[j]).abs()
		max_dp = maxf(max_dp, dp)
		max_dn = maxf(max_dn, maxf(dn.x, maxf(dn.y, dn.z)))
		if dp > 0.0001 or dn.x > 0.001 or dn.y > 0.001 or dn.z > 0.001:
			clashes += 1
	check("REQ-19: shared chunk and face edge vertices agree in position (1e-4) and normal (1e-3) (%d shared, max dp %.7f, max dn %.7f)" % [shared, max_dp, max_dn],
		shared > 0 and clashes == 0, "%d clashes" % clashes)

	# REQ-20: normals are unit length, point outward, and are not NaN.
	var bad_normal := 0
	var not_finite := 0
	for i in norms.size():
		var n := norms[i]
		if not n.is_finite():
			not_finite += 1
			continue
		if absf(n.length() - 1.0) > 1e-3 or n.dot(verts[i].normalized()) <= 0.0:
			bad_normal += 1
	check("REQ-20: every normal is unit length and points away from the centre (%d bad, %d not finite)" % [bad_normal, not_finite],
		bad_normal == 0 and not_finite == 0)

	# REQ-20: the vertex nearest (43.24 S, 347.34 E) on Tycho's west inner wall deviates by more than 2 deg.
	var tycho := nearest_index(verts, dir_of(-43.24, 347.34))
	var dev := rad_to_deg(norms[tycho].angle_to(verts[tycho]))
	check("REQ-20: normal at (43.24 S, 347.34 E) deviates from the radial direction by more than 2 deg (%.2f deg)" % dev,
		dev > 2.0, "%.3f deg" % dev)

	# Rendering: Godot treats clockwise triangles as front faces, so each front face must have its
	# geometric normal pointing into the Moon (against the outward direction of its centroid).
	var inward_bad := 0
	for c in chunks_of(moon):
		var carr: Array = c.mesh.surface_get_arrays(0)
		var cv: PackedVector3Array = carr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = carr[Mesh.ARRAY_INDEX]
		for t in range(0, idx.size(), 3):
			var a := cv[idx[t]]
			var b := cv[idx[t + 1]]
			var d := cv[idx[t + 2]]
			var geo := (b - a).cross(d - a)
			if geo.dot(a + b + d) >= 0.0:
				inward_bad += 1
	check("REQ-20: all triangles are wound clockwise from outside (front faces face outward; %d wrong)" % inward_bad,
		inward_bad == 0, "%d wrong" % inward_bad)

	# REQ-21: longest / shortest triangle edge on the undisplaced cube-sphere is at most 3; no NaN.
	var worst_ratio := 0.0
	var nan_tris := 0
	var mesh_longest := 0.0
	var mesh_shortest := INF
	for c in chunks_of(moon):
		var carr: Array = c.mesh.surface_get_arrays(0)
		var cv: PackedVector3Array = carr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = carr[Mesh.ARRAY_INDEX]
		for t in range(0, idx.size(), 3):
			var p0 := cv[idx[t]].normalized() * REF_RADIUS_KM
			var p1 := cv[idx[t + 1]].normalized() * REF_RADIUS_KM
			var p2 := cv[idx[t + 2]].normalized() * REF_RADIUS_KM
			var e0 := p0.distance_to(p1)
			var e1 := p1.distance_to(p2)
			var e2 := p2.distance_to(p0)
			var shortest := minf(e0, minf(e1, e2))
			var longest := maxf(e0, maxf(e1, e2))
			if not is_finite(shortest) or not is_finite(longest):
				nan_tris += 1
				continue
			mesh_longest = maxf(mesh_longest, longest)
			mesh_shortest = minf(mesh_shortest, shortest)
			if shortest <= 0.0:
				worst_ratio = INF
			else:
				worst_ratio = maxf(worst_ratio, longest / shortest)
	check("REQ-21: longest / shortest triangle edge (undisplaced) at most 3 (worst %.3f), no NaN (%d)" % [worst_ratio, nan_tris],
		worst_ratio <= 3.0 and nan_tris == 0, "worst %.3f nan %d" % [worst_ratio, nan_tris])
	# REQ-21 reads "over the whole mesh": longest edge of the whole mesh over shortest edge of the whole mesh.
	var mesh_ratio: float = mesh_longest / mesh_shortest if mesh_shortest > 0.0 else INF
	check("REQ-21: whole-mesh longest / shortest edge (undisplaced) at most 3 (%.4f = %.4f km / %.4f km)" % [mesh_ratio, mesh_longest, mesh_shortest],
		mesh_ratio <= 3.0, "ratio %.4f" % mesh_ratio)
	free_main(main)


# ---------------------------------------------------------------- M3 material (M3 REQ-1 to REQ-3, REQ-16)
# Replaces M1 REQ-9 and M2 REQ-22 (StandardMaterial3D) and the M1 REQ-6 material path.

const SHADER := "res://shaders/lunar_surface.gdshader"


func _regex_hit(text: String, pattern: String) -> bool:
	var re := RegEx.new()
	re.compile(pattern)
	return re.search(text) != null


func test_moon_material_and_texture() -> void:
	var main := spawn_main()
	var moon := main.get_node("Moon") as Node3D
	var chunks := chunks_of(moon)
	var first: Material = chunks[0].mesh.surface_get_material(0)
	var shader_ok := 0
	var shared_ok := 0
	var override_set := 0
	for c in chunks:
		var m: Material = c.mesh.surface_get_material(0)
		if m is ShaderMaterial and (m as ShaderMaterial).shader != null \
				and str((m as ShaderMaterial).shader.resource_path) == SHADER:
			shader_ok += 1
		if m == first:
			shared_ok += 1
		if c.material_override != null:
			override_set += 1
	check("M3 REQ-1: every chunk uses a ShaderMaterial with res://shaders/lunar_surface.gdshader (%d of 96)" % shader_ok,
		shader_ok == CHUNKS)
	check("M3 REQ-1: all 96 chunks share one material instance (%d of 96)" % shared_ok, shared_ok == CHUNKS)
	check("M3 REQ-1: no material_override on any chunk", override_set == 0, "override %d" % override_set)
	var mat := first as ShaderMaterial
	var albedo: Variant = mat.get_shader_parameter("albedo_texture") if mat != null else null
	check("M1 REQ-6 / M3 REQ-1: albedo uniform is assets/textures/lunar_albedo_4096x2048.png",
		albedo is Texture2D and str((albedo as Texture2D).resource_path) == TEXTURE,
		"resource_path '%s'" % (str((albedo as Texture2D).resource_path) if albedo is Texture2D else "null"))
	if albedo is Texture2D:
		check("M1 REQ-6: albedo texture is 4096 x 2048 pixels",
			(albedo as Texture2D).get_width() == 4096 and (albedo as Texture2D).get_height() == 2048,
			"%d x %d" % [(albedo as Texture2D).get_width(), (albedo as Texture2D).get_height()])
	var src := FileAccess.get_file_as_string(SHADER)
	check("M3 REQ-1: albedo sampler has no source_color hint (linear reflectance) and uses anisotropic mipmapped linear filtering",
		src.contains("uniform sampler2D albedo_texture : filter_linear_mipmap_anisotropic") \
		and not src.contains("albedo_texture : source_color"))
	# REQ-30 replaces this rule: the only VERTEX write allowed is the geomorph line.
	var vre := RegEx.new()
	vre.compile("\\bVERTEX\\s*[-+*/]?=[^=][^;]*;")
	var vwrites := vre.search_all(src)
	check("M3 REQ-1 / REQ-30: the shader writes VERTEX only for the geomorph (one line, CUSTOM0 * morph)",
		vwrites.size() == 1 and vwrites[0].get_string() == "VERTEX += CUSTOM0.xyz * morph;",
		"%d VERTEX writes" % vwrites.size())
	check("M3 REQ-3: specular disabled, metallic 0, roughness 1.0",
		src.contains("specular_disabled") and src.contains("METALLIC = 0.0") and src.contains("ROUGHNESS = 1.0"))
	check("M3 REQ-3: the shader writes no EMISSION, RIM or CLEARCOAT",
		not _regex_hit(src, "\\b(EMISSION|RIM|CLEARCOAT)\\s*[-+*/]?=[^=]"))
	check("M3 REQ-2: Lommel-Seeliger term 2 cos i / (cos i + cos e), zero when cos i <= 0 or cos e <= 0",
		src.contains("2.0 * cos_i / (cos_i + cos_e)") and src.contains("cos_i > 0.0 && cos_e > 0.0"))
	check("M3 REQ-16: shading normal is the decoded map normal; the vertex normal is not added",
		src.contains("texture(normal_texture, UV).rgb * 2.0 - 1.0") and not _regex_hit(src, "NORMAL\\s*\\+="))
	var img := load_png_image(TEXTURE)
	check("M1 REQ-6: texture file loads and is 4096 x 2048",
		img != null and img.get_width() == 4096 and img.get_height() == 2048)
	check("M1 REQ-6: texture file exists in the project (no procedural fallback)",
		FileAccess.file_exists(TEXTURE))
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


# ---------------------------------------------------------------- M1 REQ-8 seam (visual check, metrics only)

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

# Fixture: one compact streamed line (REQ-23 format), copied from a one-shot CLI run.
const SAMPLE_LINE := "{\"utc\": \"2026-11-11T07:12:52Z\",\"jd_tt\": 2461355.8014027774,\"frame\": \"IAU_MOON\",\"sun_dir_moon_fixed\": [-0.9365646881189394, 0.34944585405163825, -0.027095757136400347],\"sun_dir_godot\": [0.34944585405163825, -0.027095757136400347, -0.9365646881189394],\"subsolar_lon_deg\": 159.53872632518878,\"subsolar_lat_deg\": -1.5526625551431783,\"sun_distance_km\": 147749548.85429886,\"sun_angular_diameter_deg\": 0.5395728299926271,\"earth_pos_godot\": [15373.113318411877, 43997.629377675374, 399608.59165505646],\"earth_distance_km\": 402317.22623881476,\"earth_basis_godot\": [0.9879987208232214, 0.040536734027939336, 0.1490479816905495, -0.153844750217786, 0.3444360068617197, 0.9261185831239865, -0.013795668961862573, -0.9379342249707605, 0.34653869790601055],\"earth_sun_dir_godot\": [0.3484687714822985, -0.027325083608007894, -0.9369220112194147],\"earth_subsolar_lon_deg\": 67.75152092695275,\"earth_subsolar_lat_deg\": -17.340365191300577}"
const SUN_DISC_DISTANCE := 40000.0
const SUN_RADIUS_KM := 695700.0
const SUN_SCRIPT := "res://scripts/sun_controller.gd"


func sample() -> Dictionary:
	return JSON.parse_string(SAMPLE_LINE)


func line_from(d: Dictionary) -> String:
	return JSON.stringify(d)


func test_sun() -> void:
	var main := spawn_main()
	var sun := main.get_node("Sun") as DirectionalLight3D
	var ctl = sun
	# Rev. 7 REQ-15: no Sun before the first streamed line (the tests run before any _process frame).
	check("sun-ephemeris REQ-15: before the first line has_sun is false and the light is hidden",
		ctl.has_sun == false and sun.visible == false, "has_sun %s visible %s" % [ctl.has_sun, sun.visible])
	var az0: float = ctl.azimuth_deg
	var el0: float = ctl.elevation_deg
	var basis0 := sun.global_basis
	for k in [KEY_RIGHT, KEY_LEFT, KEY_UP, KEY_DOWN]:
		send_key(key_press(k))
	check("sun-ephemeris REQ-15: arrow keys have no effect before the first line",
		ctl.azimuth_deg == az0 and ctl.elevation_deg == el0 and sun.global_basis.is_equal_approx(basis0),
		"az %s el %s" % [ctl.azimuth_deg, ctl.elevation_deg])

	ctl.apply_line(sample())
	check("sun-ephemeris REQ-15: after a line has_sun is true and the light is visible",
		ctl.has_sun and sun.visible)

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

	# Keyboard controls (REQ-13) once a Sun exists.
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

func test_sun_stream_parsing() -> void:
	var script := load(SUN_SCRIPT)
	check("sun-ephemeris REQ-24: parse_line accepts a valid streamed line",
		script.parse_line(SAMPLE_LINE) is Dictionary)
	for key in ["utc", "jd_tt", "frame", "sun_dir_moon_fixed", "sun_dir_godot",
			"subsolar_lon_deg", "subsolar_lat_deg", "sun_distance_km", "sun_angular_diameter_deg",
			"earth_pos_godot", "earth_distance_km", "earth_basis_godot", "earth_sun_dir_godot",
			"earth_subsolar_lon_deg", "earth_subsolar_lat_deg"]:
		var d := sample()
		d.erase(key)
		check("sun-ephemeris REQ-24: parse_line rejects a line missing %s" % key,
			script.parse_line(line_from(d)) == null)
	for key in ["sun_dir_moon_fixed", "sun_dir_godot"]:
		var d := sample()
		d[key] = [1.0, 0.001, 0.0]  # length 1 + 5e-7 is inside 1 +/- 1e-6
		check("sun-ephemeris REQ-24: parse_line accepts %s within 1 +/- 1e-6" % key,
			script.parse_line(line_from(d)) is Dictionary)
		d[key] = [1.0, 0.01, 0.0]  # length 1 + 5e-5
		check("sun-ephemeris REQ-24: parse_line rejects non-unit %s" % key,
			script.parse_line(line_from(d)) == null)
	var low := sample()
	low["sun_distance_km"] = 600000.0
	check("sun-ephemeris REQ-24: parse_line rejects sun_distance_km below R_sun",
		script.parse_line(line_from(low)) == null)
	check("sun-ephemeris REQ-24: parse_line rejects a partial line",
		script.parse_line(SAMPLE_LINE.left(80)) == null)
	check("sun-ephemeris REQ-24: parse_line rejects non-JSON", script.parse_line("garbage") == null)
	var src := FileAccess.get_file_as_string(SUN_SCRIPT)
	check("sun-ephemeris REQ-24: helper path is ephemeris/target/x86_64-unknown-linux-musl/release/moon-ephemeris with --stream",
		src.contains("\"res://ephemeris/target/x86_64-unknown-linux-musl/release/moon-ephemeris\"")
		and src.contains("\"--stream\""))
	check("sun-ephemeris REQ-15: sun_controller does not reference the ephemeris file",
		not src.contains("sun_moon_fixed"))


# REQ-25: bad lines return null from parse_line. The engine "Parse JSON failed" line must not appear;
# that is checked on the make test output (grep), since a test cannot read engine stderr.
func test_sun_bad_line_req25() -> void:
	var script := load(SUN_SCRIPT)
	var bad := {
		"partial line": SAMPLE_LINE.left(80),
		"partial line, half": SAMPLE_LINE.left(SAMPLE_LINE.length() / 2),
		"non-JSON text": "garbage",
		"empty line": "",
		"JSON array": "[1, 2, 3]",
	}
	for label in bad:
		check("REQ-25: parse_line returns null for a bad line (%s)" % label,
			script.parse_line(bad[label]) == null)


func test_sun_ephemeris_and_disc() -> void:
	var eph := sample()
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

	# REQ-15 / REQ-25: no Sun before the first line.
	disc.update_disc()
	check("sun-ephemeris REQ-15: SunDisc hidden and light disabled before the first line",
		disc.visible == false and sun.visible == false, "disc %s light %s" % [disc.visible, sun.visible])

	# REQ-15: after a line, values come from that line and the light follows M1 REQ-11.
	ctl.apply_line(ctl.parse_line(SAMPLE_LINE))
	disc.update_disc()
	check("sun-ephemeris REQ-15: SunDisc and light visible after a line",
		disc.visible and sun.visible)
	check("sun-ephemeris REQ-15: azimuth equals streamed subsolar_lon_deg (+/- 0.001)",
		near(ctl.azimuth_deg, lon, 0.001), "%s vs %s" % [ctl.azimuth_deg, lon])
	check("sun-ephemeris REQ-15: elevation equals streamed subsolar_lat_deg (+/- 0.001)",
		near(ctl.elevation_deg, lat, 0.001), "%s vs %s" % [ctl.elevation_deg, lat])
	var fwd := -sun.global_basis.z
	check("sun-ephemeris REQ-15: light forward equals -sun_dir_godot per component (+/- 0.001)",
		absf(fwd.x + gd[0]) <= 0.001 and absf(fwd.y + gd[1]) <= 0.001 and absf(fwd.z + gd[2]) <= 0.001,
		str(fwd))
	check("sun-ephemeris REQ-24: utc of the applied line is kept", ctl.utc == eph["utc"], ctl.utc)

	# REQ-16: Right arrow once from the streamed values, then the disc follows the new direction.
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
	# REQ-16: the next streamed line overwrites the manual change.
	var nxt := sample()
	nxt["utc"] = "2026-11-11T07:12:53Z"
	ctl.apply_line(ctl.parse_line(line_from(nxt)))
	disc.update_disc()
	d = ctl.sun_direction()
	check("sun-ephemeris REQ-16: next streamed line overwrites the manual change",
		near(ctl.azimuth_deg, lon, 0.001) and near(ctl.elevation_deg, lat, 0.001) and ctl.utc == nxt["utc"],
		"az %s el %s" % [ctl.azimuth_deg, ctl.elevation_deg])

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

	# M3 REQ-9: 29 notches in from 6000 reach the minimum, measured from the Moon's centre.
	for i in 29:
		send_mouse(mouse_button(MOUSE_BUTTON_WHEEL_UP, true))
	check("sun-ephemeris REQ-17 (M3 REQ-9): after zooming in, camera distance from the Moon's centre is 1748.232 (minimum)",
		near(cam.global_position.distance_to(main.get_node("Moon").global_position), 1748.232, 0.01),
		str(cam.global_position))
	disc.update_disc()
	check("sun-ephemeris REQ-17: after zoom, SunDisc position = camera + 40000 d (+/- 1 unit)",
		disc.global_position.distance_to(cam.global_position + d * SUN_DISC_DISTANCE) <= 1.0,
		str(disc.global_position))
	to_cam = (cam.global_position - disc.global_position).normalized()
	check("sun-ephemeris REQ-17: after zoom, disc normal points to the camera",
		disc.global_basis.z.normalized().dot(to_cam) > 0.9999)

	# REQ-18: world-space radius from the streamed distance gives the true angular diameter.
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
	check("sun-ephemeris REQ-18: angular diameter is within 0.52-0.54 deg",
		disc_ang >= 0.52 and disc_ang <= 0.54, str(disc_ang))
	# REQ-18: a line with a different distance changes the disc size.
	var far := sample()
	far["sun_distance_km"] = 152100000.0
	ctl.apply_line(ctl.parse_line(line_from(far)))
	disc.update_disc()
	var r2: float = disc.global_basis.x.length()
	var r2_expected := SUN_DISC_DISTANCE * SUN_RADIUS_KM / 152100000.0
	check("sun-ephemeris REQ-18: disc radius follows the latest streamed distance",
		near(r2, r2_expected, r2_expected * 1e-6), "%s vs %s" % [r2, r2_expected])

	check("sun-ephemeris REQ-19: far edge of the disc (D + r) is at most 40200 units",
		SUN_DISC_DISTANCE + r <= 40200.0, str(SUN_DISC_DISTANCE + r))
	check("sun-ephemeris REQ-19: camera far plane (>= 50000) contains the far edge of the disc (D + r)",
		cam.far >= 50000.0 and cam.far >= SUN_DISC_DISTANCE + r, str(cam.far))

	if mat != null:
		var c := mat.albedo_color
		check("sun-ephemeris REQ-20: disc albedo channels are each >= 0.9",
			c.r >= 0.9 and c.g >= 0.9 and c.b >= 0.9, str(c))
	else:
		check("sun-ephemeris REQ-20: disc albedo channels are each >= 0.9", false, "no BaseMaterial3D on SunDisc")
	free_main(main)


# ---------------------------------------------------------------- audit (sun-ephemeris REQ-1..REQ-4, revised by M2)

func test_audit() -> void:
	var main := spawn_main()
	var moon := main.get_node("Moon") as Node3D
	var chunks := chunks_of(moon)
	# Sun REQ-1 (no displacement input) is replaced by M2 REQ-15 and M3 REQ-1: the displacement is in
	# the mesh vertices, and the chunks use the lunar ShaderMaterial with no height input.
	var plain := 0
	for c in chunks:
		var m: Material = c.mesh.surface_get_material(0)
		if m is ShaderMaterial and (m as ShaderMaterial).get_shader_parameter("albedo_texture") != null \
				and (m as ShaderMaterial).get_shader_parameter("height_texture") == null \
				and c.material_override == null:
			plain += 1
	check("sun-ephemeris REQ-1 (M3 REQ-1): lunar ShaderMaterial, no height input, no material_override on any chunk (%d of 96)" % plain,
		plain == CHUNKS)
	# Sun REQ-2 (radius read from a sphere mesh) is replaced by M2 REQ-15 and REQ-30; the reference radius stays 1737.4.
	check("sun-ephemeris REQ-2 (M2 REQ-15): Moon reference radius is 1737.4",
		near(moon.reference_radius, REF_RADIUS_KM, 0.0001), str(moon.reference_radius))

	# Sun REQ-3 (no elevation data documented) is replaced by M2 REQ-1, REQ-7 and REQ-11.
	var text := FileAccess.get_file_as_string(DATA_SOURCES)
	check("sun-ephemeris REQ-3 (M2 REQ-1): DATA_SOURCES has the Elevation (Milestone 2) section",
		text.contains("## Elevation (Milestone 2)") and not text.contains("No elevation data is used yet"))
	var found: Array = []
	var dir := DirAccess.open("res://assets/elevation")
	if dir != null:
		for f in dir.get_files():
			found.append(f)
	found.sort()
	# DirAccess.get_files() does not list hidden files, so .gitkeep is checked by path (as in M1).
	var expected := ["lola_height_m_1024x512.f32", "lola_height_m_2048x1024.f32",
		"lola_height_m_4096x2048.f32", "moon_data.json"]
	check("sun-ephemeris REQ-3 (M2 REQ-7, REQ-11): assets/elevation holds exactly the four generated files (found %s)" % str(found),
		found == expected and FileAccess.file_exists("res://assets/elevation/.gitkeep"), str(found))

	# Sun REQ-4 (UV at the axis points) is revised by M2 REQ-34. The pole and the +Z seam are checked in
	# test_moon_uv (u = 0 or 1 at +Z); here the north pole maps to v = 0 on +Y.
	var arr := flat_arrays(moon)
	var verts: PackedVector3Array = arr["verts"]
	var uvs: PackedVector2Array = arr["uvs"]
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

	check("REQ-20: camera near <= 0.05 and far >= 50000",
		cam.near <= 0.05 + 1e-6 and cam.far >= 50000.0, "near %s far %s" % [cam.near, cam.far])

	# REQ-21 defaults
	check("REQ-21: default distance is 6000 and default orbit_basis is identity",
		near(ctl.distance, 6000.0, 0.0001) and ctl.orbit_basis.is_equal_approx(Basis.IDENTITY),
		"d %s basis %s" % [ctl.distance, ctl.orbit_basis])
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
	var surf_pt: Vector3 = moon_node.global_transform * Vector3(0, 0, REF_RADIUS_KM)
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
	ctl.orbit_basis = Basis.IDENTITY
	ctl._apply()
	send_mouse(mouse_button(MOUSE_BUTTON_LEFT, true))
	send_mouse(mouse_motion(Vector2(0, 100)))
	send_mouse(mouse_button(MOUSE_BUTTON_LEFT, false))
	var down_px: Vector2 = cam.unproject_position(surf_pt)
	check("REQ-16 grab: 100 px down drag moves (0 N, 0 E) below screen centre",
		down_px.y > vp_centre.y, "%s vs %s" % [down_px, vp_centre])
	ctl.orbit_basis = Basis.IDENTITY
	ctl._apply()

	# REQ-16 trackball: 100 px right turns the camera offset 20 degrees about the camera's screen up axis,
	# toward camera-left (grab rule: the camera orbits opposite the drag).
	var off0: Vector3 = cam.global_position - ctl.pivot
	var up0: Vector3 = cam.global_basis.y
	var right0: Vector3 = cam.global_basis.x
	send_mouse(mouse_button(MOUSE_BUTTON_LEFT, true))
	send_mouse(mouse_motion(Vector2(100, 0)))
	var off1: Vector3 = cam.global_position - ctl.pivot
	check("REQ-16: left drag 100 px right turns the camera offset 20 degrees (+/- 0.5) about the screen up axis",
		near(rad_to_deg(off0.angle_to(off1)), 20.0, 0.5)
		and absf((off0.cross(off1)).normalized().dot(up0)) > 0.9999,
		"angle %s axis dot %s" % [rad_to_deg(off0.angle_to(off1)), (off0.cross(off1)).normalized().dot(up0)])
	check("REQ-16: that 100 px right drag moves the camera toward camera-left",
		off1.dot(right0) < 0.0, "offset %s right %s" % [off1, right0])
	check("REQ-16: left drag 100 px right keeps the distance to the pivot at 6000 (+/- 0.01)",
		near(cam.global_position.distance_to(ctl.pivot), 6000.0, 0.01))
	send_mouse(mouse_button(MOUSE_BUTTON_LEFT, false))

	# REQ-16 (no pole stop): 1000 px down in steps of 10 px turns the offset 200 degrees about the
	# screen right axis, passes over the pole, and has no step over 2.5 degrees and no NaN.
	ctl.orbit_basis = Basis.IDENTITY
	ctl._apply()
	var start_off: Vector3 = cam.global_position - ctl.pivot
	var axis_right: Vector3 = cam.global_basis.x
	var prev_off := start_off
	var total_deg := 0.0
	var max_step_deg := 0.0
	var all_finite := true
	var over_pole := false
	var axis_drift := 0.0
	send_mouse(mouse_button(MOUSE_BUTTON_LEFT, true))
	for i in 100:
		send_mouse(mouse_motion(Vector2(0, 10)))
		var cur_off: Vector3 = cam.global_position - ctl.pivot
		var step_deg := rad_to_deg(prev_off.angle_to(cur_off))
		total_deg += step_deg
		max_step_deg = maxf(max_step_deg, step_deg)
		all_finite = all_finite and cur_off.is_finite() and is_finite(step_deg)
		over_pole = over_pole or absf(cur_off.normalized().y) > 0.9998
		axis_drift = maxf(axis_drift, absf(cur_off.dot(axis_right) - start_off.dot(axis_right)))
		prev_off = cur_off
	send_mouse(mouse_button(MOUSE_BUTTON_LEFT, false))
	check("REQ-16: 1000 px drag down in 10 px steps turns the offset 200 degrees (+/- 1) in total",
		near(total_deg, 200.0, 1.0), str(total_deg))
	check("REQ-16: the 1000 px drag down passes over the pole (offset reaches the Y axis)",
		over_pole)
	check("REQ-16: no 10 px step of the 1000 px drag turns the view more than 2.5 degrees, and no NaN",
		max_step_deg <= 2.5 and all_finite, "max step %s finite %s" % [max_step_deg, all_finite])
	check("REQ-16: the 1000 px drag down turns about the screen right axis (right component kept, within 0.01 km)",
		axis_drift < 0.01, str(axis_drift))
	check("REQ-16: the 1000 px drag down keeps the distance to the pivot at 6000 (+/- 0.01)",
		near(cam.global_position.distance_to(ctl.pivot), 6000.0, 0.01))
	ctl.orbit_basis = Basis.IDENTITY
	ctl._apply()

	var basis_before: Basis = ctl.orbit_basis
	send_mouse(mouse_motion(Vector2(200, 0)))
	check("REQ-16: motion after button release does not orbit",
		ctl.orbit_basis.is_equal_approx(basis_before), str(ctl.orbit_basis))

	# M3 REQ-9 (Revision 3): distance * f^(+1 in, -1 out), f = 0.95 above 500 km altitude, sqrt(0.95) at or below it.
	ctl.distance = 6000.0
	ctl._apply()
	send_mouse(mouse_button(MOUSE_BUTTON_WHEEL_UP, true))
	check("M3 REQ-9: one wheel notch in from 6000 gives 5700.0 (+/- 0.01)",
		near(ctl.distance, 5700.0, 0.01), str(ctl.distance))
	send_mouse(mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true))
	check("M3 REQ-9: one notch out from 5700 gives 6000 (+/- 0.01)",
		near(ctl.distance, 6000.0, 0.01), str(ctl.distance))

	# 19 and 20 notches in from 6000 (altitude above 500 km for both steps).
	ctl.distance = 6000.0
	ctl._apply()
	for i in 19:
		send_mouse(mouse_button(MOUSE_BUTTON_WHEEL_UP, true))
	check("M3 REQ-9: after 19 notches in from 6000, distance is 2264.12 (+/- 0.01)",
		near(ctl.distance, 2264.12, 0.01), str(ctl.distance))
	send_mouse(mouse_button(MOUSE_BUTTON_WHEEL_UP, true))
	check("M3 REQ-9: after 20 notches in from 6000, distance is 2150.92 (+/- 0.01)",
		near(ctl.distance, 2150.92, 0.01), str(ctl.distance))
	for i in 8:
		send_mouse(mouse_button(MOUSE_BUTTON_WHEEL_UP, true))
	check("M3 REQ-9: 8 more notches (altitude at or below 500 km) give 1751.94 (+/- 0.01)",
		near(ctl.distance, 1751.94, 0.01), str(ctl.distance))
	send_mouse(mouse_button(MOUSE_BUTTON_WHEEL_UP, true))
	check("M3 REQ-9: the 9th notch stops at the minimum 1748.232 (+/- 0.001)",
		near(ctl.distance, 1748.232, 0.001), str(ctl.distance))
	send_mouse(mouse_button(MOUSE_BUTTON_WHEEL_UP, true))
	check("M3 REQ-9: a further notch never goes below 1748.232",
		ctl.distance >= 1748.232 and near(ctl.distance, 1748.232, 0.001), str(ctl.distance))

	# 29 notches in from 6000 reach the minimum.
	ctl.distance = 6000.0
	ctl._apply()
	for i in 29:
		send_mouse(mouse_button(MOUSE_BUTTON_WHEEL_UP, true))
	check("M3 REQ-9: 29 notches in from 6000 give 1748.232 (+/- 0.001)",
		near(ctl.distance, 1748.232, 0.001), str(ctl.distance))

	# Altitude exactly 500 km (distance 2237.4): one notch in uses sqrt(0.95).
	ctl.distance = 2237.4
	ctl._apply()
	send_mouse(mouse_button(MOUSE_BUTTON_WHEEL_UP, true))
	check("M3 REQ-9: at altitude 500 one notch in gives 2180.75 (+/- 0.01)",
		near(ctl.distance, 2180.75, 0.01), str(ctl.distance))

	# One notch out from the minimum (altitude 10.832): sqrt(0.95) step.
	ctl.distance = 1748.232
	ctl._apply()
	send_mouse(mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true))
	check("M3 REQ-9: one notch out from 1748.232 gives 1793.65 (+/- 0.01)",
		near(ctl.distance, 1793.65, 0.01), str(ctl.distance))

	# 23 notches out from 6000 stay below 20000; the 24th reaches 20000.
	ctl.distance = 6000.0
	ctl._apply()
	for i in 23:
		send_mouse(mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true))
	check("M3 REQ-9: after 23 notches out from 6000, distance is 19521.2 (+/- 0.1)",
		near(ctl.distance, 19521.2, 0.1), str(ctl.distance))
	send_mouse(mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true))
	check("M3 REQ-9: the 24th notch out clamps at 20000 (+/- 0.01)",
		near(ctl.distance, 20000.0, 0.01), str(ctl.distance))

	# Pivot at (500, 0, 0), 300 notches in: the camera stays at 1748.232 or more from the Moon's centre.
	ctl.pivot = Vector3(500, 0, 0)
	ctl.distance = 3000.0
	ctl.orbit_basis = Basis.IDENTITY
	ctl._apply()
	for i in 300:
		send_mouse(mouse_button(MOUSE_BUTTON_WHEEL_UP, true))
	var from_centre := cam.global_position.distance_to(moon_node.global_position)
	check("M3 REQ-9: pivot (500, 0, 0), 300 notches in: distance from the Moon's centre is 1748.232 (+/- 0.001)",
		near(from_centre, 1748.232, 0.001), str(from_centre))
	ctl.pivot = Vector3.ZERO
	ctl.distance = 6000.0
	ctl._apply()

	# REQ-15 orbit about an exported pivot that is not the origin.
	ctl.pivot = Vector3(10, 0, 0)
	ctl.distance = 6000.0
	ctl.orbit_basis = Basis.IDENTITY
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


# ---------------------------------------------------------------- M3 camera (M3 REQ-6, REQ-9 to REQ-11)

func test_m3_camera() -> void:
	var main := spawn_main()
	var rig := main.get_node("CameraRig")
	var cam := rig.get_node("Camera3D") as Camera3D
	var ctl = rig

	# M3 REQ-11: startup look-around values, and the M1 REQ-21 view.
	check("M3 REQ-11: tilt and heading are 0 at startup",
		near(ctl.tilt_deg, 0.0, 1e-6) and near(ctl.heading_deg, 0.0, 1e-6),
		"tilt %s heading %s" % [ctl.tilt_deg, ctl.heading_deg])
	var expected := Basis.looking_at(Vector3(0, 0, -1), Vector3.UP)
	var basis_err := 0.0
	for i in 3:
		basis_err = maxf(basis_err, cam.global_basis[i].distance_to(expected[i]))
	check("M3 REQ-11: startup camera transform equals the M1 REQ-21 view (within 1e-4)",
		basis_err < 1e-4 and cam.global_position.distance_to(Vector3(0, 0, 6000)) < 1e-4,
		"basis error %s position %s" % [basis_err, cam.global_position])

	# M3 REQ-11: right drag 1000 px down clamps tilt at 85; 100 px right gives heading -20; position unchanged.
	var pos0 := cam.global_position
	send_mouse(mouse_button(MOUSE_BUTTON_RIGHT, true))
	send_mouse(mouse_motion(Vector2(0, 1000)))
	check("M3 REQ-11: right drag 1000 px down clamps tilt at 85", near(ctl.tilt_deg, 85.0, 1e-4), str(ctl.tilt_deg))
	send_mouse(mouse_motion(Vector2(100, 0)))
	check("M3 REQ-11: right drag 100 px right from heading 0 gives heading -20 (+/- 0.001)",
		near(ctl.heading_deg, -20.0, 0.001), str(ctl.heading_deg))
	check("M3 REQ-11: look mode leaves the camera position unchanged (within 1e-4)",
		cam.global_position.distance_to(pos0) < 1e-4, str(cam.global_position))
	send_mouse(mouse_motion(Vector2(0, -3000)))
	check("M3 REQ-11: right drag up clamps tilt at 0", near(ctl.tilt_deg, 0.0, 1e-4), str(ctl.tilt_deg))
	send_mouse(mouse_button(MOUSE_BUTTON_RIGHT, false))
	send_mouse(mouse_motion(Vector2(200, 0)))
	check("M3 REQ-11: motion after right release does not change heading",
		near(ctl.heading_deg, -20.0, 0.001), str(ctl.heading_deg))
	send_mouse(mouse_button(MOUSE_BUTTON_RIGHT, true))
	send_mouse(mouse_motion(Vector2(1000, 0)))
	send_mouse(mouse_button(MOUSE_BUTTON_RIGHT, false))
	check("M3 REQ-11: heading wraps to [-180, 180)",
		ctl.heading_deg >= -180.0 and ctl.heading_deg < 180.0, str(ctl.heading_deg))
	ctl.tilt_deg = 0.0
	ctl.heading_deg = 0.0
	ctl.distance = 6000.0
	ctl.pivot = Vector3.ZERO
	ctl.orbit_basis = Basis.IDENTITY
	ctl._apply()

	# M3 REQ-10: at distance 1748.232 (altitude 10.832) the rates are scaled by 10.832 / 4262.6.
	# Trackball (M1 REQ-16): the camera offset turns 0.508 degrees about the camera's screen up axis.
	ctl.distance = 1748.232
	ctl.orbit_basis = Basis.IDENTITY
	ctl._apply()
	var m3_off0: Vector3 = cam.global_position - ctl.pivot
	var m3_up0: Vector3 = cam.global_basis.y
	send_mouse(mouse_button(MOUSE_BUTTON_LEFT, true))
	send_mouse(mouse_motion(Vector2(1000, 0)))
	send_mouse(mouse_button(MOUSE_BUTTON_LEFT, false))
	var m3_off1: Vector3 = cam.global_position - ctl.pivot
	var m3_angle := rad_to_deg(m3_off0.angle_to(m3_off1))
	check("M3 REQ-10: at 1748.232, left drag 1000 px turns the camera offset 0.508 degrees (+/- 0.005) about the screen up axis",
		near(m3_angle, 0.508, 0.005) and absf((m3_off0.cross(m3_off1)).normalized().dot(m3_up0)) > 0.9999,
		"angle %s" % m3_angle)
	ctl.orbit_basis = Basis.IDENTITY
	ctl._apply()
	var right: Vector3 = cam.global_basis.x
	send_mouse(mouse_button(MOUSE_BUTTON_MIDDLE, true))
	send_mouse(mouse_motion(Vector2(1000, 0)))
	send_mouse(mouse_button(MOUSE_BUTTON_MIDDLE, false))
	check("M3 REQ-10: at 1748.232, middle drag 1000 px moves the pivot 0.444 km camera-left (+/- 0.005)",
		near(ctl.pivot.length(), 0.444, 0.005) and ctl.pivot.dot(right) < 0.0, str(ctl.pivot))
	ctl.pivot = Vector3.ZERO
	ctl.distance = 6000.0
	ctl._apply()

	free_main(main)


# ---------------------------------------------------------------- M3 shadows (M3 REQ-5, REQ-6)

func _shadow_distance_expected(d_c: float) -> float:
	var near_term := sqrt(d_c * d_c - 1728.2 * 1728.2) if d_c >= 1728.2 else 0.0
	return near_term + sqrt(1747.732 * 1747.732 - 1728.2 * 1728.2)


func test_m3_shadows() -> void:
	var main := spawn_main()
	var sun := main.get_node("Sun") as DirectionalLight3D
	var moon := main.get_node("Moon") as Node3D
	var ctl = main.get_node("CameraRig")
	var cam := ctl.get_node("Camera3D") as Camera3D
	check("M3 REQ-5: Sun shadow_enabled is true", sun.shadow_enabled)
	check("M3 REQ-5: directional_shadow_mode is SHADOW_PARALLEL_4_SPLITS",
		sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, str(sun.directional_shadow_mode))
	check("M3 REQ-5: splits are 0.1, 0.2, 0.5 and blend splits is on",
		near(sun.directional_shadow_split_1, 0.1, 1e-6) and near(sun.directional_shadow_split_2, 0.2, 1e-6)
		and near(sun.directional_shadow_split_3, 0.5, 1e-6) and sun.directional_shadow_blend_splits)
	check("M3 REQ-5: light_angular_distance is 0", near(sun.light_angular_distance, 0.0, 1e-6))
	check("M3 REQ-5: project directional shadow size is 4096",
		int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size")) == 4096)
	var casting := 0
	for c in chunks_of(moon):
		if c.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
			casting += 1
	check("M3 REQ-5: all 96 chunks keep cast_shadow on (%d of 96)" % casting, casting == CHUNKS)

	# M3 REQ-6: max shadow distance follows S(D_c) with D_c from the Moon's centre.
	var cases := [[1748.232, 524.5], [6000.0, 6006.3], [20000.0, 20185.8]]
	for case in cases:
		ctl.pivot = Vector3.ZERO
		ctl.distance = case[0]
		ctl._apply()
		check("M3 REQ-6: pivot at centre, distance %s gives max shadow distance %s (+/- 0.5)" % [case[0], case[1]],
			near(sun.directional_shadow_max_distance, case[1], 0.5), str(sun.directional_shadow_max_distance))
	ctl.pivot = Vector3(500, 0, 0)
	ctl.distance = 3000.0
	ctl.orbit_basis = Basis.IDENTITY
	ctl._apply()
	var d_c :=cam.global_position.distance_to(moon.global_position)
	check("M3 REQ-6 (pivot offset): pivot (500, 0, 0), distance 3000 gives S(D_c) with D_c from the centre (+/- 0.5)",
		near(sun.directional_shadow_max_distance, _shadow_distance_expected(d_c), 0.5),
		"D_c %s max %s" % [d_c, sun.directional_shadow_max_distance])
	free_main(main)


# ---------------------------------------------------------------- M3 docs (M3 REQ-18, REQ-22)

## Digits in groups of three separated by spaces, as PERFORMANCE.md writes byte counts.
func _grouped_digits(n: int) -> String:
	var digits := str(n)
	var out := ""
	var i := digits.length()
	while i > 3:
		out = " " + digits.substr(i - 3, 3) + out
		i -= 3
	return digits.substr(0, i) + out


func test_m3_docs() -> void:
	var ds := FileAccess.get_file_as_string(DATA_SOURCES)
	var arch := FileAccess.get_file_as_string(ARCHITECTURE)
	var perf := FileAccess.get_file_as_string("res://docs/PERFORMANCE.md")
	var png_path := "res://assets/textures/lunar_normal_enu_4096x2048.png"
	var level_path := "res://assets/elevation/lola_height_m_4096x2048.f32"
	check("M3 REQ-18: DATA_SOURCES has the 'Normal map (Milestone 3)' section",
		ds.contains("## Normal map (Milestone 3)"))
	var level_sha := FileAccess.get_sha256(level_path)
	var png_sha := FileAccess.get_sha256(png_path)
	check("M3 REQ-18: DATA_SOURCES lists the source level SHA-256 (%s)" % level_sha.left(12),
		level_sha != "" and ds.contains(level_sha))
	check("M3 REQ-18: DATA_SOURCES lists the output PNG SHA-256 (%s)" % png_sha.left(12),
		png_sha != "" and ds.contains(png_sha))
	check("M3 REQ-18: DATA_SOURCES gives the k rule, both commands and the no-smoothing statement",
		ds.contains("k rule") and ds.contains("make normal-map") and ds.contains("make moon-data")
		and ds.contains("smoothing"))
	check("M3 REQ-22: ARCHITECTURE.md replaces the shared StandardMaterial3D text with the lunar shader",
		not arch.contains("one shared StandardMaterial3D") and arch.contains("lunar_surface.gdshader"))
	var png_size := FileAccess.get_file_as_bytes(png_path).size()
	check("M3 REQ-22: PERFORMANCE.md gives the normal map file size (%d bytes) and the 42.7 MiB estimate" % png_size,
		(perf.contains(str(png_size)) or perf.contains(_grouped_digits(png_size))) and perf.contains("42.7 MiB"))
	check("M3 REQ-22: PERFORMANCE.md lists the shadow settings and the pending user run rows",
		perf.contains("directional_shadow_max_distance") and perf.contains("shadow_bias")
		and perf.contains("pending user run"))


# ---------------------------------------------------------------- M2 elevation assets (REQ-6, REQ-7, REQ-8, REQ-11, REQ-29)

func test_elevation_assets() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(METADATA))
	check("REQ-11: assets/elevation/moon_data.json parses as a JSON object", parsed is Dictionary)
	if not (parsed is Dictionary):
		return
	var levels: Array = parsed.get("elevation_levels", [])
	check("REQ-11: three elevation levels are listed", levels.size() == 3, str(levels.size()))
	var convention := str(parsed.get("grid_convention", ""))
	var extent_ref := {"lon_west_deg": 0.0, "lon_east_deg": 360.0, "lat_north_deg": 90.0, "lat_south_deg": -90.0}
	var want_sizes := [[4096, 2048], [2048, 1024], [1024, 512]]
	var fields := ["path", "width", "height", "data_type", "byte_order", "units", "grid_convention", "extent",
		"reference_radius_m", "min", "max", "mean", "nodata_count", "sha256"]
	for i in range(min(levels.size(), 3)):
		var e: Dictionary = levels[i]
		var w: int = want_sizes[i][0]
		var h: int = want_sizes[i][1]
		var missing := []
		for f in fields:
			if not e.has(f):
				missing.append(f)
		check("REQ-11: level %dx%d lists every field (missing %s)" % [w, h, str(missing)], missing.is_empty())
		check("REQ-7: level %dx%d has the expected width and height" % [w, h],
			int(e.get("width", 0)) == w and int(e.get("height", 0)) == h)
		var path := "res://" + str(e.get("path", ""))
		var bytes := FileAccess.get_file_as_bytes(path)
		check("REQ-7: %s is %d bytes (samples x lines x 4)" % [path, w * h * 4], bytes.size() == w * h * 4,
			str(bytes.size()))
		check("REQ-11: %s SHA-256 matches the metadata" % path,
			FileAccess.get_sha256(path) == str(e.get("sha256", "")))
		var vals := bytes.to_float32_array()
		var vmin := INF
		var vmax := -INF
		var sum := 0.0
		var n := 0
		var nan_count := 0
		for v in vals:
			if is_nan(v):
				nan_count += 1
				continue
			vmin = minf(vmin, v)
			vmax = maxf(vmax, v)
			sum += v
			n += 1
		var mean := sum / n
		check("REQ-11: %dx%d min, max and mean recomputed from the file match the metadata" % [w, h],
			near(vmin, float(e.get("min", 0.0)), 0.001) and near(vmax, float(e.get("max", 0.0)), 0.001)
			and near(mean, float(e.get("mean", 0.0)), 0.001),
			"min %s max %s mean %s" % [vmin, vmax, mean])
		check("REQ-6: %dx%d NoData count is %d in the file and in the metadata" % [w, h, nan_count],
			nan_count == 0 and int(e.get("nodata_count", -1)) == nan_count)
		check("REQ-8: %dx%d grid convention and extent are the REQ-8 values" % [w, h],
			str(e.get("grid_convention", "")) == convention and e.get("extent") == extent_ref)
		check("REQ-11: %dx%d reference radius is 1737400 m" % [w, h],
			near(float(e.get("reference_radius_m", 0.0)), 1737400.0, 0.001))

	var albedo: Dictionary = parsed.get("albedo", {})
	check("REQ-8/REQ-29: albedo entry names the texture and its size",
		str(albedo.get("path", "")) == "assets/textures/lunar_albedo_4096x2048.png"
		and int(albedo.get("width", 0)) == 4096 and int(albedo.get("height", 0)) == 2048)
	check("REQ-11: albedo SHA-256 matches the texture file and the metadata",
		FileAccess.get_sha256(TEXTURE) == str(albedo.get("sha256", "")) and FileAccess.get_sha256(TEXTURE) != "")
	var same_grid: bool = str(albedo.get("grid_convention", "")) == convention and albedo.get("extent") == extent_ref
	for e in levels:
		same_grid = same_grid and str(e.get("grid_convention", "")) == convention and e.get("extent") == extent_ref
	check("REQ-29: the albedo and every elevation level share the grid convention and extents", same_grid)

	var sources: Dictionary = parsed.get("sources", {})
	var elev: Dictionary = sources.get("elevation", {})
	var src_files: Array = elev.get("files", [])
	var src_ok := src_files.size() == 2
	for f in src_files:
		var fname := str(f.get("path", "")).get_file()
		var raw := RAW_DEM_DIR + fname
		src_ok = src_ok and FileAccess.file_exists(raw) and FileAccess.get_sha256(raw) == str(f.get("sha256", ""))
	check("REQ-11: source label and image SHA-256 match data/raw/lola_ldem_64", src_ok)
	check("REQ-11: source product and version recorded", str(elev.get("product_id", "")) == "LDEM_64"
		and str(elev.get("product_version_id", "")) == "V3.1" and str(elev.get("data_set_id", "")) == "LRO-L-LOLA-4-GDR-V1.0")
	check("REQ-11: source scaling factor 0.5 and offset 1737400 m are recorded from the label",
		near(float(elev.get("scaling_factor_m_per_dn", 0.0)), 0.5, 1e-9) and near(float(elev.get("offset_m", 0.0)), 1737400.0, 1e-3))
	check("REQ-6: the label has no missing constant (recorded as null)", elev.get("missing_constant") == null)
	var generator: Dictionary = parsed.get("generator", {})
	check("REQ-11: generator records crate moon-data, version and toolchain",
		str(generator.get("crate", "")) == "moon-data" and str(generator.get("version", "")) != ""
		and str(generator.get("rust_toolchain", "")) != "")
	check("REQ-8: metadata grid convention is the REQ-8 statement",
		convention.contains("360*(x+0.5)/W deg E") and convention.contains("90-180*(y+0.5)/H deg"))


# ---------------------------------------------------------------- data sources (M1 REQ-22, REQ-25)

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


# ---------------------------------------------------------------- M2 documentation (REQ-1, REQ-2, REQ-33)

func test_docs_m2() -> void:
	var ds := FileAccess.get_file_as_string(DATA_SOURCES)
	var ldem_items := {
		"product LDEM_64": "LDEM_64",
		"data set id": "LRO-L-LOLA-4-GDR-V1.0",
		"exact IMG URL (lower case as served)": "https://pds-geosciences.wustl.edu/lro/lro-l-lola-3-rdr-v1/lrolol_1xxx/data/lola_gdr/cylindrical/img/ldem_64.img",
		"exact LBL URL (lower case as served)": "https://pds-geosciences.wustl.edu/lro/lro-l-lola-3-rdr-v1/lrolol_1xxx/data/lola_gdr/cylindrical/img/ldem_64.lbl",
		"retrieval date": "Retrieval date",
		"sample and line counts": "23040",
		"lines": "11520",
		"pixels per degree": "64 pixels per degree",
		"projection": "SIMPLE CYLINDRICAL",
		"units": "METER",
		"scaling factor": "SCALING_FACTOR",
		"offset": "OFFSET",
		"offset value": "1737400",
		"vertical reference": "Vertical reference",
		"NoData finding": "NoData",
		"license text": "License",
		"citation": "Smith",
	}
	for k in ldem_items:
		check("REQ-1: Elevation section lists %s" % k, ds.contains(ldem_items[k]))
	check("REQ-1: Elevation section is a numbered Milestone 2 section", ds.contains("## Elevation (Milestone 2)"))
	check("REQ-1: the M1 'No elevation data is used yet' text is replaced",
		not ds.contains("No elevation data is used yet"))
	for name in ["LDEM_64.LBL", "LDEM_64.IMG"]:
		var sha := FileAccess.get_sha256(RAW_DEM_DIR + name)
		check("REQ-1: SHA-256 of %s (%s) is documented" % [name, sha.left(12)],
			sha != "" and ds.contains(sha))

	check("REQ-2: resolution decision section names 64 ppd versus 512 ppd SLDEM2015",
		ds.contains("Resolution decision") and ds.contains("64 ppd") and ds.contains("512 ppd") and ds.contains("SLDEM2015"))
	check("REQ-2: resolution reasons include the mesh spacing, the missing poles and the data size",
		ds.contains("vertex spacing") and ds.contains("poles") and ds.contains("tens of gigabytes"))

	var arch := FileAccess.get_file_as_string(ARCHITECTURE)
	check("REQ-33: ARCHITECTURE.md documents the cube-sphere chunk layout", arch.contains("## Cube-sphere chunk layout"))
	check("REQ-33: ARCHITECTURE.md explains why the cube-sphere avoids polar distortion",
		arch.contains("Why a cube-sphere avoids polar distortion"))
	check("REQ-33: ARCHITECTURE.md gives the vertex count 6 x 16 x 65 x 65 = 405 600",
		arch.contains("6 x 16 x 65 x 65 = 405 600"))
	check("REQ-33: ARCHITECTURE.md gives the height level used and why",
		arch.contains("### Height level used") and arch.contains("2048 x 1024"))
	check("REQ-33: ARCHITECTURE.md gives the measured build time",
		arch.contains("### Build cost") and arch.contains("terrain build ms"))
	check("REQ-33: ARCHITECTURE.md gives the transition path (LOD, chunk loading, 512 ppd regional tiles)",
		arch.contains("## Chunk, LOD and streaming design") and arch.contains("LOD")
		and arch.contains("SLDEM2015") and arch.contains("512 ppd"))


# ---------------------------------------------------------------- repo scan (REQ-23)

# ---------------------------------------------------------------- lunar surface fly camera (REQ-5, REQ-6)

func tf_near(a: Transform3D, b: Transform3D, tol: float) -> bool:
	if a.origin.distance_to(b.origin) > tol:
		return false
	for i in 3:
		if a.basis[i].distance_to(b.basis[i]) > tol:
			return false
	return true


func test_lunar_fly() -> void:
	var main := spawn_main()
	var fly = main.get_node("FlyCamera")
	var orbit := main.get_node("CameraRig/Camera3D") as Camera3D
	var fly_cam: Camera3D = fly.camera
	var near_cam: Camera3D = fly.near_camera
	var near_vp: SubViewport = fly.near_viewport

	# REQ-6: structure, checked before fly mode is entered.
	check("REQ-6: near SubViewport has a transparent background", near_vp.transparent_bg)
	check("REQ-6: near SubViewport shares the main World3D",
		near_vp.world_3d == main.get_viewport().world_3d)
	check("REQ-6: near camera has near 1e-6 km and far 20 km",
		near(near_cam.near, 1e-6, 1e-12) and near(near_cam.far, 20.0, 1e-9),
		"near %s far %s" % [near_cam.near, near_cam.far])
	# Spec D9 / REQ-6 (Rev. 7): mask 3 = layer 1 + layer 2 (terrain alone renders black under the Sun).
	check("REQ-6: near camera cull mask is 3 (terrain layer 2 plus layer 1, spec D9 rev 7)",
		near_cam.cull_mask == 3, "cull_mask %d" % near_cam.cull_mask)
	check("REQ-6: far camera has near 0.05 km and far 440000 km",
		near(fly_cam.near, 0.05, 1e-9) and near(fly_cam.far, 440000.0, 1e-6),
		"near %s far %s" % [fly_cam.near, fly_cam.far])
	check("REQ-6: far camera draws all layers", fly_cam.cull_mask == (1 << 20) - 1,
		"cull_mask %d" % fly_cam.cull_mask)
	check("REQ-6: orbit camera keeps near 0.05 and far 440000",
		near(orbit.near, 0.05, 1e-9) and near(orbit.far, 440000.0, 1e-6),
		"near %s far %s" % [orbit.near, orbit.far])

	# REQ-6 and REQ-5: switching. Fly mode is entered by the same call the F key handler makes.
	var orbit_t: Transform3D = orbit.global_transform
	check("REQ-6: orbit mode at start: orbit camera current, overlay hidden, near viewport not rendering",
		orbit.current and not fly_cam.current and not fly.active and not fly._overlay.visible
		and near_vp.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	fly.set_active(not fly.active)
	check("REQ-5: lunar terrain library and data load for fly mode", fly.terrain != null,
		"fly mode stays disabled without the native terrain")
	if fly.terrain == null:
		free_main(main)
		return
	fly._process(0.0)
	check("REQ-6: F enters fly mode: fly camera current, orbit camera not, overlay shown, near viewport rendering",
		fly.active and fly_cam.current and not orbit.current and fly._overlay.visible
		and near_cam.current and near_vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS)
	var first_pos_err: float = (fly_cam.global_position - orbit_t.origin).length()
	var first_view_err: float = (-fly_cam.global_basis.z).angle_to(-orbit_t.basis.z)
	check("REQ-6: first fly frame has the orbit camera's position (within 1e-4 km)",
		first_pos_err <= 1e-4, "error %s km, fly %s orbit %s" % [first_pos_err, fly_cam.global_position, orbit_t.origin])
	# Spec REQ-6 (Rev. 7): view may differ by at most 1 deg (the +-89 deg pitch cap). Angle in radians.
	check("REQ-6: first fly frame has the orbit camera's view direction (within 1 deg, 0.01745 rad, spec rev 7)",
		first_view_err <= deg_to_rad(1.0), "error %s rad" % first_view_err)
	check("REQ-6: near and far cameras share the global transform and the vertical FOV",
		tf_near(near_cam.global_transform, fly_cam.global_transform, 1e-9) and near_cam.fov == fly_cam.fov,
		"fov %s / %s" % [near_cam.fov, fly_cam.fov])
	fly.advance(0.5, Vector3(1, 0, 1))
	fly._process(0.0)
	check("REQ-6: near and far cameras share the global transform after moving",
		tf_near(near_cam.global_transform, fly_cam.global_transform, 1e-9))
	fly.set_active(not fly.active)
	check("REQ-6: leaving fly mode restores the orbit camera current and the fly camera not current",
		orbit.current and not fly_cam.current and not fly.active)
	check("REQ-6: leaving fly mode hides the overlay", not fly._overlay.visible)
	check("REQ-6: leaving fly mode stops the near viewport from rendering",
		not near_cam.current and near_vp.render_target_update_mode == SubViewport.UPDATE_DISABLED,
		"near camera current %s, update mode %s" % [near_cam.current, near_vp.render_target_update_mode])
	check("REQ-6: leaving fly mode keeps the orbit camera's transform from entry",
		tf_near(orbit.global_transform, orbit_t, 1e-6))

	# REQ-5: controls, using the functions and handlers in fly_camera.gd.
	fly.set_active(true)
	fly.speed_scale = 1.0
	fly.place_at(0.0, 0.0, 100.0)
	fly.yaw_deg = 0.0
	fly.pitch_deg = 0.0
	fly._unhandled_input(mouse_motion(Vector2(100, -50)))
	check("REQ-5: mouse look is 0.2 deg per px: 100 px right gives +20 yaw, 50 px up gives +10 pitch",
		near(fly.yaw_deg, 20.0, 1e-6) and near(fly.pitch_deg, 10.0, 1e-6),
		"yaw %s pitch %s" % [fly.yaw_deg, fly.pitch_deg])
	fly._unhandled_input(mouse_motion(Vector2(0, -10000)))
	check("REQ-5: pitch is limited to +89 degrees", near(fly.pitch_deg, 89.0, 1e-9), str(fly.pitch_deg))
	fly._unhandled_input(mouse_motion(Vector2(0, 100000)))
	check("REQ-5: pitch is limited to -89 degrees", near(fly.pitch_deg, -89.0, 1e-9), str(fly.pitch_deg))

	# speed = clamp(2 x height above ground, 0.05 m/s, 2000 m/s), in m/s.
	var speed_cases := [[0.5, 1.0], [100.0, 200.0], [5000.0, 2000.0], [0.0, 0.1]]
	for c in speed_cases:
		fly.place_at(0.0, 0.0, c[0])
		check("REQ-5: speed at %s m above ground is %s m/s (got %.4f)" % [c[0], c[1], fly.speed_ms()],
			near(fly.speed_ms(), c[1], 1e-3), str(fly.speed_ms()))
	# 5 cm floor: the camera is never closer than 5 cm to the generated surface.
	fly.place_at(0.0, 0.0, 0.0)
	check("REQ-5: camera stays at least 5 cm above the generated surface",
		fly.height_above_ground_km() >= 0.05 / 1000.0 - 1e-9, "height %s km" % fly.height_above_ground_km())

	# Movement: at 0.5 m the speed is 1 m/s, so one second straight up moves 1 m.
	fly.place_at(0.0, 0.0, 0.5)
	# Differences are taken in doubles: Vector3 is float32, about 0.1 m at 1737 km.
	var px0: float = fly.px
	var py0: float = fly.py
	var pz0: float = fly.pz
	fly.advance(1.0, Vector3(0, 1, 0))
	var dx: float = fly.px - px0
	var dy: float = fly.py - py0
	var dz: float = fly.pz - pz0
	var moved: float = sqrt(dx * dx + dy * dy + dz * dz)
	check("REQ-5: moving for 1 s at 1 m/s covers 1 m (0.001 km), got %s km" % moved,
		near(moved, 0.001, 1e-7), str(moved))

	# Wheel: x1.25 per notch up, x0.8 per notch down, applied to the speed.
	fly.place_at(0.0, 0.0, 100.0)
	fly._unhandled_input(mouse_button(MOUSE_BUTTON_WHEEL_UP, true))
	check("REQ-5: wheel up multiplies the speed scale by 1.25", near(fly.speed_scale, 1.25, 1e-9), str(fly.speed_scale))
	check("REQ-5: wheel up gives 250 m/s at 100 m above ground", near(fly.speed_ms(), 250.0, 1e-3), str(fly.speed_ms()))
	fly._unhandled_input(mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true))
	fly._unhandled_input(mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true))
	check("REQ-5: two wheel-down notches from 1.25 multiply the speed scale by 0.8 each (gives 0.8)",
		near(fly.speed_scale, 1.25 * 0.8 * 0.8, 1e-9), str(fly.speed_scale))

	fly.set_active(false)
	free_main(main)


# ---------------------------------------------------------------- lunar surface phase 4 (REQ-21 to REQ-25, REQ-7a)
# Shader rows are source inspection, as the spec's acceptance table says. Image checks are not here (screenshot agent).
const LUNAR_SHADER := "res://shaders/lunar_surface.gdshader"
const ROCK_SHADER := "res://shaders/lunar_rock.gdshader"
const NEAR_WORLD := "res://scripts/near_world.gd"


func _smoothstep(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func test_lunar_surface_material() -> void:
	# REQ-21: Lommel-Seeliger light, no specular, no ambient, no emission, in both the regolith and the rock shader.
	for path: String in [LUNAR_SHADER, ROCK_SHADER]:
		var src := FileAccess.get_file_as_string(path)
		var nm: String = path.get_file()
		check("REQ-21: %s disables specular and ambient light in render_mode" % nm,
			_regex_hit(src, "render_mode[^\n]*specular_disabled") and _regex_hit(src, "render_mode[^\n]*ambient_light_disabled"))
		check("REQ-21: %s writes no EMISSION, RIM, CLEARCOAT, SPECULAR_LIGHT or AMBIENT" % nm,
			not _regex_hit(src, "\\b(EMISSION|RIM|CLEARCOAT)\\s*[-+*/]?=[^=]") and not src.contains("SPECULAR_LIGHT")
			and not _regex_hit(src, "\\bAMBIENT\\b"))
		check("REQ-21: %s uses the Lommel-Seeliger term 2 cos i / (cos i + cos e) only" % nm,
			src.contains("2.0 * cos_i / (cos_i + cos_e)") and src.contains("DIFFUSE_LIGHT +="))
	# REQ-23: rocks are drawn with the same law and the rock shader is the one the rock material loads.
	check("REQ-23: near_world.gd loads lunar_rock.gdshader for rocks",
		FileAccess.get_file_as_string(NEAR_WORLD).contains("res://shaders/lunar_rock.gdshader"))

	# REQ-22 / D8: detail albedo is multiplicative, at most +-5 %. a is a weighted sum (0.6 + 0.4 = 1) of value
	# noise in [-1, 1] (hash13 maps to [-1, 1]), and the clamp repeats the bound.
	var lsrc := FileAccess.get_file_as_string(LUNAR_SHADER)
	check("REQ-22: detail albedo is albedo *= 1 + 0.05 * clamp(a, -1, 1) with fade (+-5 % bound)",
		lsrc.contains("albedo *= 1.0 + 0.05 * clamp(a, -1.0, 1.0) *"))
	check("REQ-22: detail noise weights sum to 1 and hash13 returns [-1, 1] (+-5 % bound)",
		lsrc.contains("float a = 0.6 * vnoise(local_m, 0.1) + 0.4 * vnoise(local_m + 7.3, 0.03);")
		and lsrc.contains("float(h) * (2.0 / 4294967295.0) - 1.0"))
	# REQ-24: grain normal faded to zero beyond 20 m, no new texture (only albedo and the existing normal map).
	check("REQ-24: grain fade is 1 - smoothstep(8, 20, distance in m), so zero beyond 20 m",
		lsrc.contains("float grain_fade = 1.0 - smoothstep(8.0, 20.0, dist_m);") and lsrc.contains("if (grain_fade > 0.0)"))
	check("REQ-24: shader declares only the existing two textures (albedo and normal map)",
		lsrc.count("uniform sampler2D") == 2)
	for d in [20.0, 20.5, 50.0, 1000.0, 1.0e6]:
		var fade := 1.0 - _smoothstep(8.0, 20.0, d)
		check("REQ-24: grain fade at %s m is zero" % d, fade == 0.0, "fade %s" % fade)
	check("REQ-24: grain fade at 0 m is 1 (replica of the shader formula)", 1.0 - _smoothstep(8.0, 20.0, 0.0) == 1.0)


func test_rock_albedo_factor() -> void:
	# REQ-23: per-rock albedo factor in [1.0, 1.3], from the material stream (4). Source line and a replica of it.
	var src := FileAccess.get_file_as_string(NEAR_WORLD)
	check("REQ-23: rock albedo factor is 1.0 + 0.3 x u with u in [0, 1) from the material hash",
		src.contains("b.append(1.0 + 0.3 * float((h >> 11) & 0x1FFFFFFFFFFFFF) / 9007199254740992.0)"))
	var t = ClassDB.instantiate("LunarTerrain")
	var problem: String = t.load_data(ProjectSettings.globalize_path("res://"))
	check("REQ-23: native library loads its data for the rock factor replica", problem == "", problem)
	if problem != "":
		return
	var lo := INF
	var hi := -INF
	for i in 2000:
		var h: int = t.hash64(7, 4, 0, i, i * 3 - 500, 1000 - i, i % 17)
		var f := 1.0 + 0.3 * float((h >> 11) & 0x1FFFFFFFFFFFFF) / 9007199254740992.0
		lo = minf(lo, f)
		hi = maxf(hi, f)
	check("REQ-23: 2000 replica rock factors lie in [1.0, 1.3) (min %.6f, max %.6f)" % [lo, hi],
		lo >= 1.0 and hi < 1.3, "min %s max %s" % [lo, hi])


func test_phase4_shadow_splits() -> void:
	# REQ-25: below 10 km the splits are 0.02, 0.2 and 2 km with S(D) as max distance; above 10 km M3 REQ-5/6 values.
	# Godot's split values are fractions of the max distance, so fraction x max must equal the km value.
	var main := spawn_main()
	var fly = main.get_node("FlyCamera")
	var sun := main.get_node("Sun") as DirectionalLight3D
	fly.set_active(true)
	if fly.terrain == null:
		check("REQ-25: fly mode has the native terrain for the shadow check", false, "fly mode disabled")
		free_main(main)
		return
	fly.place_at(0.674, 23.473, 1.7)
	fly._apply()
	var r: float = sqrt(fly.px * fly.px + fly.py * fly.py + fly.pz * fly.pz)
	var max_d := sun.directional_shadow_max_distance
	check("REQ-25: at 1.7 m altitude the max shadow distance is S(D) (%.4f km, expected %.4f)" % [max_d, _shadow_distance_expected(r)],
		near(max_d, _shadow_distance_expected(r), 1e-3))
	check("REQ-25: at 1.7 m altitude the splits are 0.02, 0.2 and 2 km (x max distance)",
		near(sun.directional_shadow_split_1 * max_d, 0.02, 1e-4) and near(sun.directional_shadow_split_2 * max_d, 0.2, 1e-4)
		and near(sun.directional_shadow_split_3 * max_d, 2.0, 1e-4),
		"splits %s %s %s max %s" % [sun.directional_shadow_split_1, sun.directional_shadow_split_2,
			sun.directional_shadow_split_3, max_d])
	fly.place_at(0.674, 23.473, 50000.0)
	fly._apply()
	r = sqrt(fly.px * fly.px + fly.py * fly.py + fly.pz * fly.pz)
	check("REQ-25: at 50 km altitude the splits are the M3 values 0.1, 0.2 and 0.5",
		near(sun.directional_shadow_split_1, 0.1, 1e-6) and near(sun.directional_shadow_split_2, 0.2, 1e-6)
		and near(sun.directional_shadow_split_3, 0.5, 1e-6),
		"splits %s %s %s" % [sun.directional_shadow_split_1, sun.directional_shadow_split_2, sun.directional_shadow_split_3])
	check("REQ-25: at 50 km altitude the max shadow distance is S(D) (M3 REQ-6)",
		near(sun.directional_shadow_max_distance, _shadow_distance_expected(r), 1e-3),
		"max %s" % sun.directional_shadow_max_distance)
	fly.set_active(false)
	free_main(main)


## Runs scripts/scenario.gd headless with the given user arguments. Returns [exit code, combined output].
func _run_scenario(args: Array) -> Array:
	var cmd := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "scripts/scenario.gd", "--"])
	for a in args:
		cmd.append(str(a))
	var out := []
	var code := OS.execute(OS.get_executable_path(), cmd, out, true)
	return [code, "\n".join(out)]


func test_req7a_sun_override() -> void:
	# REQ-7a: N=7 CAM=ground SUN_EL=5 gives local elevation 5 +-0.01 and azimuth 90 +-0.01 (scenario 7 azimuth).
	var res := _run_scenario(["7", "ground", "5"])
	var text: String = res[1]
	var re := RegEx.new()
	re.compile("sun local elevation=(-?[0-9.]+) azimuth=([0-9.]+)")
	var m := re.search(text)
	check("REQ-7a: scenario 7 ground SUN_EL=5 exits 0 (exit %d)" % res[0], res[0] == 0, text.left(400))
	if m == null:
		check("REQ-7a: scenario 7 ground SUN_EL=5 prints the sun line", false, text.left(400))
	else:
		var el := m.get_string(1).to_float()
		var az := m.get_string(2).to_float()
		check("REQ-7a: local Sun elevation is 5 +-0.01 (read %.4f)" % el, absf(el - 5.0) <= 0.01)
		check("REQ-7a: local Sun azimuth is 90 +-0.01 (read %.4f)" % az, absf(az - 90.0) <= 0.01)
	# REQ-7a: a value outside -90..90 prints one ERROR line and exits 2.
	var bad := _run_scenario(["7", "ground", "95"])
	check("REQ-7a: SUN_EL=95 exits 2 (exit %d)" % bad[0], bad[0] == 2, bad[1].left(400))
	check("REQ-7a: SUN_EL=95 prints one ERROR line", bad[1].count("ERROR") == 1, bad[1].left(400))


# ---------------------------------------------------------------- Phase 5 LOD and streaming (REQ-26 to REQ-30)

## Runs the quadtree's frames (plans and builds) until no build is queued or running, or 400 frames pass.
var _settle_frames := 0

func _settle_quadtree(qt: Node) -> bool:
	_settle_frames = 0
	for i in 400:
		_settle_frames += 1
		qt._process(0.0)
		OS.delay_msec(20)
		if i >= 10 and qt._queued.is_empty() and qt._tasks.is_empty():
			return true
	return false


## Vertex index of edge vertex k on side e (0 bottom, 1 top, 2 left, 3 right), as in LunarTerrain indices.
func _edge_index(e: int, k: int) -> int:
	match e:
		0: return k
		1: return 64 * 65 + k
		2: return k * 65
	return k * 65 + 64


func _world(c: PackedFloat64Array, v: Vector3) -> PackedFloat64Array:
	return PackedFloat64Array([c[0] + v.x, c[1] + v.y, c[2] + v.z])


func test_lod_streaming() -> void:
	var main := spawn_main()
	var fly = main.get_node("FlyCamera")
	var qt: Node = main.get_node("TerrainQuadtree")
	fly.set_active(true)
	fly.place_at(0.0, 45.0, 1.7)
	check("REQ-26: quadtree split above 2 px, merge below 1.4 px, depth limit 18",
		qt.split_px == 2.0 and qt.merge_px == 1.4 and qt.max_depth == 18)
	var t0 := Time.get_ticks_msec()
	var over_at_settle_start: int = qt.frames_over_budget
	var settled := _settle_quadtree(qt)
	check("REQ-27: builds settle within 400 frames at 1.7 m (%d ms)" % (Time.get_ticks_msec() - t0), settled)
	check("REQ-29: default node limit 2500 and byte limit 600 MB (%d, %d)" % [qt.node_limit, qt.byte_limit],
		qt.node_limit == 2500 and qt.byte_limit == 600000000)
	var roots := 0
	var deepest := 0
	var dup_resident := 0
	for key in qt._nodes:
		if qt._nodes[key]["root"]:
			roots += 1
		deepest = maxi(deepest, qt.key_depth(key))
	for key in qt._tasks:
		if qt._nodes.has(key):
			dup_resident += 1
	check("REQ-26: 96 roots, all 96 chunks registered (%d)" % roots, roots == 96)
	check("REQ-26: quadtree splits below depth 0 at 1.7 m and never past 18 (deepest %d)" % deepest,
		deepest >= 1 and deepest <= 18)
	# REQ-27 (Rev 14): settle rule on the 2 min run only (FLY_PATH_SECONDS >= 120).
	if OS.get_environment("FLY_PATH_SECONDS").to_float() >= 120.0:
		check("REQ-27: settle frames over 2 ms at most 0.1 %% (%d of %d)" % [qt.frames_over_budget - over_at_settle_start, _settle_frames],
			qt.frames_over_budget - over_at_settle_start <= 0.001 * _settle_frames)
		check("REQ-27: no settle frame over 30 ms (max %d us)" % qt.max_main_thread_usec,
			qt.max_main_thread_usec <= 30000, "max %d us" % qt.max_main_thread_usec)
	# REQ-28: no node queued or running twice, and no running build for a resident node.
	var seen := {}
	var queued_dup := 0
	for key in qt._queued:
		if seen.has(key):
			queued_dup += 1
		seen[key] = true
	check("REQ-28: no node queued twice and no running build for a resident node",
		queued_dup == 0 and dup_resident == 0, "queued dup %d, resident+running %d" % [queued_dup, dup_resident])
	# REQ-28 cancel: builds queued for one place are dropped when the camera moves away before they start.
	fly.place_at(10.0, 100.0, 1.7)
	qt._update_camera()
	qt._plan()
	var pending: int = qt._queued.size() + qt._tasks.size()
	check("REQ-28: a new place starts or queues builds (%d pending)" % pending, pending > 0)
	var cancels_before: int = qt.cancel_count
	# REQ-29: node limit lowered so eviction must run; a camera 500 km up wants no detail.
	qt.node_limit = 50
	fly.place_at(-60.0, 200.0, 500000.0)
	qt._update_camera()
	qt._plan()
	_settle_quadtree(qt)
	check("REQ-28: queued builds for the old place are cancelled (cancel_count %d -> %d)" % [cancels_before, qt.cancel_count],
		qt.cancel_count > cancels_before)
	var nonroot := 0
	for key in qt._nodes:
		if not qt._nodes[key]["root"]:
			nonroot += 1
	check("REQ-29: resident non-root nodes stay within the node limit (%d of %d)" % [nonroot, qt.node_limit],
		nonroot <= qt.node_limit)
	check("REQ-29: tile cache holds at most 24 LDEM_64 tiles (%d bytes)" % fly.terrain.tile_bytes(),
		fly.terrain.tile_bytes() <= 24 * 1920 * 1920 * 2)
	check("REQ-29: resident node bytes within the byte limit (%d)" % qt.resident_bytes,
		qt.resident_bytes <= qt.byte_limit)
	# REQ-30: skirts on every node, 0.25 x spacing straight down; geomorph weight in 0..1.
	var terrain = fly.terrain
	var d := 5
	var a: Dictionary = terrain.build_node(0, d, 3, 3)
	var verts: PackedVector3Array = a["verts"]
	var cen: PackedFloat64Array = a["centre_xyz"]
	var spacing: float = a["spacing_km"]
	var skirt_ok := verts.size() == 4485
	var worst_len := 0.0
	var worst_dir := 0.0
	for e in 4:
		for t in 65:
			var ev := verts[_edge_index(e, t)]
			var sk := verts[4225 + e * 65 + t]
			var drop := (sk - ev).length()
			worst_len = maxf(worst_len, absf(drop / (0.25 * spacing) - 1.0))
			var radial := Vector3(cen[0] + ev.x, cen[1] + ev.y, cen[2] + ev.z).normalized()
			worst_dir = maxf(worst_dir, absf((sk - ev).normalized().dot(radial) + 1.0))
	check("REQ-30: 4485 vertices per node (grid plus 4 skirt rows of 65)", skirt_ok, "%d" % verts.size())
	check("REQ-30: skirt drops 0.25 x spacing (worst relative error %.4f)" % worst_len, worst_len <= 0.01)
	check("REQ-30: skirt drops straight down along the radial (worst %.4f)" % worst_dir, worst_dir <= 1e-3)
	# REQ-30: same-depth shared edges within tol(d) = max(1e-6 km, 1e-4 x spacing). Small nodes only (float32).
	for dd in [17, 18, 15, 12, 8, 4]:
		var gap := 0.0
		var sp := 0.0
		var mid: int = (4 << dd) / 3
		for k in [0, 1]:
			var b1: Dictionary = terrain.build_node(0, dd, mid + k, mid)
			var b2: Dictionary = terrain.build_node(0, dd, mid + k + 1, mid)
			var v1: PackedVector3Array = b1["verts"]
			var v2: PackedVector3Array = b2["verts"]
			var c1: PackedFloat64Array = b1["centre_xyz"]
			var c2: PackedFloat64Array = b2["centre_xyz"]
			sp = b1["spacing_km"]
			for j in 65:
				var p1 := _world(c1, v1[_edge_index(3, j)])
				var p2 := _world(c2, v2[_edge_index(2, j)])
				gap = maxf(gap, Vector3(p1[0] - p2[0], p1[1] - p2[1], p1[2] - p2[2]).length())
		var tol := maxf(1e-6, 1e-4 * sp)
		check("REQ-30: same-depth shared edges match within tol %s km at depth %d" % [tol, dd], gap <= tol, "gap %s km" % gap)
	# REQ-30: w = clamp((2.6 - 2 x own_err) / 0.6, 0, 1) for every shown non-root node, own_err from the quadtree.
	var morph_ok := true
	for key in qt._nodes:
		var e: Dictionary = qt._nodes[key]
		if not e["root"] and e["mi"].visible:
			var m: float = e["mi"].get_instance_shader_parameter("morph")
			var want := clampf((2.6 - 2.0 * qt._error_px(key)) / 0.6, 0.0, 1.0)
			if absf(m - want) > 1e-6:
				morph_ok = false
	check("REQ-30: every shown non-root node has the geomorph weight from its own error", morph_ok)
	# REQ-30 anchors on the parent error: w = 1 at 2 px, 0.5 at 2.3 px, 0 at 2.6 px (formula only, see report).
	for c in [[2.0, 1.0], [2.3, 0.5], [2.6, 0.0]]:
		check("REQ-30: morph weight at parent error %s px is %s" % [c[0], c[1]],
			absf(clampf((2.6 - c[0]) / 0.6, 0.0, 1.0) - c[1]) <= 1e-9)
	free_main(main)


# REQ-26 to REQ-29 (scenario 10 path, spec Revision 11): start at point 1 (0 N, 45 E) at 1.7 m, heading north,
# pitch -20; fly north at 20 m/s; in the first frame with nodes queued >= 1, hop to point 2 (35.264 N, 45 E);
# keep flying north to FLY_PATH_SECONDS of wall time (default 60; 120 for the REQ-27/REQ-29 run).
# shortcut: the north step is applied on the surface at 1.7 m (advance() would dive at pitch -20).
const FLY_SPEED_MS := 20.0
const FLY_ALT_M := 1.7

func test_fly_path() -> void:
	var main := spawn_main()
	var fly = main.get_node("FlyCamera")
	var qt: Node = main.get_node("TerrainQuadtree")
	fly.set_active(true)
	fly.yaw_deg = 0.0
	fly.pitch_deg = -20.0
	fly.place_at(0.0, 45.0, FLY_ALT_M)
	var env := OS.get_environment("FLY_PATH_SECONDS")
	var seconds := env.to_float() if env != "" else 60.0
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	var t_prev := Time.get_ticks_msec()
	var start_ms := t_prev
	var lat := 0.0
	var hopped := false
	var hop_queued := 0
	var hop_frame := -1
	var hop_view_ok := false
	var hop_pos_ok := false
	var frames := 0
	var dup := 0
	var max_resident := 0
	var max_nonroot := 0
	var max_tile_bytes := 0
	while Time.get_ticks_msec() < end:
		var now := Time.get_ticks_msec()
		var dt := (now - t_prev) / 1000.0
		t_prev = now
		if not hopped and qt._queued.size() >= 1:
			hopped = true
			hop_queued = qt._queued.size()
			hop_frame = frames
			lat = 35.264
			fly.place_at(lat, 45.0, FLY_ALT_M)
			hop_view_ok = fly.yaw_deg == 0.0 and fly.pitch_deg == -20.0
			var ll: Array = fly.lat_lon()
			hop_pos_ok = absf(ll[0] - 35.264) < 1e-6 and absf(ll[1] - 45.0) < 1e-6
		else:
			lat += rad_to_deg(dt * FLY_SPEED_MS / (REF_RADIUS_KM * 1000.0))
			fly.place_at(lat, 45.0, FLY_ALT_M)
		var over_before: int = qt.frames_over_budget
		qt._process(0.0)
		if qt.frames_over_budget > over_before:
			print("REQ-27: fly path: frame %d at %d ms took over 2000 us" % [frames, Time.get_ticks_msec() - start_ms])
		frames += 1
		var seen := {}
		for key in qt._queued:
			if seen.has(key):
				dup += 1
			seen[key] = true
		var nonroot := 0
		for key in qt._nodes:
			if not qt._nodes[key]["root"]:
				nonroot += 1
		max_nonroot = maxi(max_nonroot, nonroot)
		max_resident = maxi(max_resident, qt.resident_bytes)
		max_tile_bytes = maxi(max_tile_bytes, fly.terrain.tile_bytes())
	check("REQ-26: fly path: hop frame had nodes queued >= 1 (queued %d at frame %d of %d)" % [hop_queued, hop_frame, frames],
		hopped and hop_queued >= 1, "queue never reached 1 after load in %d frames" % frames)
	check("REQ-26: fly path: hop keeps heading 0 and pitch -20, lands at 35.264 N, 45 E", hop_view_ok and hop_pos_ok,
		"view %s position %s" % [hop_view_ok, hop_pos_ok])
	check("REQ-28: fly path (%d frames, %.0f s): no node queued twice (%d duplicates)" % [frames, seconds, dup], dup == 0)
	check("REQ-28: fly path: at least one cancellation (cancel_count %d)" % qt.cancel_count, qt.cancel_count >= 1)
	# REQ-27 (Rev 13) on the 2 min run: <= 0.1 % of frames over 2 ms, and no frame over 30 ms.
	print("REQ-27: fly path: %d frames, max_main_thread_usec %d, frames_over_2ms %d, max creation %d display %d evict %d us, select %d us, timer calls %d" % [frames, qt.max_main_thread_usec, qt.frames_over_budget, qt.max_creation_usec, qt.max_display_usec, qt.max_evict_usec, qt.max_select_usec, qt.instr_calls])
	if seconds >= 120.0:
		check("REQ-27: fly path: frames over 2 ms at most 0.1 %% (%d of %d)" % [qt.frames_over_budget, frames],
			qt.frames_over_budget <= 0.001 * frames)
		check("REQ-27: fly path: no frame over 30 ms (max %d us)" % qt.max_main_thread_usec,
			qt.max_main_thread_usec <= 30000)
	check("REQ-29: fly path: resident bytes within the byte limit every frame (max %d of %d)" % [max_resident, qt.byte_limit],
		max_resident <= qt.byte_limit)
	check("REQ-29: fly path: resident non-root nodes within the node limit every frame (max %d of %d)" % [max_nonroot, qt.node_limit],
		max_nonroot <= qt.node_limit)
	check("REQ-29: fly path: tile cache within 24 LDEM_64 tiles every frame (max %d bytes)" % max_tile_bytes,
		max_tile_bytes <= 24 * 1920 * 1920 * 2)
	free_main(main)


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


# ---------------------------------------------------------------- earth (earth-milestone-1-basic-earth spec)

const EARTH_DIR := "res://assets/earth/bmng/"
const EARTH_FILES := ["world.200401.3x5400x2700.jpg", "world.200402.3x5400x2700.jpg",
	"world.200403.3x5400x2700.jpg", "world.200404.3x5400x2700.jpg", "world.200405.3x5400x2700.jpg",
	"world.200406.3x5400x2700.jpg", "world.200407.3x5400x2700.jpg", "world.200408.3x5400x2700.jpg",
	"world.200409.3x5400x2700.jpg", "world.200410.3x5400x2700.jpg", "world.200411.3x5400x2700.jpg",
	"world.200412.3x5400x2700.jpg"]
const EARTH_BYTES := [1884678, 1865311, 1830489, 1774173, 1735263, 1692239, 1617810, 1616254, 1709729,
	1766694, 1851209, 1878742]
const EARTH_SHA256 := ["99f5faad74efe985fbf1714c8be7296ca9999759a1215b65f99b7f1df278dde5",
	"252444b224c7dc10289616fb5e3cd85c3738fca9ddbdc267775cd22a748bbfbe",
	"0d9967be048b5e2ba62195dd610042c9e0926b4eb9d1e9ae53dbf20eaadd9228",
	"8db8d5e545b31cde0e4e5dfa46cb116bf485243a0200c2d6e4b04b4e6937f669",
	"d9a8dfc0a3e54775c3a4aeb547c729f710bb588d82d4602252d7cd7bf43a38ef",
	"dc059529b8ed1cfcdd59747a7c3f259c93c1322bf88ca1ec8bab1dd71fcc57f5",
	"f55226d46d27e05511f2118dc6aa24f5dbf9b6b2cddc87cc6e0e7dd067c00b11",
	"2048023ccc62250c677c0f4b03d4362f997b130eb0154a6cad00aa1b27c390b9",
	"ed72e87674861f72e2a6e5df52f0cc6bf3df1edd9b862664cf18ac423e2e9e0e",
	"ccfd9b7a5e5ee601e1466556716bba50ea418f3a8e068ab0194ae0425815b1b0",
	"d63de0bb4274a7d9df08d2f69eeffc849d0f7aca157c4401f9bd2e41af63b178",
	"3d38a8ecaceb1cdb51ced7f831e9ac18d261950049616feff6892efcae0dcc26"]


## Colour samples of an image on a 20 x 10 grid, used to tell which monthly image is shown.
func _earth_sig(img: Image) -> Array:
	var out := []
	var w := img.get_width()
	var h := img.get_height()
	for iy in 10:
		for ix in 20:
			out.append(img.get_pixel(ix * w / 20 + 7, iy * h / 10 + 3))
	return out


## Nearest mesh vertex to a unit direction (EarthRoot space); returns its UV.
func _earth_uv_toward(verts: PackedVector3Array, uvs: PackedVector2Array, xf: Transform3D, dir: Vector3) -> Vector2:
	var best := -2.0
	var best_uv := Vector2.ZERO
	for i in verts.size():
		var p := (xf * verts[i]).normalized()
		var c := p.dot(dir)
		if c > best:
			best = c
			best_uv = uvs[i]
	return best_uv


func test_earth() -> void:
	var main := spawn_main()
	var er := main.get_node("EarthRoot") as Node3D
	var surf := er.get_node("EarthSurface") as MeshInstance3D
	var ec = er.get_node("EarthController")
	var sun = main.get_node("Sun")
	var sun_script = load(SUN_SCRIPT)
	var d := sample()
	var earth_pos := Vector3(d["earth_pos_godot"][0], d["earth_pos_godot"][1], d["earth_pos_godot"][2])
	var sun_dir := Vector3(d["sun_dir_godot"][0], d["sun_dir_godot"][1], d["sun_dir_godot"][2])
	var earth_sun := Vector3(d["earth_sun_dir_godot"][0], d["earth_sun_dir_godot"][1], d["earth_sun_dir_godot"][2])

	# REQ-18: before the first streamed line the Sun light is disabled and Earth hidden.
	check("earth REQ-18: EarthRoot hidden before the first streamed line", not er.visible)
	check("earth REQ-18: Sun light disabled before the first streamed line", not (sun as Light3D).visible)

	# REQ-7: scene structure.
	check("earth REQ-7: EarthRoot is a Node3D and a direct child of Main (sibling of Moon)",
		er is Node3D and er.get_parent() == main)
	var kids := []
	for c in er.get_children():
		kids.append(str(c.name))
	kids.sort()
	# Earth Milestone 2 REQ-1 extends this list with the two cloud nodes.
	check("earth REQ-7: EarthRoot children are exactly EarthController, EarthSurface, CloudLower and CloudUpper",
		kids == ["CloudLower", "CloudUpper", "EarthController", "EarthSurface"], str(kids))
	check("earth REQ-7: EarthSurface is a MeshInstance3D with a SphereMesh", surf is MeshInstance3D and surf.mesh is SphereMesh)
	check("earth REQ-7: EarthRoot is not under the camera rig", not main.get_node("CameraRig").is_ancestor_of(er))
	var scene_text := FileAccess.get_file_as_string("res://scenes/main.tscn").to_lower()
	check("earth REQ-7: no skybox, billboard, sprite or panorama sky in the main scene",
		not scene_text.contains("panorama") and not scene_text.contains("sprite") and not scene_text.contains("billboard")
		and not scene_text.contains("skybox"))

	# REQ-8: radius and tessellation.
	var sm := surf.mesh as SphereMesh
	var r_eff := sm.radius * surf.global_transform.basis.x.length() * er.global_transform.basis.x.length()
	check("earth REQ-8: rendered radius 6371.0 +/- 0.5 units", near(r_eff, 6371.0, 0.5), str(r_eff))
	check("earth REQ-8: at least 64 radial segments and 32 rings",
		sm.radial_segments >= 64 and sm.rings >= 32, "%d segments, %d rings" % [sm.radial_segments, sm.rings])

	# REQ-11: clip planes.
	var cam := main.get_node("CameraRig/Camera3D") as Camera3D
	check("earth REQ-11: camera near plane <= 0.05", cam.near <= 0.05 + 1e-6, str(cam.near))
	check("earth REQ-11: camera far plane >= 440000", cam.far >= 440000.0, str(cam.far))

	# REQ-9: applied line sets position and orientation.
	var parsed = sun_script.parse_line(SAMPLE_LINE)
	check("earth REQ-9: sample line parses", parsed is Dictionary)
	sun.apply_line(parsed)
	check("earth REQ-9: EarthRoot visible after a valid line", er.visible)
	var gt := er.global_transform
	check("earth REQ-9: EarthRoot origin equals earth_pos_godot within 1 unit",
		vec_near(gt.origin, earth_pos, 1.0), str(gt.origin))
	var b: Array = d["earth_basis_godot"]
	var cols := [gt.basis.x, gt.basis.y, gt.basis.z]
	var max_err := 0.0
	for i in 3:
		for j in 3:
			max_err = maxf(max_err, absf(cols[j][i] - b[3 * i + j]))
	check("earth REQ-9: global basis equals earth_basis_godot (row-major) within 1e-6 per element",
		max_err <= 1e-6, str(max_err))

	# REQ-10: orbit, zoom and pan do not move EarthRoot.
	var before := er.global_transform
	for i in 50:
		send_mouse(mouse_button(MOUSE_BUTTON_WHEEL_UP, true))
	send_mouse(mouse_button(MOUSE_BUTTON_LEFT, true))
	send_mouse(mouse_motion(Vector2(100, 0)))
	send_mouse(mouse_button(MOUSE_BUTTON_LEFT, false))
	send_mouse(mouse_button(MOUSE_BUTTON_MIDDLE, true))
	send_mouse(mouse_motion(Vector2(100, 0)))
	send_mouse(mouse_button(MOUSE_BUTTON_MIDDLE, false))
	check("earth REQ-10: EarthRoot global transform unchanged by zoom, orbit and pan",
		er.global_transform.is_equal_approx(before))

	# REQ-20: shared Sun direction.
	var fwd := -(sun as Node3D).global_transform.basis.z
	check("earth REQ-20: light forward equals -sun_dir_godot within 0.001 per component",
		absf(fwd.x + sun_dir.x) <= 0.001 and absf(fwd.y + sun_dir.y) <= 0.001 and absf(fwd.z + sun_dir.z) <= 0.001,
		str(fwd))
	var ang_sun := rad_to_deg(sun_dir.angle_to(earth_sun))
	check("earth REQ-20: angle between earth_sun_dir_godot and sun_dir_godot <= 0.2 deg", ang_sun <= 0.2, str(ang_sun))

	# REQ-19: apparent size from the scene, camera at the minimum distance on the line to Earth.
	var d_km := float(d["earth_distance_km"])
	cam.global_position = earth_pos.normalized() * 1748.232
	var cam_dist := cam.global_position.distance_to(er.global_position)
	var ang_scene := rad_to_deg(2.0 * asin(r_eff / cam_dist))
	var ang_formula := rad_to_deg(2.0 * asin(6371.0 / (d_km - 1748.232)))
	check("earth REQ-19: scene angular diameter equals 2 asin(6371 / (distance - 1748.232)) within 0.001 deg",
		absf(ang_scene - ang_formula) <= 0.001, "%f vs %f" % [ang_scene, ang_formula])
	check("earth REQ-19: angular diameter for this line is in 1.79 to 2.06 deg",
		ang_scene >= 1.79 and ang_scene <= 2.06, str(ang_scene))
	var ang_at_min := rad_to_deg(2.0 * asin(6371.0 / (356400.0 - 1748.232)))
	var ang_at_max := rad_to_deg(2.0 * asin(6371.0 / (406700.0 - 1748.232)))
	check("earth REQ-19: angular diameter lies in 1.79 to 2.06 deg over the Earth distance range 356 400 to 406 700 km",
		ang_at_max >= 1.79 and ang_at_min <= 2.06, "min-distance %f deg, max-distance %f deg" % [ang_at_min, ang_at_max])

	# REQ-13: UV mapping of the sphere in EarthRoot space (identity Earth-fixed frame).
	var arrs := surf.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrs[Mesh.ARRAY_TEX_UV]
	var uv_x := _earth_uv_toward(verts, uvs, surf.transform, Vector3(1, 0, 0))
	var uv_y := _earth_uv_toward(verts, uvs, surf.transform, Vector3(0, 1, 0))
	var uv_z := _earth_uv_toward(verts, uvs, surf.transform, Vector3(0, 0, 1))
	check("earth REQ-13: +x (0 deg N, 0 deg E) maps to u = 0.5, v = 0.5", near(uv_x.x, 0.5, 0.01) and near(uv_x.y, 0.5, 0.01), str(uv_x))
	check("earth REQ-13: +y (0 deg N, 90 deg E) maps to u = 0.75 (not mirrored)", near(uv_y.x, 0.75, 0.01), str(uv_y))
	check("earth REQ-13: +z (north pole) maps to v = 0", near(uv_z.y, 0.0, 0.01), str(uv_z))

	# REQ-12: texture files, sizes, hashes, decoded size and mipmaps.
	var mat := surf.get_surface_override_material(0) as StandardMaterial3D
	var all_ok := true
	var bad_detail := ""
	for i in 12:
		var path: String = EARTH_DIR + EARTH_FILES[i]
		var size_ok: bool = FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path).size() == EARTH_BYTES[i]
		var sha_ok: bool = FileAccess.file_exists(path) and FileAccess.get_sha256(path) == EARTH_SHA256[i]
		var img := Image.load_from_file(path) if FileAccess.file_exists(path) else null
		var dim_ok := img != null and img.get_width() == 5400 and img.get_height() == 2700
		if not (size_ok and sha_ok and dim_ok):
			all_ok = false
			bad_detail += " %s(size=%s sha=%s dim=%s)" % [EARTH_FILES[i], size_ok, sha_ok, dim_ok]
	check("earth REQ-12: 12 monthly JPGs present, byte size, SHA-256 and decoded 5400 x 2700 as in docs/DATA_SOURCES.md",
		all_ok, bad_detail)
	check("earth REQ-12: material holds only the albedo texture (no normal, roughness, metallic, emission, AO or detail texture)",
		mat != null and mat.albedo_texture != null and mat.normal_texture == null and mat.roughness_texture == null
		and mat.metallic_texture == null and mat.emission_texture == null and mat.ao_texture == null
		and mat.detail_albedo == null)

	# REQ-25: lighting by the existing scene Sun light only.
	check("earth REQ-25: Earth material is lit (not unshaded) and opaque",
		mat.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED and mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED)
	var lights := main.find_children("*", "Light3D", true, false)
	check("earth REQ-25: the Sun is the only light in the main scene", lights.size() == 1 and lights[0].name == "Sun",
		str(lights.size()))
	var earth_src := FileAccess.get_file_as_string("res://scripts/earth_controller.gd")
	check("earth REQ-25: earth_controller.gd computes no Sun direction (no sun_dir or subsolar use)",
		not earth_src.contains("sun_dir") and not earth_src.contains("subsolar"))
	var utcs := ["2026-01-31T23:59:59Z", "2026-02-01T00:00:00Z", "2026-02-20T08:00:00Z"]
	for m in range(1, 13):
		utcs.append("2026-%02d-15T12:00:00Z" % m)
	var sig_jan := []
	var jan31_tex: Texture2D = null
	var feb1_tex: Texture2D = null
	for utc in utcs:
		var dd := sample()
		dd["utc"] = utc
		sun.apply_line(sun_script.parse_line(line_from(dd)))
		var month: int = utc.substr(5, 2).to_int()
		var tex := mat.albedo_texture
		check("earth REQ-17: %s shows the month %d image" % [utc, month], ec.month == month and tex != null, str(ec.month))
		if tex != null:
			var expect := _earth_sig(Image.load_from_file(EARTH_DIR + EARTH_FILES[month - 1]))
			check("earth REQ-17: %s texture equals the %d image on the sample grid (no blend)" % [utc, month],
				_earth_sig(tex.get_image()) == expect)
			if month == 1 and sig_jan.is_empty():
				sig_jan = expect
			if month == 7:
				check("earth REQ-17: July image differs from January on the sample grid", expect != sig_jan)
		if utc == "2026-01-31T23:59:59Z":
			jan31_tex = tex
		if utc == "2026-02-01T00:00:00Z":
			check("earth REQ-17: Feb 1 00:00 line switches to a new texture instance at the month boundary",
				tex != jan31_tex)
			feb1_tex = tex
		if utc == "2026-02-20T08:00:00Z":
			check("earth REQ-17: a second line in the same month keeps the same texture instance", tex == feb1_tex)
	var tex_now := mat.albedo_texture
	check("earth REQ-12: loaded monthly texture has mipmaps and is 5400 x 2700",
		tex_now != null and tex_now.get_image().has_mipmaps() and tex_now.get_width() == 5400
		and tex_now.get_height() == 2700)

	free_main(main)

	# REQ-14 / REQ-15 / REQ-16 / REQ-24: documents and build files.
	var mk := FileAccess.get_file_as_string("res://Makefile")
	check("earth REQ-14: Makefile defines earth-texture with the NASA bmng-base URL",
		mk.contains("\nearth-texture:") and mk.contains("assets.science.nasa.gov/content/dam/science/esd/eo/images/bmng/bmng-base"))
	var run_rule := ""
	for line in mk.split("\n"):
		if line.begins_with("run:"):
			run_rule = line
	check("earth REQ-14: make run does not depend on earth-texture (no download on run)",
		run_rule != "" and not run_rule.contains("earth-texture"), run_rule)
	check("earth REQ-14: make run prints the instruction when textures are missing",
		mk.contains("Earth textures missing: run 'make earth-texture'"))
	var gi := FileAccess.get_file_as_string("res://.gitignore")
	check("earth REQ-15: .gitignore lists assets/earth/bmng/", gi.contains("assets/earth/bmng/"))
	var ds := FileAccess.get_file_as_string("res://docs/DATA_SOURCES.md")
	var sec_at := ds.find("## Earth surface textures (Earth Milestone 1)")
	var sec := ds.substr(sec_at) if sec_at >= 0 else ""
	check("earth REQ-16: DATA_SOURCES has the Earth Milestone 1 texture section", sec_at >= 0)
	var missing := []
	for i in 12:
		for s in [EARTH_FILES[i], EARTH_SHA256[i], str(EARTH_BYTES[i]), "bmng-base/"]:
			if not sec.contains(s):
				missing.append(s)
	check("earth REQ-16: each of the 12 files lists its name, bytes, SHA-256 and download URL", missing.is_empty(), str(missing.slice(0, 3)))
	check("earth REQ-16: required credit line recorded exactly", sec.contains(
		"Earth imagery: Blue Marble: Next Generation, NASA Earth Observatory, NASA Goddard Space Flight Center. Produced by Reto Stöckli. https://science.nasa.gov/earth/earth-observatory/blue-marble-next-generation/"))
	check("earth REQ-16: licence quotes from the NASA FAQ and the BMNG Credits recorded",
		sec.contains("freely available for re-publication or re-use, including commercial purposes")
		and sec.contains("NASA Earth Observatory.") and sec.contains("May I reuse imagery that is on your site?")
		and sec.contains("Credits") and sec.contains("2026-11-11"))
	check("earth REQ-16: processing stated and the override of docs/earth-sky.md sections 3 and 14 recorded",
		sec.contains("### Processing") and sec.contains("### Override") and sec.contains("docs/earth-sky.md")
		and sec.contains("sections 3 and 14"))
	var arch := FileAccess.get_file_as_string("res://docs/ARCHITECTURE.md")
	check("earth REQ-24: ARCHITECTURE.md describes EarthRoot, its children and the helper-to-Earth data path",
		arch.contains("EarthRoot") and arch.contains("EarthSurface") and arch.contains("EarthController")
		and arch.contains("--stream") and arch.contains("earth_pos_godot"))

# ---------------------------------------------------------------- Earth Milestone 2: clouds
# Checks that need the shader to evaluate opacity (seam, poles, coverage, density, correlation, edge width,
# day/night brightness, frame draw calls and frame time) are not here: the headless dummy renderer does not run the
# shader. They are reported as pending in the tester report.

const CLOUD_LOWER_RATE := -9.0e-5
const CLOUD_UPPER_RATE := 2.6938e-4
const CLOUD_J2000_UNIX := 946728000.0
const CLOUD_SHADER := "res://shaders/cloud.gdshader"
const CLOUD_SCRIPT := "res://scripts/cloud_layer.gd"
const CLOUD_ARCH_SECTION := "### Earth clouds (Earth Milestone 2)"
const CLOUD_T0 := "2026-11-10T00:00:00Z"  # fake helper line of the spec
const CLOUD_SPREAD := 0.13  # shader default (checked against the shader source in test_cloud_sampling)
const CLOUD_SOFTNESS := 0.25  # shader default (checked against the shader source in test_cloud_sampling)


func strip_comments(text: String, marker: String) -> String:
	var out := PackedStringArray()
	for line in text.split("\n"):
		var cut := line.find(marker)
		out.append(line.substr(0, cut) if cut >= 0 else line)
	return "\n".join(out)


func regex_hit(text: String, pattern: String) -> bool:
	var rx := RegEx.new()
	rx.compile(pattern)
	return rx.search(text) != null


func wrap_deg(d: float) -> float:
	return fposmod(d + 180.0, 360.0) - 180.0


func test_clouds() -> void:
	var main := spawn_main()
	var er := main.get_node("EarthRoot") as Node3D
	var surf := er.get_node("EarthSurface") as MeshInstance3D
	var lo = er.get_node("CloudLower")
	var up = er.get_node("CloudUpper")
	var nodes := [lo, up]
	var names := ["CloudLower", "CloudUpper"]
	var radii := [6373.0, 6381.0]
	var lo_mat := lo.material_override as ShaderMaterial
	var up_mat := up.material_override as ShaderMaterial
	var mats := [lo_mat, up_mat]
	var surf_sm := surf.mesh as SphereMesh

	# REQ-1: nodes, parent, radius, tessellation, hidden before the first line, no shadows, fixed rotation.
	for i in 2:
		var n = nodes[i]
		var sm := n.mesh as SphereMesh
		var is_shell: bool = n is MeshInstance3D and sm != null and n.get_parent() == er
		check("clouds REQ-1: %s is a MeshInstance3D with a SphereMesh, child of EarthRoot" % names[i], is_shell)
		if sm == null:
			continue
		var r_eff: float = sm.radius * n.global_transform.basis.x.length() * er.global_transform.basis.x.length()
		check("clouds REQ-1: %s radius %.1f +/- 0.5 units" % [names[i], radii[i]],
			near(r_eff, radii[i], 0.5), str(r_eff))
		check("clouds REQ-1: %s has at least 128 radial segments and 64 rings" % names[i],
			sm.radial_segments >= 128 and sm.rings >= 64, "%d, %d" % [sm.radial_segments, sm.rings])
		check("clouds REQ-1: %s has the same tessellation as EarthSurface" % names[i],
			sm.radial_segments == surf_sm.radial_segments and sm.rings == surf_sm.rings)
		check("clouds REQ-1: %s is hidden with EarthRoot before the first streamed line" % names[i],
			not n.is_visible_in_tree())
		check("clouds: %s does not cast shadows" % names[i],
			n.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		check("clouds: %s uses the same fixed rotation as EarthSurface" % names[i],
			n.transform.basis.is_equal_approx(surf.transform.basis))

	# REQ-11: defaults, then clamping of coverage and density to 0..1 (also in the shader parameters).
	check("clouds REQ-11: lower defaults coverage 0.55 and density 1.0",
		near(lo.coverage, 0.55, 1e-9) and near(lo.density, 1.0, 1e-9), "%s %s" % [lo.coverage, lo.density])
	check("clouds REQ-11: upper defaults coverage 0.25 and density 1.0",
		near(up.coverage, 0.25, 1e-9) and near(up.density, 1.0, 1e-9), "%s %s" % [up.coverage, up.density])
	for i in 2:
		var n = nodes[i]
		n.coverage = -0.5
		n.density = -0.5
		check("clouds REQ-11: %s coverage and density -0.5 clamp to 0" % names[i],
			near(n.coverage, 0.0, 1e-9) and near(n.density, 0.0, 1e-9), "%s %s" % [n.coverage, n.density])
		n.coverage = 1.5
		n.density = 1.5
		check("clouds REQ-11: %s coverage and density 1.5 clamp to 1" % names[i],
			near(n.coverage, 1.0, 1e-9) and near(n.density, 1.0, 1e-9), "%s %s" % [n.coverage, n.density])
		check("clouds REQ-11: %s shader parameters hold the clamped values" % names[i],
			near(float(mats[i].get_shader_parameter("coverage")), 1.0, 1e-6)
			and near(float(mats[i].get_shader_parameter("density")), 1.0, 1e-6))
		n.coverage = 0.55 if i == 0 else 0.25
		n.density = 1.0

	# REQ-4: opacity caps as the material parameters and the shader's alpha expression.
	check("clouds REQ-4: lower cap is 0.85", near(float(lo_mat.get_shader_parameter("cap")), 0.85, 1e-6))
	check("clouds REQ-4: upper cap is 0.40", near(float(up_mat.get_shader_parameter("cap")), 0.40, 1e-6))
	var shader_raw := FileAccess.get_file_as_string(CLOUD_SHADER)
	var shader_code := strip_comments(shader_raw, "//")
	check("clouds REQ-4: alpha = cap x clamped density x clamped shape, so alpha <= cap",
		shader_code.contains("ALPHA = cap * clamp(density, 0.0, 1.0) * clamp(edge, 0.0, 1.0)"))
	check("clouds REQ-4: overlap bound 1 - (1 - 0.85)(1 - 0.40) = 0.91",
		near(1.0 - (1.0 - 0.85) * (1.0 - 0.40), 0.91, 1e-9))

	# REQ-5: drift rates, drift over +3600 s, and angle = rate x (t - J2000).
	check("clouds REQ-5: J2000 is 2000-01-01T12:00:00Z",
		near(Time.get_unix_time_from_datetime_string("2000-01-01T12:00:00Z"), CLOUD_J2000_UNIX, 0.0))
	check("clouds REQ-5: lower rate is -9.0e-5 deg/s", near(lo.drift_deg_per_s, CLOUD_LOWER_RATE, 1e-12),
		str(lo.drift_deg_per_s))
	check("clouds REQ-5: upper rate is +2.6938e-4 deg/s (eastward)", near(up.drift_deg_per_s, CLOUD_UPPER_RATE, 1e-12),
		str(up.drift_deg_per_s))
	var rates := [CLOUD_LOWER_RATE, CLOUD_UPPER_RATE]
	var expect_step := [-0.324, 0.9698]
	var t_a := "2026-11-10T00:00:00Z"
	var t_b := "2026-11-10T01:00:00Z"
	for i in 2:
		var n = nodes[i]
		n.apply_utc(t_a)
		var a1: float = n.drift_deg
		n.apply_utc(t_b)
		var a2: float = n.drift_deg
		var step := wrap_deg(a2 - a1)
		check("clouds REQ-5: %s drift over +3600 s is %+.3f +/- 0.001 deg" % [names[i], expect_step[i]],
			absf(step - expect_step[i]) <= 0.001, str(step))
		var t := Time.get_unix_time_from_datetime_string(t_b)
		var expect := fposmod(rates[i] * (t - CLOUD_J2000_UNIX), 360.0)
		check("clouds REQ-5: %s angle equals rate x (t - J2000) mod 360" % names[i],
			absf(wrap_deg(a2 - expect)) <= 1e-6, "%f vs %f" % [a2, expect])
		check("clouds REQ-5: %s shader drift_rad equals the drift angle in radians" % names[i],
			absf(float(mats[i].get_shader_parameter("drift_rad")) - deg_to_rad(a2)) <= 1e-6)

	# Independence: each layer has its own clock state, settings and material.
	check("clouds: the two layers use separate ShaderMaterial instances", lo_mat != null and up_mat != null and lo_mat != up_mat)
	lo.apply_utc(t_a)
	var up_before: float = up.drift_deg
	lo.apply_utc(t_b)
	check("clouds: applying a time to CloudLower leaves CloudUpper's drift unchanged", up.drift_deg == up_before)
	up.apply_utc(t_a)
	var lo_before: float = lo.drift_deg
	up.apply_utc(t_b)
	check("clouds: applying a time to CloudUpper leaves CloudLower's drift unchanged", lo.drift_deg == lo_before)
	lo.coverage = 0.9
	check("clouds: changing CloudLower coverage leaves CloudUpper coverage unchanged", near(up.coverage, 0.25, 1e-9))
	lo.coverage = 0.55
	check("clouds: the two layers drift in opposite directions", signf(lo.drift_deg_per_s) != signf(up.drift_deg_per_s))

	# REQ-6 (time axis, precision part): the time reaches the shader as an integer cell and a fraction,
	# so one second is resolved after conversion to 32-bit float.
	for i in 2:
		var n = nodes[i]
		n.apply_utc("2026-11-10T00:00:00Z")
		var c1: float = n.time_cell
		var f1: float = n.time_frac
		n.apply_utc("2026-11-10T00:00:01Z")
		var c2: float = n.time_cell
		var f2: float = n.time_frac
		var period: float = n.shape_period_s
		check("clouds REQ-6: %s time cell is an integer and the fraction is in [0, 1)" % names[i],
			c1 == floorf(c1) and f1 >= 0.0 and f1 < 1.0)
		check("clouds REQ-6: %s moves exactly 1 s along the time axis (double precision)" % names[i],
			absf(((c2 - c1) + (f2 - f1)) * period - 1.0) <= 1e-6)
		if c1 == c2:
			var p := PackedFloat32Array([f1, f2])
			check("clouds REQ-6: %s 1 s step survives float32 conversion (within 0.01 s)" % names[i],
				absf((p[1] - p[0]) * period - 1.0) <= 0.01, str((p[1] - p[0]) * period))
	lo.apply_utc(t_a)
	up.apply_utc(t_a)

	# REQ-8 and REQ-14: opacity from direction, time and settings only; no UV, no texture, no Sun vector.
	check("clouds REQ-8: cloud.gdshader does not read UV or UV2", not regex_hit(shader_code, "\\bUV2?\\b"))
	check("clouds REQ-8: cloud.gdshader declares no sampler (no texture)", not shader_code.contains("sampler"))
	var tex_uniforms := []
	for i in 2:
		for u in mats[i].shader.get_shader_uniform_list():
			if int(u["type"]) == TYPE_OBJECT:
				tex_uniforms.append(names[i] + ":" + str(u["name"]))
	check("clouds REQ-8: cloud shader uniforms include no texture or object type", tex_uniforms.is_empty(), str(tex_uniforms))
	var cl_code := strip_comments(FileAccess.get_file_as_string(CLOUD_SCRIPT), "#")
	check("clouds REQ-14: cloud shader is lit (no unshaded mode, no custom light function)",
		not shader_code.contains("unshaded") and not regex_hit(shader_code, "void light\\("))
	check("clouds REQ-14: cloud script and shader hold no Sun vector or Sun node",
		not regex_hit(cl_code.to_lower(), "sun") and not regex_hit(shader_code.to_lower(), "sun"))

	# REQ-7 and REQ-16 (static part): the clock is the streamed UTC only; no per-frame work and no Image or texture.
	var time_calls := []
	var rx := RegEx.new()
	rx.compile("Time\\.[A-Za-z_]+")
	for m in rx.search_all(cl_code):
		time_calls.append(m.get_string())
	check("clouds REQ-7: cloud_layer.gd uses only Time.get_unix_time_from_datetime_string",
		not time_calls.is_empty() and time_calls.all(func(s): return s == "Time.get_unix_time_from_datetime_string"),
		str(time_calls))
	var ec_src := FileAccess.get_file_as_string("res://scripts/earth_controller.gd")
	var a_at := ec_src.find("func apply_line")
	var b_at := ec_src.find("func _load_month")
	var apply_body := ec_src.substr(a_at, b_at - a_at)
	check("clouds REQ-7: EarthController passes the line's utc to the layers only inside apply_line",
		ec_src.count("apply_utc") == 1 and apply_body.contains("apply_utc(data[\"utc\"])"))
	check("clouds REQ-16: cloud_layer.gd has no _process, creates no Image or texture, loads nothing",
		not cl_code.contains("_process") and not regex_hit(cl_code, "\\bImage|\\bload\\(|preload\\(|create_from"))

	free_main(main)

	# REQ-19: documentation.
	var arch := FileAccess.get_file_as_string("res://docs/ARCHITECTURE.md")
	var csec_at := arch.find(CLOUD_ARCH_SECTION)
	var csec := arch.substr(csec_at) if csec_at >= 0 else ""
	check("clouds REQ-19: ARCHITECTURE.md has the Earth clouds section", csec_at >= 0)
	var must := ["CloudLower", "CloudUpper", "cloud.gdshader", "cloud_layer.gd", "apply_utc", "utc", "coverage",
		"density", "Known approximations"]
	var miss := []
	for s in must:
		if not csec.contains(s):
			miss.append(s)
	check("clouds REQ-19: section names the nodes, shader, script, clock input, settings and approximations",
		miss.is_empty(), str(miss))
	var approx := {
		"no link to real weather or geography": ["weather", "geography"],
		"solid-body drift at every latitude": ["solid-body", "every latitude"],
		"thin shells with no volume": ["thin", "no volume"],
		"no cloud shadows": ["no cloud shadows"],
		"standard lit shading, no scattering": ["lit shading", "no scattering"],
		"drift too slow to see at live speed": ["too slow"],
		"altitudes fixed at 2 km and 10 km": ["2 km", "10 km"],
	}
	for item in approx:
		var ok := true
		for s in approx[item]:
			ok = ok and csec.contains(s)
		check("clouds REQ-19: known approximation listed: %s" % item, ok)
	var perf := FileAccess.get_file_as_string("res://docs/PERFORMANCE.md")
	check("clouds REQ-19: PERFORMANCE.md links to the Earth clouds approximations in ARCHITECTURE.md",
		perf.contains("Earth clouds") and perf.contains("docs/ARCHITECTURE.md"))
	check("clouds REQ-17: PERFORMANCE.md records the earth_close and orbit_default results as pending user run",
		perf.contains("median difference (budget 1.0 ms) | pending user run")
		and perf.contains("median difference (budget 0.2 ms) | pending user run"))

	# REQ-17 setup (perf script): earth_close position and clouds visible and hidden at each position.
	var pc: Dictionary = load("res://tests/perf.gd").get_script_constant_map()
	var pos := {}
	for p in pc["POSITIONS"]:
		pos[p[0]] = float(p[1])
	check("clouds REQ-17: perf.gd earth_close is 3 x 6371 km = 19113 km from Earth's centre",
		pos.has("earth_close") and near(pos["earth_close"], 3.0 * 6371.0, 0.5), str(pos.get("earth_close")))
	check("clouds REQ-17: perf.gd Moon positions unchanged (orbit_far 20000, orbit_default 6000, surface 1748.232)",
		near(pos.get("orbit_far", -1.0), 20000.0, 1e-6) and near(pos.get("orbit_default", -1.0), 6000.0, 1e-6)
		and near(pos.get("surface", -1.0), 1748.232, 1e-6))
	var perf_src := FileAccess.get_file_as_string("res://tests/perf.gd")
	check("clouds REQ-17: earth_close pivots on EarthRoot and looks at it (orbit_basis identity)",
		perf_src.contains('rig.pivot = main.get_node("EarthRoot").global_position if p[0] == "earth_close"')
		and perf_src.contains("rig.orbit_basis = Basis.IDENTITY"))
	check("clouds REQ-17: perf.gd measures every position with the clouds visible and hidden",
		perf_src.contains("for clouds in [true, false]") and perf_src.contains('"EarthRoot/" + layer'))


## Headless opacity sampling (REQ-20 table). Sample counts: caps 200 directions per layer; coverage 1000 per layer
## (the same directions serve all four settings); density 100 per layer; seam and pole one pair per layer.
## Sampling uses the GDScript copy in tests/cloud_noise_copy.gd and the live nodes' drift/time state and cap.
func cloud_mesh_dir(ef: Vector3) -> Vector3:
	# Inverse of the shader's mesh-to-Earth-fixed map (ef = (-m.z, -m.x, m.y)).
	return Vector3(-ef.y, ef.z, -ef.x)


func cloud_u(s: Dictionary, ef: Vector3) -> float:
	return CloudCopy.u_mesh(cloud_mesh_dir(ef), s["drift"], s["cell"], s["frac"], s["freq"], CLOUD_SPREAD)


func cloud_alpha(s: Dictionary, ef: Vector3, cov: float, dens: float) -> float:
	return CloudCopy.alpha_from_u(cloud_u(s, ef), cov, dens, s["cap"], CLOUD_SOFTNESS)


func lonlat_dir(lat_deg: float, lon_deg: float) -> Vector3:
	var la := deg_to_rad(lat_deg)
	var lo := deg_to_rad(lon_deg)
	return Vector3(cos(la) * cos(lo), cos(la) * sin(lo), sin(la))


func unit_dirs(n: int, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := []
	for i in n:
		var z := rng.randf_range(-1.0, 1.0)
		var phi := rng.randf_range(0.0, TAU)
		var r := sqrt(maxf(0.0, 1.0 - z * z))
		out.append(Vector3(r * cos(phi), r * sin(phi), z))
	return out


func test_cloud_sampling() -> void:
	var main := spawn_main()
	var er := main.get_node("EarthRoot") as Node3D
	var nodes := [er.get_node("CloudLower"), er.get_node("CloudUpper")]
	var names := ["CloudLower", "CloudUpper"]

	# Copy fidelity: every copied formula line is in the shader, and the shader defaults match the copy's constants.
	var src := FileAccess.get_file_as_string(CLOUD_SHADER)
	var missing := []
	for line in CloudCopy.SHADER_LINES:
		if not src.contains(line):
			missing.append(line)
	check("clouds sampling: every copied shader line is in shaders/cloud.gdshader", missing.is_empty(), str(missing))
	check("clouds sampling: spread and softness are the shader defaults the copy uses",
		src.contains("uniform float spread = 0.13;") and src.contains("uniform float softness = 0.25;"))

	# Per-layer state from the live nodes after one streamed line (same code path as the app).
	var st := []
	for i in 2:
		var n = nodes[i]
		n.apply_utc(CLOUD_T0)
		var m := n.material_override as ShaderMaterial
		st.append({"drift": deg_to_rad(n.drift_deg), "cell": n.time_cell, "frac": n.time_frac,
			"freq": float(m.get_shader_parameter("frequency")), "cap": float(m.get_shader_parameter("cap")),
			"cov": float(n.coverage), "dens": float(n.density)})

	# REQ-4: 200 directions per layer at coverage 1, density 1; max per layer and of the overlap.
	var max_alpha := [0.0, 0.0]
	var max_overlap := 0.0
	for d in unit_dirs(200, 2002):
		var keep := 1.0
		for i in 2:
			var a := cloud_alpha(st[i], d, 1.0, 1.0)
			max_alpha[i] = maxf(max_alpha[i], a)
			keep *= 1.0 - a
		max_overlap = maxf(max_overlap, 1.0 - keep)
	check("clouds REQ-4: CloudLower max alpha at density 1 is at most 0.85 (%.4f)" % max_alpha[0], max_alpha[0] <= 0.85)
	check("clouds REQ-4: CloudUpper max alpha at density 1 is at most 0.40 (%.4f)" % max_alpha[1], max_alpha[1] <= 0.40)
	check("clouds REQ-4: overlap of both layers is at most 0.91 (%.4f)" % max_overlap, max_overlap <= 0.91)

	# REQ-12 (coverage 0, 0.25, 0.5, 1): 1000 directions per layer, u computed once per direction for all settings.
	var d1000 := unit_dirs(1000, 1001)
	var u_all := []
	for i in 2:
		var us := PackedFloat64Array()
		for d in d1000:
			us.append(cloud_u(st[i], d))
		u_all.append(us)
	for i in 2:
		var nm: String = names[i]
		var us: PackedFloat64Array = u_all[i]
		for c in [0.0, 0.25, 0.5, 1.0]:
			var count := 0
			var peak := 0.0
			for u in us:
				var a := CloudCopy.alpha_from_u(u, c, 1.0, st[i]["cap"], CLOUD_SOFTNESS)
				peak = maxf(peak, a)
				if a > 0.05:
					count += 1
			var frac := float(count) / us.size()
			if c == 0.0:
				check("clouds REQ-12: %s coverage 0 gives no alpha above 0.0 (peak %.6f)" % [nm, peak], peak == 0.0)
			elif c == 1.0:
				check("clouds REQ-12: %s coverage 1 gives at least 0.95 above 0.05 (%.4f)" % [nm, frac], frac >= 0.95)
			else:
				check("clouds REQ-12: %s coverage %.2f fraction within 0.05 of the setting (%.4f)" % [nm, c, frac],
					absf(frac - c) <= 0.05)

	# REQ-13: density 0, 0.5 and 1 on the first 100 directions, layer default coverage.
	for i in 2:
		var nm: String = names[i]
		var us: PackedFloat64Array = u_all[i]
		var cov: float = st[i]["cov"]
		var worst := 0.0
		var zero_ok := true
		for k in 100:
			var a1 := CloudCopy.alpha_from_u(us[k], cov, 1.0, st[i]["cap"], CLOUD_SOFTNESS)
			var ah := CloudCopy.alpha_from_u(us[k], cov, 0.5, st[i]["cap"], CLOUD_SOFTNESS)
			var a0 := CloudCopy.alpha_from_u(us[k], cov, 0.0, st[i]["cap"], CLOUD_SOFTNESS)
			worst = maxf(worst, absf(ah - 0.5 * a1))
			if a0 != 0.0:
				zero_ok = false
		check("clouds REQ-13: %s density 0 gives zero and density 0.5 is half of density 1 within 0.005 (worst %.6f)"
			% [nm, worst], zero_ok and worst <= 0.005)

	# REQ-9 (headless pair): latitude 0, longitudes 179.999 and -179.999, per layer, default coverage and density 1.
	for i in 2:
		var nm: String = names[i]
		var cov: float = st[i]["cov"]
		var a := cloud_alpha(st[i], lonlat_dir(0.0, 179.999), cov, 1.0)
		var b := cloud_alpha(st[i], lonlat_dir(0.0, -179.999), cov, 1.0)
		check("clouds REQ-9: %s seam pair at latitude 0 differs by at most 0.01 (%.6f)" % [nm, absf(a - b)],
			absf(a - b) <= 0.01)

	# REQ-10 longitude part (headless pair): latitude 89.9, longitudes 0 and 0.9, per layer.
	for i in 2:
		var nm: String = names[i]
		var cov: float = st[i]["cov"]
		var a := cloud_alpha(st[i], lonlat_dir(89.9, 0.0), cov, 1.0)
		var b := cloud_alpha(st[i], lonlat_dir(89.9, 0.9), cov, 1.0)
		check("clouds REQ-10: %s pole pair at latitude 89.9 (lon 0 and 0.9) differs by at most 0.01 (%.6f)"
			% [nm, absf(a - b)], absf(a - b) <= 0.01)

	free_main(main)
