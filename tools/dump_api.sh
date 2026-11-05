#!/usr/bin/env bash
# Dump an engine's extension_api.json and gdextension_interface.json into api/, then regenerate the
# bindings from them. Run when you move to another engine version or a custom build.
#
#   tools/dump_api.sh /path/to/godot
set -euo pipefail
godot=${1:?usage: tools/dump_api.sh /path/to/godot}
godot=$(realpath "$godot")
cd "$(dirname "$0")/.."
mkdir -p api
# Both dumps write into the working directory.
(cd api && "$godot" --headless --dump-extension-api >/dev/null)
(cd api && "$godot" --headless --dump-gdextension-interface-json >/dev/null)
python3 tools/odin_bindgen.py
