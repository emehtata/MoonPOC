extends SceneTree
## Live check for REQ-24 and REQ-25 (sun-ephemeris spec, Revision 8), run by tests/sun_helper_live.sh.
## The shell script sets MOON_SUN_HELPER to a fake helper that prints one valid line, then one bad line.
## This script runs the main scene for RUN_MS and checks that the Sun kept the valid line's position.
## Exit code 0 only if the Sun is at the valid line's subsolar longitude and latitude (+/- 0.001).

const MAIN_SCENE := "res://scenes/main.tscn"
const RUN_MS := 3000
# subsolar_lon_deg and subsolar_lat_deg of the valid line written by tests/sun_helper_live.sh.
const EXPECTED_LON := 175.40821536021815
const EXPECTED_LAT := -1.545933882331383

var _main: Node = null
var _start_ms := 0


func _initialize() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(_main)
	_start_ms = Time.get_ticks_msec()


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _start_ms < RUN_MS:
		return false
	var ctl = _main.get_node("Sun")
	var az: float = ctl.azimuth_deg
	var el: float = ctl.elevation_deg
	var ok: bool = ctl.has_sun \
		and absf(az - EXPECTED_LON) <= 0.001 \
		and absf(el - EXPECTED_LAT) <= 0.001
	print("%s  REQ-24/REQ-25: Sun position after bad line az=%f el=%f has_sun=%s (expected az=%f el=%f)" \
		% ["PASS" if ok else "FAIL", az, el, ctl.has_sun, EXPECTED_LON, EXPECTED_LAT])
	quit(0 if ok else 1)
	return true
