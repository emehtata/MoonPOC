extends Node3D
## Cube-face quadtree terrain (spec lunar-surface-procedural, REQ-26 to REQ-30; docs/ARCHITECTURE.md).
##
## The 96 roots are the M2 chunks that moon.gd builds (depth 0). A node whose screen error is more than
## `split_px` is replaced by its 4 children (depth up to `max_depth`); children are merged back when the
## node's error falls below `merge_px`. Nodes are built on worker threads by the native library
## (`LunarTerrain.build_node`); the main thread only creates the mesh, within a 2 ms budget per frame, and
## the old node stays visible until all 4 replacements are ready. Hidden nodes are kept in an LRU cache
## and freed above the node and byte limits. A root is hidden while its children are shown.
## Node positions are the node centre minus the floating origin, computed in doubles (D6).

const TERRAIN_LAYERS := 3
## Quality levels (REQ-34), the one selection point: env MOON_QUALITY = low | medium | high, default medium.
## Split 4/3/2 px and depth 16/17/18 are from the spec; merge is 0.7 x split (High keeps the old 1.4 px). The rock draw
## radii (km, small/medium/large) and cache limits for Low and Medium are assumptions; High keeps the Phase 5 values.
const QUALITY := {
	"low": {"split_px": 4.0, "max_depth": 16, "rock_km": [0.015, 0.15, 0.8], "node_limit": 1200, "byte_limit": 300_000_000},
	"medium": {"split_px": 3.0, "max_depth": 17, "rock_km": [0.02, 0.2, 1.2], "node_limit": 1800, "byte_limit": 420_000_000},
	"high": {"split_px": 2.0, "max_depth": 18, "rock_km": [0.025, 0.25, 1.5], "node_limit": 2500, "byte_limit": 600_000_000},
}
const MERGE_RATIO := 0.7
## Estimated bytes of one node's mesh: 4485 vertices x (position, normal, uv, morph) = 44 bytes each.
const NODE_BYTES := 4485 * 44
const MAIN_BUDGET_USEC := 2000
const ROOTS := 96
const EVICT_BUDGET_USEC := 1000
const MAX_TASKS := 4
## Geometric error of a node as a fraction of its vertex spacing (assumption).
const ERROR_FRACTION := 0.5
const PLAN_INTERVAL_MS := 100
const REFERENCE_RADIUS := 1737.4

@export var split_px: float = quality()["split_px"]
@export var merge_px: float = quality()["split_px"] * MERGE_RATIO
@export var max_depth: int = quality()["max_depth"]
## LRU limits per node count and bytes (set by the quality level, REQ-34).
@export var node_limit: int = quality()["node_limit"]
@export var byte_limit: int = quality()["byte_limit"]

var terrain
var fly: Node3D
var resident_bytes := 0
var cancel_count := 0
var duplicate_requests_blocked := 0
var max_main_thread_usec := 0
var max_plan_usec := 0
var create_usec_total := 0
var max_create_usec := 0
var frames_over_budget := 0
# REQ-27 per-frame main-thread resource time, split by operation; each has a max.
var max_creation_usec := 0
var max_display_usec := 0
var max_select_usec := 0  # _collect plus per-node error maths, excluded from REQ-27
var max_evict_usec := 0
var _frame_create := 0
var _frame_display := 0
var _frame_evict := 0
var instr_calls := 0  # timer calls made, for the overhead report
var build_count := 0
var build_ms := PackedFloat64Array()  # worker build time per node (perf report, REQ-31)
var shown_count := 0

var _moon: Node3D
var _material: ShaderMaterial
var _indices: PackedInt32Array
var _nodes := {}  # key -> {"mi": MeshInstance3D, "centre": Array, "bytes": int, "used": int, "root": bool}
var _bounds := {}  # key -> PackedFloat64Array
var _split := {}  # key -> true, nodes currently wanted split
var _shown := {}  # key -> true
var _queued: Array = []  # keys to build, nearest first
var _tasks := {}  # key -> {"id": int, "out": Array}
var _wanted_build := {}
var _last_plan_ms := 0
var _dirty := true
const MORPH_CAP_PER_PLAN := 24
var _morph_left := false
var _planned_at := Vector3.ZERO
var _frame := 0
var _cam := [0.0, 0.0, 0.0]
var _px_per_rad := 700.0


static func quality() -> Dictionary:
	var name := OS.get_environment("MOON_QUALITY").to_lower()
	if name != "" and not QUALITY.has(name):
		push_warning("MOON_QUALITY '%s' unknown (low, medium, high); using medium" % name)
	return QUALITY.get(name, QUALITY["medium"])


