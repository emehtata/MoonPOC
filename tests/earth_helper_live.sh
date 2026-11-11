#!/bin/bash
# Live check for Earth spec REQ-9 (helper stops after one valid line).
# Usage: tests/earth_helper_live.sh <godot-binary>
# A fake helper prints one valid streamed line (with the six Earth fields) and exits.
# Godot runs the main scene headless for a few seconds; EarthRoot must keep the line's transform,
# and exactly one ERROR line (the helper stopped, Sun spec REQ-25) may be printed.
set -u
GODOT="${1:?usage: earth_helper_live.sh <godot-binary>}"
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
helper="$tmp/fake-moon-ephemeris"
out="$tmp/godot.txt"

cat > "$helper" <<'HELPER'
#!/bin/bash
printf '%s\n' '{"utc":"2026-11-10T00:00:00Z","jd_tt":2461354.500800926,"frame":"IAU_MOON","sun_dir_moon_fixed":[-0.9964275535234517,0.0800268613163577,-0.026978362573017247],"sun_dir_godot":[0.0800268613163577,-0.026978362573017247,-0.9964275535234517],"subsolar_lon_deg":175.40821536021815,"subsolar_lat_deg":-1.545933882331383,"sun_distance_km":147771651.3542463,"sun_angular_diameter_deg":0.5394921244144147,"earth_pos_godot":[23646.01715565163,45535.04206722649,395987.9491594832],"earth_distance_km":399298.1718752578,"earth_basis_godot":[-0.08978744560458263,0.9654386896322211,0.24467601266373465,-0.273360895463111,-0.26012226342557765,0.9260724749726451,0.9577118749620944,0.016264828052405644,0.28726889829046137],"earth_sun_dir_godot":[0.07965450418717351,-0.02721396130077164,-0.9964509823734511],"earth_subsolar_lon_deg":175.9365696278748,"earth_subsolar_lat_deg":-16.97545047307045}'
HELPER
chmod +x "$helper"

MOON_SUN_HELPER="$helper" timeout 20 "$GODOT" --headless --path "$root" --script res://tests/earth_helper_live.gd > "$out" 2>&1
rc=$?
fail=0
if [ $rc -ne 0 ]; then echo "FAIL  Godot exit code $rc"; fail=1; fi
grep -E '^(PASS|FAIL)  earth REQ-9' "$out" || { echo "FAIL  earth REQ-9: check line did not print"; fail=1; }
n_err=$(grep -cE '^(SCRIPT ERROR|ERROR)' "$out")
if [ "$n_err" -eq 1 ] && grep -q 'helper process .* stopped' "$out"; then echo "PASS  earth REQ-9: exactly one ERROR line, for the stopped helper"
else echo "FAIL  earth REQ-9: $n_err ERROR lines (expected 1, helper stopped)"; fail=1; fi
if [ $fail -ne 0 ]; then echo "earth-helper-live: FAILED"; exit 1; fi
echo "earth-helper-live: OK"
