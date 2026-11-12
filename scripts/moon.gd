extends Node3D
## The Moon: a cube-sphere displaced by real LOLA elevation.
##
## Six cube faces, each split into 4 x 4 chunks of 64 x 64 quads. Every chunk is
## a MeshInstance3D child. The mesh is built once in _ready() from the
## 2048 x 1024 height level listed in assets/elevation/moon_data.json; nothing
## is computed per frame. Heights are used at scale 1.0 (1 unit = 1 km).
##
## Orientation: north pole on +Y, (0 N, 0 E) on +Z, (0 N, 90 E) on +X.

const ALBEDO_PATH := "res://assets/textures/lunar_albedo_4096x2048.png"
const METADATA_PATH := "res://assets/elevation/moon_data.json"
const SHADER_PATH := "res://shaders/lunar_surface.gdshader"
const NORMAL_MAP_PATH := "res://assets/textures/lunar_normal_enu_4096x2048.png"
const NORMAL_MAP_WIDTH := 4096
const NORMAL_MAP_HEIGHT := 2048
const HEIGHT_LEVEL_WIDTH := 2048
const HEIGHT_LEVEL_HEIGHT := 1024

const CHUNKS_PER_FACE_SIDE := 4
const QUADS_PER_CHUNK_SIDE := 64
## Quads along one cube-face side (4 x 64).
const FACE_QUADS := CHUNKS_PER_FACE_SIDE * QUADS_PER_CHUNK_SIDE
const FACE_VERTS := FACE_QUADS + 1
const HALF := FACE_QUADS / 2

## Cube faces as [normal, u axis, v axis], with u x v = normal (outward).
const FACES: Array = [
	[Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1)],
	[Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 1, 0)],
	[Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 0)],
	[Vector3i(0, -1, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1)],
	[Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(0, 1, 0)],
	[Vector3i(0, 0, -1), Vector3i(0, 1, 0), Vector3i(1, 0, 0)],
]

## Reference sphere radius in units (km), read from the metadata file.
var reference_radius := 0.0
## True once the displaced terrain has been built.
var terrain_built := false
var terrain_build_ms := 0

var _heights: PackedFloat32Array
var _height_w := 0
var _height_h := 0


func _ready() -> void:
	var material := ShaderMaterial.new()
	material.shader = load(SHADER_PATH)
	if ResourceLoader.exists(ALBEDO_PATH):
		material.set_shader_parameter("albedo_texture", load(ALBEDO_PATH))
	else:
		# No procedural fallback is allowed: the Moon renders plain and the error is visible.
		push_error("Moon albedo texture missing: %s" % ALBEDO_PATH)
	var normal_problem := _check_normal_map()
	if normal_problem == "":
		material.set_shader_parameter("normal_texture", load(NORMAL_MAP_PATH))
		material.set_shader_parameter("use_normal_map", true)
	else:
		# REQ-17: the shader keeps the interpolated vertex normal; no other normal is made up.
		push_error("Moon normal map not used: %s" % normal_problem)

	var problem := _load_heights()
	if problem != "":
		# No flat sphere and no generated surface replace the missing data.
		push_error("Moon terrain not built: %s" % problem)
		return
	var start := Time.get_ticks_msec()
	_build_terrain(material)
	terrain_build_ms = Time.get_ticks_msec() - start
	terrain_built = true
	print("terrain build ms: %d" % terrain_build_ms)


## Loads the height level named in the metadata file. Returns "" on success,
## otherwise a message naming the file that is missing or does not match.
func _load_heights() -> String:
	if not FileAccess.file_exists(METADATA_PATH):
		return "%s is missing" % METADATA_PATH
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(METADATA_PATH))
	if not (parsed is Dictionary) or not (parsed.get("elevation_levels") is Array):
		return "%s is not valid metadata (no elevation_levels)" % METADATA_PATH
	var level = null
	for entry in parsed["elevation_levels"]:
		if entry is Dictionary and int(entry.get("width", 0)) == HEIGHT_LEVEL_WIDTH \
				and int(entry.get("height", 0)) == HEIGHT_LEVEL_HEIGHT:
			level = entry
	if level == null:
		return "%s lists no %d x %d elevation level" % [METADATA_PATH, HEIGHT_LEVEL_WIDTH, HEIGHT_LEVEL_HEIGHT]
	for key in ["path", "data_type", "byte_order", "units", "reference_radius_m", "nodata_count", "sha256"]:
		if not level.has(key):
			return "%s: the %d x %d level has no '%s' field" % [METADATA_PATH, HEIGHT_LEVEL_WIDTH, HEIGHT_LEVEL_HEIGHT, key]
	if level["data_type"] != "float32" or level["byte_order"] != "little-endian" or level["units"] != "m":
		return "%s: the %d x %d level is not little-endian float32 metres" % [METADATA_PATH, HEIGHT_LEVEL_WIDTH, HEIGHT_LEVEL_HEIGHT]

	var path := "res://%s" % str(level["path"])
	if not FileAccess.file_exists(path):
		return "%s is missing" % path
	var bytes := FileAccess.get_file_as_bytes(path)
	var expected_size := HEIGHT_LEVEL_WIDTH * HEIGHT_LEVEL_HEIGHT * 4
	if bytes.size() != expected_size:
		return "%s has %d bytes, the metadata needs %d" % [path, bytes.size(), expected_size]
	if FileAccess.get_sha256(path) != str(level["sha256"]):
		return "%s does not match the SHA-256 in %s" % [path, METADATA_PATH]
	if int(level["nodata_count"]) != 0:
		# A NoData cell has no height, and none may be invented for it.
		return "%s holds %d NoData cells, so no surface can be built from it" % [path, int(level["nodata_count"])]

	_heights = bytes.to_float32_array()
	_height_w = HEIGHT_LEVEL_WIDTH
	_height_h = HEIGHT_LEVEL_HEIGHT
	reference_radius = float(level["reference_radius_m"]) / 1000.0
	return ""


