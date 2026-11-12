extends Node3D
## Near-camera world for fly mode (spec lunar-surface-procedural, Phase 3): the rock chunks, drawn as one
## MultiMeshInstance3D per chunk per base mesh (D3, REQ-19). Everything sits on layers 1 and 2 (D9).
## Node positions are chunk centre minus the floating origin, computed in doubles (D6).

const TERRAIN_LAYERS := 3
## D2 stream id for rock material (albedo factor).
const MATERIAL_STREAM := 4
## Rock draw radius per category (small, medium, large) in km. Provisional until the Phase 6 quality levels.
const DRAW_RADIUS_KM := [0.025, 0.25, 1.5]
## REQ-20: small rocks cast shadows within this distance; medium and large always.
const SHADOW_DISTANCE_M := 200.0
## Chunk distance (m) below which LOD 0, then LOD 1 is used; LOD 2 beyond.
const LOD_DISTANCE_M := [30.0, 150.0]
const BUILD_BUDGET_MS := 25
const REPLAN_DISTANCE_M := 16.0
const MAX_TASKS := 1
const LOD_INTERVAL_MS := 500

var terrain
var fly: Node3D
var moon_material: ShaderMaterial
var rock_count := 0

var _chunks := {}  # key -> {"nodes": Array, "centre": Array, "cat": int, "lod": int}
var _meshes := {}
var _rock_material := ShaderMaterial.new()
var _pending: Array = []
var _planned := false
var _tasks := {}
var _wanted := {}
var _planned_at := Vector3.ZERO
var _last_lod_ms := 0


func _ready() -> void:
	_rock_material.shader = load("res://shaders/lunar_rock.gdshader")
	visible = false
	setup(get_node("../FlyCamera"), get_node("../Moon"))


func setup(fly_camera: Node3D, moon: Node3D) -> void:
	fly = fly_camera
	for child in moon.get_children():
		if child is MeshInstance3D:
			moon_material = (child as MeshInstance3D).mesh.surface_get_material(0).duplicate()
			_rock_material.set_shader_parameter("albedo_texture", moon_material.get_shader_parameter("albedo_texture"))
			break
	fly.rebased.connect(_on_rebased)


func _process(_delta: float) -> void:
	if fly == null or not fly.active or fly.terrain == null:
		visible = false
		return
	visible = true
	terrain = fly.terrain
	_rock_material.set_shader_parameter("moon_centre", -fly.origin)
	var ll: Array = fly.lat_lon()
	_update_rocks(ll[0], ll[1])


func _pos_of(centre: Array) -> Vector3:
	return Vector3(centre[0] - fly.origin.x, centre[1] - fly.origin.y, centre[2] - fly.origin.z)


func _on_rebased() -> void:
	for key in _chunks:
		for node in _chunks[key]["nodes"]:
			node.position = _pos_of(_chunks[key]["centre"])


## Horizontal distance in metres between the camera and a Moon-fixed point (km): the arc on the reference
## sphere, so the terrain height (up to -9 km) does not count.
func _cam_distance_m(centre: Array) -> float:
	# In doubles (Vector3 is float32): chord length minus the radial part.
	var dx: float = centre[0] - fly.px
	var dy: float = centre[1] - fly.py
	var dz: float = centre[2] - fly.pz
	var radial: float = sqrt(fly.px * fly.px + fly.py * fly.py + fly.pz * fly.pz) - sqrt(centre[0] * centre[0] + centre[1] * centre[1] + centre[2] * centre[2])
	return sqrt(maxf(0.0, dx * dx + dy * dy + dz * dz - radial * radial)) * 1000.0


func _rock_mesh(cat: int, idx: int, lod: int) -> ArrayMesh:
	var key := "%d:%d:%d" % [cat, idx, lod]
	if _meshes.has(key):
		return _meshes[key]
	var d: Dictionary = terrain.rock_mesh(cat, idx, lod)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = d["verts"]
	arrays[Mesh.ARRAY_NORMAL] = d["normals"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _rock_material)
	_meshes[key] = mesh
	return mesh


func _lod_for(distance_m: float) -> int:
	return 0 if distance_m < LOD_DISTANCE_M[0] else (1 if distance_m < LOD_DISTANCE_M[1] else 2)