static func make_key(face: int, depth: int, x: int, y: int) -> int:
	return (((face << 5 | depth) << 20 | x) << 20) | y


static func key_face(k: int) -> int:
	return k >> 45


static func key_depth(k: int) -> int:
	return (k >> 40) & 31


static func key_x(k: int) -> int:
	return (k >> 20) & 0xFFFFF


static func key_y(k: int) -> int:
	return k & 0xFFFFF


func _ready() -> void:
	_moon = get_node("../Moon")
	fly = get_node("../FlyCamera")
	fly.rebased.connect(_on_rebased)


func _register_roots() -> bool:
	if not _nodes.is_empty():
		return true
	if _moon.get_child_count() < 96:
		return false
	for f in 6:
		for cx in 4:
			for cy in 4:
				var chunk := _moon.get_node_or_null("Chunk_%d_%d_%d" % [f, cx, cy]) as MeshInstance3D
				if chunk == null:
					return false
				_nodes[make_key(f, 0, cx, cy)] = {"mi": chunk, "centre": [0.0, 0.0, 0.0], "bytes": 0, "used": 0, "root": true, "on": chunk.visible}
				_shown[make_key(f, 0, cx, cy)] = true
				if _material == null:
					_material = chunk.mesh.surface_get_material(0)
	return true


func _on_rebased() -> void:
	for key in _nodes:
		var e: Dictionary = _nodes[key]
		if not e["root"]:
			e["mi"].position = _pos_of(e["centre"])


func _pos_of(c: Array) -> Vector3:
	return Vector3(c[0] - fly.origin.x, c[1] - fly.origin.y, c[2] - fly.origin.z)


func _process(_delta: float) -> void:
	if fly.terrain == null or not _register_roots():
		return
	if terrain != fly.terrain:
		terrain = fly.terrain
		_indices = terrain.node_indices()
	_frame += 1
	_frame_create = 0
	_frame_display = 0
	_frame_evict = 0
	_update_camera()
	_finish_builds()
	var now := Time.get_ticks_msec()
	var moved := Vector3(_cam[0], _cam[1], _cam[2]).distance_to(_planned_at)
	if now - _last_plan_ms >= PLAN_INTERVAL_MS and (_dirty or moved > 0.0 and moved > 0.0001):
		_last_plan_ms = now
		_plan()
		_planned_at = Vector3(_cam[0], _cam[1], _cam[2])
	# One place per frame: total = creation + display + eviction, whether or not a node completed.
	var total := _frame_create + _frame_display + _frame_evict
	max_creation_usec = maxi(max_creation_usec, _frame_create)
	max_display_usec = maxi(max_display_usec, _frame_display)
	max_evict_usec = maxi(max_evict_usec, _frame_evict)
	max_main_thread_usec = maxi(max_main_thread_usec, total)
	frames_over_budget += int(total > MAIN_BUDGET_USEC)


func _update_camera() -> void:
	var camera := get_viewport().get_camera_3d()
	if fly.active:
		_cam = [fly.px, fly.py, fly.pz]
	elif camera:
		var p := camera.global_position
		_cam = [p.x, p.y, p.z]
	var height_px := float(get_viewport().get_visible_rect().size.y)
	var fov := camera.fov if camera else 75.0
	_px_per_rad = height_px / (2.0 * tan(deg_to_rad(fov) * 0.5))


func _get_bounds(key: int) -> PackedFloat64Array:
	if not _bounds.has(key):
		_bounds[key] = terrain.node_bounds(key_face(key), key_depth(key), key_x(key), key_y(key))
	return _bounds[key]


## Screen-space error in pixels of a node's mesh: half its vertex spacing at the distance of its nearest point.
func _error_px(key: int) -> float:
	var b := _get_bounds(key)
	var dx: float = b[0] - _cam[0]
	var dy: float = b[1] - _cam[1]
	var dz: float = b[2] - _cam[2]
	var dist := maxf(sqrt(dx * dx + dy * dy + dz * dz) - b[3], 1e-7)
	return ERROR_FRACTION * b[4] / dist * _px_per_rad


