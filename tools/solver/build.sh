#!/usr/bin/env bash
# Builds the native solver (design 23.10.4): build/solver/maze_solver
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/solver
g++ -std=c++17 -O2 -Wall -Wextra -o build/solver/maze_solver tools/solver/maze_solver.cpp