## Height in metres at latitude/longitude (radians, longitude 0..TAU east):
## bilinear between cell centres, wrapping in longitude and clamped to the
## first and last row centres in latitude.
func sample_height_m(lat: float, lon: float) -> float:
	var fx := lon / TAU * _height_w - 0.5
	var x_floor := floorf(fx)
	var ax := fx - x_floor
	var x0 := posmod(int(x_floor), _height_w)
	var x1 := (x0 + 1) % _height_w
	var fy := clampf((PI / 2.0 - lat) / PI * _height_h - 0.5, 0.0, _height_h - 1.0)
	var y0 := int(floorf(fy))
	var y1 := mini(y0 + 1, _height_h - 1)
	var ay := fy - y0
	var top := lerpf(_heights[y0 * _height_w + x0], _heights[y0 * _height_w + x1], ax)
	var bottom := lerpf(_heights[y1 * _height_w + x0], _heights[y1 * _height_w + x1], ax)
	return lerpf(top, bottom, ay)


func _build_terrain(material: Material) -> void:
	# Equal-angle spacing across each face keeps the triangles close to the
	# same size everywhere, including near the poles and the cube corners.
	var warp := PackedFloat64Array()
	warp.resize(FACE_VERTS)
	for i in FACE_VERTS:
		warp[i] = tan(float(i - HALF) / HALF * PI / 4.0)
	warp[0] = -1.0
	warp[FACE_QUADS] = 1.0

	# Global vertices. Vertices on face edges are shared between faces, so
	# positions and normals there are the same in every chunk that uses them.
	var positions := PackedVector3Array()
	var lons := PackedFloat64Array()
	var lats := PackedFloat64Array()
	var border_ids := {}
	var face_ids: Array[PackedInt32Array] = []
	for face in FACES:
		var n: Vector3i = face[0]
		var u: Vector3i = face[1]
		var v: Vector3i = face[2]
		var ids := PackedInt32Array()
		ids.resize(FACE_VERTS * FACE_VERTS)
		for j in FACE_VERTS:
			var tb := warp[j]
			for i in FACE_VERTS:
				var on_border := i == 0 or j == 0 or i == FACE_QUADS or j == FACE_QUADS
				var key := Vector3i.ZERO
				if on_border:
					key = n * HALF + u * (i - HALF) + v * (j - HALF)
					if border_ids.has(key):
						ids[j * FACE_VERTS + i] = border_ids[key]
						continue
				var ta := warp[i]
				var x := n.x + u.x * ta + v.x * tb
				var y := n.y + u.y * ta + v.y * tb
				var z := n.z + u.z * ta + v.z * tb
				var inv := 1.0 / sqrt(x * x + y * y + z * z)
				x *= inv
				y *= inv
				z *= inv
				var lat := asin(clampf(y, -1.0, 1.0))
				var lon := atan2(x, z)
				if lon < 0.0:
					lon += TAU
				var r := reference_radius + sample_height_m(lat, lon) / 1000.0
				var id := positions.size()
				positions.append(Vector3(x * r, y * r, z * r))
				lons.append(lon)
				lats.append(lat)
				ids[j * FACE_VERTS + i] = id
				if on_border:
					border_ids[key] = id
		face_ids.append(ids)

	# Area-weighted normals from the displaced triangles, summed over every
	# triangle that touches a vertex, across chunk and face edges.
	var normals := PackedVector3Array()
	normals.resize(positions.size())
	for ids in face_ids:
		for j in FACE_QUADS:
			for i in FACE_QUADS:
				var ia := ids[j * FACE_VERTS + i]
				var ib := ids[j * FACE_VERTS + i + 1]
				var ic := ids[(j + 1) * FACE_VERTS + i]
				var id := ids[(j + 1) * FACE_VERTS + i + 1]
				var pb := positions[ib]
				var pc := positions[ic]
				var n1 := (pb - positions[ia]).cross(pc - positions[ia])
				var n2 := (positions[id] - pb).cross(pc - pb)
				normals[ia] += n1
				normals[ib] += n1 + n2
				normals[ic] += n1 + n2
				normals[id] += n2
	for k in normals.size():
		normals[k] = normals[k].normalized()

	# Triangle indices are the same for every chunk. Godot front faces are
	# clockwise, so each outward triangle is listed in clockwise order.
	var side := QUADS_PER_CHUNK_SIDE + 1
	var indices := PackedInt32Array()
	indices.resize(QUADS_PER_CHUNK_SIDE * QUADS_PER_CHUNK_SIDE * 6)
	var w := 0
	for j in QUADS_PER_CHUNK_SIDE:
		for i in QUADS_PER_CHUNK_SIDE:
			var a := j * side + i
			var b := a + 1
			var c := a + side
			var d := c + 1
			indices[w] = a
			indices[w + 1] = c
			indices[w + 2] = b
			indices[w + 3] = b
			indices[w + 4] = c
			indices[w + 5] = d
			w += 6

	for f in FACES.size():
		var n: Vector3i = FACES[f][0]
		var u: Vector3i = FACES[f][1]
		var v: Vector3i = FACES[f][2]
		var ids := face_ids[f]
		for cy in CHUNKS_PER_FACE_SIDE:
			for cx in CHUNKS_PER_FACE_SIDE:
				var i0 := cx * QUADS_PER_CHUNK_SIDE
				var j0 := cy * QUADS_PER_CHUNK_SIDE
				# The chunk centre tells which side of the 0 E seam the chunk is on.
				var mid := QUADS_PER_CHUNK_SIDE / 2
				var centre: Vector3i = n * HALF + u * (i0 + mid - HALF) + v * (j0 + mid - HALF)
				var centre_u := lons[ids[(j0 + mid) * FACE_VERTS + i0 + mid]] / TAU
				var seam_u := 1.0 if centre.x < 0 else 0.0
				var verts := PackedVector3Array()
				var norms := PackedVector3Array()
				var uvs := PackedVector2Array()
				verts.resize(side * side)
				norms.resize(side * side)
				uvs.resize(side * side)
				for j in side:
					for i in side:
						var id := ids[(j0 + j) * FACE_VERTS + i0 + i]
						var k := j * side + i
						verts[k] = positions[id]
						norms[k] = normals[id]
						var tex_u := lons[id] / TAU
						var cube: Vector3i = n * HALF + u * (i0 + i - HALF) + v * (j0 + j - HALF)
						if cube.x == 0 and cube.z == 0:
							# A pole has no longitude; use the chunk's own.
							tex_u = centre_u
						elif cube.x == 0 and cube.z > 0:
							# On the 0 E meridian: u = 1 for chunks west of it, 0 east of it,
							# so no triangle spans the whole texture.
							tex_u = seam_u
						uvs[k] = Vector2(tex_u, (PI / 2.0 - lats[id]) / PI)
				var arrays := []
				arrays.resize(Mesh.ARRAY_MAX)
				arrays[Mesh.ARRAY_VERTEX] = verts
				arrays[Mesh.ARRAY_NORMAL] = norms
				arrays[Mesh.ARRAY_TEX_UV] = uvs
				arrays[Mesh.ARRAY_INDEX] = indices
				var mesh := ArrayMesh.new()
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				mesh.surface_set_material(0, material)
				var chunk := MeshInstance3D.new()
				chunk.name = "Chunk_%d_%d_%d" % [f, cx, cy]
				chunk.mesh = mesh
				chunk.layers = 3  # layer 1 (all) + layer 2 (terrain, drawn by the fly near camera)
				add_child(chunk)


