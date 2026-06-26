#!/usr/bin/env bash
set -euo pipefail
GODOT="${GODOT:-/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot}"
cd "$(dirname "$0")/.."
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd \
  -gdir=res://tests/unit -gexit -gdisable_colors