func _plan() -> void:
	var plan_start := Time.get_ticks_usec()
	var new_split := {}
	_wanted_build = {}
	for f in 6:
		for cx in 4:
			for cy in 4:
				_visit(f, 0, cx, cy, new_split)
	_split = new_split
	# Queue: nearest first; anything queued earlier that is no longer wanted is dropped (cancelled).
	var ordered := _wanted_build.keys()
	ordered.sort_custom(func(a, b): return _wanted_build[a] < _wanted_build[b])
	for key in _queued:
		if not _wanted_build.has(key):
			cancel_count += 1
	_queued = ordered
	_start_tasks()
	_apply_display()
	var t2 := Time.get_ticks_usec()
	_evict()
	_frame_evict += Time.get_ticks_usec() - t2
	instr_calls += 3
	_dirty = _morph_left or not _queued.is_empty() or not _tasks.is_empty()
	max_plan_usec = maxi(max_plan_usec, Time.get_ticks_usec() - plan_start)


func _visit(f: int, d: int, x: int, y: int, new_split: Dictionary) -> void:
	var key := make_key(f, d, x, y)
	var thr := merge_px if _split.has(key) else split_px
	var want := d < max_depth and _error_px(key) > thr
	if want:
		var b := _get_bounds(key)
		var lat := rad_to_deg(asin(clampf(b[1] / sqrt(b[0] * b[0] + b[1] * b[1] + b[2] * b[2]), -1.0, 1.0)))
		var lon := fposmod(rad_to_deg(atan2(b[0], b[2])), 360.0)
		want = terrain.max_depth(lat, lon) > d
	if not want:
		return
	if not _nodes.has(key):
		_request(key)
		return
	new_split[key] = true
	_nodes[key]["used"] = _frame
	for k in 4:
		var child := make_key(f, d + 1, 2 * x + (k & 1), 2 * y + (k >> 1))
		var cx := 2 * x + (k & 1)
		var cy := 2 * y + (k >> 1)
		_visit_child(f, d + 1, cx, cy, new_split, child)


func _visit_child(f: int, d: int, x: int, y: int, new_split: Dictionary, key: int) -> void:
	if not _nodes.has(key):
		# A child below a split node is always needed, whatever its own error.
		_request(key)
		return
	_visit(f, d, x, y, new_split)


func _request(key: int) -> void:
	if _tasks.has(key):
		duplicate_requests_blocked += 1
	# Coarse nodes first (an area is covered level by level), nearest first within a depth.
	_wanted_build[key] = float(key_depth(key)) * 1.0e9 - _error_px(key)


func _start_tasks() -> void:
	while not _queued.is_empty() and _tasks.size() < MAX_TASKS:
		var key: int = _queued.pop_front()
		if _nodes.has(key) or _tasks.has(key):
			duplicate_requests_blocked += 1
			continue
		var out := []
		var id := WorkerThreadPool.add_task(_task_build.bind(key, out))
		_tasks[key] = {"id": id, "out": out}


func _task_build(key: int, out: Array) -> void:
	var t0 := Time.get_ticks_usec()
	var data: Dictionary = terrain.build_node(key_face(key), key_depth(key), key_x(key), key_y(key))
	if not data.is_empty():
		# Mesh upload runs on the worker so the main thread only creates the node (REQ-27).
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = data["verts"]
		arrays[Mesh.ARRAY_NORMAL] = data["normals"]
		arrays[Mesh.ARRAY_TEX_UV] = data["uvs"]
		arrays[Mesh.ARRAY_CUSTOM0] = data["morph"]
		arrays[Mesh.ARRAY_INDEX] = _indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		mesh.surface_set_material(0, _material)
		data["mesh"] = mesh
	out.append(data)
	out.append((Time.get_ticks_usec() - t0) / 1000.0)  # worker build time in ms, read by _finish_builds


## Creates the meshes of finished builds, within the main-thread budget (REQ-27).
func _finish_builds() -> void:
	var start := Time.get_ticks_usec()
	var made := 0
	var dropped := false
	for key in _tasks.keys():
		var task: Dictionary = _tasks[key]
		if not WorkerThreadPool.is_task_completed(task["id"]):
			continue
		if not _wanted_build.has(key) and not _split.has(key):
			WorkerThreadPool.wait_for_task_completion(task["id"])
			_tasks.erase(key)
			cancel_count += 1  # no longer wanted: dropped before any resource is created, so not gated by the cap
			dropped = true
			continue
		# Stop once another node (at the worst creation cost seen) would pass the budget.
		if made > 0 and Time.get_ticks_usec() - start + max_create_usec > MAIN_BUDGET_USEC:
			break
		if _nodes.size() - ROOTS >= node_limit:
			break  # cap reached: wait for _evict to free nodes, never exceed the cap (REQ-29)
		WorkerThreadPool.wait_for_task_completion(task["id"])
		_tasks.erase(key)
		var data: Dictionary = task["out"][0]
		build_ms.append(task["out"][1])
		if not data.is_empty():
			_create_node(key, data)
			made += 1
	if dropped:
		_start_tasks()
	if made > 0:
		_dirty = true
		_start_tasks()
	_frame_create += Time.get_ticks_usec() - start
	instr_calls += 1


