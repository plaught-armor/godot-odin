#!/usr/bin/env bash
# Build the demos extension into demos/project/bin. Given an engine, also run check.gd: every demo's
# Odin and GDScript backends from one seed, compared output for output, with their timings.
#
#   demos/build.sh [/path/to/godot]
set -euo pipefail
cd "$(dirname "$0")"
odin build src -build-mode:shared -o:aggressive -out:project/bin/libdemos.linux.x86_64.so
if [ $# -gt 0 ]; then
	# Godot 4.7 can crash on the first import of a project with extension classes; the import
	# still lands, so ignore its status.
	("$1" --headless --path project --import) >/dev/null 2>&1 || true
	"$1" --headless --path project -s check.gd
fi
