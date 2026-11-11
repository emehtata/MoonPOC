extends SceneTree
## User-run GPU checks for docs/specs/visual-quality-milestone-3.md (REQ-4, REQ-7, REQ-8).
## Run with: make visual-check             (windowed, needs a display and a GPU)
##           make visual-check HEADLESS=1  (prints one "not available headless" line per check)
## Loads scenes/main.tscn unchanged. As a test-only step it stops the Sun node's
## per-frame updates and sets fixed Sun directions. Writes nothing to the project.

const MAIN_SCENE := "res://scenes/main.tscn"
const R := 1737.4
const SETTLE_FRAMES := 5
const TYCHO := Vector2(-43.31, 348.64)  # lat, lon (deg)
const TYCHO_RADIUS_KM := 43.0
const IMBRIUM := Vector2(35.0, 340.0)
const IMBRIUM_RADIUS_KM := 100.0
const CHECK_ALTITUDE_DISTANCE := 2037.4
const REF_GRID_KM := 1.0
const REF_RAY_KM := 200.0
const REF_RAY_STEP_KM := 0.5
## Linear values at or below this count as unlit (no light to form a ratio from).
const DARK := 1e-4

var _main: Node
var _rig: Node
var _sun: DirectionalLight3D
var _moon: Node3D


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		for check in ["REQ-4 zero-phase limb response", "REQ-7 Tycho shadow fraction", "REQ-8 Imbrium shadow acne"]:
			print("%s: not available headless (dummy renderer); run make visual-check with a display" % check)
		quit(0)
		return
	_main = load(MAIN_SCENE).instantiate()
	root.add_child(_main)
	await process_frame
	_moon = _main.get_node("Moon")
	_rig = _main.get_node("CameraRig")
	_sun = _main.get_node("Sun")
	if not _moon.terrain_built:
		print("terrain: absent (see the ERROR above); no check can run")
		quit(1)
		return
	# Test-only: no streamed Sun updates, so the fixed directions below hold.
	_sun.set_process(false)
	_sun.visible = true
	var disc: Node3D = _main.get_node("SunDisc")
	disc.set_process(false)
	disc.visible = false

	var ok := true
	ok = await _check_zero_phase() and ok
	ok = await _check_tycho() and ok
	ok = await _check_imbrium() and ok
	quit(0 if ok else 1)


func _verdict(passed: bool) -> String:
	return "PASS" if passed else "FAIL"


## Surface "up" in the Moon's frame at latitude/longitude in degrees.
func _up(lat_deg: float, lon_deg: float) -> Vector3:
	var p := deg_to_rad(lat_deg)
	var l := deg_to_rad(lon_deg)
	return Vector3(cos(p) * sin(l), sin(p), cos(p) * cos(l))


func _east(lon_deg: float) -> Vector3:
	var l := deg_to_rad(lon_deg)
	return Vector3(cos(l), 0.0, -sin(l))


func _set_sun(dir_moon: Vector3) -> void:
	var d := (_moon.global_basis * dir_moon).normalized()
	var up := Vector3.FORWARD if absf(d.y) > 0.999 else Vector3.UP
	_sun.global_basis = Basis.looking_at(-d, up)


func _view(lat_deg: float, lon_deg: float, distance: float) -> void:
	_rig.pivot = _moon.global_position
	_rig.orbit_basis = Basis.looking_at(-(_moon.global_basis * _up(lat_deg, lon_deg)), Vector3.UP)
	_rig.tilt_deg = 0.0
	_rig.heading_deg = 0.0
	_rig.distance = distance


## Renders a few frames and returns the frame as linear values (red channel; the albedo is grey).
func _capture() -> PackedFloat32Array:
	for k in SETTLE_FRAMES:
		await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	var out := PackedFloat32Array()
	out.resize(image.get_width() * image.get_height())
	var w := image.get_width()
	for y in image.get_height():
		for x in w:
			out[y * w + x] = image.get_pixel(x, y).srgb_to_linear().r
	return out


## For every pixel, the unit direction (Moon frame) of the ray's hit on the
## reference sphere, or Vector3.ZERO when the ray misses the Moon.
func _hits() -> PackedVector3Array:
	var cam: Camera3D = _rig.camera
	var size := root.get_visible_rect().size
	var w := int(size.x)
	var h := int(size.y)
	var inv := _moon.global_transform.affine_inverse()
	var out := PackedVector3Array()
	out.resize(w * h)
	for y in h:
		for x in w:
			var px := Vector2(x + 0.5, y + 0.5)
			var o := inv * cam.project_ray_origin(px)
			var d := (inv.basis * cam.project_ray_normal(px)).normalized()
			var b := o.dot(d)
			var disc := b * b - (o.length_squared() - R * R)
			if disc >= 0.0:
				out[y * w + x] = (o + d * (-b - sqrt(disc))).normalized()
	return out