## Checks the normal map PNG against the `normal_map` entry of the metadata
## file (REQ-17). Returns "" when it matches, otherwise a message naming the file.
func _check_normal_map() -> String:
	if not FileAccess.file_exists(NORMAL_MAP_PATH):
		return "%s is missing" % NORMAL_MAP_PATH
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(METADATA_PATH)) \
			if FileAccess.file_exists(METADATA_PATH) else null
	if not (parsed is Dictionary) or not (parsed.get("normal_map") is Dictionary):
		return "%s: %s has no normal_map entry" % [NORMAL_MAP_PATH, METADATA_PATH]
	var entry: Dictionary = parsed["normal_map"]
	if int(entry.get("width", 0)) != NORMAL_MAP_WIDTH or int(entry.get("height", 0)) != NORMAL_MAP_HEIGHT:
		return "%s: %s lists a size other than %d x %d" % [NORMAL_MAP_PATH, METADATA_PATH, NORMAL_MAP_WIDTH, NORMAL_MAP_HEIGHT]
	if FileAccess.get_sha256(NORMAL_MAP_PATH) != str(entry.get("sha256", "")):
		return "%s does not match the SHA-256 in %s" % [NORMAL_MAP_PATH, METADATA_PATH]
	var texture := load(NORMAL_MAP_PATH) as Texture2D
	if texture == null or texture.get_width() != NORMAL_MAP_WIDTH or texture.get_height() != NORMAL_MAP_HEIGHT:
		return "%s is not a %d x %d texture" % [NORMAL_MAP_PATH, NORMAL_MAP_WIDTH, NORMAL_MAP_HEIGHT]
	return ""
