extends SceneTree
## Performance measurement for docs/specs/performance-milestone-4.md.
## Run with: make perf             (windowed, needs a display; user-run values)
##           make perf HEADLESS=1  (headless values only)
## Loads scenes/main.tscn unchanged and only sets the camera rig's
## distance and orbit_basis (reset to identity). Writes nothing to the project.

const MAIN_SCENE := "res://scenes/main.tscn"
const WARMUP_FRAMES := 120
const SAMPLE_SECONDS := 10.0
const BUILD_RUNS := 5
const POSITIONS := [
	["orbit_far", 20000.0],
	["orbit_default", 6000.0],
	["surface", 1748.232],
	["earth_close", 19113.0],  # 3 x R_E from Earth's centre, pivot on Earth (Earth Milestone 2 REQ-17)
]
const DATA_FILES_DIR := "res://assets/elevation/"
const ALBEDO_FILE := "res://assets/textures/lunar_albedo_4096x2048.png"
const RENDER_STATS := ["FPS and frame time", "Draw calls", "Primitives", "Objects drawn",
	"Texture memory", "Video memory", "CPU time of _process per frame"]
## Bytes per element of the arrays moon.gd passes to add_surface_from_arrays:
## PackedVector3Array position and normal (3 x float32), PackedVector2Array UV
## (2 x float32), PackedInt32Array index.
const BYTES_POSITION := 12
const BYTES_NORMAL := 12
const BYTES_UV := 8
const BYTES_INDEX := 4

var _headless := false


func _initialize() -> void:
	_headless = DisplayServer.get_name() == "headless"
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	print("== machine ==")
	print("rendering method: %s" % RenderingServer.get_current_rendering_method())
	print("rendering driver: %s" % RenderingServer.get_current_rendering_driver_name())
	print("adapter: %s" % RenderingServer.get_video_adapter_name())
	print("godot: %s" % Engine.get_version_info().string)
	print("cpu: %s, %d cores" % [OS.get_processor_name(), OS.get_processor_count()])
	print("mode: %s" % ("headless" if _headless else "windowed"))

	_print_file_sizes()

	var main: Node = load(MAIN_SCENE).instantiate()
	root.add_child(main)
	await process_frame
	var moon := main.get_node("Moon")
	if not moon.terrain_built:
		print("terrain: absent (see the ERROR above)")
		print("chunk count: 0")
		print("vertex count: 0")
		print("triangle count: 0")
		quit(1)
		return
	_print_geometry(moon)
	_print_processing(main)

	if _headless:
		var times: Array[int] = [moon.terrain_build_ms]
		main.free()
		for k in BUILD_RUNS - 1:
			var again: Node = load(MAIN_SCENE).instantiate()
			root.add_child(again)  # moon.gd prints its "terrain build ms:" line here
			times.append(again.get_node("Moon").terrain_build_ms)
			again.free()
		times.sort()
		print("== terrain build (%d runs, ms from moon.gd 'terrain build ms:') ==" % BUILD_RUNS)
		print("runs: %s" % str(times))
		print("min %d  median %d  max %d" % [times[0], times[BUILD_RUNS / 2], times[BUILD_RUNS - 1]])
		print("== render statistics ==")
		for stat in RENDER_STATS:
			print("%s: not available headless (dummy renderer); needs a windowed run" % stat)
		quit(0)
		return

	var rig := main.get_node("CameraRig")
	for p in POSITIONS:
		rig.distance = p[1]
		rig.orbit_basis = Basis.IDENTITY
		rig.pivot = main.get_node("EarthRoot").global_position if p[0] == "earth_close" else Vector3.ZERO
		# Earth Milestone 2 REQ-17: every position is measured with the clouds visible, then hidden.
		for clouds in [true, false]:
			for layer in ["CloudLower", "CloudUpper"]:
				main.get_node("EarthRoot/" + layer).visible = clouds
			await _measure("%s clouds %s" % [p[0], "visible" if clouds else "hidden"], p[1])
	print("texture memory MiB: %.1f" % (Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0))
	print("video memory MiB: %.1f" % (Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0))
	quit(0)


func _print_file_sizes() -> void:
	print("== data file sizes (bytes) ==")
	var files: Array[String] = []
	for f in DirAccess.get_files_at(DATA_FILES_DIR):
		files.append(DATA_FILES_DIR + f)
	files.append(ALBEDO_FILE)
	for path in files:
		if FileAccess.file_exists(path):
			print("%s: %d" % [path, FileAccess.get_file_as_bytes(path).size()])
		else:
			print("%s: missing" % path)