func _update_rocks(lat: float, lon: float) -> void:
	var deadline := Time.get_ticks_msec() + BUILD_BUDGET_MS
	var here := Vector3(fly.px, fly.py, fly.pz)
	# Re-plan the resident set only after the camera moved 16 m and nothing is still pending.
	if _pending.is_empty() and _tasks.is_empty() and (not _planned or here.distance_to(_planned_at) * 1000.0 > REPLAN_DISTANCE_M):
		_plan(lat, lon)
		_planned_at = here
		_planned = true
	# Rock placement runs on worker threads; the main thread only creates the nodes (budgeted).
	for key in _tasks.keys():
		var task: Dictionary = _tasks[key]
		if WorkerThreadPool.is_task_completed(task["id"]) and Time.get_ticks_msec() < deadline:
			WorkerThreadPool.wait_for_task_completion(task["id"])
			_tasks.erase(key)
			if _wanted.has(key) and not _chunks.has(key):
				_build_chunk(key, task["cat"], task["c"], task["centre"], task["out"][0])
	while not _pending.is_empty() and _tasks.size() < MAX_TASKS:
		var m: Array = _pending.pop_back()
		if _chunks.has(m[0]) or _tasks.has(m[0]):
			continue
		var out := []
		var id := WorkerThreadPool.add_task(_task_place.bind(m[2], m[1], out))
		_tasks[m[0]] = {"id": id, "cat": m[1], "c": m[2], "centre": m[3], "out": out}
	if Time.get_ticks_msec() - _last_lod_ms < LOD_INTERVAL_MS:
		return
	_last_lod_ms = Time.get_ticks_msec()
	for key in _chunks:
		var entry: Dictionary = _chunks[key]
		var dist := _cam_distance_m(entry["centre"])
		var lod := _lod_for(dist)
		var shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (entry["cat"] > 0 or dist < SHADOW_DISTANCE_M) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for node in entry["nodes"]:
			var mmi := node as MultiMeshInstance3D
			if entry["lod"] != lod:
				mmi.multimesh.mesh = _rock_mesh(entry["cat"], mmi.get_meta("mesh_index"), lod)
			mmi.cast_shadow = shadow
		entry["lod"] = lod


## Chooses the chunks to keep and queues the missing ones, nearest last (popped from the back).
func _plan(lat: float, lon: float) -> void:
	var k: float = terrain.rock_chunk_km()
	var wanted := {}
	for cat in 3:
		var list: PackedInt64Array = terrain.rock_chunks_near(lat, lon, DRAW_RADIUS_KM[cat])
		for i in list.size() / 3:
			wanted["%d:%d:%d:%d" % [cat, list[i * 3], list[i * 3 + 1], list[i * 3 + 2]]] = Vector3i(list[i * 3], list[i * 3 + 1], list[i * 3 + 2])
	_wanted = wanted
	for key in _chunks.keys():
		if not wanted.has(key):
			for node in _chunks[key]["nodes"]:
				node.queue_free()
			_chunks.erase(key)
	var missing := []
	for key in wanted:
		if not _chunks.has(key):
			var c: Vector3i = wanted[key]
			var centre := [(c.x + 0.5) * k, (c.y + 0.5) * k, (c.z + 0.5) * k]
			missing.append([-_cam_distance_m(centre), key, int(key.get_slice(":", 0)), c, centre])
	missing.sort_custom(func(a, b): return a[0] < b[0])
	_pending = missing.map(func(m): return [m[1], m[2], m[3], m[4]])


func _task_place(c: Vector3i, cat: int, out: Array) -> void:
	out.append(terrain.rock_chunk(c.x, c.y, c.z, cat))


func _build_chunk(key: String, cat: int, c: Vector3i, centre: Array, data: PackedFloat64Array) -> void:
	var buffers := {}
	var counts := {}
	for i in data.size() / 22:
		var o := i * 22
		var mesh_index := int(data[o + 6])
		if not buffers.has(mesh_index):
			buffers[mesh_index] = PackedFloat32Array()
		var b: PackedFloat32Array = buffers[mesh_index]
		var off := [data[o + 7] - centre[0], data[o + 8] - centre[1], data[o + 9] - centre[2]]
		# Row-major 3 x 4: each row holds a basis row (x, y, z components of the 3 columns) and the origin.
		for r in 3:
			b.append(data[o + 10 + r])
			b.append(data[o + 13 + r])
			b.append(data[o + 16 + r])
			b.append(off[r])
		# Custom data for lunar_rock.gdshader: albedo factor from the material stream (4), texture UV, height and sink.
		var h: int = terrain.hash64(terrain.seed, MATERIAL_STREAM, int(data[o]), int(data[o + 1]), int(data[o + 2]), int(data[o + 3]), int(data[o + 4]))
		var p := Vector3(data[o + 7], data[o + 8], data[o + 9])
		b.append(1.0 + 0.3 * float((h >> 11) & 0x1FFFFFFFFFFFFF) / 9007199254740992.0)
		b.append(fposmod(rad_to_deg(atan2(p.x, p.z)), 360.0) / 360.0)
		b.append((90.0 - rad_to_deg(asin(clampf(p.y / p.length(), -1.0, 1.0)))) / 180.0)
		b.append(floorf(data[o + 20] * 1000.0) + data[o + 21])
		buffers[mesh_index] = b
		counts[mesh_index] = counts.get(mesh_index, 0) + 1
	var nodes := []
	for mesh_index in buffers:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.instance_count = counts[mesh_index]
		mm.buffer = buffers[mesh_index]
		mm.mesh = _rock_mesh(cat, mesh_index, 0)
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.layers = TERRAIN_LAYERS
		node.set_meta("mesh_index", mesh_index)
		node.position = _pos_of(centre)
		add_child(node)
		nodes.append(node)
		rock_count += counts[mesh_index]
	_chunks[key] = {"nodes": nodes, "centre": centre, "cat": cat, "lod": 0}


func _exit_tree() -> void:
	for key in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[key]["id"])
