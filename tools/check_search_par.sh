#!/usr/bin/env bash
# Calibration of tools/search_par.gd: the search must still find known solutions.
#   tools/check_search_par.sh           quick case (l001, under a second), runs in CI
#   tools/check_search_par.sh --full    also l002 and l003, minutes; run by hand after changing the sim or the tool
set -euo pipefail

GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."

fail=0
# <level> <extra rings> <extra args>
check() {
	local out
	out=$(timeout 900 "$GODOT" --headless --path . -s res://tools/search_par.gd -- --level="$1" --rings="$2" "${@:3}" 2>&1)
	if grep -q "FINISH script" <<<"$out"; then
		echo "search_par $1 ok"
	else
		echo "search_par $1 FAILED to find the known solution"
		fail=1
	fi
}

check l001 "38,11,up" --weight=3 --nodes=100000
if [ "${1:-}" = "--full" ]; then
	check l002 "0,4,right;22,11,up" --nodes=300000
	check l003 "1,11,up;0,4,right;24,11,up" --weight=3 --nodes=300000
fi
exit "$fail"
