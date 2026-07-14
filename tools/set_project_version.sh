#!/bin/sh
# tools/set_project_version.sh — set application/config/version in project.godot.
# Usage: set_project_version.sh <version>
# Inserts the key after config/name if absent; replaces if present.

set -eu

version="$1"
file="project.godot"
tmp="${file}.tmp"

if grep -q '^config/version=' "$file"; then
	# Replace existing value
	awk -v v="$version" '/^config\/version=/ { print "config/version=\"" v "\""; next } { print }' "$file" > "$tmp"
else
	# Insert after config/name
	awk -v v="$version" '/^config\/name=/ { print; print "config/version=\"" v "\""; next } { print }' "$file" > "$tmp"
fi

mv "$tmp" "$file"
