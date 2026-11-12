#!/usr/bin/env bash
# Build the example extension into example/project/bin, then run its test with the given engine.
#
#   example/build.sh /path/to/godot
set -euo pipefail
cd "$(dirname "$0")"
python3 ../tools/odin_docgen.py src
odin build src -build-mode:shared -debug -out:project/bin/libexample.linux.x86_64.so
if [ $# -gt 0 ]; then
	"$1" --headless --path project --import >/dev/null 2>&1 || true
	"$1" --headless --path project -s test.gd
	# The editor takes ExamplePlugin, which logs a line from its _enter_tree, and loads the help XML.
	editor=$("$1" --headless -e --path project --quit-after 300 2>&1)
	if ! grep -qx 'ExamplePlugin: in the editor' <<<"$editor"; then echo "editor: FAIL no plugin"; exit 1; fi
	if grep -q 'ERROR' <<<"$editor"; then grep 'ERROR' <<<"$editor"; echo "editor: FAIL errors"; exit 1; fi
	echo "editor: PASS"
	# Hot reload runs only in the editor, which logs its own shutdown noise: keep the verdict.
	verdict=$("$1" --headless -e --path project -s reload_test.gd 2>&1 | grep '^reload:' || true)
	echo "${verdict:-reload: FAIL no verdict}"
	[ "$verdict" = "reload: PASS" ]
fi