func _print_geometry(moon: Node) -> void:
	var chunks := 0
	var vertices := 0
	var indices := 0
	var surface_bytes := 0
	var edge_min := INF
	var edge_max := 0.0
	var radius: float = moon.reference_radius
	for child in moon.get_children():
		if not (child is MeshInstance3D):
			continue
		var mesh: Mesh = child.mesh
		chunks += 1
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			vertices += verts.size()
			# Quad side lengths on the reference sphere (heights removed), as vertex spacing.
			var side := int(round(sqrt(verts.size())))
			for j in side:
				for i in side:
					var a := verts[j * side + i].normalized() * radius
					if i + 1 < side:
						var d := a.distance_to(verts[j * side + i + 1].normalized() * radius)
						edge_min = minf(edge_min, d)
						edge_max = maxf(edge_max, d)
					if j + 1 < side:
						var d := a.distance_to(verts[(j + 1) * side + i].normalized() * radius)
						edge_min = minf(edge_min, d)
						edge_max = maxf(edge_max, d)
			indices += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
			var data := RenderingServer.mesh_get_surface(mesh.get_rid(), s)
			for key in ["vertex_data", "attribute_data", "skin_data", "index_data"]:
				if data.has(key):
					surface_bytes += (data[key] as PackedByteArray).size()
	var per_vertex := BYTES_POSITION + BYTES_NORMAL + BYTES_UV
	var estimate := vertices * per_vertex + indices * BYTES_INDEX
	print("== geometry ==")
	print("chunk count: %d" % chunks)
	print("vertex count: %d" % vertices)
	print("index count: %d" % indices)
	print("triangle count: %d" % (indices / 3))
	print("quad side km on the %.1f km reference sphere: min %.3f  max %.3f" % [radius, edge_min, edge_max])
	print("mesh memory estimate bytes: %d = %d vertices x (%d + %d + %d) + %d indices x %d" % [
		estimate, vertices, BYTES_POSITION, BYTES_NORMAL, BYTES_UV, indices, BYTES_INDEX])
	print("mesh surface buffers bytes (RenderingServer.mesh_get_surface): %d" % surface_bytes)
	if chunks > 0:
		print("per chunk: %d vertices, %d triangles, estimate %d bytes, surface buffers %d bytes" % [
			vertices / chunks, indices / 3 / chunks, estimate / chunks, surface_bytes / chunks])


func _print_processing(main: Node) -> void:
	print("== nodes with per-frame processing ==")
	var stack: Array[Node] = [main]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.is_processing() or n.is_physics_processing():
			var script: Script = n.get_script()
			print("%s: process=%s physics_process=%s script=%s" % [n.get_path(), n.is_processing(),
				n.is_physics_processing(), script.resource_path if script else "none"])
		stack.append_array(n.get_children())


func _measure(name: String, distance: float) -> void:
	for k in WARMUP_FRAMES:
		await process_frame
	var deltas := PackedFloat64Array()
	var draw := 0.0
	var prims := 0.0
	var objects := 0.0
	var proc := 0.0
	var start := Time.get_ticks_usec()
	var last := start
	while true:
		await process_frame
		var now := Time.get_ticks_usec()
		deltas.append((now - last) / 1000.0)
		last = now
		draw += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		if (now - start) / 1000000.0 >= SAMPLE_SECONDS:
			break
	var seconds := (last - start) / 1000000.0
	var n := deltas.size()
	var sorted := deltas.duplicate()
	sorted.sort()
	var total := 0.0
	for d in deltas:
		total += d
	print("== %s ==" % name)
	print("distance: %.3f  orbit_basis: identity" % distance)
	print("warm-up frames: %d" % WARMUP_FRAMES)
	print("sample seconds: %.3f" % seconds)
	print("frames: %d" % n)
	print("mean fps: %.2f" % (n / seconds))
	print("frame ms mean %.3f  median %.3f  p95 %.3f  max %.3f" % [total / n, sorted[n / 2],
		sorted[mini(n - 1, int(ceil(n * 0.95)) - 1)], sorted[n - 1]])
	print("draw calls mean: %.1f" % (draw / n))
	print("primitives mean: %.1f" % (prims / n))
	print("objects drawn mean: %.1f" % (objects / n))
	print("process ms mean: %.3f" % (proc / n))
