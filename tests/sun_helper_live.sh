#!/bin/bash
# Live check for REQ-24 and REQ-25 (sun-ephemeris spec, Revision 8).
# Usage: tests/sun_helper_live.sh <godot-binary>
# Writes a fake helper into a temporary directory (removed on exit), points MOON_SUN_HELPER at it,
# runs the main scene headless for a few seconds, and checks the output.
set -u
GODOT="${1:?usage: sun_helper_live.sh <godot-binary>}"
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export FAKE_HELPER_ARGS="$tmp/args.txt"
helper="$tmp/fake-moon-ephemeris"
out="$tmp/godot.txt"

# Fake helper: records its arguments, prints one valid line (format of --stream), one bad line, stays open 6 s.
cat > "$helper" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" > "$FAKE_HELPER_ARGS"
printf '%s\n' '{"utc":"2026-11-10T00:00:00Z","jd_tt":2461354.500800926,"frame":"IAU_MOON","sun_dir_moon_fixed":[-0.9964275535234517,0.0800268613163577,-0.026978362573017247],"sun_dir_godot":[0.0800268613163577,-0.026978362573017247,-0.9964275535234517],"subsolar_lon_deg":175.40821536021815,"subsolar_lat_deg":-1.545933882331383,"sun_distance_km":147771651.3542463,"sun_angular_diameter_deg":0.5394921244144147,"earth_pos_godot":[23646.01715565163,45535.04206722649,395987.9491594832],"earth_distance_km":399298.1718752578,"earth_basis_godot":[-0.08978744560458263,0.9654386896322211,0.24467601266373465,-0.273360895463111,-0.26012226342557765,0.9260724749726451,0.9577118749620944,0.016264828052405644,0.28726889829046137],"earth_sun_dir_godot":[0.07965450418717351,-0.02721396130077164,-0.9964509823734511],"earth_subsolar_lon_deg":175.9365696278748,"earth_subsolar_lat_deg":-16.97545047307045}'
printf '%s\n' 'this is not json'
sleep 6
EOF
chmod +x "$helper"

fail=0
MOON_SUN_HELPER="$helper" timeout 20 "$GODOT" --headless --path "$root" --script res://tests/sun_helper_live.gd > "$out" 2>&1
rc=$?
if [ $rc -ne 0 ]; then echo "FAIL  Godot exit code $rc (position check or run failed)"; fail=1; fi

args=$(cat "$tmp/args.txt" 2>/dev/null || echo "<not started>")
if [ "$args" = "--stream" ]; then echo "PASS  REQ-24: fake helper started with --stream"
else echo "FAIL  REQ-24: fake helper arguments were '$args'"; fail=1; fi

n_err=$(grep -c '^ERROR: Sun helper moon-ephemeris --stream: invalid line' "$out")
if [ "$n_err" -eq 1 ]; then echo "PASS  REQ-25: exactly one ERROR line for the bad line"
else echo "FAIL  REQ-25: $n_err ERROR lines for the bad line (expected 1)"; fail=1; fi

n_all=$(grep -cE '^(SCRIPT ERROR|ERROR)' "$out")
if [ "$n_all" -eq 1 ]; then echo "PASS  REQ-25: no other ERROR or SCRIPT ERROR line"
else echo "FAIL  REQ-25: $n_all ERROR or SCRIPT ERROR lines in total (expected 1)"; fail=1; fi

if grep -q 'Parse JSON failed' "$out"; then echo "FAIL  REQ-25: engine 'Parse JSON failed' line present"; fail=1
else echo "PASS  REQ-25: no engine 'Parse JSON failed' line"; fi

grep -E '^(PASS|FAIL)  REQ-24/REQ-25' "$out" || { echo "FAIL  REQ-24/REQ-25: position check did not print"; fail=1; }

if [ $fail -ne 0 ]; then echo "sun-helper-test: FAILED"; exit 1; fi
echo "sun-helper-test: OK"
