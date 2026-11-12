#!/usr/bin/env bash
# Build the example extension into example/project/bin, then run its test with the given engine.
#
#   example/build.sh /path/to/godot
set -euo pipefail
cd "$(dirname "$0")"
odin build src -build-mode:shared -debug -out:project/bin/libexample.linux.x86_64.so
if [ $# -gt 0 ]; then
	"$1" --headless --path project --import >/dev/null 2>&1 || true
	"$1" --headless --path project -s test.gd
	# Hot reload runs only in the editor, which logs its own shutdown noise: keep the verdict.
	verdict=$("$1" --headless -e --path project -s reload_test.gd 2>&1 | grep '^reload:' || true)
	echo "${verdict:-reload: FAIL no verdict}"
	[ "$verdict" = "reload: PASS" ]
fi
