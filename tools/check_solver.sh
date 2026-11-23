#!/usr/bin/env bash
# Native solver (design 23.10.4): build, tick-for-tick equivalence with the GDScript simulation, calibration, speed.
#   tools/check_solver.sh            runs in CI (about two minutes)
#   tools/check_solver.sh --full     also the cheaper-route searches of design 17.2, printed not judged (minutes)
# Exit 1 on any difference or failed calibration. Output goes to build/solver/.
set -euo pipefail

export LC_ALL=C
GODOT="${GODOT:-godot}"
SEEDS="${SEEDS:-20}"
SWEEP="${SWEEP:-8000}"
TICKS="${TICKS:-900}"
cd "$(dirname "$0")/.."
out=build/solver
fail=0

godot_run() {
	local log
	if ! log=$(timeout 900 "$GODOT" --headless --path . -s "$@" 2>&1); then
		echo "$log"
		echo "godot failed: $*"
		exit 1
	fi
	grep -v '^\[\|^$\|^Godot Engine' <<<"$log" || true
}

tools/solver/build.sh
echo "solver built"

godot_run res://tools/export_levels.gd -- --out=$out/levels.txt
godot_run res://tools/trace_sim.gd -- --levels=$out/levels.txt --seeds="$SEEDS" --ticks="$TICKS" --sweep="$SWEEP" --out=$out/
$out/maze_solver trace $out/levels.txt $out/cases.txt >$out/trace_cpp.txt
if cmp -s $out/trace_gd.txt $out/trace_cpp.txt; then
	echo "trace ok: $(wc -l <$out/trace_gd.txt) ticks in $(wc -l <$out/cases.txt) cases equal"
else
	echo "trace FAILED: first difference (gd, then cpp)"
	diff $out/trace_gd.txt $out/trace_cpp.txt | head -4 || true
	fail=1
fi

# <expect finish|none> <level> <extra rings> <weight> <nodes>
calibrate() {
	local result
	result=$($out/maze_solver search $out/levels.txt --level="$2" --rings="$3" --weight="$4" --nodes="$5")
	if grep -q "FINISH script" <<<"$result"; then
		got=finish
	else
		got=none
	fi
	if [ "$got" = "$1" ]; then
		echo "solver $2 ($got) ok"
	else
		echo "solver $2 expected $1, got $got ($3)"
		fail=1
	fi
}

# the thrown rings of the stored solutions (tests/solutions.json) are found
calibrate finish l001 "38,11,up" 3 100000
calibrate finish l002 "0,5,right;22,11,up" 1 300000
calibrate finish l003 "1,11,up;0,4,right;24,11,up" 3 300000
calibrate finish l004 "7,11,up;19,11,up;31,11,up" 3 300000
calibrate finish l005 "21,9,right;26,9,left" 1 300000
calibrate finish l006 "5,21,up;9,17,up;13,13,up;17,9,up" 1 300000
calibrate finish l007 "10,9,right;27,12,up" 1 300000
calibrate finish l008 "0,6,right;10,13,up" 1 3000000
calibrate finish l009 "8,13,up;11,13,up;10,6,right;20,13,up" 2 3000000
calibrate finish lab01 "10,12,up;37,15,up" 1 300000
calibrate finish lab02 "" 1 300000
calibrate finish lab03 "17,15,up" 1 300000
# without extra rings only l001 (finding B1 of the test report of 2026-11-21) and the lab have a route
calibrate finish l001 "" 3 1000000
for id in l002 l003 l004 l005 l006 l007 l008 l009; do
	calibrate none "$id" "" 1 300000
done

# speed: nodes per second on l005 with one of its two rings (no route, so the node limit is reached), startup of
# Godot subtracted
now() { date +%s.%N; }
gd_time() {
	local t0 t1
	t0=$(now)
	timeout 900 "$GODOT" --headless --path . -s res://tools/search_par.gd -- --level=l005 --rings="21,9,right" \
		--nodes="$1" >/dev/null 2>&1
	t1=$(now)
	awk -v a="$t0" -v b="$t1" 'BEGIN { print b - a }'
}
gd_nodes=20000
cpp_nodes=200000
gd_base=$(gd_time 1)
gd_run=$(gd_time $gd_nodes)
cpp_line=$($out/maze_solver search $out/levels.txt --level=l005 --rings="21,9,right" --nodes=$cpp_nodes | tail -1)
cpp_ms=$(awk '{print $4}' <<<"$cpp_line")
gd_s=$(awk -v a="$gd_run" -v b="$gd_base" 'BEGIN { print a - b }')
ratio=$(awk -v s="$gd_s" -v gn="$gd_nodes" -v ms="$cpp_ms" -v cn="$cpp_nodes" \
	'BEGIN { print (cn / (ms + 1)) / (gn / s) * 1000 }')
printf "speed l005: search_par.gd %d nodes in %.1f s (%.0f nodes/s), maze_solver %d nodes in %s ms (%.0f nodes/s), factor %.0f\n" \
	"$gd_nodes" "$gd_s" "$(awk -v n="$gd_nodes" -v s="$gd_s" 'BEGIN { print n / s }')" "$cpp_nodes" "$cpp_ms" \
	"$(awk -v n="$cpp_nodes" -v ms="$cpp_ms" 'BEGIN { print n * 1000 / (ms + 1) }')" "$ratio"
if awk -v r="$ratio" 'BEGIN { exit !(r < 100) }'; then
	echo "speed FAILED: less than 100 times faster"
	fail=1
fi

if [ "${1:-}" = "--full" ]; then
	# settings of design 17.2 and the test report of 2026-11-21: l005, l007, l008 and lab03 find no set with a finish,
	# lab01 finds three (design 23.21)
	search() {
		echo "search $*"
		$out/maze_solver search $out/levels.txt "$@" | tail -3
	}
	search --level=l007 --subset=1 --weight=1 --nodes=3000000
	search --level=l008 --subset=1 --weight=1 --nodes=3000000
	search --level=l005 --subset=1 --weight=1 --nodes=3000000
	search --level=lab01 --subset=1 --weight=1 --nodes=300000
	search --level=lab03 --subset=0 --weight=1 --nodes=300000
fi
exit "$fail"
