#!/usr/bin/env bash
# Build the benchmark extension with release optimisation into bench/project/bin, then run it with
# the given engine. Prints nanoseconds per call for each path the bindings own.
#
#   bench/build.sh /path/to/godot
set -euo pipefail
cd "$(dirname "$0")"
odin build src -build-mode:shared -o:speed -out:project/bin/libbench.linux.x86_64.so
if [ $# -gt 0 ]; then
	"$1" --headless --path project --import >/dev/null 2>&1 || true
	"$1" --headless --path project -s bench.gd
fi
