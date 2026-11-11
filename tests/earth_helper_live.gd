extends SceneTree
## Live check for Earth spec REQ-9 after the helper stops, run by tests/earth_helper_live.sh.
## The fake helper prints one valid line and exits; this script waits for it, then checks EarthRoot.

const MAIN_SCENE := "res://scenes/main.tscn"
const WAIT_MS := 2500
const EXPECTED_POS := Vector3(23646.01715565163, 45535.04206722649, 395987.9491594832)
const EXPECTED_BASIS := [-0.08978744560458263, 0.9654386896322211, 0.24467601266373465, -0.273360895463111, -0.26012226342557765, 0.9260724749726451, 0.9577118749620944, 0.016264828052405644, 0.28726889829046137]

var _main: Node = null
var _start_ms := 0


func _initialize() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(_main)
	_start_ms = Time.get_ticks_msec()


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _start_ms < WAIT_MS:
		return false
	var er := _main.get_node("EarthRoot") as Node3D
	var gt := er.global_transform
	var max_err := 0.0
	var cols := [gt.basis.x, gt.basis.y, gt.basis.z]
	for i in 3:
		for j in 3:
			max_err = maxf(max_err, absf(cols[j][i] - EXPECTED_BASIS[3 * i + j]))
	var ok: bool = er.visible and gt.origin.distance_to(EXPECTED_POS) <= 1.0 and max_err <= 1e-6
	var sun = _main.get_node("Sun")
	var sun_ok: bool = sun.has_sun
	print("%s  earth REQ-9: after helper stop visible=%s origin=%s basis_err=%f has_sun=%s" \
		% ["PASS" if ok and sun_ok else "FAIL", er.visible, gt.origin, max_err, sun_ok])
	quit(0 if ok and sun_ok else 1)
	return true