func _create_node(key: int, data: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var centre: PackedFloat64Array = data["centre_xyz"]
	var mi := MeshInstance3D.new()
	mi.mesh = data["mesh"]
	mi.layers = TERRAIN_LAYERS
	mi.visible = false
	mi.set_instance_shader_parameter("moon_offset", Vector3(centre[0], centre[1], centre[2]))
	var c := [centre[0], centre[1], centre[2]]
	mi.position = _pos_of(c)
	add_child(mi)
	_nodes[key] = {"mi": mi, "centre": c, "bytes": NODE_BYTES, "used": _frame, "root": false}
	resident_bytes += NODE_BYTES
	build_count += 1
	var spent := Time.get_ticks_usec() - t0
	create_usec_total += spent
	max_create_usec = maxi(max_create_usec, spent)


## Shows, for every area, the finest resident node whose replacement chain is complete.
func _apply_display() -> void:
	var t_sel := Time.get_ticks_usec()
	var show := {}
	for f in 6:
		for cx in 4:
			for cy in 4:
				_collect(make_key(f, 0, cx, cy), show)
	var morphs := 0
	_morph_left = false
	var t := Time.get_ticks_usec()
	var spent := 0  # REQ-27 counts only the shader-parameter and visibility calls; collect and error maths are selection
	for key in _nodes:
		var e: Dictionary = _nodes[key]
		var on := show.has(key)
		var fresh: bool = e.get("on", false) != on
		if fresh:  # only changed nodes pay a visibility call
			var t0 := Time.get_ticks_usec()
			(e["mi"] as MeshInstance3D).visible = on
			spent += Time.get_ticks_usec() - t0
			e["on"] = on
		if on:
			e["used"] = _frame
			if not e["root"]:
				# Geomorph (REQ-30): parent-interpolated shape at the split error, own shape 0.6 px above it.
				var parent_err := 2.0 * _error_px(key)
				var m := clampf(1.0 - (parent_err - split_px) / (split_px - merge_px), 0.0, 1.0)
				if e.get("morph", -1.0) != m:  # unchanged values cost no resource call
					# shortcut: later-changed morphs wait for the next plan (100 ms) once the cap is hit, raise MORPH_CAP_PER_PLAN if visible
					if not fresh and morphs >= MORPH_CAP_PER_PLAN:
						_morph_left = true
						continue
					morphs += 1
					var t0 := Time.get_ticks_usec()
					e["mi"].set_instance_shader_parameter("morph", m)
					spent += Time.get_ticks_usec() - t0
					e["morph"] = m
	_shown = show
	shown_count = show.size()
	_frame_display += spent
	max_select_usec = maxi(max_select_usec, Time.get_ticks_usec() - t_sel - spent)


func _collect(key: int, out: Dictionary) -> bool:
	if _split.has(key):
		var tmp := {}
		var ok := true
		var f := key_face(key)
		var d := key_depth(key)
		for k in 4:
			if not _collect(make_key(f, d + 1, 2 * key_x(key) + (k & 1), 2 * key_y(key) + (k >> 1)), tmp):
				ok = false
		if ok:
			out.merge(tmp)
			return true
	if _nodes.has(key):
		out[key] = true
		return true
	return false


func _evict() -> void:
	var count := _nodes.size() - ROOTS
	if count <= node_limit and resident_bytes <= byte_limit:
		return
	var start := Time.get_ticks_usec()
	var victims := []
	for key in _nodes:
		var e: Dictionary = _nodes[key]
		if e["root"] or _shown.has(key) or _split.has(key) or _wanted_build.has(key):
			continue
		victims.append([e["used"], key])
	victims.sort()
	for v in victims:
		if count <= node_limit and resident_bytes <= byte_limit:
			break
		if Time.get_ticks_usec() - start > EVICT_BUDGET_USEC:
			break  # the rest goes next plan; creation is gated on the cap meanwhile
		var e: Dictionary = _nodes[v[1]]
		e["mi"].queue_free()  # frees the node's mesh and GPU buffers
		resident_bytes -= e["bytes"]
		_nodes.erase(v[1])
		count -= 1


func _exit_tree() -> void:
	for key in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[key]["id"])