func _median(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return NAN
	var s := values.duplicate()
	s.sort()
	return s[s.size() / 2]


func _check_zero_phase() -> bool:
	_view(0.0, 0.0, 6000.0)
	_set_sun(Vector3(0, 0, 1))
	var lunar := await _capture()
	var unshaded := StandardMaterial3D.new()
	unshaded.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	unshaded.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	unshaded.albedo_texture = load(_moon.ALBEDO_PATH)
	for c in _moon.get_children():
		if c is MeshInstance3D:
			c.material_override = unshaded
	var flat := await _capture()
	for c in _moon.get_children():
		if c is MeshInstance3D:
			c.material_override = null
	var hits := _hits()
	var toward_camera := Vector3(0, 0, 1)
	var central := PackedFloat32Array()
	var limb := PackedFloat32Array()
	for i in hits.size():
		if hits[i] == Vector3.ZERO or flat[i] <= DARK:
			continue
		var angle := rad_to_deg(hits[i].angle_to(toward_camera))
		if angle <= 30.0:
			central.append(lunar[i] / flat[i])
		elif angle >= 70.0 and angle <= 80.0:
			limb.append(lunar[i] / flat[i])
	var c_med := _median(central)
	var l_med := _median(limb)
	var ratio := l_med / c_med
	var pc := c_med >= 0.90 and c_med <= 1.10
	var pl := l_med >= 0.90 and l_med <= 1.10
	var pr := ratio >= 0.90 and ratio <= 1.10
	print("REQ-4 central median ratio: %.4f (threshold [0.90, 1.10], %d px) %s" % [c_med, central.size(), _verdict(pc)])
	print("REQ-4 limb median ratio: %.4f (threshold [0.90, 1.10], %d px) %s" % [l_med, limb.size(), _verdict(pl)])
	print("REQ-4 limb / central: %.4f (threshold [0.90, 1.10]) %s" % [ratio, _verdict(pr)])
	return pc and pl and pr


## Fraction of pixels within radius_km of the site where on / off < limit.
## A pixel with no light even without shadows counts as dark (on / off taken as 0).
func _dark_fraction(site_up: Vector3, radius_km: float, limit: float) -> Array:
	_sun.shadow_enabled = true
	var on := await _capture()
	_sun.shadow_enabled = false
	var off := await _capture()
	_sun.shadow_enabled = true
	var hits := _hits()
	var total := 0
	var dark := 0
	for i in hits.size():
		if hits[i] == Vector3.ZERO or hits[i].angle_to(site_up) * R > radius_km:
			continue
		total += 1
		if off[i] <= DARK or on[i] / off[i] < limit:
			dark += 1
	return [float(dark) / maxi(total, 1), total]


func _check_tycho() -> bool:
	var up := _up(TYCHO.x, TYCHO.y)
	var east := _east(TYCHO.y)
	var sun := cos(deg_to_rad(5.0)) * east + sin(deg_to_rad(5.0)) * up
	_view(TYCHO.x, TYCHO.y, CHECK_ALTITUDE_DISTANCE)
	_set_sun(sun)
	var measured := await _dark_fraction(up, TYCHO_RADIUS_KM, 0.1)
	var f_render: float = measured[0]
	var f_ref := _reference_shadow_fraction(up, east, sun)
	var passed := absf(f_render - f_ref) <= 0.10 and f_ref >= 0.05
	print("REQ-7 F_render: %.4f (%d px)  F_ref: %.4f  |diff| %.4f (threshold <= 0.10, F_ref >= 0.05) %s" % [
		f_render, measured[1], f_ref, absf(f_render - f_ref), _verdict(passed)])
	return passed


func _check_imbrium() -> bool:
	var up := _up(IMBRIUM.x, IMBRIUM.y)
	var sun := cos(deg_to_rad(30.0)) * _east(IMBRIUM.y) + sin(deg_to_rad(30.0)) * up
	_view(IMBRIUM.x, IMBRIUM.y, CHECK_ALTITUDE_DISTANCE)
	_set_sun(sun)
	var measured := await _dark_fraction(up, IMBRIUM_RADIUS_KM, 0.5)
	var passed: bool = measured[0] <= 0.01
	print("REQ-8 Imbrium dark fraction: %.4f (%d px, threshold <= 0.01) %s" % [measured[0], measured[1], _verdict(passed)])
	return passed


## Terrain radius (km) along a Moon-frame direction, bilinear on the mesh's 2048 x 1024 level.
func _terrain_radius(dir: Vector3) -> float:
	var lat := asin(clampf(dir.y, -1.0, 1.0))
	var lon := fposmod(atan2(dir.x, dir.z), TAU)
	return R + _moon.sample_height_m(lat, lon) / 1000.0


## REQ-7 F_ref: independent CPU ray march on a 1 km grid inside the crater radius.
func _reference_shadow_fraction(up: Vector3, east: Vector3, sun: Vector3) -> float:
	var north := up.cross(east)
	var n := int(TYCHO_RADIUS_KM / REF_GRID_KM)
	var total := 0
	var shadowed := 0
	for j in range(-n, n + 1):
		for i in range(-n, n + 1):
			var e := i * REF_GRID_KM
			var s := j * REF_GRID_KM
			if e * e + s * s > TYCHO_RADIUS_KM * TYCHO_RADIUS_KM:
				continue
			var dir := (up * R + east * e + north * s).normalized()
			var p := dir * _terrain_radius(dir)
			total += 1
			var t := REF_RAY_STEP_KM
			while t <= REF_RAY_KM:
				var q := p + sun * t
				if q.length() < _terrain_radius(q.normalized()):
					shadowed += 1
					break
				t += REF_RAY_STEP_KM
	return float(shadowed) / maxi(total, 1)
